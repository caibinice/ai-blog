---
title: 从一次对话到完整工作流：我在智能座舱里落地的 Agent 运行时实践
excerpt: 从为什么单次 Prompt 无法搞定复杂业务讲起，拆解基于 Graph 的状态图模型、工具循环与多专家协作，并结合智能座舱项目分享实际架构图、代码实现与避坑经验。
---

很多同学在做技术分享或者聊到大模型应用时，很容易一上来就罗列各种流行框架和名词：Spring AI、LangGraph、RAG、MCP……听起来很前沿，但听完后大家心里往往还是会有个疑问：**“我们平时调个大模型 API 聊聊天挺顺畅的，为什么非要大费周章去搞一套复杂的工作流编排？”**

其实在刚开始做 Agent 时，我也经历过这个阶段。直到我试着用 AI 去解决一个真实的业务诉求：

**“帮我查一下订单 SO20261001，看我还能退多少钱。”**

表面上看，这只是一句普通的自然语言咨询。但只要你动手写过业务代码，就会发现单次 Prompt 在这里彻底抓瞎了：

大模型刚收到这句话的瞬间，它根本不可能知道这个订单到底签收了几天、买的是什么商品、当前处于什么物流状态。就算你把提示词写得再长，让它在文字里头头是道地写出“第一步查订单、第二步算金额”，自然语言的规划也绝不等于物理世界的系统执行。程序必须先停下来，拿着提取出的订单号去订单中心真实发起请求；拿到“已签收 3 天、未拆封”这个事实后，再把数据塞回给模型，模型才能依据业务退货政策算出准确金额。

这个最初为了内训技术分享、使用 Vue 3 + Spring AI Alibaba Graph + DeepSeek 编写的 `agentDemo` 原型，后来被我完整迁移合入了智能座舱项目（[enterprise-ai-cockpit 仓库](https://github.com/caibinice/enterprise-ai-cockpit)）。今天这篇文章，我就结合项目里的架构图、流程图和实际代码，聊聊为什么工业级智能体必须依赖工作流编排，以及我们是怎样一步步把它做扎实的。

## 破除迷思：智能体的本质究竟是什么？

### 从“单次 API 调用”到“目标驱动的有状态程序”

在最基础的 LLM 使用模式里，逻辑其实非常简单：编写一段 System Prompt，拼上用户问题，调用一次 Chat Completion 接口，然后把返回的 Markdown 渲染出来。写周报、润色文案、提炼单篇长文时，这种“一次性请求”非常好用。

但这往往会让人产生一种错觉：似乎只要把 Prompt 调得足够高级，就等于做出了一个“智能体（Agent）”。

然而一碰到真实的工业级场景，单次调用的空中楼阁就会瞬间坍塌。主要卡在三个避不开的工程硬伤上：

1. **步骤之间的强动态依赖**：就像前面提到的退款场景，第二步的计算输入完全依赖第一步的系统返回值。没有拿到第一步的真实 Observation，后续推理只能靠猜。
2. **确定性业务规则的强约束**：政策解答必须严格对齐最新向量知识库；报表分析必须通过内部安全隔离的 MCP 接口取数；退款试算必须走专用计费逻辑；用户情绪激动时必须无缝转人工。如果试图把整本业务手册、实时数据库结构和各种接口一股脑塞进 Prompt，不仅上下文窗口吃不消，严重的注意力稀释和模型幻觉会直接摧毁业务可靠性。
3. **环境波动与自愈容错**：外部接口可能超时，首次向量检索可能漏掉关键切片，模型偶尔可能吐出格式非法的 JSON。单次调用在遇到任何局部抖动时，除了全盘报错别无他法，缺乏在错误中保留状态并自动重试修复的能力。

因此，智能体绝不是一段神奇的提示词，也不是单纯的模型 API，而是一个**“围绕目标推进任务的有状态工程系统”**。在架构设计上，必须坚决把“大脑”与“四肢”拆开：

- **大脑（LLM / Reasoner）**：只负责非结构化的语义理解、意图抽取，以及基于当前事实推断下一步行动建议（Policy Inference）；
- **四肢与容器（Host Runtime & State Container）**：负责跨步骤状态的持有与持久化、真实工具的安全调用、业务权限校验、流转预算控制以及人工干预恢复。

| 对比维度 | 单次 Prompt + API 模式 | 广义工作流编排与状态图 |
|---|---|---|
| **上下文供给** | 运行前一次性静态塞入，容易信息过载或遗漏 | 随执行逐步动态注入，前一步工具的实际结果作为下一步上下文 |
| **外部动作执行** | 只能在文字里生成参数，无法自我闭环执行 | 宿主程序负责参数合法性校验、发起真实网络调用并捕获异常 |
| **逻辑分支跳转** | 模型在回答中碰运气猜测各种可能分支 | 通过状态机中的条件边（Conditional Edge）执行物理级路由 |
| **异常恢复能力** | 单次调用抛异常即整体任务终止 | 异常被包装为 Observation 写入状态，支持自动重试、降级或转人工 |
| **任务终止依据** | 模型吐出结束符（EOS）即代表完结 | 基于业务验收条件、证据完备性与最大执行预算综合判定 |

## 工作流编排的核心范式：Graph（图计算）理念

### 为什么不能只用流水线？状态图（State Graph）的核心抽象

在刚开始做 Agent 编排时，很多同学最容易想到的就是类似 LangChain 早期 LCEL 管道操作符的线性链（Sequential Chain，A -> B -> C）。

线性链写固定流程很舒服，可一旦遇到真实 Agent 中的**循环（Loop）**与**反馈修正（Feedback Revision）**，就会非常难受：如果检索结果不满意需要改写重试，如果工具调用报错需要带着错误信息重新决策，线性链要么陷入无限深的递归调用栈，要么被迫在外部堆砌一堆满是全局变量的 `while` 循环。

为了从根上解决这个问题，状态图（State Graph）架构成为了行业共识。Graph 不是为了在界面上画流程图而画的，它是一套严密的底层计算模型，把业务逻辑抽象为四个核心支柱：

![Graph 状态图的核心架构：节点、状态、边与循环控制](/images/agent-graph-basics.png)

1. **状态（State / 黑板机制）**：贯穿整张图生命周期的共享记忆容器。它记录了任务从启动到结束的所有关键数据：用户原始提问、意图分类与置信度、检索到的知识切片、工具调用的请求与真实返回（Observations）、当前迭代轮数以及生成的草稿。在工程落地时，状态键必须定义明确的合并策略，比如用覆盖策略替换单条记录，或者用追加策略累加列表条目。
2. **节点（Node）**：图中的原子业务单元。每个节点都遵循纯函数式的设计理念：吃进当前 State 的切片，执行单一职责的任务（例如调用模型、查向量库、调外部 API 或做数据格式转换），然后输出一个状态增量（State Delta）。节点自身绝不持有跨请求的私有状态。
3. **边（Edge）与条件边（Conditional Edge）**：普通边表示固定的确定性跳转；而条件边则是智能路由的核心。条件边绑定了一个路由函数：根据当前 State 中的状态值，动态算出下一个目标节点。比如意图是“政策咨询”就去检索节点，是“订单查询”就去工具节点，意图置信度不足时果断切去人工处理。
4. **循环（Cycle）与安全预算（Budget）**：在 Graph 拓扑里，边允许指回前面的上游节点，从而自然形成闭环。循环让经典的“决策 - 行动 - 观察 - 再决策”（ReAct）范式能够极其自然地表达出来。为了防止死锁或无限空转，宿主运行时必须设置硬性的递归深度上限（Recursion Limit）与业务轮数预算（Budget），一旦预算耗尽立刻熔断转人工。

### 为什么在 Java 生态里选 Spring AI Alibaba Graph？

在 Python 生态里，LangGraph 率先将 Pregel 分布式图计算模型与有限状态机（FSM）思想引入了 Agent 领域。Python 写原型验证非常敏捷，但在企业级微服务、生产中台和高并发后端场景中，Java 依然是绝对的中流砥柱。

让团队为了一个 Agent 功能单独维护一套 Python 微服务，在部署、多线程并发控制、分布式事务以及与已有业务库打通上成本都很高。智能座舱后端本身就是基于 Java 与 Spring Boot 搭建的，因此我们选用了 Spring AI Alibaba Graph。它不仅完整实现了 Graph 状态图的核心设计哲学，还带来了强类型安全、依赖注入、以及与 Spring 生态体系的无缝集成。

## 场景实战：智能座舱客服工作流的骨架设计

为了让整套理念落到实处，我们以智能座舱里的企业级智能客服作为切入点。真实场景下的客户输入五花八门：

- **咨询 A**：“Aero 耳机的退货政策是什么？签收三天未使用可以退吗？”（纯政策咨询，需要向量知识库检索并溯源条文）；
- **咨询 B**：上传耳机指示灯红闪截图问“这是什么问题？怎么处理？”（多模态视觉理解，需抽取 E02 错误码后检索排障手册）；
- **咨询 C**：“查询订单 SO20261001，然后根据实际状态试算可退款金额。”（前后强依赖的动态工具调用）；
- **咨询 D**：“查询 2026-09 月销售报表，告诉我营收和订单数。”（企业系统集成，需通过 MCP 协议动态发现并调用内部报表服务）；
- **咨询 E**：“请分别说明耳机退货政策、SO20261001 可退款金额以及 9 月销售报表。”（跨领域组合任务，需拆解子任务并调度多个专家协作）；
- **咨询 F**：“我对赔偿金额极不满意，必须给我一个说法！”（争议纠纷或低置信度意图，需保存全量上下文并安全平滑转交人工）。

针对这些诉求，我们设计了端到端的状态图工作流架构：

![企业级智能客服端到端工作流拓扑结构](/images/agent-workflow-topology.png)

整个系统的运行时数据流与架构拓扑如下，各节点通过标准事件驱动，将状态变更与跟踪信息实时推送给前端：

![运行时前后端架构与事件流机制](/images/agent-runtime-architecture.png)

合入座舱后，工作台提供了 8 个场景入口、运行历史追溯、客服主图可视化以及实时详情面板：

![智能座舱完整编排工作台：八个场景入口、运行历史、客服主图和节点详情](/images/cockpit-agent-overview.png)

主图的核心执行阶段非常清晰：
1. **输入归一化与图片观察**：若用户带图，先调用轻量视觉模型提取可见文字与故障码特征，转为规范文本；
2. **意图分类与动态路由**：输出目标分支（rag / report / tool / multi / human）与置信度。置信度不足 0.6 时，条件边强制路由至转人工；
3. **领域分支执行**：进入 RAG 知识检索、MCP 报表查询、原生 Tool 循环或多 Agent 协作；
4. **生成与评审闭环（Draft & Review）**：汇聚 State 中的全部证据生成草稿，由 Review 节点核对证据引用的一致性，通过则结束，存疑则触发重写重检；
5. **人机协同（Human-in-the-Loop）**：在转人工节点打下快照并挂起，等待人工意见提交后继续流转。

落实到代码时，还要为状态字段规定合并方式。座舱主图在多处使用 `ReplaceStrategy`：节点返回新的证据或观察列表替换对应字段；若需追加工具结果，由节点逻辑在返回增量前完成合并，保证状态流转严谨可控。

此外，很多技术交流里容易把 MCP 和 Tool Calling 混为一谈。在我们的架构中：**Tool Calling 是模型层的协议标准**，规定模型如何声明函数名和实参；**MCP 则是应用层与外部系统的集成规范**，规定客户端如何动态发现（`tools/list`）和调用（`tools/call`）外部服务。报表服务作为独立 MCP Server 运行，在工作流眼里它们都被统一包装为受控 Tool，执行时机与容错皆由状态机掌管。

## 硬核实战剖析：两大核心机制的代码落地

在智能座舱的演示中，最硬核、最容易看清工作流价值的是两个机制：**工具调用循环** 与 **多 Agent 协作**。

### 核心一：工具调用循环（Tool Loop / ReAct Loop）

以“查订单 SO20261001 并依据实际状态试算退款金额”为例，模型在第一步根本不可能知道试算所需的金额与商品状态。必须查到订单事实并放回状态后，才能继续规划第二步。

![工具调用循环（ReAct 循环）的状态流转与反馈控制](/images/agent-tool-loop-flow.png)

在智能座舱界面里，能够清晰看到两个执行轮次的流转详情：

![智能座舱工具循环实际运行详情：两个实际执行轮次，分别查订单和试算退款](/images/cockpit-agent-tool-loop.png)

我们在 Graph 中把闭环拆解为 `tool_plan`（决策节点）与 `tool_execute`（物理执行节点）：

```java
// 1. 注册核心节点：决策节点与物理执行节点
graph.addNode("tool_plan", this::toolPlanNode);
graph.addNode("tool_execute", this::toolExecuteNode);

// 2. 配置条件边：根据决策输出决定是继续执行工具、完成生成、还是熔断转人工
graph.addConditionalEdges(
    "tool_plan",
    edge_async(state -> (String) state.data().get("toolNext")),
    Map.of(
        "execute", "tool_execute",   // 提出新工具调用 -> 去物理执行
        "done",    "draft",          // 证据已齐全 -> 去生成最终回答
        "human",   "human_handoff"   // 超出预算或异常 -> 安全切入人工
    )
);

// 3. 闭环连接：工具执行完毕后，无条件回跳到决策节点重新评估
graph.addEdge("tool_execute", "tool_plan");

CompiledGraph app = graph.compile(
    CompileConfig.builder().recursionLimit(80).build()
);
```

两个节点的职责切分至关重要：

```java
Map<String, Object> toolPlanNode(State state) {
    // A. 业务终止检查：若前序步骤已拿到最终退款试算结果，直接跳出循环
    if (state.hasObservation("calculate_refund")) {
        return Map.of("toolNext", "done");
    }

    // B. 安全预算熔断：若当前工具轮次达到设定预算（如 3 轮），切断循环转人工
    if (state.getInt("toolRound", 0) >= state.getInt("maxIterations", 3)) {
        return Map.of("toolNext", "human", "handoffReason", "工具调用超出最大预算限制");
    }

    // C. 动态权限控制：根据当前阶段，只向模型暴露当前合法的工具列表（防越权/乱调）
    List<ToolDefinition> allowedTools = resolveAllowedTools(state);

    // D. 请求大模型决策：基于已积累的 toolMessages 与 observations 决定下一动作
    ToolCall call = modelGateway.planNextTool(state.getMessages(), allowedTools);

    return Map.of(
        "pendingTool", call,
        "toolNext", "execute"
    );
}

Map<String, Object> toolExecuteNode(State state) {
    ToolCall call = (ToolCall) state.get("pendingTool");

    // 物理执行外部调用（HTTP / MCP / RPC），捕获超时与异常
    ToolResult result = enterpriseTools.execute(call.name(), call.arguments());

    // 将 Observation 包装为 role=tool 协议消息写回状态，供下一轮决策读取
    return Map.of(
        "observations", state.appendObservation(result),
        "toolMessages", state.appendToolMessage(call.id(), result.toText()),
        "toolRound", state.getInt("toolRound", 0) + 1
    );
}
```

这里最容易混淆的概念是：**模型输出的 `tool_calls` 只是意图提议，只有宿主发起 HTTP 拿到响应后，才算产生了真正的 Observation。**

第一轮，`tool_plan` 提议调用 `lookup_order`，后端校验参数后向接口发起真实 HTTP 请求，拿到“已签收三天、未使用、金额 599 元”；
第二轮，订单数据已进入 `observations`，此时才向模型开放 `calculate_refund`，模型据此发起试算，拿到可退金额 599 元。两样证据齐备，跳出循环。如果调用超时，超时信息同样作为 Observation 写入状态让模型尝试自愈重试；一旦超过轮数上限，条件边强行熔断切人工，确保整个系统有明确的安全边界。

### 核心二：多 Agent 协作（Multi-Agent Collaboration）

当用户提问：“请分别说明耳机退货政策、SO20261001 可退款金额以及 9 月销售报表”时，如果把知识库检索、订单接口和庞大的报表 Schema 全塞进同一个上下文，模型会遭遇严重的“注意力稀释”与“工具污染”，极易串号串参数。

解法就是“专家子图协作模型”（Specialist Sub-graphs）：

![主图调度专家子图的多 Agent 协作层次架构](/images/agent-multi-hierarchy.png)

在座舱界面里，可以看到协调器逐步调度知识、报表、订单三个专家子图的执行痕迹：

![智能座舱多 Agent 工作台：知识、报表、订单专家的实际子图运行](/images/cockpit-agent-multi.png)

```java
// 多 Agent 协作协调器的状态机流转
graph.addNode("multi_plan", this::decomposeTasksNode);
graph.addNode("specialist", this::invokeSpecialistSubGraphNode);
graph.addNode("multi_review", this::reviewProgressNode);

graph.addEdge("multi_plan", "specialist");
graph.addEdge("specialist", "multi_review");

// 检查进度：未完成则循环调度下一位专家；全部完成则进入最终汇总结点
graph.addConditionalEdges(
    "multi_review",
    edge_async(state -> (String) state.data().get("multiNext")),
    Map.of(
        "next",  "specialist",
        "done",  "draft",
        "human", "human_handoff"
    )
);
```

- **任务拆解（`multi_plan` 节点）**：主模型先将复杂问题拆分为独立子任务列表：`tasks = [Task(RAG), Task(Tool), Task(Report)]`；
- **专家子图执行（`specialist` 节点）**：主图根据任务类型，调用对应的独立 `CompiledGraph`（拥有各自独立的节点拓扑和内置循环）。子图拥有独立的 Thread ID 隔离状态，但继承主图的 Trace ID 与当前父 Span ID，保证追踪链路清晰完整；
- **进度推进与汇总（`multi_review` -> `draft` 节点）**：维护一个任务指针，做完一个推进一步。全部专家完成后，汇集所有证据，由汇总节点一次性生成条理分明的综合答复。

目前我们采用的是**顺序协作**。不仅便于理顺上下文边界，对部署服务器的并发资源消耗也更友好。

## 前沿延伸：从业务客服到 Coding Agent 与控制论

当我们把视野拓展到如今最火热的 Coding Agent（例如 Claude Code、Cursor、OpenAI Codex、SWE-agent）时，你会发现它们能写代码、修 Bug，底层的核心架构与我们这里的客服工作流在本质上是**完全同构的**。

![Coding Agent 的闭环控制：以反馈消除误差](/images/agent-coding-loop.png)

没有哪个成熟的 Coding Agent 是靠“给一段提示词直接一次性生成整套系统”做出来的。它们无一例外都依赖于高频的反馈循环：
1. 需求解析与意图对齐（Goal Setting）；
2. 检索代码库与符号定位（Grep / AST 工具）；
3. 制定编辑方案（Plan）；
4. 局部代码文件修改（Action）；
5. 运行编译器、Linter 或单元测试（Observe）；
6. 观察报错堆栈：若通过则退出，若报错则将错误信息反哺回状态，重新规划修改（Self-Correction Loop）。

最近 Anthropic 和 OpenAI 经常强调一个概念：**Harness Engineering（座架工程）**。“Prompt is cheap, foundation model is commodity, harness is the differentiator”（提示词是廉价的，基础模型是标准化商品，座架工程才是核心护城河）。

什么是 Harness？就是包裹在模型外部的安全沙箱、工具链、上下文裁剪管理、进度断言与评测系统。模型是大脑，Harness 则是赋予大脑真实生产力的工程座架。

这实际上正是维纳在 20 世纪创立的“控制论（Cybernetics）”在现代计算机软件中的经典重现：**任何自主系统要想在不确定环境中实现目标，必须依靠负反馈调节机制——测量当前状态与目标状态之间的偏差（Error），并将偏差反向输入给控制器，指导下一次行动，直到偏差彻底消除、系统趋向收敛。**

单次 Prompt 是开环系统，对错全凭运气；而基于 Graph 状态图与工作流编排的智能体，则是严密的闭环系统。这正是工作流编排带给 AI 应用的最核心价值。

---

如果想亲自体验这套工作流的运转细节，可以直接访问项目中的[智能座舱工作流页面](/smartCockpit/workflow)。下一篇我们将详细聊聊这套工作流背后的[节点监控与时间线回放实现](/articles/agent-node-monitoring-replay)。
