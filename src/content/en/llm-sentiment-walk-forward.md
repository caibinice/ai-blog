---
title: Let large models do what they’re good at: sentiment factors, walk‑forward analysis, and out-of-sample testing
excerpt: I didn’t let the large model decide positions directly; instead, I first turn text into structured events that can be reviewed, then use out-of-sample experiments to see whether it adds incremental value.
---

When integrating a large model into a quantitative project, the most direct idea is to ask: “Will this stock go up or down?” The question is tempting because the answer looks like a final decision. But for a beginner it is also the hardest to verify: the model may cite wrong facts, time boundaries can get confused, and the same prompt might give different conclusions across model versions.

I later chose a more restrained path: let the large model do information extraction, not direct position control.

## Turning text into auditable events

When a news article or announcement enters the system, we first save the original text, source link, publication time, and a content hash. The model reads the text and outputs:

- bullish, neutral, or bearish label;
- a normalized score;
- confidence level;
- a summary and the reasoning behind the judgment;
- model name and analysis timestamp.

These fields do not overwrite the original news; they form separate derived data. When I switch models or prompts later, I can re‑analyze and compare how different versions interpret the same text.

The biggest value of this step is not that “AI is smart,” but that it turns natural‑language judgments into data that can be filtered, aggregated, tested, and questioned.

## Time remains the first rule

The publication time of the news must be earlier than the time the strategy makes a decision. Duplicate re‑posts must be deduplicated; multiple reports of the same event cannot be treated as independent bullish signals. Sentiment is not permanently valid either: a message from seven days ago usually shouldn’t carry the same weight as a just‑released announcement.

Therefore, the system constructs decay windows based on event time, then aggregates sentiment scores by stock. Any backtest must make it explicit when the news becomes visible, when it enters the factor, and when it starts affecting the next period’s position.

If the timeline order is wrong, even perfectly accurate text classification merely creates a look‑ahead bias.

## Comparing “with AI” and “without AI”

Accurate labels do not guarantee trading value. In my experiments I first build a baseline that uses only market and financial factors, then add the sentiment factor, and compare them using the same stock pool, costs, and window:

- out‑of‑sample cumulative and annualized returns;
- maximum drawdown and volatility;
- turnover and extra transaction costs;
- performance across different market phases;
- cost, latency, and failure fallback of large model calls.

If adding sentiment only improves the training period but degrades most test windows, the conclusion is not to keep tuning until the curve looks good, but to admit that the factor may not yet bring stable incremental value.

## Walk‑forward teaches me to accept imperfect results

Each walk‑forward window contains a training period followed by a test period. Parameters can only be selected during training; during testing the locked plan may only be run once. The final result is simply the concatenation of the out‑of‑sample returns from each segment.

This workflow makes me more willing to keep failed windows. In the past I would view them as flaws of the model; now I am more likely to ask: did the market regime change, is the decay period wrong, is there a bias in text sources, or does the sentiment factor simply lack strong enough economic meaning?

“6 out of 8 windows negative” is a fact; “the model is not large enough” is only an explanation. Explanations must wait for the next pre‑designed experiment; they cannot be used to retroactively alter a test set that has already been seen.

## My current conclusion

In a quantitative system, large models are best suited for traceable information organizing, classification, and research assistance. Position and risk control should still be governed by explicit rules. The ultimate value must be validated through out‑of‑sample results and cost checks.

Restraint does not weaken AI. On the contrary, giving it a clearly bounded and verifiable responsibility is what lets me know what it actually contributes.

These methods are being continuously verified within the research loop of the [AI quantitative system](/quant/).

> This article only records my personal learning and research process and does not constitute investment advice.
