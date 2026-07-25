---
title: From Engineering Loop to Trustworthy Research: My AI Quantitative System
excerpt: Instead of starting with "predicting what will go up tomorrow," I first connected data, tasks, factors, backtesting, and learning records into an auditable chain of evidence.
---

When I first began exploring AI-driven quantitative strategies, I was most attracted by the results: an upward-sloping equity curve, a set of impressive return metrics, or a claim that "the model has discovered market patterns." After actually building things myself, I realized that the hardest part of a quant project is not writing down some formula, but answering a series of more down-to-earth questions: When was the data obtained? If a task fails, can it be re-run? Can a model's judgment be traced? Does the backtest peek into the future?

So instead of turning this project into an isolated stock-picking page, I built it as a research system.

## A Complete Research Loop

The front end uses React and Vite to present market data, stock pools, factor rankings, sentiment, backtests, walk-forward analysis, task status, and learning courses. The FastAPI backend only serves clear API responsibilities; the truly time-consuming data synchronization, model analysis, and backtesting are handled by independent workers. MySQL is not just a result warehouse—it also stores task states, data versions, and learning progress.

The life cycle of a research task looks like this:

1. The research parameters are submitted through the page, and the API records the task as `queued`;
2. A worker picks up the task, updating its status to `running`;
3. Data collection, sentiment analysis, or backtesting gradually writes back their progress;
4. On success, structured results are saved; on failure, a readable error is logged and the task can be retried;
5. After a page refresh or service restart, the task status remains intact.

This design does not pursue dramatic throughput. The server only has 2 cores and 2 GB of memory, and a single worker executing tasks serially is actually more controllable: it prevents market data fetching, large model requests, and pandas backtesting from creating memory spikes at the same time, and it makes it easier to pinpoint which layer failed.

## Letting AI Handle “Auditable Judgments”

I mostly place the large language model at the structured extraction layer for news and announcements: it outputs a bullish, neutral, or bearish label, along with a score, confidence level, summary, and rationale. The model's results are saved together with the model name and analysis timestamp, while the original text is preserved.

This allows me to examine two things separately:

- What exactly the model read from the text;
- How the strategy uses this structured information.

Position sizing and trading rules remain the responsibility of deterministic factor combinations and backtesting code. This approach may not be “fully automated,” but it lets me find evidence when results look abnormal, rather than facing a black box that only gives a conclusion.

## A Research System Should Also Be a Learning System

I also included eleven chapters of beginner-friendly courses and runnable experiments in the project. They start with candlestick charts, Python, and pandas, and progress all the way to trustworthy backtesting, sentiment factors, walk-forward analysis, and research engineering. Learning progress is first saved in the browser and synced to MySQL when the API is available.

I increasingly agree with a view: the real achievement is not that a single backtest produced a high return, but that tomorrow, with a different batch of data, a different time window, or even a different machine, I can still explain the experiment, reproduce it, and acknowledge its limitations.

## Current Boundaries

This system is only for research and teaching; it does not connect to any brokerage and will not execute real trades. Trading suspensions, price limits, impact costs, capacity, data licensing, and real-time fault recovery all require far stricter handling than a teaching system. Until that work is done, “auto-ordering” is not progress—it is leaping beyond the evidence.

You can open the currently running version at [/quant/](/quant/). It feels more like a continuously renovated laboratory than a machine that promises answers.

> This project and article are for learning and research only and do not constitute any investment advice.
