---
title: Traceable Data Architecture for Cross-Border Trend Intelligence
excerpt: Integrating multi-source data ingestion, deterministic category normalization, and a profit waterfall model to deliver an auditable daily decision-support system.
---

In cross-border e-commerce product selection and market trend analysis, relying solely on isolated bestseller rankings or scattered media claims often leads to untraceable data sources, undefined metrics, omitted currency volatility, and disconnected fulfillment costs. Without clear tracking of timestamps, raw origins, and gross margin calculations, such information fails to serve as a reliable basis for inventory procurement and advertising spend.

The Cross-Border Trend Reporting system addresses these issues by aggregating fragmented cross-platform data into a daily, reproducible report, ensuring every product recommendation can be traced back to its raw source, reference exchange rates, and itemized cost breakdown.

## Multi-Source Ingestion and Adapter Layer Architecture

The system integrates Google Trends RSS feeds, public WooCommerce product catalogs, Frankfurter live exchange rates, and credential-based connectors for Rakuten, Yahoo Shopping, and Rainforest. For every candidate product, the system persists its source URL, original title, image assets, target market, currency, and ingestion timestamp to enable end-to-end data auditing.

Because data providers vary widely in protocol formats, authentication schemes, and rate limits, the ingestion layer encapsulates these differences behind a unified `SourceAdapter` interface. Authentication signatures, pagination, and schema mappings are handled internally, exposing only standardized batch retrieval methods to upper-level orchestration and deduplication logic.

Task scheduling is driven by dynamic database configurations rather than hardcoded intervals. Deduplication uses a composite idempotent key—`source + external_product_id + target_market`—preventing duplicate entries within the same cycle from distorting ranking weights.

Every ingestion run creates an explicit audit record (`CollectionRun`), capturing start time, source name, item count, status (SUCCESS / PARTIAL / FAILED), and diagnostic notes. When a source encounters network timeouts or credential errors, the daily report explicitly flags the missing status, ensuring complete data transparency.

```text
CollectionRun Audit Entity
  ├─ source        Data provider (Rakuten / Yahoo / WooCommerce, etc.)
  ├─ startedAt     Ingestion trigger timestamp
  ├─ fetched       Candidate items retrieved in this batch
  ├─ status        SUCCESS | PARTIAL | FAILED
  └─ note          Diagnostic reason / Rate limit notes / Credential status
```

The backend is built with Spring Boot, managing source adaptation, scheduling, deduplication, currency conversion, and the profit margin engine; MySQL stores trend signals, product pools, historical reports, market configurations, and audit logs; the Vue 3 frontend provides both an analytical cockpit and an administrative back-office.

![Pipeline overview: from multi-source collection to a traceable daily report](/images/cross-border-trends-pipeline.svg)

## LLM-Driven Normalization with Deterministic Fallbacks

Product listings across different platforms are frequently cluttered with marketing buzzwords, brand abbreviations, and multilingual text. The system employs large language models (such as DeepSeek) for title normalization, standardized category mapping, and ranking rationales, operating exclusively on persisted raw data without fabricating synthetic products.

To maintain high availability, a complete fallback mechanism is implemented: if LLM calls time out, exceed rate limits, or encounter exceptions, the pipeline automatically routes through local keyword dictionaries and regex rules for category classification, applying deterministic weighted sorting.

```text
Candidate Normalization Flow:
  IF LLM service is healthy:
      Raw Title → Standardized Title, Category Alignment, Ranking Rationale
  ELSE (Timeout / Error / Unconfigured):
      Raw Title → Keyword Dictionary Classification
      Ranking   → Deterministic Weighted Rules
  Both execution paths write to the product database with normalizedBy = ai | rule
```

This dual-track architecture guarantees that core business flows remain operational independently of external AI APIs. Storing the `normalizedBy` property (`ai` vs. `rule`) facilitates quality auditing and performance comparison.

## Profit Waterfall Model and Multi-Market Simulation

Product popularity alone does not indicate profitability. The daily report incorporates a profit waterfall model that accounts for purchase costs, FX gains/losses, international shipping, marketplace commissions, payment gateway fees, import tariffs/taxes, and estimated customer acquisition costs (CAC).

The gross margin calculation is formulated as:

```text
Gross Profit       = Listing Price
                   − Purchase Cost
                   − Currency Conversion Variance
                   − International Freight
                   − Marketplace Commission
                   − Payment Gateway Fees
                   − Import Tariffs & VAT
                   − Estimated CAC per Unit
Gross Margin Rate  = Gross Profit / Listing Price
```

![Profit waterfall: deducting costs step-by-step from selling price to reach gross profit](/images/cross-border-trends-profit.svg)

In cross-border scenarios, the profit structure of the same SKU varies significantly across target markets due to local price points, settlement exchange rates, category fee schedules, and customs tariffs. The system supports side-by-side market comparisons:

| Cost Component | Market A (Illustrative) | Market B (Illustrative) |
| --- | --- | --- |
| Local Selling Price (Base Equiv.) | 100 | 92 |
| Procurement + Logistics | 52 | 52 |
| Platform Fees + Payment + Tax | 18 | 15 |
| Estimated CAC | 12 | 10 |
| Estimated Gross Margin | 18% | 16% |

All shipping tiers, fee schedules, tax rates, and CAC assumptions are managed as configurable parameters in the administration console. When market conditions shift, recalculations can be triggered immediately, with historical calculations remaining fully traceable.

## Administrative Controls and Security Auditing

The administration console provides RBAC user management, multi-tenant/market settings, category taxonomy maintenance, data source connection management, and ingestion interval controls. Production deployments enforce JWT authentication with BCrypt password hashing, and all sensitive parameter updates and deletion actions are logged in audit tables.

## Single-Node Lightweight Engineering Constraints

In a resource-constrained 2GB RAM cloud environment, the system avoids heavy middleware (such as Kafka or distributed caches). Instead, lightweight dynamic schedulers, constrained database connection pools, and controlled single-node concurrency ensure low memory usage and long-term operational stability.

## Model Assumptions and Operational Boundaries

The metrics produced by this system represent static simulations based on configured parameters. In practical operations, factors such as return rates, overseas warehousing storage fees, inventory turnover velocity, and real-time ad bidding fluctuations will impact realized profitability. By maintaining transparent, parameterized assumptions, operations teams can continuously calibrate baselines to improve decision precision.

You can see the running cockpit at [/crossBorderTrend/](/crossBorderTrend/). It isn’t a “hot‑product guarantee machine”—it’s a workbench that lays the judgement process out in the open.
