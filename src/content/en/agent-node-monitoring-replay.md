---
title: Keeping an Execution Record for the Agent: Node Monitoring and Replay in the Smart Cockpit
excerpt: Add an ordered execution record to the full customer service graph: RAG, images, MCP, tool loops, expert collaboration, and human recovery can all be inspected. Then replay using event prefixes to distinguish observation, review, and continued execution.
---

After the workflow could return correct answers, I ran into a very practical problem: during technical sharing, the audience saw "599 yuan can be refunded" but still didn't know how it got there. Was the order actually checked? Why did it switch tools in the second round? What information did each of the three experts receive?

Backend logs could be checked, but when explaining, switching back and forth between the terminal and the web page quickly pulled attention away. So I added a structured execution record to the Smart Cockpit's Graph workbench: node transitions can be seen in real time, and after completion, you can pause at a certain step to see input and output. This article mainly records several easily confused boundaries in the implementation process.

The recorded object is the complete customer service main graph, not just the tool loop and multiple Agents highlighted during the demo. RAG, images, reports, human takeover, and the two feedback loops all pass through the same node wrapper and enter the same event sequence. Only then can the difference between "directly obtaining evidence" and "going through another round after failure" be compared in the same interface.

## First distinguish monitoring, replay, and recovery

![Smart Cockpit node graph and detail panel: highlights come from actual execution events](/images/cockpit-agent-monitor.png)

**Monitoring** is observing a task that the backend is executing. **Replay** is browsing existing records; the backend will not query orders or call models again. **Human recovery** submits new information and lets the backend continue executing the recovery graph, which generates new events.

"Pause replay" on the page only stops the frontend cursor; only "Stop current workflow" requests backend cancellation of the task. To avoid misunderstanding, "current status" in the details is also clearly marked as the latest status: it will not roll back with replay. Input and output of historical nodes can be viewed, but this version is not yet full state time-travel, and even less is it re-executing business logic from an arbitrary node.

## First check whether the record is sufficient from eight entry points

When accepting this, I didn't just look at whether nodes turned green, but looked for what actually happened according to scenarios:

| Scenario | What to verify in the same record |
|---|---|
| Product knowledge RAG | Knowledge sources, scores, and queries returned by `retrieve`; which evidence the answer used |
| Images and text | Whether `vision` image observations entered the next classification and retrieval context |
| Enterprise report MCP | The actual report result of `report_mcp`, not the model claiming "already checked" |
| Tool call loop | Tool name, parameters, observation result, and different Spans for each round of `tool_execute` |
| Multi-Agent collaboration | Three expert paths, outer parent Span, subgraph nodes, and final aggregation |
| Human takeover | `run.waiting`, handoff materials, `run.resumed`, and `human_reply`; prior actions are not repeated |
| Feedback-driven re-retrieval | There is indeed `requery` between two `retrieve` calls, and the query text does change |
| Tool exceptions and budget | Whether failed observations are retained; three rounds of recovery and two rounds of human handoff took different exits |

After each scenario ended, I reopened history, exported JSON, and used the same replay bar to go back to zero, then advanced to the completion node. During replay, no new model calls or order requests appeared. Tasks in human waiting could also be stopped, avoiding a demo record that had already been abandoned but still hung in waiting status.

Knowledge maintenance and sharing guide are workbench entry points, not two Agent nodes to be stuffed into the main graph: the former prepares retrievable materials, and the latter loads input. What needs monitoring is the execution facts after these inputs enter the Graph. Once this boundary is clear, page navigation, business execution, and call tracing are less likely to be mixed together.

## In the end I chose to record events rather than remotely manipulate node colors

Nodes uniformly pass through a wrapper. When entering a node, input is recorded; when ending, returned increments and elapsed time are recorded; when an exception is thrown, failure is recorded. The same logic wraps the main graph and expert graphs, so monitoring code does not need to be repeatedly written in every business function.

Below is trimmed-down logic, not a complete copyable class:

```java
String span = newSpanId();
emit("node.started", nodeId, path, span, input);
long started = System.nanoTime();
try {
    Map<String, Object> delta = businessStep(input);
    emit("node.completed", nodeId, path, span,
         Map.of("output", delta, "durationMs", elapsed(started)));
    return delta;
} catch (Exception e) {
    emit("node.failed", nodeId, path, span, publicError(e));
    throw e;
}
```

Model requests are recorded separately as started/completed/failed, along with model name, purpose, and token usage, with the parent Span pointing to the containing node. What is shown here is requests, public results, and structured decisions, not the model's internal thinking. The static definition of the graph is provided by `/api/workflow/graph`; node positions are preconfigured, and runtime events determine which edges were traversed and which node has completed.

I deliberately kept the term "state increment." `node.completed.output` only indicates which fields this node changed; if treated as the complete State, when reviewing later one may mistakenly think other fields were lost.

## In loops, node names are not enough

The tool branch passes through `tool_execute` twice, and the order expert also uses this name internally. If input and output are matched by nodeId, sooner or later the first round's input will be matched to the second round's result.

Now the record contains several identifiers at different levels:

| Field | What it distinguishes in the cockpit |
|---|---|
| traceId | The entire run; in this project it is the same as Run ID |
| nodeId | Business node, for example tool_execute |
| spanId | This specific execution, not the permanent ID of this node |
| parentSpanId | Which outer call a model request or child node belongs to |
| path | Main graph root, or an expert path such as root/toolAgent[3] |
| seq | Incrementing event sequence number within the same Run, used for resend and deduplication |

Input and output are paired by **spanId + path**. Expert lifecycle markers reuse the outer specialist's Span, but the paths differ; when pairing, adding path prevents retrieving the outer complete state. The `[3]` in the path is the task sequence number for this run, not a fixed third position for the order expert.

This also made me change another habit: directly summing all durations. The outer specialist's elapsed time already includes the subgraph; summing parent and child together double-counts. Page end-to-end elapsed time uses the event interval, while node elapsed time describes a single call or cumulative situation for nodes with the same name; the two have different definitions.

## From logs to SSE, the main concern is not missing a segment

Each Run stores sequentially appended events in `RunStore`. `emit` allocates seq, appends the record, and notifies subscribers within the Run lock. New subscriptions also happen under this lock: first resend history after the cursor, then join real-time subscription.

This handles a small but real race: if the lock were released after resending history and the subscriber were registered only later, events arriving in between might be received by neither side.

The cockpit's original backend is WebFlux, so during integration I did not continue using the demo project's MVC `SseEmitter`, but returned `Flux<ServerSentEvent<...>>`. The protocol is still simple:

```text
id: 19
event: trace
data: {"seq":19,"type":"node.completed","nodeId":"tool_execute",...}
```

The browser receives `trace` via `EventSource` and deduplicates by seq. On reconnection, the server takes the larger of `after` and `Last-Event-ID`, and only resends later events. During human waiting there are no business events; a 15-second heartbeat without ID keeps the proxy connection alive; after the five-minute stream ends, the browser can reconnect. The heartbeat does not advance the execution cursor.

The response also sets `X-Accel-Buffering: no` and no-cache, to prevent a generic Nginx proxy from buffering events without sending them. If this were not verified, the page might suddenly "light up an entire chain" only at final completion, appearing real-time while actually having missed the process.

## Replay was simpler than I first thought, and its boundaries are clearer

![Smart Cockpit paused at a tool result from the order expert: event cursor, input and output, and call path](/images/cockpit-agent-replay.png)

The frontend always keeps the complete received events. The real-time view uses all events, and the replay view uses an array prefix:

```ts
const visibleEvents = computed(() =>
  trackLive.value ? events.value : events.value.slice(0, cursor.value)
)
```

Node colors, execution counts, traversed edges, tool rounds, and expert cards are all computed from `visibleEvents`. Under the same cursor, every place is looking at the same segment of the record, and there is no need to separately arrange animation timers.

The cursor is an **array position**, not seq. A node leaves multiple events such as edge traversal, started, and completed; stepping forward looks for the position of the next `node.completed`, rather than simply adding one to the sequence number. Continuous playback currently advances one event every 600ms, a speed convenient for explanation, not a reproduction of the original execution duration.

During replay, SSE can still receive new events, but the cursor does not automatically move. Only clicking Live returns to the latest record. Therefore, pausing playback neither pauses the Graph nor causes subsequent events to be lost. Expert path filtering currently applies to the timeline and details, while the main graph is still aggregated by nodeId; I will make this distinction clear during demos.

There is another detail with tool timeouts: after being caught by business code, it returns `toolOutcome.ok=false`. At this point the node itself has completed its responsibility of "producing a failed observation," so the event is `node.completed`, while the tool card shows failure. Looking only at whether the node is green is not enough to determine whether the business action succeeded.

The full online regression also exposed a failure that was easy to misread: the first three rounds had already handled the timeout retry, fetched the order, and produced the 599-yuan quote, but execution then ended at `review`. Following the record forward showed a native-thread creation failure, not another refund-tool timeout. Threads used by Graph, HTTP, SSE, and MCP together had reached the process limit. I raised only the cockpit's limit from 90 to 128, kept the CPU and memory limits, and reran all eight online scenarios. Business-loop budgets and runtime-resource budgets are different things; node records help avoid blaming every failure on the model.

## Persist only as far as the promise

Root node boundaries, run completion, human recovery, and cancellation save JSON, first writing a temporary file and then atomically replacing it. Production files are placed in `shared/workflow/runs` and are not cleaned up with releases, so history can still be read after upgrading the frontend or JAR.

It is not a complete event database: each emit is not immediately written to disk, and on sudden exit, events after the last checkpoint may be missing. On startup, leftover RUNNING entries are marked as INTERRUPTED, and human waiting status is retained. Recovery uses the saved application state to enter `HumanResumeGraph`; it is not framework-native checkpoint support for resuming from an arbitrary position.

Currently at most 100 runs are retained, and the API shows the most recent 40. Records remove internal control fields, original images, and api-key, but this is not a general sensitive-information scanner. The customers, orders, and reports in the screenshots are samples; when connecting real business materials later, field-level masking, access permissions, and retention periods must still be designed separately.

At first I only wanted to make the sharing more intuitive, but in the end I found this record equally useful for debugging: it can confirm whether model proposals and actual execution are consistent, whether retrieval retries changed the query, and whether failures went to the expected exit. A beautiful node graph can be done later; first record the execution facts and several IDs correctly, and replay will have a trustworthy foundation.

The case entry point is on the [Smart Cockpit workflow page](/smartCockpit/workflow), and the code is in the `workflow` backend package and frontend module of the [enterprise-ai-cockpit repository](https://github.com/caibinice/enterprise-ai-cockpit). For the background of the workflow design, see [the previous note](/articles/agent-workflow-orchestration).
