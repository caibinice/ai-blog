---
title: Sub2APIゲートウェイの内部実装と企業AIエージェント基盤
excerpt: Sub2APIの実コードをもとに、ストリーミングプロキシ、アカウントプールのスケジューリング、Redisによる原子的な同時実行制御、多段認証キャッシュ、冪等課金を解説します。
---
> **本稿の要点**
>
> LLMゲートウェイは、業務アプリケーションと上流のモデル計算資源を接続する制御点です。リクエスト転送だけでなく、テナント分離、異種アカウントプール、分散同時実行、ストリームのバックプレッシャー、課金整合性まで扱う必要があります。本稿ではSub2APIの実装を読み解き、企業AI基盤に再利用できる設計原則を整理します。

検証に使用したローカルソースはコミット `9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015` です。

## 0. なぜゲートウェイをソースレベルで読むのか

企業向けエージェント基盤では、次の課題が繰り返し現れます。

1. **同時実行と容量制御**：複数インスタンスからの要求をまとめても、上流の制限を超えない原子的な制御が必要です。
2. **異種リソースのスケジューリング**：サブスクリプションと従量課金APIでは、遅延、健全性、単価、残容量が異なります。
3. **コンテキスト局所性**：同一会話を同じ供給元に送るとPrompt Cacheを活用できますが、障害時には即座に離脱しなければなりません。
4. **長時間ストリーム**：クライアント切断を上流まで伝播させ、計算とスロットをすぐに解放する必要があります。
5. **計量と課金**：Token数は生成完了後に確定し、再試行が起きても二重課金を防ぐ必要があります。

Sub2APIは、サブスクリプションと複数チャネルを標準APIへ集約するシステムですが、内部で解決している問題は企業向けLLMゲートウェイと共通しています。

## 1. ランタイムアーキテクチャ

### 1.1 技術スタックと単一バイナリ配布

| レイヤー | 技術 | 役割 |
|---|---|---|
| フロントエンド | Vue 3、TypeScript、Vite、TailwindCSS | 管理画面、ユーザーワークスペース、利用量表示 |
| バックエンド | Go 1.26+、Gin、Ent | ルーティング、プロトコル変換、スケジューリング、ストリーム転送、課金 |
| 永続データ | PostgreSQL | ユーザー、API Key、グループ、アカウント、利用実績 |
| 実行時状態 | Redis | 同時実行スロット、レート制限、キャッシュ無効化、OAuth更新ロック |

![Sub2APIの単一プロセス構成とランタイムトポロジー](/images/sub2api/runtime-topology.png)

*Sub2APIの単一プロセス構成とランタイムトポロジー*

Goの`embed`でViteの成果物をバックエンド実行ファイルへ組み込みます。

    Vueソース ── pnpm build ──> backend/internal/web/dist
                                      │
                                      ▼
    Goソース ── go build -tags embed ──> フロントエンド内蔵の単一実行ファイル

この構成は本番CORSを単純化し、フロントエンドとAPIを常に同じバージョンで原子的に配布できます。

![Sub2API管理ダッシュボード](/images/sub2api/admin-dashboard.png)

*Sub2API管理ダッシュボード*

### 1.2 事実データと高頻度状態の分離

PostgreSQLは、ID、製品設定、上流アカウント、利用ログなどトランザクションが必要な事実を保持します。Redisは、ZSET同時実行スロット、RPM/TPMカウンター、Token更新ロック、Pub/Subによるキャッシュ無効化など、低遅延の制御を担当します。この分離によって、ホットパスの性能と金銭データの整合性を両立します。

## 2. 上流IDの仮想化

| 観点 | サブスクリプションアカウント | 従量課金API Key |
|---|---|---|
| 支払い | 月額・年額の前払い | Token使用量に応じた課金 |
| 資格情報 | Access Token、Refresh Token、Account ID | 長期API Key |
| 容量 | ローリング時間窓と周期上限 | 残高とRPM/TPM上限 |
| 主な課題 | Token更新、会話固定、期間容量の有効利用 | 残高管理、分配、供給元フェイルオーバー |

![ChatGPT OAuthとAPI Keyの2種類のOpenAI接続](/images/sub2api/openai-account-types.png)

*ChatGPT OAuthとAPI Keyの2種類のOpenAI接続*

下流システムには一貫したOpenAI互換API Keyを発行し、権限の強い上流資格情報は制御面だけで管理します。仮想台帳によって、定額容量を従量サービスとして分割し、複数の従量チャネルを高可用なルーティンググループへ統合できます。

## 3. リクエストの全処理フロー

![APIリクエストのエンドツーエンド処理](/images/sub2api/request-lifecycle.png)

*APIリクエストのエンドツーエンド処理*

中心的な制御フローは次の5段階です。

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

認証とポリシー検査の後、スケジューラが上流アカウントのスロットを原子的に確保します。アダプターがプロトコルと認証ヘッダーを組み立て、ストリームを逐次返し、最終的な利用量が確定してから課金トランザクションを実行します。

## 4. 5つの中核メカニズム

### 4.1 ストリーミングとキャンセル伝播

`http.ResponseWriter`は出力をバッファするため、SSEチャンクごとに`Flush`しないとTTFTが悪化します。

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

上流リクエストを下流の`Request.Context()`へ接続すると、ブラウザーの終了や生成停止が即座に上流へ伝わります。`defer`によるスロット解放と組み合わせることで、孤立した計算を残しません。

### 4.2 健全性を考慮したアカウントプール

![動的アカウント選択と原子的スロット確保](/images/sub2api/account-scheduler.png)

*動的アカウント選択と原子的スロット確保*

スケジューラは能力条件で候補を絞り、複数の要素からスコアを計算します。

```math
Score = w_p P + w_l(1-Load) + w_q(1-Queue) + w_e(1-Error) + w_t(1-TTFT) + w_r Reset + w_c Cost
```

エラー率とTTFTはEWMAで平滑化します。ローリング時間窓のリセットが近いサブスクリプションには、未使用容量を活用するための加点を与えます。最高点だけへ集中させると新たなホットスポットになるため、Top-K候補に対する重み付きランダム選択で負荷を分散します。

会話ハッシュや`previous_response_id`はPrompt Cacheの局所性を維持します。ただし、同時実行枠の飽和、エラー率の上昇、TTFTの異常があれば固定ルートから即座に離脱します。

### 4.3 Redisによる原子的な分散同時実行制御

複数インスタンスで`GET`の後に`INCR`すると競合が起きます。Sub2APIは、リクエストIDをmember、Redisサーバー時刻をscoreとするZSETを使い、次のLua処理を一回で実行します。

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

期限切れmemberの削除、再試行の冪等処理、容量確認、スロット挿入が原子的です。プロセスが異常終了してもTTLで自己回復します。同じ方式をユーザー、API Key、上流アカウントに独立して適用できます。

### 4.4 二段階計量と冪等課金

開始時は利用資格を確認し、生成完了後に確定したTokenで決済します。

```math
Cost = InputTokens \times InputPrice + OutputTokens \times OutputPrice + CacheTokens \times CachePrice + ReasoningTokens \times ReasoningPrice
```

`usage_billing_repo.go`はPostgreSQLトランザクション内で、`(request_id, api_key_id, request_fingerprint)`を重複排除テーブルへ挿入します。`ON CONFLICT DO NOTHING`によって同じ決済命令を無処理にし、残高更新とUsageLogを同一トランザクションで確定します。

### 4.5 多段認証キャッシュ

![多段認証キャッシュとインスタンス間無効化](/images/sub2api/auth-cache.png)

*多段認証キャッシュとインスタンス間無効化*

L1のRistrettoはホットパスからDBとネットワークI/Oを外します。SingleFlightは同一Keyの同時ミスを一つの問い合わせへ集約し、TTLのランダムな揺らぎは一斉失効を防ぎます。管理者がAPI Key、割当、ホワイトリスト、状態を変更した場合は、Redis Pub/Subが全インスタンスのL1キャッシュを即時無効化します。

## 5. マルチテナントのデータモデル

| エンティティ | 現実の役割 | 主な制御 |
|---|---|---|
| User | テナント・顧客 | 残高、全体同時実行、状態、利用可能Group |
| API Key | アプリケーション資格情報 | 所有者、Group、期限、IP許可、時間窓割当 |
| Group | 製品SKU・ルーティングポリシー | モデル、課金方式、倍率、利益率、RPM/TPM |
| Account | 上流の物理供給単位 | 資格情報、同時実行、優先度、負荷、健全性、制限状態 |
| UsageLog | 変更不可の利用事実 | Request ID、モデル、Token内訳、原価、課金額、Trace ID |

![主要エンティティの関係](/images/sub2api/entity-relationship.png)

*主要エンティティの関係*

`Group`は下流製品と上流供給を分離する重要な境界です。利用者は安定した製品定義を使い続け、運用側はクライアント設定を変えずにアカウントの交換、集約、価格変更、障害切替を行えます。

![製品グループの設定例](/images/sub2api/group-configuration.png)

*課金、モデル対応、セキュリティ制御を集約した製品グループ設定*

## 6. 容量再利用とSLA階層

ゲートウェイの事業価値は、従量マージン、統計的多重化、SLA別サービスから生まれます。サブスクリプションの供給能力は抽象的な月額ではなく、7〜14日間の実プロンプトから評価します。

```math
EquivalentValue = \sum SuccessfulTokens \times OfficialAPIPrice
```

等価価値に加え、成功率、P95 TTFT、429比率、実利用率を合わせて容量レポートを作ると、現実的なオーバーサブスクリプション上限とリセット考慮型スケジューリングを設計できます。

## 7. 企業AIエージェント基盤への適用

| 企業課題 | ゲートウェイの仕組み | 効果 |
|---|---|---|
| 社内同時実行の暴走 | テナントと上流の二重ゲート、Lua、TTL | インスタンス間の超過を防止し自動回復 |
| 複数供給元の障害切替 | 能力フィルター、EWMA、Top-K重み付きルーティング | 可用性、遅延、コストを同時に制御 |
| テナント分離 | User → API Key → Group → Account | 監査可能な境界と供給元交換 |
| 切断と再試行 | Contextキャンセルと一意な決済キー | 無駄な計算と二重課金を削減 |
| 異種モデルAPI | OpenAI互換プロトコルとProvider Adapter | 業務接続と原価計算を統一 |

![推奨する企業AIエージェントの実行アーキテクチャ](/images/sub2api/enterprise-agent-architecture.png)

*推奨する企業AIエージェントの実行アーキテクチャ*

ゲートウェイノードをステートレスにすれば水平拡張できます。会話メモリーと企業ナレッジをモデル供給から独立させることで、OpenAI、DeepSeek、プライベートモデル間を切り替えても業務資産を維持できます。共通の`request_id`を使えば、エージェント推論、ツール呼び出し、Token消費、課金記録を一つのトレースへ統合できます。

## 8. まとめ

Sub2APIは、本番志向のLLM接続層を理解するうえで優れた実装例です。堅牢なAI基盤には、SDK呼び出しだけでなく、ID抽象化、トラフィック制御、状態分離、原子的同時実行、ストリームのキャンセル伝播、トランザクション課金を分離しつつ協調させる設計が必要です。

## 主要ソース

- [ゲートウェイルートとミドルウェア](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/server/routes/gateway.go)
- [OpenAIプロトコル変換とストリーム転送](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/service/openai_gateway_forward.go)
- [アカウントプールスケジューラ](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/service/openai_account_scheduler.go)
- [Redis同時実行制御](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/repository/concurrency_cache.go)
- [認証キャッシュ](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/service/api_key_auth_cache_impl.go)
- [冪等な利用量課金](https://github.com/Wei-Shaw/sub2api/blob/9d5171c5d1d345f7e0cdacf0e3bc0aa360a15015/backend/internal/repository/usage_billing_repo.go)
