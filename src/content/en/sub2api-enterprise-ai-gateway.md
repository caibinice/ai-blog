---
title: Sub2API Gateway Internals and Enterprise Agent Architecture
excerpt: A source-level study of streaming proxying, account-pool scheduling, atomic Redis concurrency control, multi-level authentication caching, and idempotent billing in Sub2API.
---
> **Core value**
>
> An LLM gateway is the control point between business applications and upstream model capacity. Beyond forwarding requests, it must manage tenant isolation, heterogeneous account pools, distributed concurrency, streaming backpressure, and billing correctness. This article studies the real Sub2API implementation and extracts practices that also apply to enterprise AI gateways and agent platforms.

The local source used for verification is commit `9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015`.

## 0. Why the gateway deserves a source-level review

Production agent platforms repeatedly encounter five engineering problems:

1. **Concurrency and capacity control.** Distributed instances must respect upstream limits without overselling slots.
2. **Heterogeneous resource scheduling.** Subscription accounts and metered API keys have different latency, health, cost, and quota characteristics.
3. **Context locality.** Stable routing improves prompt-cache reuse, but unhealthy sticky routes must be escaped quickly.
4. **Long-lived streams.** A downstream disconnect must cancel the upstream computation and release resources immediately.
5. **Metering and billing.** Token cost is known only after generation, while retries must never produce duplicate charges.

Sub2API solves these problems as a subscription and multi-channel aggregation gateway. Its mechanisms are directly relevant to internal model platforms.

## 1. Runtime architecture

### 1.1 Stack and single-binary packaging

| Layer | Technology | Responsibility |
|---|---|---|
| Frontend | Vue 3, TypeScript, Vite, TailwindCSS | Administration, user workspace, dashboards, and usage views |
| Backend | Go 1.26+, Gin, Ent | Routing, protocol adaptation, scheduling, streaming proxying, and billing |
| Durable storage | PostgreSQL | Users, API keys, groups, accounts, and immutable usage facts |
| Runtime state | Redis | Concurrency slots, rate limits, invalidation events, and OAuth refresh locks |

![Sub2API single-process deployment and runtime topology](/images/sub2api/runtime-topology.png)

*Sub2API single-process deployment and runtime topology*

Go's `embed` feature packages the Vite output into the backend executable:

    Vue source ── pnpm build ──> backend/internal/web/dist
                                         │
                                         ▼
    Go source ── go build -tags embed ──> one executable with frontend assets

This design removes production CORS complexity and makes the frontend and API an atomic release unit.

![Sub2API administration dashboard](/images/sub2api/admin-dashboard.png)

*Sub2API administration dashboard*

### 1.2 Durable facts and volatile controls

PostgreSQL owns transactional facts: identity, product configuration, account metadata, and usage records. Redis owns high-frequency controls: ZSET concurrency slots, RPM/TPM counters, refresh locks, and Pub/Sub cache invalidation. Separating these responsibilities keeps the request path fast without weakening financial consistency.

## 2. Upstream identity virtualization

| Dimension | Subscription account | Metered platform API key |
|---|---|---|
| Payment | Prepaid subscription | Token-based usage |
| Credential | Access token, refresh token, account ID | Long-lived API key |
| Capacity | Rolling windows and periodic limits | Balance plus RPM/TPM limits |
| Main challenge | Refresh, sticky sessions, window utilization | Balance control, allocation, and provider failover |

![OpenAI accounts support ChatGPT OAuth and API-key access](/images/sub2api/openai-account-types.png)

*OpenAI accounts support ChatGPT OAuth and API-key access*

The gateway gives downstream systems a stable OpenAI-compatible API key while retaining privileged upstream credentials in the control plane. A virtual ledger can expose prepaid capacity as metered usage and combine multiple metered channels into one resilient routing group.

## 3. End-to-end request lifecycle

![End-to-end API request lifecycle](/images/sub2api/request-lifecycle.png)

*End-to-end API request lifecycle*

The main control flow can be reduced to five steps:

    func HandleGatewayRequest(c *gin.Context, req *UnifiedRequest) error {
        keyInfo, user, group, err := authService.Authenticate(req.APIKey)
        if err != nil {
            return c.AbortWithStatusJSON(401, gin.H{"error": "invalid_api_key"})
        }
        if err := precheck(user, keyInfo, group, req.Model); err != nil {
            return c.AbortWithStatusJSON(403, gin.H{"error": err.Error()})
        }

        account, releaseSlot, err := scheduler.AcquireSlot(c.Request.Context(), group, req)
        if err != nil {
            return c.AbortWithStatusJSON(429, gin.H{"error": "rate_limited_or_concurrency_full"})
        }
        defer releaseSlot()

        upstreamReq, err := prepareUpstreamRequest(c.Request.Context(), account, req)
        if err != nil {
            return err
        }
        usage, err := streamForwardWithFlush(c, upstreamReq)
        if err != nil {
            return err
        }
        return billingRepo.SettleUsageTransaction(c.Request.Context(), req.ID, keyInfo.ID, usage)
    }

Authentication and policy checks happen before scheduling. The scheduler atomically acquires an account slot. The adapter prepares the upstream protocol and credential. Streaming returns data as it arrives, and billing commits only after the final usage facts are available.

## 4. Five core engineering mechanisms

### 4.1 Streaming proxying and cancellation propagation

`http.ResponseWriter` may buffer output. Calling `Flush` after each SSE chunk protects time to first token:

    flusher, ok := c.Writer.(http.Flusher)
    if !ok {
        return errors.New("streaming unsupported by underlying transport")
    }

    for {
        chunk, err := streamReader.ReadChunk()
        if errors.Is(err, io.EOF) {
            break
        }
        if err != nil {
            return err
        }
        _, _ = c.Writer.Write(chunk)
        flusher.Flush()
    }

The upstream request uses the downstream `Request.Context()`. Closing the browser or stopping generation therefore cancels upstream work and triggers deferred slot release instead of leaving an expensive orphaned request.

### 4.2 Health-aware account-pool scheduling

![Dynamic account scheduling and atomic slot acquisition](/images/sub2api/account-scheduler.png)

*Dynamic account scheduling and atomic slot acquisition*

The scheduler first applies hard capability filters, then computes a multi-factor score:

```math
Score = w_p P + w_l(1-Load) + w_q(1-Queue) + w_e(1-Error) + w_t(1-TTFT) + w_r Reset + w_c Cost
```

Error rate and TTFT are smoothed with EWMA. Subscription accounts that are close to a rolling-window reset receive a use-it-or-lose-it bonus. Cost becomes a deciding factor when multiple channels meet the same SLA.

Selecting only the highest score would create a traffic hotspot. Sub2API therefore keeps a Top-K candidate set and performs weighted random selection. Session hashes and `previous_response_id` preserve prompt-cache locality, while concurrency saturation, elevated error rate, or abnormal TTFT immediately breaks the sticky binding.

### 4.3 Atomic distributed concurrency control

A normal `GET` followed by `INCR` races across gateway instances. Sub2API models active requests in a Redis ZSET whose member is the request ID and whose score is Redis server time. A Lua script removes expired members, handles retries idempotently, checks capacity, and inserts the new slot as one atomic operation:

    local now = tonumber(redis.call('TIME')[1])
    local expireBefore = now - tonumber(ARGV[2])
    redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', expireBefore)

    if redis.call('ZSCORE', KEYS[1], ARGV[3]) ~= false then
        redis.call('ZADD', KEYS[1], now, ARGV[3])
        redis.call('EXPIRE', KEYS[1], ARGV[2])
        return {1, now}
    end

    local count = redis.call('ZCARD', KEYS[1])
    if count < tonumber(ARGV[1]) then
        redis.call('ZADD', KEYS[1], now, ARGV[3])
        redis.call('EXPIRE', KEYS[1], ARGV[2])
        return {1, now}
    end
    return {0, now}

TTL-based cleanup makes the control self-healing after a gateway crash. The same pattern can be applied independently to user, API-key, and upstream-account limits.

### 4.4 Two-phase metering and idempotent billing

The request begins with a soft eligibility check and finishes with an atomic settlement after token usage is known:

```math
Cost = InputTokens \times InputPrice + OutputTokens \times OutputPrice + CacheTokens \times CachePrice + ReasoningTokens \times ReasoningPrice
```

`usage_billing_repo.go` opens a PostgreSQL transaction and inserts `(request_id, api_key_id, request_fingerprint)` into a deduplication table. `ON CONFLICT DO NOTHING` turns repeated settlement messages into a no-op. Balance mutation and the immutable usage record are then committed in the same transaction.

### 4.5 Multi-level authentication cache

![Multi-level authentication cache and cross-instance invalidation](/images/sub2api/auth-cache.png)

*Multi-level authentication cache and cross-instance invalidation*

The L1 Ristretto cache removes database and network I/O from the hot path. SingleFlight collapses concurrent misses for the same key. A randomized TTL avoids synchronized expiration, and Redis Pub/Sub invalidates every instance when an administrator changes a key, quota, whitelist, or status.

## 5. Multi-tenant data model

| Entity | Role | Main controls |
|---|---|---|
| User | Tenant or customer | Balance, global concurrency, status, allowed groups |
| API Key | Application credential | Owner, group, expiry, IP whitelist, rolling-window quotas |
| Group | Product SKU and routing policy | Models, billing mode, price multiplier, margin, RPM/TPM |
| Account | Physical upstream supply | Credential, concurrency, priority, load, health, rate-limit state |
| UsageLog | Immutable consumption fact | Request ID, model, token breakdown, raw cost, billed cost, trace IDs |

![Core entity relationships](/images/sub2api/entity-relationship.png)

*Core entity relationships*

`Group` is the key decoupling boundary. Downstream consumers buy a stable product definition, while upstream accounts can be replaced, pooled, repriced, or failed over without changing client configuration.

![Product-group configuration](/images/sub2api/group-configuration.png)

*Product-group configuration centralizes billing, model mapping, and policy controls*

## 6. Capacity reuse and service tiers

Gateway economics come from metered margin, statistical multiplexing, and differentiated SLA tiers. Subscription capacity should not be valued by an abstract monthly figure; it should be measured from 7–14 days of real prompts:

```math
EquivalentValue = \sum SuccessfulTokens \times OfficialAPIPrice
```

A useful capacity report combines equivalent value, success rate, P95 TTFT, 429 share, and actual utilization. These measurements support realistic oversubscription limits and make reset-aware scheduling defensible.

## 7. Enterprise agent platform design

The same mechanisms produce a clean enterprise architecture:

| Enterprise problem | Gateway mechanism | Result |
|---|---|---|
| Uncontrolled internal concurrency | Tenant and upstream slot gates with Lua and TTL | No cross-instance overselling; automatic recovery |
| Provider failover | Capability filters, EWMA score, Top-K weighted routing | High availability with cost and latency control |
| Tenant isolation | User → API Key → Group → Account | Auditable boundaries and replaceable providers |
| Streaming disconnects and retries | Context cancellation plus unique settlement key | Less wasted compute and no duplicate billing |
| Heterogeneous model APIs | OpenAI-compatible protocol and provider adapters | Standard business integration and unified cost accounting |

![Recommended enterprise agent runtime architecture](/images/sub2api/enterprise-agent-architecture.png)

*Recommended enterprise agent runtime architecture*

The gateway nodes remain stateless and scale horizontally. Conversation memory and enterprise knowledge stay independent from model supply. Routing can evolve from priority rules to multi-objective optimization, while one request ID joins agent steps, tool calls, token usage, and financial records into a complete trace.

## 8. Conclusion

Sub2API is valuable as a production-oriented gateway sample. Reliable LLM infrastructure requires more than an SDK call: identity abstraction, traffic governance, state isolation, atomic concurrency, streaming cancellation, and transactional settlement must be designed as separate but coordinated layers.

## Source index

- [Gateway routes and middleware pipeline](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/server/routes/gateway.go)
- [OpenAI protocol adaptation and streaming proxy](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/service/openai_gateway_forward.go)
- [Account-pool scheduler](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/service/openai_account_scheduler.go)
- [Redis concurrency control](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/repository/concurrency_cache.go)
- [Authentication cache](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/service/api_key_auth_cache_impl.go)
- [Idempotent usage billing](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/repository/usage_billing_repo.go)
