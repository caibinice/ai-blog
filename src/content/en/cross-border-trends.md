---
title: Turning “Product Selection Gut Feel” Into Traceable Data: A Cross-Border Trends Daily
excerpt: Cross-border product selection isn’t about finding a screenshot of a hot-seller list—it’s about organising sources, trends, exchange rates, costs and AI judgements into decision materials that can be rerun every day.
---

When selecting products for cross‑border e‑commerce, the most dangerous state is not having no information at all, but having plenty of information without being able to explain where it came from: a short video suddenly goes viral, a platform leaderboard looks hot, a supplier claims a certain category is growing. All of these may hold value, but if you can’t answer “when, from where and how was this calculated”, they are difficult to turn into a stable basis for decisions.

The goal of the cross‑border trends report project is to turn that scattered “feeling” into a daily digest that is traceable and repeatable.

## Start with multi‑source collection, not with AI

The system combines Google Trends RSS, public WooCommerce product catalogues, the Frankfurter exchange rate, and sources like Rakuten, Yahoo Shopping and Rainforest that are enabled based on credentials. Every candidate product keeps its source link, original title, image, market, currency and collection timestamp.

The Spring Boot backend handles data‑source adapters, scheduling, deduplication, currency conversion and profit modelling; MySQL stores trend signals, the product pool, daily reports, market configurations, collection audit records and admin permission data. The Vue frontend is split into a public product‑selection cockpit and a standalone admin console.

I want the system to be able to answer at any moment: exactly which source today’s recommendation comes from, which exchange rate was used, how shipping and platform fees were calculated, and whether the collection tasks completed successfully.

## AI is a standardisation layer, not a data source

Product titles from different platforms often mix brands, specs, marketing phrases and language differences. DeepSeek is mainly used here for title standardisation, category induction and reasons for candidate ranking—it doesn’t create “hot products” out of thin air.

When the large language model is unavailable, source data can still enter the system, which falls back to deterministic Chinese categories and rules. This design avoids a common illusion: as long as the AI output is fluent enough, the data must be real.

For me, an AI judgement must always be attached to a known source. The model can help organise and compare, but it can’t replace the evidence gathered from collection.

## Profit modelling is closer to a real decision than hot‑rankings

Just because a product is hot doesn’t mean it’s worth selling. The daily report feeds purchase price, exchange rate, shipping, platform fees, payment fees, taxes and advertising costs into the same profit calculation, then compares selling prices and gross margins across markets.

This model is still an estimate: real return rates, warehousing, inventory turnover and ad bidding will continue to shift the result. But making the assumptions explicit and configurable already takes you a step beyond just staring at sales rankings. Every time freight or fee rates are changed, the historical reports and calculation parameters can be traced too.

## The admin panel isn’t decoration

The admin console supports configuring users, roles, menus, tenants, markets, categories, data sources and collection frequencies. In production, JWT login is enforced, passwords are hashed with BCrypt, and deletions and configuration changes leave audit records.

On a 2 GB server, I haven’t introduced message brokers, container orchestration or extra caching services. Dynamic scheduling, idempotent tasks and a small connection pool are already enough for the current scale. Complexity is only worth introducing when it solves a clear problem.

You can see the running cockpit at [/crossBorderTrend/](/crossBorderTrend/). It isn’t a “hot‑product guarantee machine”—it’s a workbench that lays the judgement process out in the open.
