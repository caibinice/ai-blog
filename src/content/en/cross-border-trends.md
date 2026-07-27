---
title: Turning “Product Selection Gut Feel” Into Traceable Data: A Cross-Border Trends Daily
excerpt: Cross-border product selection isn’t about finding a screenshot of a hot-seller list—it’s about organising sources, trends, exchange rates, costs and AI judgements into decision materials you can rerun, and hold accountable, every day.
---

When selecting products for cross‑border e‑commerce, the most dangerous state is not having no information at all, but having plenty of information without being able to explain where it came from: a short video suddenly goes viral, a platform leaderboard looks hot, a supplier claims a certain category is growing. All of these may hold value, but if you can’t answer “when, from where and how was this calculated”, they are difficult to turn into a stable basis for decisions.

Worse, this kind of “feeling” tends to get amplified as it spreads: a screenshot gets forwarded, the framing gets simplified, the timestamp gets dropped, and eventually nobody can say which market, which day or which price band it originally came from. By the time you actually stock inventory and buy ads, the basis has quietly gone stale.

The goal of the cross‑border trends report project is to turn that scattered “feeling” into a daily digest that is traceable and repeatable—where every recommendation can be traced back to its source, and every number back to how it was calculated.

## Start with multi‑source collection, not with AI

The system combines Google Trends RSS, public WooCommerce product catalogues, the Frankfurter exchange rate, and sources like Rakuten, Yahoo Shopping and Rainforest that are enabled based on credentials. Every candidate product keeps its source link, original title, image, market, currency and collection timestamp. Those fields are the foundation of everything traceable later; drop one and the record only “looks like” evidence.

The sources differ a lot in shape: some are RSS, some are REST, some need credentials and rate limits. So the first job of the collection layer is adaptation: each source is wrapped as a uniform `SourceAdapter` that exposes a single action—“fetch a batch of candidates”—while handling auth, pagination and field mapping internally. The scheduling, deduplication and conversion above it never have to care about any one platform’s protocol.

For scheduling I use fixed-frequency dynamic tasks rather than hard-coding cycles in code—when a source slows down or is temporarily disabled, I change config, not a release. Deduplication uses “source + external ID + market” as an idempotency key, so products collected twice on the same day are merged, not stacked, and the same item never shows up twice in a ranking.

Whether a collection run “fully succeeded” must be recorded, not guessed. Each run writes an audit entry: start time, source, candidate count, success or failure, and the reason for failure. If one source is down today, the daily report won’t pretend it’s still there—it will clearly show that source as absent.

```text
CollectionRun
  ├─ source        Rakuten / Yahoo / WooCommerce ...
  ├─ startedAt     when the run began
  ├─ fetched       candidates retrieved this run
  ├─ status        SUCCESS | PARTIAL | FAILED
  └─ note          failure reason / rate limit / missing credentials
```

The Spring Boot backend handles data‑source adapters, scheduling, deduplication, currency conversion and profit modelling; MySQL stores trend signals, the product pool, daily reports, market configurations, collection audit records and admin permission data. The Vue frontend is split into a public product‑selection cockpit and a standalone admin console. I want the system to answer at any moment: exactly which source today’s recommendation comes from, which exchange rate was used, how shipping and platform fees were calculated, and whether the collection tasks completed successfully.

![Pipeline from multi-source collection to a traceable daily report](/images/cross-border-trends-pipeline.svg)

## AI is a standardisation layer, not a data source

Product titles from different platforms often mix brands, specs, marketing phrases and language differences: the same wireless earbuds might appear once as a long promotional string and elsewhere as just a model number. DeepSeek is mainly used here for title standardisation, category grouping and explaining candidate ranking—it doesn’t create “hot products” out of thin air. It only ever processes data that has already been collected; it never manufactures data.

When the large language model is unavailable, source data can still enter the system, which falls back to deterministic Chinese categories and rules. The fallback isn’t “degrade to unusable”; it swaps in a predictable, deterministic path: map keywords to fixed categories, sort by known rules. The result is stable and reproducible—it just lacks the natural-language polish.

```text
Standardise one candidate:
  if LLM available:
      title → normalised title, unified category, ranking rationale
  else (timeout / error / not configured):
      title → keyword rules mapped to a deterministic category
      rank  → existing weight rules, no model call
  both paths write to the same product table, tagged normalizedBy = ai | rule
```

This design avoids a common illusion: as long as the AI output is fluent enough, the data must be real. Fluency is a language model’s default ability; it has nothing to do with whether the data is correct. I’ve seen too many “professional-looking” analyses that fall apart once you trace them down to a source that was never there. For me, an AI judgement must always be attached to a known source—the model can help organise and compare, but it can’t replace the evidence gathered from collection. So every candidate records whether it was standardised by AI or by rule, which lets me tell a collection problem apart from a processing one.

## Profit modelling is closer to a real decision than popularity rankings

Just because a product is hot doesn’t mean it’s worth selling. The daily report feeds purchase price, exchange rate, shipping, platform fees, payment fees, taxes and advertising costs into the same profit calculation, then compares selling prices and gross margins across markets. Popularity only answers “is anyone looking”; profit answers “how much is actually left after the sale”.

The full formula is really just one long subtraction:

```text
gross margin = sell price
             − purchase cost
             − FX conversion loss
             − shipping
             − platform fee
             − payment fee
             − tax
             − advertising cost
margin rate  = gross margin / sell price
```

![Profit waterfall: subtracting every cost from the sell price down to gross margin](/images/cross-border-trends-profit.svg)

Drawn as a waterfall it’s clearer: the sell price is the full bar on the left, each cost is a step downward, and what’s left at the far right is the margin. What actually eats the profit is often not the most visible purchase cost, but the platform, payment and advertising fees stacked together—each one looks small, but together they can turn a “hot product” into a loss.

Put the same product in different markets and every term in that subtraction shifts: the sell price moves with local demand, the FX rate settles daily, platform fees and taxes differ by market rule. So the report does a side-by-side comparison—the same candidate can have one margin rate in market A and a very different one in market B:

| Item | Market A (example) | Market B (example) |
| --- | --- | --- |
| Sell price | 100 | 92 |
| Purchase + shipping | 52 | 52 |
| Platform + payment + tax | 18 | 15 |
| Advertising | 12 | 10 |
| Margin rate | 18% | 16% |

The numbers above are illustrative, meant to show that “same item, different market, different margin structure”—not any measured result.

This model is still an estimate: real return rates, warehousing, inventory turnover and ad bidding will continue to shift the result. But making the assumptions explicit and configurable already takes you a step beyond just staring at sales rankings. Every time freight or fee rates change, the historical reports and calculation parameters can be traced too—if today’s margin differs from last week’s, I can find out whether the FX moved or whether I changed a rate myself.

## The admin panel isn’t decoration

The admin console supports configuring users, roles, menus, tenants, markets, categories, data sources and collection frequencies. None of this is ornamental: markets and categories define the collection scope, data sources and frequencies define what runs each day and how often, roles and menus define who gets to change any of it. Configuration is behaviour—change one frequency and tomorrow’s report changes.

In production, JWT login is enforced, passwords are hashed with BCrypt, and deletions and configuration changes leave audit records. Why audit deletions too? Because product selection is a chain of judgements: if someone quietly removes a data source or edits a fee rate with no record, the report’s changes become impossible to explain. The point of the audit isn’t to police anyone—it’s to make every change in the calculation traceable in hindsight.

## Restraint on a small server

On a 2 GB server, I haven’t introduced message brokers, container orchestration or extra caching services. Not because I don’t know their benefits, but because at the current scale I haven’t hit the problems they solve. Dynamic scheduling, idempotent tasks and a small connection pool are enough: the workload is bounded, idempotency makes reruns safe, and a small pool actually keeps the database from being starved of connections.

Adding a broker means raising another component that has to be monitored, can fail, and consumes memory. On a machine with only 2 GB, that cost is real. Complexity is only worth introducing when it solves a clear problem—if collection volume ever crushes the single machine, I can split things async and add a queue then, with real bottleneck data to back the decision instead of architecting on imagination.

## The honesty of an estimate

I want to state this plainly: this report gives you an estimate, not a promise. Real return rates, warehousing costs, inventory turnover and ad bidding all keep changing the final result in places I can’t see. Any one of them can drag a beautiful margin rate back down to earth.

So I’d rather lay the assumptions out in the open than chase a number that “looks certain”. Shipping, fees, tax rates and assumed ad costs are all configurable parameters in the admin panel, not constants buried in code. That has two benefits: anyone can see which assumptions a recommendation rests on, and when reality and the estimate diverge, I can go back and adjust that specific assumption rather than tear down the whole system.

An honest estimate is more useful than a precise illusion.

You can see the running cockpit at [/crossBorderTrend/](/crossBorderTrend/). It isn’t a “hot‑product guarantee machine”—it’s a workbench that lays the judgement process out in the open.
