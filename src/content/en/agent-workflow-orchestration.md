---
title: From a Single Q&A to a Workflow: The Agent Runtime I Added Inside the Smart Cockpit
excerpt: Starting from the definition of an Agent and moving to a complete customer-service state graph, this walks through RAG, images, MCP, tools, expert collaboration, and human branches, then opens up the order-tool loop and three expert subgraphs to see how orchestration lands in code.
---

While preparing this talk, I noticed how easily I slipped into talking about "which frameworks I used." I could go through Spring AI, RAG, and MCP one by one, but the audience still might not know: why, when there is already a chat box that can answer questions, do we still need workflow orchestration?

So I changed my starting point: **"Look up order SO20261001 and see how much can still be refunded."**

The sentence is not hard to understand, but when the model first receives it, it does not know whether the order has been signed for, how many days ago it was signed for, or whether the product has been used. With a longer prompt, the model can list the steps; but to get the amount, the program still has to look up the order and hand the result back to the next step. My smart cockpit already had knowledge Q&A and tool integration. What I added this time was the Graph runtime that organizes these steps, and a page that lets you see how it works.

## Let me first describe an Agent in plainer terms

I now prefer to understand an Agent as: **a program that, around a goal, chooses actions based on the information it has, obtains results, and then decides whether to continue.** The model is the decision-making component inside it, not the whole program.

This does not mean a single model call is worthless. When the materials are already complete, one call can absolutely analyze a few questions and organize an answer. What needs orchestration is the situation where the task still depends on external facts, where actions have a sequential relationship, or where the result of execution changes the next step.

These kinds of input in customer service are typical:

- Asking about the return policy requires pulling evidence from the knowledge base; uploading an E02 fault screenshot requires first extracting visible information and then retrieving.
- Asking how much can be refunded on an order requires looking up the order and doing a trial calculation—do not mistake "planning to query" for "already queried."
- Asking about policy, refund, and sales report at the same time requires splitting them apart, handling them separately, and then summarizing with each result.
- Query failure, insufficient evidence, or a customer request for a human requires an explicit exit path.

Here there are both pre-defined workflows and local loops where the model chooses actions; there is no need to force them into two mutually exclusive products. I quite agree with Anthropic's distinction between workflows and Agents: the difference lies in how far the flow is predetermined by code, not in whether the prompt says "you are an agent." [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)

## Graph manages state and transitions, not lines on a page

The three basic concepts of Graph are enough to get started.

**State** holds the facts already known for this task, such as the customer question, the knowledge that was hit, tool observation results, the current round, and the answer draft. **Node** does one specific thing, reads the state and returns an increment; retrieval nodes and formatting nodes do not have to call the model. **Edge** decides where to go next; it can be a fixed connection, or it can branch differently based on state.

When I first understood Graph, I easily saw it as a DAG. The key to an Agent happens to be allowing an edge to go back to a previous node: after a tool result comes back, make another decision; when retrieval yields nothing, rewrite the query with the feedback. A loop also needs an exit and a budget.

In its January 2024 introduction, LangGraph already treated cyclic graphs as an important capability of an Agent runtime. The cockpit was originally a Java/Spring project, so I chose to use Spring AI Alibaba Graph's `StateGraph` and `CompiledGraph` within the same tech stack, rather than starting another Python service for this demo. [LangGraph announcement](https://www.langchain.com/blog/langgraph), [Spring AI Alibaba Graph guide](https://java2ai.com/docs/frameworks/graph-core/quick-start/)

When it comes down to the code, you also have to specify how state fields are merged. This cockpit main graph uses `ReplaceStrategy`: when a node returns a new evidence or observation list, it replaces the corresponding field; when you want to append a tool result, the node first combines the old list with the new result into one list and returns that. It is not that adding a field to a Map means subsequent state will merge correctly on its own.

The framework drives this graph forward; the frontend only observes events. Even if you close the web page, an already submitted run will not stop just because an animation is missing. Conversely, the frontend lighting up a line does not mean the backend actually executed that node.

## Drawing the skeleton of an enterprise application from customer-service requirements

My approach was to first pin down the branches: normalize the input, do image observation when necessary, then recognize intent. Policy and faults go to retrieval; sales data goes to the report MCP; orders go to the tool loop; combined questions go to the expert graph; human requests directly form handover materials. The evidence collected by each branch returns to the answer and review nodes, and is revised or re-retrieved when necessary.

![Smart cockpit full orchestration workbench: eight scenario entries, run history, customer-service main graph, and node details](/images/cockpit-agent-overview.png)

Opening up the main graph, it is roughly the structure below. Tools, experts, and retrieval all have loops, but their exit conditions differ:

```text
输入归一化 → 有图则提取图片证据 → 意图识别
  ├─ 政策或故障 → 知识检索 ─────────────────────┐
  ├─ 销售报表 → MCP 工具发现与调用 ──────────────┤
  ├─ 订单退款 → 工具决策 ⇄ 实际执行与观察 ───────┤
  ├─ 组合问题 → 拆任务 → 专家子图 ⇄ 完成检查 ────┤
  └─ 人工诉求 → 保存交接资料 → 等待人工          │
                         人工反馈 → 恢复图 → 完成│
                                               ↓
                                证据驱动回答 → 评审 → 完成
                                         ↑      │
                                  修订草稿┘      └→ 改写查询 → 再检索
```

What was merged into the cockpit this time is the entire workbench, not just two buttons left for orders and experts. The sections from the original Agent Studio can still be operated item by item; after being placed into the cockpit, the scenario bar became a compact layout at the top of the page, to avoid stacking another permanent sidebar.

| Scenario entry | What this path is used to verify |
|---|---|
| Product knowledge RAG | Intent classification, real vector retrieval, answer with sources, and review |
| Image and text | Image evidence enters the state first, then influences classification and retrieval |
| Enterprise report MCP | Discover the tool schema, execute `tools/call`, read back the monthly report |
| Tool-call loop | Look up the order, then trial-calculate the refund, and observe the result affecting the next round |
| Multi-Agent collaboration | Split tasks, call three expert graphs, check progress, and summarize |
| Human takeover | Preserve handover materials, and continue executing the recovery graph after a human fills in comments |
| Feedback-driven re-retrieval | First evidence is missing, then retrieve again after rewriting the query |
| Tool exception and budget | Timeout as failed observation; continue if budget allows, hand off to human if exhausted |

There are also three easily overlooked entries: **demo knowledge** can be searched, added, and imported from TXT/MD; **share tour** can directly load key cases; **recent runs** can reopen records, inspect nodes, and export the chain. All eight scenarios share the same monitoring and replay instead of each having its own preset animation. Review rework can be verified separately through the fault option in the input area.

This graph did not solve all enterprise problems for me. What tools can access, who can perform write operations, how many times to retry on failure, and whether there is an idempotency key for refunds all remain the responsibility of the host program. This demo deliberately only does refund **trial calculation**, with no charge or refund interface; when actually executing transactions, business authorization, approval, and idempotency control still need to be added.

To make repeated explanations easier, the cockpit workbench uses isolated sample orders, monthly reports, and knowledge samples. Knowledge retrieval is 2048-dimensional hashed n-gram cosine retrieval, not cloud semantic embedding; it has also not replaced the cockpit's original MySQL/pgvector enterprise knowledge base. MCP and HTTP, by contrast, are real protocol calls. Being clear about the separation between "real execution" and "demo data" is more useful than calling the whole page a "production-grade intelligent customer service."

## Tool loop: this is where I stop and talk for five minutes

![Smart cockpit tool loop: two actual execution rounds, looking up the order and trial-calculating the refund respectively](/images/cockpit-agent-tool-loop.png)

This example has only two business actions, but it fully demonstrates the closed loop.

Its key structure in `WorkflowEngine` is as follows, with node registration, state strategy, and event wrapping omitted:

```java
graph.addConditionalEdges(
    "tool_plan",
    edge_async(state -> (String) state.data().get("toolNext")),
    Map.of("execute", "tool_execute",
           "done", "draft",
           "human", "human_handoff")
);
graph.addEdge("tool_execute", "tool_plan");

CompiledGraph app = graph.compile(
    CompileConfig.builder().recursionLimit(80).build()
);
```

`tool_plan` first checks whether the results are complete, then checks the business round count, and only then asks the model to choose a tool. `tool_execute` validates and executes the call, puts success or failure into `observations`, and increments `toolRound`; in online mode it also writes the result as a `role=tool` message keyed by `tool_call_id`. When it returns to the decision node, what it reads is the updated state. The graph's recursion limit is another layer of fallback, not equal to the business three-round budget.

In the first round, `tool_plan` receives the order number and, in online mode, proposes `lookup_order` through native `tool_calls`. Java validates the tool name and parameters, sends an HTTP request to the standalone sample service, and gets "signed for three days, unused, product amount 599 yuan."

In the second round, the order result has already entered `observations`, and is also returned to the model as a `role=tool` message. Only then is `calculate_refund` opened, the program performs the trial calculation, and returns a refundable product amount of 599 yuan, along with a note that shipping needs to be determined by responsibility. Once both types of results are complete, the host ends the tool loop and enters the answer node.

The easiest thing to get wrong here is treating the function name output by the model as already executed. **`tool_calls` is a proposal; the HTTP return is the observation result.** Between the two there are also allowlist, parameter format, and dependency-order checks. `tool_call_id` must also match, otherwise even the protocol context for the next round may be incomplete.

I did not leave all exit responsibility to the model: repeated calls, missing order number, and exhausted rounds are all caught by code. After injecting one tool timeout, the failed observation goes into the next round, rather than silently retrying and only showing a green "success" on the page. If the budget is only two rounds and recovery is not enough to complete lookup and trial calculation, it goes to a human.

## Multi-Agent: look at the boundaries first, then count the models

![Smart cockpit multi-Agent workbench: actual subgraph runs of knowledge, report, and order experts](/images/cockpit-agent-multi.png)

A combined question is split into three subtasks: policy, sales report, and order refund. The main graph calls three independently compiled expert graphs, and each graph receives only the task and state it needs. They can use the same DeepSeek model; the difference is in task, context, tools, and graph structure, not in giving the same prompt three different names.

The current implementation is **sequential collaboration**. After each expert returns, the main graph checks whether there are more tasks, continues to the next one, and finally summarizes. The order expert also has an internal loop of order lookup and trial calculation, so here you can see both the "outer task loop" and the "inner tool loop." I do not call it parallel collaboration: the fact that all three experts are complete in the screenshot does not mean they executed at the same time.

The scheduling skeleton of the main graph is not long; node registration is likewise omitted below:

```java
graph.addEdge("multi_plan", "specialist");
graph.addEdge("specialist", "multi_review");
graph.addConditionalEdges(
    "multi_review",
    edge_async(state -> (String) state.data().get("multiNext")),
    Map.of("next", "specialist",
           "done", "draft",
           "human", "human_handoff")
);
```

The real responsibility boundary is inside `specialist`: it takes the current task according to `taskCursor`, constructs the expert state, selects the already compiled `rag`, `report`, or `tool` graph, and calls `invoke()`. An expert only gets the current question and necessary configuration, not the full history of the main graph directly; after returning, it appends `agentResults` and advances the task cursor. Subgraphs have independent Thread IDs, but events inherit the same Run's Trace ID and parent Span, which is what makes it possible to inspect both outer scheduling and inner steps in the same workbench.

Sequential execution also has practical benefits. The first demo is easier to explain in terms of context boundaries, and the concurrency pressure on a low-memory server is smaller. Whether to parallelize later should depend on whether tasks are independent, how state is merged, and whether tools share resources—not on the idea that more Agents is better.

## Looking back at coding agents

Having gotten this far, when I look at coding agents like Codex and Claude Code, it becomes easier to shift attention from "how impressive the prompt is" to "how the runtime environment supports the task": reading files, modifying code, running tests, letting test results influence the next step, and preserving progress for subsequent sessions to continue when necessary.

Harness can be understood as this surrounding engineering: tools, context organization, progress records, validation methods, and termination conditions. Anthropic's article on long-task harnesses gave me a very direct reminder: the environment design beyond the model affects whether a task can continue to advance. [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

"Act—observe—correct" is close to the idea of feedback control. I treat it as an engineering analogy for understanding Loop Engineering, not as a strict guarantee of cybernetic convergence, nor as a basis for inferring the historical origins of all frameworks.

What I want this talk to leave behind is not a string of framework names, but an entry point for further questions: **based on what information does the next step decide, who executes it, where does the result go, and under what conditions does it end?** Once these four questions are answered clearly, an Agent begins to turn from a chat interface into an application that can be inspected and adjusted.

You can first walk through the eight scenarios on the [smart cockpit workflow page](/smartCockpit/workflow), then focus on reproducing the tool loop and expert collaboration. For the talk I arranged it as "Agent 2 minutes, Graph 3 minutes, customer-service full graph 2 minutes, tool loop 5 minutes, expert collaboration 4 minutes, coding agent 2 minutes," about 18 minutes of main text. The other branches are examples you can keep clicking into to verify, rather than expanding line by line within twenty minutes. The implementation of monitoring and replay is recorded separately in the [next note](/articles/agent-node-monitoring-replay).
