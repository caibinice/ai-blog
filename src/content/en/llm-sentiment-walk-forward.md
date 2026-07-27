---
title: Let large models do what they’re good at: sentiment factors, walk‑forward analysis, and out-of-sample testing
excerpt: I didn’t let the large model decide positions directly; instead, I first turn text into structured events that can be reviewed, then use out-of-sample experiments to see whether it adds incremental value.
---

When integrating a large model into a quantitative project, the most direct idea is to ask: “Will this stock go up or down?” The question is tempting because the answer looks like a final decision. But for a beginner it is also the hardest to verify: the model may cite wrong facts, time boundaries can get confused, and the same prompt might give different conclusions across model versions.

What makes it worse is that this framing fuses two different jobs: reading what happened out of the text, and judging what that event means for price. The first is language understanding, which the model is genuinely good at; the second is a decision loaded with cost, lag, and risk, which belongs to rules that a backtest can check. Bundling them into one question throws away the chance to verify each step on its own.

I later chose a more restrained path: let the large model do information extraction, not direct position control.

## Turning text into auditable events

When a news article or announcement comes in, the system first saves the original text, source link, publication time, and a content hash. The model reads the text and outputs:

- bullish, neutral, or bearish label;
- a normalized score;
- confidence level;
- a summary and the reasoning behind the judgment;
- model name and analysis timestamp.

These fields do not overwrite the original news; they form separate derived data. When I switch models or prompts later, I can re‑analyze and compare how different versions interpret the same text.

Separating "raw" from "derived" is a discipline I keep coming back to. The raw text is immutable evidence and carries its own publication time; the derived record is a recomputable interpretation and carries the model name and analysis time. The moment you write a model's judgment back onto the raw fields, you can no longer say which model version produced a given score, or when — which is exactly what a backtest needs to interrogate. The reason field is not decoration either: when an out‑of‑sample trade surprises me, I can follow the reasoning back to the source and tell whether the model misread a fact or the fact simply had no value.

The output contract can be as plain as this — fixed fields, easy to validate later:

```json
{
  "event_id": "sha1(raw_text)",
  "published_at": "2026-03-11T09:20:00Z",
  "source_url": "https://…",
  "label": "bullish",          // bullish | neutral | bearish
  "score": 0.62,               // normalized to [-1, 1]
  "confidence": 0.71,          // [0, 1], example value
  "summary": "…",
  "reason": "…",              // reviewable basis
  "model": "llm-vX",
  "analyzed_at": "2026-03-11T09:24:10Z"
}
```

The biggest value of this step is not that “AI is smart,” but that it turns natural‑language judgments into data that can be filtered, aggregated, tested, and questioned. A black box that only says "bullish" cannot be backtested; a table of events with timestamps, sources, and confidence can.

## Time remains the first rule

The publication time of the news must be earlier than the time the strategy makes a decision. That sounds obvious, but the implementation is full of traps: crawl time is not publication time, the same filing can land on different platforms hours apart, and if a backtest ever uses "when I fetched it" instead of "when it went public," it quietly introduces look‑ahead bias.

Duplicate re‑posts must be deduplicated; multiple reports of the same event cannot be treated as independent bullish signals. The content hash earns its keep here: near‑identical bodies collapse into one event, and syndicated copies are just duplicates of the same event, not three separate signals. Without dedup, a heavily re‑posted story gets counted again and again in the sentiment score, manufacturing a fake sense of "consensus strength."

Sentiment is not permanently valid either: a message from seven days ago usually shouldn’t carry the same weight as a just‑released announcement. So the system builds a decay window on event time, letting weight fall as a story ages, then aggregates sentiment scores by stock. One illustrative approach gives each event an exponential decay weight (the formula below is only an example; the half‑life must be chosen on the training segment, never fitted on the test segment):

```text
w(t) = exp(-λ · Δt)          # Δt = decision time − event time (days)
score_stock = Σ_i  w(t_i) · confidence_i · score_i   (sum over the stock's events)
```

![Sentiment time-decay window: weight falls as an event ages, and multiple reports of one event are deduplicated](/images/llm-sentiment-decay.svg)

Any backtest must make three moments explicit: when the news becomes visible, when it enters the factor, and when it starts affecting the next period’s position. I prefer to record them separately rather than vaguely say "I used this news." If the timeline order is wrong, even perfectly accurate text classification merely creates look‑ahead bias.

## Comparing “with AI” and “without AI”

Accurate labels do not guarantee trading value. The model can read a filing's sentiment perfectly, but if that information is already priced in, or the excess return it brings can't cover turnover cost, it adds nothing to the strategy. The only way to answer "does it help" is a controlled experiment.

In my experiments I first build a baseline that uses only market and financial factors, then add the sentiment factor, and compare them using the **same stock pool, same costs, and same window**. Controlling variables is the whole point: the only difference between the two arms should be the sentiment factor itself, otherwise a win tells you nothing about why. The dimensions I compare:

| Dimension | Baseline (no AI) | With sentiment | What I'm asking |
| --- | --- | --- | --- |
| OOS cumulative / annualized return | reference | comparison | is the increment positive |
| Max drawdown / volatility | reference | comparison | did I trade return for wider swings |
| Turnover / extra cost | reference | comparison | can the increment cover cost |
| Different market phases | reference | comparison | robust throughout or only one regime |
| Call cost / latency / fallback | — | to assess | is the engineering price worth it |

Leaving the cells without numbers is deliberate: those values must come from each pre‑designed experiment, not from writing a flattering conclusion first and reverse‑fitting to it. The last row is easy to forget — large‑model calls cost money, add latency, and sometimes fail, so there must be a fallback path (degrade to a neutral score, or reuse the previous result), and that overhead belongs in the "with AI" bill too.

If adding sentiment only improves the training period but degrades most test windows, the conclusion is not to keep tuning until the curve looks good, but to admit that the factor may not yet bring stable incremental value.

![Pipeline from news text to an auditable sentiment factor, then an out-of-sample baseline-vs-sentiment comparison](/images/llm-sentiment-pipeline.svg)

## Walk‑forward teaches me to accept imperfect results

Each walk‑forward window contains a training period followed by a test period. Parameters can only be selected during training; during testing the locked plan may only be run once. The final result is simply the concatenation of the out‑of‑sample returns from each segment. Its virtue is that it mimics the real information rhythm of trading: at each point you can only decide on data known then, never borrowing a pattern that only shows up in the future.

There is a subtle trap I've walked into: the test segment can be looked at only once. If a window disappoints and I go back to change the decay parameters and rerun the same test, that "out‑of‑sample" segment has already been seen and used for tuning — it has quietly become part of the training set. Out‑of‑sample results are persuasive precisely because they stay unfamiliar to the strategy until they are evaluated.

This workflow makes me more willing to keep failed windows. In the past I would view them as flaws of the model; now I am more likely to ask: did the market regime change, is the decay period wrong, is there a bias in text sources, or does the sentiment factor simply lack strong enough economic meaning? Each cause points to a completely different next step and can't be lumped into "the model is bad."

“6 out of 8 windows negative” is a fact; “the model is not large enough” is only an explanation. Between fact and explanation there is one experiment: the explanation must wait for the next pre‑designed test, and cannot be used to retroactively alter a test set that has already been seen. Treating an explanation as a conclusion is the mistake I make most easily and can self‑check the least.

## My current conclusion

In a quantitative system, large models are best suited for traceable information organizing, classification, and research assistance. Position and risk control should still be governed by explicit rules. The ultimate value must be validated through out‑of‑sample results and cost checks. Keep the model inside the "turn text into auditable data" cell, and its contribution stays additive, subtractable, and reproducible.

Restraint does not weaken AI. On the contrary, giving it a clearly bounded and verifiable responsibility is what lets me know what it actually contributes.

These methods are being continuously verified within the research loop of the [AI quantitative system](/quant/).

> This article only records my personal learning and research process and does not constitute investment advice.
