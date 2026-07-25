---
title: Before the Pretty Curve: The First Thing I Learned as a Quant Beginner Was to Distrust Backtests
excerpt: I used to treat backtests as answers; now I prefer to treat them as testimony that needs auditing—time, cost, sample, and parameters can all make them lie.
---

As a quantitative beginner, my earliest sense of achievement came from equity curves. Adjust a few windows, thresholds, and weights, and the curve could suddenly turn smooth and steep. In that moment, it’s easy to fall under the illusion that you’ve found a pattern.

One sentence from the course later changed my order of judgment: **Before the pretty curve, prove there is no cheating.**

## A same-day signal cannot earn same-day returns

The smallest and most common look-ahead bias often boils down to a single `shift(1)`.

Suppose I calculate a moving-average signal using today’s closing price. The signal can only be fully determined after today’s close, so normally it should only decide whether to hold on the next trading day. If I directly multiply today’s signal by today’s return, I am essentially learning how much the price rose today and then pretending I’ve been holding since the open.

Now I write a very small test for this kind of logic: construct three to five days of prices, let the signal appear only after the close of a particular day, and then assert that the strategy’s return can only start from the next period. The test doesn’t need real market data—its value is to fix the time semantics.

## Financial data has more than one date

The reporting period of an annual report might be December 31, but the market may not actually see it until March of the following year. If the backtest only uses `report_date`, you could use data in January that hasn’t been announced yet.

Therefore, financial data should keep at least:

- Which reporting period it describes;
- When the market could have obtained it;
- What the source is;
- Whether it’s a preliminary estimate, an express report, a formal report, or a revised version.

On every scoring date, you should only select records that were already available at that time. This “point-in-time” constraint looks like a database detail, but at its core it determines whether the researcher in the experiment has traveled through time.

## Gross returns do not belong to the real world

Commissions, stamp duties, slippage, and market impact costs can turn many high-turnover strategies from “excellent” to “unimplementable.” I no longer look only at gross returns; instead I compare at least a set of cost sensitivities:

1. Results under baseline costs;
2. Results after doubling the costs;
3. Results after lowering the rebalancing frequency;
4. How turnover, returns, and maximum drawdown change together.

If a strategy only works under extremely low cost assumptions, it looks more like a decoration in the data than a research hypothesis worth pursuing.

## The test set is not an answer sheet you can read over and over

Another pitfall that left a deep impression was continuing to adjust parameters when performance on the test period was poor. Even if every change is reasonable, as long as I repeatedly examine the same test results, they gradually participate in parameter selection and are no longer true out-of-sample data.

Walk-forward gave me a stricter process: in each window, compare candidate parameters only on the training segment, lock in the winning parameters, and run them once on the immediately following test segment. The final curve simply concatenates the out-of-sample returns from each window. Even if a test window loses money, you cannot change parameters on the spot, because the loss itself is evidence.

## How I read a curve now

When I see results, I first ask:

- Did the signal and the trade miss the correct timing?
- Were financial data, news, and the stock universe using the version available at the time?
- Have I factored in sufficiently conservative trading costs?
- Was the parameter grid fixed before the experiment?
- Does the final result rely only on data that didn’t take part in parameter selection?
- Does the report also include drawdown, turnover, per-window performance, and failure periods?

After studying quantitative methods, I haven’t become better at believing models; instead, I’ve become better at asking questions that make models uncomfortable. I think that’s progress: backtesting is not about proving how smart you are, but about discovering as early as possible where you might be wrong.

I’m also gradually embedding these checks into the research and audit process of my [AI quantitative system](/quant/).

> This article is a personal learning note and does not constitute investment advice.
