---
title: Engineering a Trustworthy AI Quantitative Research System
excerpt: Building a robust quantitative research platform with state machine persistence, data versioning, and auditable execution across collection, factor mining, backtesting, and learning.
---

When building quantitative trading systems, backtest equity curves and annualized returns are often the most noticeable metrics. However, in practical engineering, system reliability depends on much more fundamental data and execution guarantees: deterministic timestamps during data acquisition, safe retrievability for failed jobs, traceable model inference, and strict prevention of look-ahead bias.

To address these core engineering requirements, this project is built as a reproducible research platform rather than a simple stock-picking tool. Whether encountering data revisions or runtime exceptions, the system maintains clear state transitions and audit logs.

## Complete Research Lifecycle Architecture

The frontend is built with Vue 3 + Vite, displaying market dashboards, universe selectors, factor rankings, sentiment events, strategy backtests, walk-forward analysis, job status monitoring, and experimental courses. The backend utilizes FastAPI to provide clean RESTful endpoints; resource-intensive data synchronization, LLM inference, and backtesting are executed asynchronously by an independent worker process; MySQL serves as the persistent store for business entities, state machines, data versions, and learning progress.

The lifecycle of a typical research task includes the following stages:

1. The frontend submits research parameters, and the API creates a task record with the initial state `queued`;
2. An independent worker claims the task, atomically updating its status to `running`;
3. Data ingestion, news sentiment extraction, or multi-factor backtesting executes while streaming progress updates;
4. On success, structured metrics are persisted; on failure, detailed stack traces are captured to facilitate manual retries;
5. Upon service restarts or page refreshes, task states remain intact due to database persistence.

![Data flow and lifecycle of a research task: Frontend → FastAPI → single Worker → MySQL, with persistent state and retryable failures](/images/ai-quant-system-flow.svg)

In resource-constrained environments (such as a 2-core, 2GB RAM server), the system operates in a single-worker serial execution model. This design prevents memory spikes caused by concurrent market fetching, LLM API calls, and pandas matrix computations, while keeping diagnostic overhead low.

## State Machine and Persistence Mechanism

Abstracting computation tasks into state machine objects with full lifecycles forms the bedrock of system stability. Every state transition corresponds to an explicit database transaction: `queued` upon submission, `running` upon claiming, and `success` or `failed` upon termination.

Database-backed persistence provides distinct fault-tolerance advantages: worker crashes, system reboots, or maintenance interruptions do not lead to state loss. Upon reboot, tasks marked as `running` without an active process are identified as interrupted and can be requeued, while existing `success` and `failed` records remain unchanged.

![Research task state machine: queued → running → (success or failed), failures retry back to queued, successes persist to the database](/images/ai-quant-system-state.svg)

When a task fails, the system records structured error messages (such as upstream timeouts, suspended tickers causing missing data, or abnormal date ranges) directly into the record to streamline post-mortem analysis.

Retry mechanisms must ensure idempotency. Before restarting a failed job, the system purges intermediate derived data and temporary outputs from prior runs; raw market feeds are incrementally backfilled rather than overwritten. A representative state transition pattern is shown below:

```python
# Task state transition logic example
def run_task(task):
    task.mark("running")            # Claim task and persist state
    try:
        clean_previous_outputs(task)  # Clean previous derived artifacts for idempotency
        result = execute(task)        # Execute ingestion / sentiment / backtest
        task.save(result)             # Persist structured metrics
        task.mark("success")
    except Exception as e:
        task.mark("failed", error=readable(e))  # Record formatted diagnostic error
```

## Data Versioning and Reproducibility

If a system only stores the latest data snapshots, historical backtests cannot be accurately reproduced once underlying data shifts. To prevent this, data ingestion is structured around identifiable batches, allowing backtesting engines to pin specific historical versions.

Versioning ensures that strategy research stands on deterministic grounds. When comparing strategy performance across different time windows or data providers, historical batches can be directly indexed, guaranteeing experiment reproducibility.

## LLM Information Extraction and Separation of Concerns

The system deploys large language models specifically for structured text extraction: given news and regulatory filings, the model outputs bullish, neutral, or bearish sentiment labels, accompanied by normalized scores, confidence metrics, concise summaries, and reasoning points. Results are persisted alongside model identifiers and analysis timestamps, while the original raw text remains untouched.

A sample structured extraction result is formatted as follows:

```json
{
  "label": "bullish",
  "score": 0.62,
  "confidence": 0.71,
  "summary": "raised quarterly revenue guidance",
  "reason": "the filing expects next-quarter shipments above consensus",
  "model": "llm-extractor",
  "analyzed_at": "2026-05-11T09:20:00Z"
}
```

System design adheres strictly to the rule: "raw data is immutable; derived features are recomputable." The raw text serves as the ground truth. Sentiment scores and labels are derived features; whenever prompts are refined or underlying models are upgraded, the extraction pipeline can be re-run over historical corpora to produce fresh feature sets.

This separation of concerns establishes clear modular boundaries:

- LLMs focus on semantic understanding and information extraction from unstructured text;
- Position sizing and portfolio management are handled entirely by deterministic factor computation and backtesting routines.

Deterministic code guarantees identical outputs for identical inputs, preventing non-deterministic variations from propagating into decision layers.

## Structured Learning Curriculum and Interactive Labs

The platform integrates an eleven-chapter progressive curriculum with interactive labs, spanning candlestick fundamentals, Python/pandas time series manipulation, trustworthy backtesting standards, sentiment factor construction, walk-forward validation, and quantitative system architecture. Learning progress is cached locally in the browser and synchronized with MySQL when connected.

The curriculum follows a bottom-up pedagogical approach: establishing rigorous temporal and causality rules (avoiding look-ahead and survivorship biases), progressing to text factor mining, and concluding with robust out-of-sample evaluation.

## Scope and Live Trading Boundaries

This project focuses on research methodologies and instructional experimentation; it does not include brokerage connectivity or automated execution. Live trading entails complex market microstructure challenges—including trading halt handling, limit-up/limit-down liquidity constraints, market impact models, slippage dynamics, and disconnect recovery. Until such live trading infrastructure is thoroughly tested, the system remains strictly dedicated to backtesting and simulation.

You can explore the live research environment at [/quant/](/quant/).

> This project and its contents are for technical research and learning purposes only and do not constitute financial advice.
