---
title: 多工厂部署中的 Cherry-pick 分支治理
excerpt: 针对多工厂独立部署场景下的代码分支管理实践：通过主干收敛与双向解耦的 Cherry-pick 流转机制，实现通用业务模块跨工厂的安全复用与可追溯发布。
---

在多工厂、多工区分别部署同一套业务系统（基于 Java + Vue 架构）的场景中，不同现场拥有各自的生产发布分支，其中包含特定的 PLC/硬件通信地址、产线路由配置与本地数据库初始化脚本。与此同时，通用业务功能（如统一日志平台、通用报表模块）在各工厂之间存在强烈的复用需求。

如果直接在工厂部署分支之间执行 `git merge`，极易将源工厂的专属配置与未经验证的本地代码夹带合入目标工厂分支。为了保证生产环境代码的安全性与可追溯性，本文总结了一套基于 `cherry-pick` 的两段式分支流转与治理规范。

## 分支分层与角色定义

在多分支仓库中，各分支承担不同的发布职责：

- **公共主干分支（`prod_main`）**：沉淀各工厂通用的标准功能与公共组件，作为功能跨现场复用的标准中枢；
- **工厂部署分支（`prod_factory_a`、`prod_factory_b` ...）**：对应各工厂现场真实运行环境，包含各工厂独立的配置与差异化适配；
- **历史归档分支**：早期遗留分支，仅作为历史归档保留，不参与日常开发与发布。

跨工厂功能复用的核心原则是：**部署分支之间严禁直接交叉合并，所有通用功能必须先在公共主干 `prod_main` 上收敛为单一原子提交，再由目标工厂分支进行定向遴选（cherry-pick）。**

```text
源工厂分支(prod_factory_a)
       │
       ▼ (cherry-pick -n 多笔提交并清洗排除现场配置)
公共主干(prod_main) ───> 收敛为 1 个标准提交
       │
       ▼ (cherry-pick -x 带原提交追踪)
目标工厂分支(prod_factory_b)
```

## 部署分支禁止交叉合并

在多工厂架构下，以下操作属于典型的高危模式：

```bash
# 高危操作：禁止在工厂部署分支间直接 merge
git switch prod_factory_b
git merge origin/prod_factory_a
```

直接 merge 会将工厂 A 的硬件接口、专用中间件地址与特定的 SQL 变更一并合入工厂 B。这类污染往往在编译期不会报错，而是在现场运行时引发严重的设备连接异常。

标准的两段式流转方案将“功能提炼”与“现场适配”解耦：

![两段式流转：源工厂部署分支 →（cherry-pick -n 多笔 + 筛选）→ prod_main 一个干净提交 →（cherry-pick -x）→ 目标工厂部署分支](/images/cherry-pick-flow.svg)

## 功能在主干上的原子化收敛

在源工厂分支上开发某项功能时，往往伴随着多次零散提交（包括特性开发、现场联调、配置临时微调等）。将这些改动合入公共主干时，应提取功能代码本身，并收敛为一个干净的提交。

操作步骤如下：

```bash
git switch prod_main
git pull --ff-only origin prod_main
# 使用 -n (--no-commit) 将源分支的多笔提交改动加载至工作区暂存
git cherry-pick -n <源提交SHA_1> <源提交SHA_2> <源提交SHA_3>
```

使用 `cherry-pick -n` 可以将多笔提交的变更平铺在工作区中而不立即生成提交。随后进行差异核对：
1. 回滚所有工厂专属的配置文件与现场调用类；
2. 剔除未经验证的外围脚本与测试文件；
3. 清理 Maven `pom.xml`，仅保留该模块所需的最小依赖与模块声明；
4. 运行单元测试与本地编译验证；
5. 完成后提交为单一原子 Commit：

```bash
git commit -m "feat(common): add log platform"
```

这种原子化提交使得主干历史清晰可溯，后续无论是在其他工厂分支复用还是执行版本回滚，均能精确定位至该特定提交。

## 第一阶段：从源工厂提炼并合入主干

在从源工厂分支向主干提炼功能时，操作流程如下：

1. **环境核对**：检查本地工作区状态，拉取远程最新分支，记录当前 `prod_main` 的 HEAD SHA 作为回滚锚点；
2. **提交梳理**：查看源分支提交日志与文件变更列表，明确涉及的文件范围与依赖关系：

```bash
git log origin/prod_factory_a --oneline --decorate
git show --stat <源提交SHA>
```

3. **变更筛选**：执行 `cherry-pick -n` 后，借助 IDE Diff 工具剔除工厂特定逻辑，确认工作区仅保留通用代码；
4. **验证与推送**：执行模块级编译与测试，确认无误后推送到远程 `prod_main` 分支。

## 第二阶段：目标工厂分支引入主干提交

当通用功能已在主干形成标准提交后，目标工厂分支引入改动的流程相对轻量：

```bash
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
# 使用 -x 参数自动记录来源提交 SHA
git cherry-pick -x <主干功能提交SHA>
```

参数 `-x` 会在生成的提交说明中追加 `(cherry picked from commit ...)`，为日后代码溯源提供明确依据。若目标工厂需要针对该模块进行本地参数配置或依赖注入适配，**必须另行创建独立的适配提交**，严禁将现场改动反向混合进公共提交中。

## 实战案例：日志平台模块跨工厂迁移

以工厂 A 开发的统一日志平台迁移至工厂 B 为例，源分支上的改动分布在三笔提交中：

| 源提交 | 提交内容 | 包含的非通用改动 |
|---|---|---|
| `a1c9f0e` | 日志核心管理模块 | 移动了旧业务文件并修改了全局根 POM |
| `b2d47a1` | 日志收集 Service 与配置类 | 包含未成熟的内部 Starter 及工厂 A 专属硬件调用 |
| `c3e8b90` | 日志查询 Controller 与 Mapper | 调整了现场线程池参数与本地 SQL 脚本 |

为了安全迁移，制定明确的文件白名单：

![案例筛选去向：进入 prod_main 的是日志模块与最小 POM 接线，排除的是独立 starter、工厂专属调用、外围改动与前端脚本](/images/cherry-pick-selection.svg)

- **允许进入 `prod_main`**：`log-platform/**` 核心目录、通用 Controller、配置类及根 POM 中关于该子模块的最小声明；
- **严格排除**：`log-platform-starter` 模块、工厂 A 专用的工单上报接口、线程池参数修改、前端本地路由及本地建表脚本。

操作命令如下：

```bash
git switch prod_main
git pull --ff-only origin prod_main
git cherry-pick -n a1c9f0e b2d47a1 c3e8b90
git restore --staged .
# 剔除白名单外的文件，清理 POM 多余依赖
git status --short
mvn -pl log-platform -am clean test
git add log-platform
git add -p pom.xml
git commit -m "feat(common): add log platform"
git push origin prod_main
```

目标工厂 B 进行引入与测试：

```bash
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
git cherry-pick -x <主干提交SHA>
mvn -pl log-platform -am clean test
git push origin prod_factory_b
```

## 冲突消解、回滚策略与提交规范

### 1. 冲突处理
当 `cherry-pick` 发生冲突时，通过标准三路合并解决冲突，使用 `git add` 暂存后执行 `git cherry-pick --continue`；如需终止本次合并，可执行 `git cherry-pick --abort` 恢复至初始状态。

### 2. 回滚规范
- **未推送本地回滚**：执行 `git reset --hard <操作前SHA>`，并配合 `git clean -fd` 清除新增未跟踪文件；
- **已推送到主干回滚**：严禁强制推送（Force Push）覆盖公共历史，使用 `git revert <提交SHA>` 生成反向提交；已引入该提交的工厂分支同步执行 `revert`。

### 3. Commit Message 规范
提交信息遵循结构化约定，以明确改动归属：
- `feat(common): ...`：公共主干通用功能
- `fix(common): ...`：公共主干通用缺陷修复
- `feat(factory-a): ...`：特定工厂的专属业务与环境适配

通过规范化的 Cherry-pick 治理，实现了多工厂架构下通用资产的沉淀与各现场配置的安全隔离，大幅降低了系统维护与排障成本。
