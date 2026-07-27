---
title: Before the Pretty Curve: The First Thing I Learned as a Quant Beginner Was to Distrust Backtests
excerpt: I used to treat backtests as answers; now I prefer to treat them as testimony that needs auditing—time, cost, sample, and parameters can all make them lie. This is the cross-examination I run.
---

As a quantitative beginner, my earliest sense of achievement came from equity curves. Adjust a few windows, thresholds, and weights, and the curve could suddenly turn smooth and steep. In that moment, it’s easy to fall under the illusion that you’ve found a pattern.

One sentence from the course later changed my order of judgment: **Before the pretty curve, prove there is no cheating.**

It demotes a backtest from a "result" to "testimony." Testimony can be true, or it can lie without meaning to, and my job is not to admire it but to cross-examine it like an auditor. The checks below are the questions I now ask most often.

## A same-day signal cannot earn same-day returns

The smallest and most common look-ahead bias often boils down to a single `shift(1)`.

Suppose I calculate a moving-average signal using today’s closing price. The signal can only be fully determined after today’s close, so normally it should only decide whether to hold on the next trading day. If I directly multiply today’s signal by today’s return, I am essentially finding out how much the price rose today and then pretending I’ve been holding since the open. This kind of error throws no exception and doesn’t make the curve ugly—on the contrary, it makes the curve prettier, which is exactly what makes it dangerous.

Now I write a very small test for this kind of logic: construct three to five days of prices, let the signal appear only after the close of a particular day, and then assert that the strategy’s return can only start from the next period. The test doesn’t need real market data—its value is to fix the time semantics. The illustrative pseudocode looks roughly like this:

```python
# Illustrative: prove the signal can only act on the next period
import pandas as pd

price = pd.Series([10, 10, 11, 12, 13])          # rise happens at index 2
raw_signal = (price > price.shift(1)).astype(int)  # known only after close
position = raw_signal.shift(1).fillna(0)         # the key: shift by one bar
ret = price.pct_change().fillna(0)
strat = position * ret

# assert: the rise is at index 2, so the return must land at index 3 onward
assert strat.iloc[2] == 0
assert strat.iloc[3] != 0
```

If someone later refactors the order logic and quietly drops that shift, this test turns red immediately. What it protects is not the return but the causal direction of time.

![Same-day signal look-ahead trap: signal(T) × return(T) peeks at today’s move, while shift(1) lets the signal act only on T+1](/images/trust-the-backtest-timing.svg)

## Financial data has more than one date

The reporting period of an annual report might be December 31, but the market may not actually see it until March of the following year. If the backtest only uses `report_date`, you could use data in January that hasn’t been announced yet.

Therefore, financial data should keep at least:

- Which reporting period it describes (`report_period`);
- When the market could have obtained it (`available_at`);
- What the source is (`source`);
- Whether it’s a preliminary estimate, an express report, a formal report, or a revision (`revision`).

With these columns, the query logic gains a hard constraint: on every scoring date `t`, select only records where `available_at <= t`, and among the qualifying versions take the latest one. A single reporting period often cycles through "preliminary → express → formal → revised." Keeping only one "final value" looks clean but actually stuffs a number you learned later back into the past. Revisions are especially treacherous: they hand a more accurate figure—one nobody knew at the time—back to your past self ahead of schedule.

This "point-in-time" constraint looks like a database detail, but at its core it determines whether the researcher in the experiment has traveled through time. My habit is to make it the default behavior of the storage layer, not a filter I remember at analysis time—because once forgotten, the backtest doesn’t error out, it just looks better.

## Gross returns do not belong to the real world

Commissions, stamp duties, slippage, and market impact costs can turn many high-turnover strategies from "excellent" to "unimplementable." I no longer look only at gross returns; instead I compare at least a set of cost sensitivities:

1. Results under baseline costs;
2. Results after doubling the costs;
3. Results after lowering the rebalancing frequency;
4. How turnover, returns, and maximum drawdown change together.

These tiers aren’t read in isolation; the point is the interaction between them. When costs double, what really gets eaten is the thin edge earned by frequent trading, so net return drops and drawdown deepens while turnover itself stays flat—a sign that the return leans heavily on a low-friction assumption. I also remind myself here that cost is not a fixed constant: market impact scales with order size and liquidity, and the slippage a small account can ignore may, at live-trading scale, be enough to consume the entire excess return. Lowering the rebalancing frequency checks it from the other direction: if returns don’t collapse once turnover is suppressed, the core of the strategy is the holding itself, not the feel of going in and out. The diagram below places the three tiers side by side; the directions only express the interaction and are not measured numbers:

![Cost sensitivity ladder: base cost, doubled cost, and lower turnover side by side, showing how return, max drawdown, and turnover move together](/images/trust-the-backtest-cost.svg)

If a strategy only works under extremely low cost assumptions, it looks more like a decoration in the data than a research hypothesis worth pursuing.

## The test set is not an answer sheet you can read over and over

Another pitfall that left a deep impression was continuing to adjust parameters when performance on the test period was poor. Even if every change is reasonable, as long as I repeatedly examine the same test results, they gradually participate in parameter selection and are no longer true out-of-sample data. This leak has no single "moment of cheating"; it accumulates quietly across many rounds of "let me try one more."

Walk-forward gave me a stricter process: in each window, compare candidate parameters only on the training segment, lock in the winning parameters, and run them once on the immediately following test segment. The final curve simply concatenates the out-of-sample returns from each window. Even if a test window loses money, you cannot change parameters on the spot, because the loss itself is evidence. Only with a lock between "choosing" and "checking" can I claim that segment of returns wasn’t contaminated by my hindsight.

The length of the training window is itself a parameter that must be decided beforehand rather than nudged after the fact: too short, and the chosen parameters merely fit recent noise; too long, and the window may straddle a shift in market regime. My approach is to write this choice into the process too—together with the rolling step size—and fix it up front, so it doesn’t become yet another hidden knob I keep probing.

## Beyond time, a few overlooked peeks

Apart from time semantics, the sample itself can peek at the future, and more subtly:

- **Survivorship bias**: if the universe contains only names still trading today, you’ve pre-removed the companies that later delisted or blew up, and every survivor in the backtest is a winner.
- **Halts and price limits**: a signal tells me to buy on a given day, but that day happens to be a locked limit-up or a trading halt, so in reality I can’t fill at all. If the backtest assumes I can always transact at the close, it pockets a batch of the fiercest moves for free.
- **Universe look-ahead**: using today’s sector classifications, index membership, or market-cap ranks to pick stocks years ago stuffs today’s labels back into the past.

What these traps share is that they all make the backtest more forgiving than reality—and forgiveness always leans toward a prettier curve.

## How I read a curve now

When I see results, I first ask—and behind each question I make the corresponding failure mode explicit:

- Did the signal and the trade miss the correct timing? — If so, a look-ahead bias is peeking at the same day.
- Were financial data, news, and the universe using the version available at the time? — If not, it’s a point-in-time leak or look-ahead.
- Have I factored in sufficiently conservative trading costs? — If not, gross returns overstate what’s executable.
- Was the parameter grid fixed before the experiment? — If not, I’m tuning on the test set.
- Does the final result rely only on data that didn’t take part in selection? — If not, "out-of-sample" is a misnomer.
- Does the report also include drawdown, turnover, per-window performance, and failure periods? — Reporting only one smooth curve is usually hiding something.

After studying quantitative methods, I haven’t become better at believing models; instead, I’ve become better at asking questions that make models uncomfortable. I think that’s progress: backtesting is not about proving how smart you are, but about discovering as early as possible where you might be wrong. The curve I’m willing to trust is usually not the steepest one, but the one that still stands after every question above has cross-examined it.

I’m also gradually embedding these checks into the research and audit process of my [AI quantitative system](/quant/).

> This article is a personal learning note and does not constitute investment advice.
