---
title: From Engineering Loop to Trustworthy Research: My AI Quantitative System
excerpt: Instead of starting with "predicting what will go up tomorrow," I first connected data, tasks, factors, backtesting, and learning records into an auditable chain of evidence—this is a walk through every link.
---

When I first began exploring AI-driven quantitative strategies, I was most attracted by the results: an upward-sloping equity curve, a set of impressive return metrics, or a claim that "the model has discovered market patterns." After actually building things myself, I realized that the hardest part of a quant project is not writing down some formula, but answering a series of more down-to-earth questions: When was the data obtained? If a task fails, can it be re-run? Can a model's judgment be traced? Does the backtest peek into the future?

None of these questions are glamorous, yet they decide whether a system can be trusted at all. So instead of turning this project into an isolated stock-picking page, I built it as a research system—one that can be reviewed, reproduced, and made to hand over its evidence when I find something wrong.

## A Complete Research Loop

The front end uses React and Vite to present market data, stock pools, factor rankings, sentiment, backtests, walk-forward analysis, task status, and learning courses. The FastAPI backend only serves clear API responsibilities; the truly time-consuming data synchronization, model analysis, and backtesting are handled by independent workers. MySQL is not just a store for results—it also holds task states, data versions, and learning progress.

The life cycle of a research task looks like this:

1. The research parameters are submitted through the page, and the API records the task as `queued`;
2. A worker picks up the task, updating its status to `running`;
3. Data collection, sentiment analysis, or backtesting gradually writes back their progress;
4. On success, structured results are saved; on failure, a readable error is logged and the task can be retried;
5. After a page refresh or service restart, the task status remains intact.

![Data flow and lifecycle of a research task: Frontend → FastAPI → single Worker → MySQL, with persistent state and retryable failures](/images/ai-quant-system-flow.svg)

This design does not pursue dramatic throughput. The server only has 2 cores and 2 GB of memory, and a single worker executing tasks serially is actually more controllable: it prevents market data fetching, large model requests, and pandas backtesting from creating memory spikes at the same time, and it makes it easier to pinpoint which layer failed.

## The State Machine Is the Foundation

Treating a task as a stateful object rather than a one-shot function call is the single most important decision here. Each state corresponds to an explicit write to the database: `queued` on submission, `running` on claim, and `success` or `failed` on completion. State does not live in some process's memory—it lives as a row in the database.

That yields a benefit that is easy to overlook: the process is allowed to die at any moment. A worker crash, a machine restart, or me killing the service by accident—none of it takes the task state down with it. After a restart, a task still marked `running` with no live process behind it is treated as interrupted and can be re-queued; `success` and `failed` are kept as they were. In other words, "state survives a restart" is not a slogan but the natural consequence of the decision to put state in the database.

![Research task state machine: queued → running → (success or failed), failures retry back to queued, successes persist to the database](/images/ai-quant-system-state.svg)

I deliberately made the failure step verbose. When a task fails, I don't just flip the status to `failed`; I also write a human-readable error into the same row—a data-source timeout, a suspended ticker leaving a gap, an outlier inside the backtest window. When I come back the next day, I read *why* it failed, not a blank red dot.

Retries have to be idempotent. Re-running a task should not leave two half-finished results in the database. My approach is to have each run first clean up the derived data this task wrote before, then recompute; raw data is only filled in, never overwritten. Here is that transition sketched as pseudocode (illustrative only):

```python
# Illustrative: task state transitions, not real project code
def run_task(task):
    task.mark("running")              # claimed, written to DB
    try:
        clean_previous_outputs(task)  # keep retries idempotent
        result = execute(task)        # fetch / sentiment / backtest
        task.save(result)
        task.mark("success")          # structured result persisted
    except Exception as e:
        task.mark("failed", error=readable(e))  # readable error
        # do not swallow silently; leave it to a human or retry policy
```

## Data Needs Versions Too

If I only store "the latest data," then yesterday's backtest can never be honestly reproduced—because the ground under it has shifted. So I stamp data with an acquisition time and a version: one collection is an identifiable batch, and a backtest references a specific version rather than "whatever happened to be there at the time."

The value of this only shows up when I swap datasets. When I say "the experiment still reproduces on a different batch of data," the premise is that the old batch still exists and can be named. Data versioning isn't fancy; it just turns "reproducible" from a wish into a property I can actually check.

## Letting AI Handle "Auditable Judgments"

I mostly place the large language model at the structured extraction layer for news and announcements: it outputs a bullish, neutral, or bearish label, along with a score, confidence level, summary, and rationale. The model's results are saved together with the model name and analysis timestamp, while the original text is preserved.

The fields are deliberate. Beyond the label, I keep a score, a confidence, a summary, a rationale, the model name, and the analysis time. Every judgment then carries its own context: who produced it, when, with how much certainty, and based on which sentence. An illustrative extraction result looks roughly like this (fields are examples):

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

There is a principle I keep here: the source is immutable, the derived is recomputable. The original text is fact—once stored, it is never changed; labels and scores are all derived from it, so when the model or the prompt changes, I can re-run the same corpus and get a fresh set of derived results without ever contaminating the source.

This lets me examine two things separately:

- What exactly the model read from the text;
- How the strategy uses this structured information.

Position sizing and trading rules remain the responsibility of deterministic factor combinations and backtesting code. I drew this boundary on purpose: AI is good at reading a leaning out of unstructured text, but its output carries uncertainty; factor computation and backtesting, by contrast, must be deterministic—the same input always yields the same output, or the backtest loses its meaning. Let AI extract and let deterministic code decide, and the two kinds of error won't mask each other. This approach may not be "fully automated," but it lets me find evidence when results look abnormal, rather than facing a black box that only gives a conclusion.

## A Research System Should Also Be a Learning System

I also included eleven chapters of beginner-friendly courses and runnable experiments in the project. They start with candlestick charts, Python, and pandas, and progress all the way to trustworthy backtesting, sentiment factors, walk-forward analysis, and research engineering. Learning progress is first saved in the browser and synced to MySQL when the API is available.

The course is really a ladder of skills: first read a candlestick chart and handle time series with pandas, then understand what makes a single backtest "trustworthy" (no look-ahead, no survivorship bias), and only then turn sentiment into a factor and use walk-forward to test whether it is merely overfit—finally arriving at research engineering, the unglamorous base of tasks, state, and versions this whole article has been about. The order can't be reversed: chase factors before you trust your backtest, and what you catch is mostly self-deception.

I increasingly agree with a view: the real achievement is not that a single backtest produced a high return, but that tomorrow, with a different batch of data, a different time window, or even a different machine, I can still explain the experiment, reproduce it, and acknowledge its limitations.

## Current Boundaries

This system is only for research and teaching; it does not connect to any brokerage and will not execute real trades. This isn't laziness—it's because real order placement faces problems a teaching system simply hasn't handled seriously: what happens to an order during a trading halt, whether it fills at a price limit, how much impact cost a large order carries, where a strategy's capacity runs out, whether the data license even covers live use, and how to recover safely when the market feed drops. Any one of these can make a paper-pretty strategy lose money in a real market.

Until that work is done, "auto-ordering" is not progress—it is leaping beyond the evidence. I would rather leave this system parked where it can explain, reproduce, and trace than rush to wire it up to real money.

You can open the currently running version at [/quant/](/quant/). It feels more like a continuously renovated laboratory than a machine that promises answers.

> This project and article are for learning and research only and do not constitute any investment advice.
