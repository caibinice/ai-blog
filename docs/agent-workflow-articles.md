# 两篇 Agent 心得文章的编辑记录

## 内容与写作日期

| 文章 | 日期 | 中文源文件 |
|---|---|---|
| 从一次问答到一段工作流：我在智能座舱里补上的 Agent 运行时 | 2026-10-06 | `src/content/zh/agent-workflow-orchestration.md` |
| 给 Agent 留一份执行记录：智能座舱的节点监控与回放 | 2026-10-15 | `src/content/zh/agent-node-monitoring-replay.md` |

日期按用户指定写入 `src/lib/articles.ts`。两篇按后续请求一起发布，第二篇仍保留指定的 2026-10-15 日期，没有设置定时任务。两篇均已补齐英文、日文版本，沿用博客三语内容规范。

基础材料是 `E:\codes\agentDemo\docs\AI智能体工作流编排技术分享.docx` 和 `E:\codes\agentDemo\docs\智能体节点监控与回放实现说明.md`。文章重新组织为第一人称工程心得，不直接照搬材料中较重的宣传式表述。案例均换成实际合入并发布的企业智能座舱：Graph 运行时、WebFlux 事件流、原生 Vue 工作台与既有操作验证。

## 配图来源

截图日期 2026-10-09，来自 `https://caibinice.com/smartCockpit/workflow`，不是独立 Agent Demo 页面，也不是生成的 UI 示意图。原四张重点截图来自 release `20261009111652-50803b7`，新增全工作台截图来自 `20261009135330-8855abf`。

| 本地资源 | 场景与运行记录 |
|---|---|
| `public/images/cockpit-agent-overview.png` | 八场景栏、三个工作台入口、历史、主图及 RAG 详情；Run 332142dc-2aa2-413a-9711-a5600007073c |
| `public/images/cockpit-agent-tool-loop.png` | 在线工具循环，Run e05a5d0f-1cc0-4993-bcae-7353731aa3c2 |
| `public/images/cockpit-agent-multi.png` | 在线三专家协作，Run c893608d-0a41-4580-8658-7571cb45d7c1 |
| `public/images/cockpit-agent-monitor.png` | 上述多 Agent 运行的完整节点图、指标与分类输出 |
| `public/images/cockpit-agent-replay.png` | 上述记录的 41/92 游标，root/toolAgent[2] 第一次订单工具结果 |

页面和文字都明确：订单、退款、报表为隔离样例；知识示例用 hashed n-gram 向量；工具真实执行但不实际退款；三专家顺序协作；回放不重跑业务；检查点不是完整事件数据库或任意节点续跑。

## 验证与提交范围

- 文章结构调整为 Agent 定义 → Graph → 完整客服主图与八场景 → 两个重点闭环的代码 → Coding agent；监控文章补齐全分支验收与真实线程额度故障定位。
- Vue 类型检查通过；工作区 Vitest 63 项通过（12 项内容测试与原有 51 项拼豆测试）。发布使用仅含提交内容的独立构建目录，额外未提交测试及游戏不进入本次提交或产物。
- 编排文章三张截图，监控文章两张截图；各语言保留同一组代码和链接，日期保持不变。
- 本次仅提交两篇文章的三语版本、五张图片、文章注册、内容测试与本记录；博客原有拼豆游戏与 Nginx 未提交改动保持原样。
- 使用博客独立发布脚本，切换博客静态 release，不发布其他项目、不覆盖共享 Nginx 路由。先提交和推送，再从该提交构建发布；构建产物与凭据不入 Git。
