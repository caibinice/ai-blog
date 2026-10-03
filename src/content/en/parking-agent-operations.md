---
title: Business orchestration and data integrity for a 3D parking agent
excerpt: A reproducible year of synthetic parking data, server-side roles, a maintainable POI graph and AG-UI turn an immersive scene into a practical recommendation, inspection and operations workspace.
---

The parking scene already has a detailed campus, animated wheels and a fixed-distance chase camera. This iteration adds business workflows without shrinking the full-screen canvas. Chat and operations remain hideable overlays. The backend reuses the enterprise cockpit's Spring Boot process, MySQL, pgvector and knowledge retrieval; no extra agent service is deployed.

[Desktop scene](/smartParking/) · [Mobile landscape scene](/smartParking/mobile) · [Frontend source](https://github.com/caibinice/3dSmartParking) · [Backend source](https://github.com/caibinice/enterprise-ai-cockpit)

![Parking recommendations inside the immersive scene](/images/parking-agent-recommendation.png)

## A reproducible annual ledger

Real device data is not readily available, so the generator derives patterns from [UCI Parking Birmingham](https://archive.ics.uci.edu/dataset/482/parking%2Bbirmingham). The original daytime observations come from Birmingham City Council/NCP and were prepared by Daniel Stolfi. They are partial 2016 observations, not a complete all-day series. Attribution, the source hash and license notes are retained in the repository.

Invalid capacities and out-of-range occupancy are removed. Weekday/weekend patterns are grouped into fifteen-minute slots. Explicit synthetic night curves, seasonal effects, zone factors and a fixed random seed extend the pattern into **365 days, 2025-10-03 through 2026-10-02**.

| Data | Rows | Purpose |
|---|---:|---|
| Zone occupancy snapshots | 105,120 | Availability and utilization |
| Anonymous parking stays | 167,906 | Arrivals, departures and fee ledger |
| Synthetic alerts | 365 | Inspection and work-order tests |

Zone capacities are A120, B100 and C80. Consecutive samples obey occupancy conservation:

```text
current occupancy = previous occupancy + arrivals - departures
0 <= occupancy <= capacity
```

Arrivals create anonymous stays; departures settle those stays. Fees use a separate synthetic policy, stored as integer cents. The public source has no fee ledger, and the generated charges are not a real hospital tariff. Revenue comes from settled `paid_cents`, never occupancy multiplied by an assumed ticket price.

```sql
SELECT COUNT(*) AS settled_stays,
       COALESCE(SUM(paid_cents), 0) AS paid_cents
FROM parking_stays
WHERE dataset_id = 'parking-year-v1'
  AND exited_at >= :from
  AND exited_at < :to_exclusive;
```

Source SHA256, seed and range make regeneration deterministic. Import is preceded by a database backup, uses immutable dataset IDs and idempotent keys, and verifies row counts. Every business view labels its synthetic source and sampling time; historical values are not presented as live sensor readings.

## Roles enforced by the server

Every parking GET and write endpoint resolves a signed principal. Named users are rechecked against the database. Passwords use BCrypt hashes and sessions last thirty minutes.

| Role | Capabilities |
|---|---|
| Visitor | Availability, recommendations, POIs, routes and visitor tours |
| Security | Alerts, recent events, work orders and confirmed scene-image queries |
| Operator | Fee ledger, period reports, global audits, approval and closure |
| Administrator | Accounts, knowledge initialization and graph configuration |

Visitor free-form questions use local parking knowledge without paid model calls. Staff default to Flash with thinking max; Pro remains an authenticated option. Editing browser role metadata does not change server permissions, and disabling an account invalidates its signed role session.

## POIs and explainable recommendations

The model outputs stable POI IDs rather than arbitrary coordinates. The versioned graph stores node kinds, zones, model coordinates, facility capabilities and closure states. Saves validate unique IDs, finite coordinates, legal edge endpoints and optimistic versions.

Dijkstra runs only over open nodes and edges. Distances are explicitly model estimates, not surveyed navigation. Closed or disconnected destinations return an error rather than a fabricated line. Recommendation first removes full, closed, inaccessible or preference-mismatched candidates, then scores walking distance, remaining spaces and a synthetic emergency reserve.

Charging requires zone B capability; emergency preference selects C. Ordinary requests reserve ten spaces in C. Candidates display distance, free spaces, reserve and reasoning. These amenities are zone-level demonstration configuration, not individual bay sensors.

## Confirmed work-order lifecycle

The agent's `workorder.prepare` produces a draft only. A person checks the alert, writes a note and explicitly confirms submission before database mutation.

```text
Pending review → Operator approval → Staff assignment
→ Verified resolution → Operator closure
```

Request keys prevent duplicate creation; an alert with an open order reuses that order. Transactions lock records and check versions, rejecting stale updates. No model tool bypasses review or operates a gate. Audits distinguish model plans from browser effects; scene feedback is labelled `client-result`, not a device acknowledgement.

## Reports use actual synthetic fee records

The operations panel filters dates and zones, displays capacity-weighted daily utilization, settled stays and synthetic receipts, and exports every daily row to CSV. The eighteen-row table is only a preview.

![Annual synthetic ledger analytics](/images/parking-agent-year-report.png)

Daily, weekly, monthly and yearly periods are anchored to the dataset's latest date. Monthly means that data month through the latest day; yearly covers the full 365 days. The existing cockpit process generates all four report caches at **02:15 Asia/Shanghai**, using database aggregation only, with no model calls. Data range and generation time are preserved.

## AG-UI as the interaction boundary

`/api/parking/ag-ui` emits standard run, text, tool-call and state-snapshot events. Named CUSTOM events carry reports, routes, drafts and references. The frontend validates every event with official `@ag-ui/core` schemas before applying the local tool whitelist.

```json
{
  "type": "TOOL_CALL_ARGS",
  "toolCallId": "action-0",
  "delta": "{\"target\":\"outpatient\"}"
}
```

The adapter implements the event set actually produced here; it does not invent unexecuted tool results. Nginx disables buffering and caching for SSE. Cancelling a request prevents later scene actions, and a response can retain multiple report cards.

## Explicit voice and vision controls

Single-shot, wake-word and continuous modes share the same role-bound tools. Continuous mode listens during processing; saying the assistant's wake phrase interrupts narration. Matching the current narration helps avoid echo-triggered commands. Microphone access is off by default and stops when the page goes into the background.

SpeechRecognition and speechSynthesis are browser services. Actual recognition and latency depend on browser support, microphone conditions and network access. Event-level regression tests verify interruption and release logic, not human speech accuracy.

Vision first captures and previews the 3D canvas, excluding chat and account fields. A staff member confirms transmission. The backend validates JPEG format, byte and pixel limits, and rejects arbitrary external image URLs. The image-capable `deepseek-flash` endpoint runs with thinking max, describes visible evidence only, triggers no tools and stores no image in the database. Real integration returned descriptions of roads, buildings and parking areas with checkable inspection suggestions.

## Knowledge and regression coverage

The isolated `smart-parking-agent-v2` knowledge domain updates the original five guides and adds eight covering data, roles, graph maintenance, recommendations, work orders, reports, voice/vision and evaluation. The old domain is retained. Search remains parking-scoped and inherits the cockpit's structured chunking and hybrid retrieval.

All thirty-two local API/workflow cases passed, including two real Flash plans. In SSH-tunnel integration, their first AG-UI event took approximately 63 ms; total sample durations were about 3.1 and 21.2 seconds. These are observations, not latency guarantees. Vision was verified separately. Twenty-one frontend regressions also retain vehicle heading, wheel motion and fixed chase-camera behavior.

The UI keeps the campus's blue-grey and teal palette, clear business verbs, visible keyboard focus and forty-pixel touch targets. Desktop and mobile retain detailed models and a full-screen canvas. Later device integration can replace the data adapter, surveyed graph and operational policy while preserving the protocol, permissions and regression suite.

## References

- [UCI data and licensing](https://archive.ics.uci.edu/dataset/482/parking%2Bbirmingham)
- [Dataset DOI](https://doi.org/10.24432/C51K5Z)
- [AG-UI event specification](https://github.com/ag-ui-protocol/ag-ui/blob/main/docs/spec/1.0/schema.mdx)
- [DeepSeek vision documentation](https://api-docs.deepseek.com/guides/vision/)
- [frontend-design skill](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md)
