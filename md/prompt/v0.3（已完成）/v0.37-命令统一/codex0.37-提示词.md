# Codex v0.37 任务提示词 — 命令层统一整合 + 探针补强 + 0.4 接口预留

> 本文档是交给 Codex 的具体任务说明，配合项目级 `AGENT.md` 一起读。`AGENT.md` 是长期不变的工程铁律，本文档是 v0.37 这一版的具体任务范围。两者冲突时，`AGENT.md` 优先；本文档对 `AGENT.md` 没覆盖的细节做本版补充。

---

## 0. 先读什么

按 `AGENT.md` 第 2 节的顺序读完 `README.md`、`md/xcode测试规范.md`、最近相关阶段文档之后，再读本文档。本文档不重复 `AGENT.md` 已经写清楚的架构铁律，只在涉及处引用章节号。

---

## 1. 本版定位与决策背景

当前版本：v0.36 已完成（默认战争 AI 管线为 `TheaterCommanderPool → ZoneCommanderAgent → ZoneDirective → WarCommandExecutor → RuleEngine → WarDirectiveRecord`，Legacy Agent D 管线保留作回归参考）。

**重要决策（本版边界由此确定，不是临时偷懒）：**

撤退类命令扩展和未来的突破/闪电战机制，在设计讨论中被判断为复杂度远超表面认知的一类问题——目标位置怎么选、部队怎么排布、何时算撤退完成、完成后防线怎么重新形成，这些子问题彼此关联，而且撤退和突破在结构上是同一个"多回合追踪行动"骨架的两种镜像实现，仓促做任何一个都可能在做另一个时推倒重写。因此**明确推迟到 1.x 系列**，不在 0.37 处理。

0.37 因此收窄为一个**地基工程任务**，不引入任何新游戏机制：

1. 把命令层（`ZoneDirective` 新管线）真正收口为唯一权威路径，确认 Legacy Agent D 不会在默认运行路径中被意外触发。
2. 补充探针/专项测试，把"单一路径"这个结论从口头汇报变成可回归验证的断言。
3. 为 0.4 的玩家操控 UI 确认/预留接口能力——核心问题是：**`WarCommandExecutor` 能否在不依赖某个 `ZoneCommanderAgent` 实例的前提下，仅凭一个合法的 `ZoneDirective` 就完成执行？** 这是 0.4 让玩家和 AI 共用同一条命令管线的前提。

---

## 2. 工作方式的强制要求

**不知道的代码不要猜，不要补。** 本文档里凡是涉及具体函数签名、字段名、调用关系的地方，如果你（Codex）尚未读过对应源码，必须先用 `rg` 定位、`cat`/查看实际内容确认，再下结论或动手改。如果某个判断在读码后发现和本文档预期不一致，**以代码为准**，并在最终汇报里写明文档预期与实际代码的差异，不要为了让汇报"看起来符合预期"而扭曲描述。

本版严格分两个阶段执行，**不允许跳过第一阶段直接改代码**：

- **阶段 A：只读审计**，产出一份发现清单。
- **阶段 B：基于审计结论决定要不要改、改多少**——如果审计发现现状已经符合目标，阶段 B 可能什么都不用改，这是完全可以接受的结果，不要为了"显得做了事"而无意义改代码。

---

## 3. 阶段 A：只读审计清单

请用 `rg`（不要盲扫）确认以下问题，逐条记录结论，形成一份不超过一页的发现清单：

1. **谁在默认路径上真正驱动战争 AI？**
   - `AppContainer.runAIIfNeeded()` 实际调用链是什么？是否经过 `TheaterCommanderPool`/`ZoneCommanderAgent`，还是仍有路径直接调用 `MockAICommander` 或 Legacy `DecisionProvider`？
   - `TurnManager.runGermanAITurn(state:)` 当前内部走的是哪条管线？

2. **Legacy Agent D 管线现在的触发条件是什么？**
   - 全局搜索 `AgentContextBuilder`、`AgentDecisionParser`、`AgentCommandMapper` 的调用方，确认它们是否只在测试 target / 显式 `WarPipelineMode.legacy` 切换下才被实例化，还是仍残留在某个默认执行路径里（哪怕是 fallback 分支）。

3. **`MockAICommander` 现在是不是纯 facade？**
   - 确认它是否只被 `ZoneCommanderAgent` 内部调用，还是仍有外部代码直接 new 出来当作独立决策入口使用。

4. **`WarCommandExecutor` 的对外入口长什么样？**
   - 找到它真实的函数签名。确认：执行一个 directive 时，是否要求传入 `ZoneCommanderAgent` 实例，还是只需要一个合法的 `ZoneDirective`/`DirectiveEnvelope` + 必要的 `GameState`/上下文？
   - 确认内部逻辑是否有任何隐藏假设绑定"这个 directive 一定是 AI agent 生成的"（例如读取了只有 AI 决策路径才会填充的字段）。

5. **`ZoneDirective`/`DirectiveEnvelope` 当前字段。**
   - 列出当前实际 Codable 字段，特别是是否已存在某种"issuer/来源"字段（agent id、来源类型等）。如果没有，记录"无"，不要假设它存在。

6. **`WarDirectiveRecord` 是否对每条命令都留痕。**
   - 确认是否存在任何路径能绕开 `WarDirectiveRecord` 直接产出 `Command` 并执行（这是判断"单一路径"是否成立的关键证据，不能只看代码注释，要看真实调用图）。

7. **`CommandCategory`/`TacticName` 当前取值集合。**
   - 确认目前真实存在哪些取值（预期只有 attack 类 / `standardAttack` 与 defend 类 / `holdPosition` 这一组二元分类），并对照 README 当前措辞，看文档是否有夸大或滞后的描述（例如 README 如果暗示 `AttackIntensity` 已经生效，需要在文档更新阶段纠正）。

审计完成后，请先把这份清单作为中间产出展示出来，再进入阶段 B。

---

## 4. 阶段 B：基于审计结论的整改

只针对阶段 A 中**确认存在差距**的项目动手，不要预设所有项目都需要改。

### 4.1 命令层收口（仅当审计发现确有残留主路径调用时才执行）

- 目标状态：默认运行时（未显式切换 `WarPipelineMode` 的情况下），唯一驱动战争行为的路径是 `TheaterCommanderPool → ZoneCommanderAgent → ZoneDirective → WarCommandExecutor → CommandValidator → RuleEngine → WarDirectiveRecord`。
- Legacy Agent D **代码本身不能删除**（`AGENT.md` 4.6/12）。如果发现它在默认路径被意外触发，修复方式是切断默认触发条件，不是删代码。
- 如果发现 `MockAICommander` 仍被外部直接当独立入口调用，把调用方改为统一经过 `ZoneCommanderAgent`，`MockAICommander` 类保留。

### 4.2 `WarCommandExecutor` / `ZoneDirective` 的 0.4 接口预留

这是本版**最重要**的一项，目标只有一个：**确认或做最小化改造，让"凭一个合法 `ZoneDirective` 即可执行，不要求来自某个特定 AI agent 实例"这件事成立。**

- 如果审计发现 `WarCommandExecutor` 已经是这样设计的（即输入只需要合法 directive + 上下文，不关心生成者是谁）——**什么都不用改**，把这个结论写进阶段文档即可，这是最理想的情况。
- 如果发现有耦合（例如签名强制要求传入 agent 实例，或内部读取了只有 AI 决策路径才会填的字段），做**最小化解耦**：
  - 如果需要标记来源，给 `ZoneDirective`/`DirectiveEnvelope` 增加一个**可选**字段表示 issuer（例如区分"AI 将领"与"玩家"），必须保证 Codable 向后兼容（旧 JSON 不带这个字段时要有默认值），按 `AGENT.md` 4.7/7 的要求执行。
  - 这一步**只做接口能力确认/最小暴露**，不写任何 UI、不实现"玩家如何在界面上发出 directive"，0.4 才做这部分。也不要顺手给玩家加一条可调用的公开方法去触发它——0.4 再做这件事，本版只验证"如果将来这样调用，会不会工作"。

### 4.3 `CommandCategory`/`TacticName` 范围核对（不扩展，只核对口径）

- 不新增 `retreat` 分类，不新增任何 `AttackIntensity` 分流逻辑，不新增装甲/高机动差异化字段或逻辑。
- 如果发现文档（README/AGENT.md）的描述和代码实际情况不一致，按 `AGENT.md` 第 10 节要求修正文档措辞，不要动代码去"凑"文档描述。

---

## 5. 明确非目标（防止范围蔓延）

本版**不做**以下任何事，发现自己在做就停下来：

- 不做撤退命令（`RetreatOperation`、`FrontOperation` 抽象骨架）——已决定推迟到 1.x。
- 不做突破/闪电战（`BreakthroughCorridorPlanner`、`PincerOperation`、`BlitzkriegTarget`、`BreakthroughDepth`）——同样推迟到 1.x。
- 不做 `AttackIntensity` 实际分流执行逻辑。
- 不做装甲/高机动单位的差异化处理。
- 不做 `FrontSegment` 从 region 粒度升级到 hex 粒度（这件事只在突破场景下才有意义，突破推迟，它也跟着推迟，不要提前做）。
- 不实现 0.4 玩家操控 UI 的任何界面代码——本版只确认/暴露后端接口能力。
- 不落地战区互助接口（`requestSupport`/`getAvailableForces`/`notifyThreat`）的调用方。

---

## 6. 诊断优先（按 `AGENT.md` 第 8 节）

如果在阶段 A 审计过程中发现任何"现象学"异常（比如某些战区从不出 directive、拒绝率异常、`WarDirectiveRecord` 缺记录），先按 `AGENT.md` 第 8 节列出的层级定位根因，再判断：

- 如果这个问题直接挡住"命令层能否收口为单一路径"这个本版目标 → 必须本版修。
- 如果是独立的、不影响本版目标达成的旧问题 → 写入阶段文档作为已知问题留给后续版本，不要在本版地毯式排雷。

---

## 7. 测试要求

按 `md/xcode测试规范.md` 确定本版改动对应的测试层级。命令层相关改动建议至少跑到 Stage Regression；如果对 `ZoneDirective`/`DirectiveEnvelope` 做了字段变更，必须跑 Full。

新增/补充的 Probe 级测试至少应覆盖：

1. **默认路径单一性测试**：在默认 `AppContainer` 启动配置下，验证 Legacy Agent D 不会被触发。具体怎么断言（计数、标记字段、调用图检查等）由你按实际代码结构设计，不要假设现成有某个"路径标记"字段。
2. **`WarCommandExecutor` issuer-agnostic 测试**：手工构造一个合法的 `ZoneDirective`（不经过 `ZoneCommanderAgent` 生成），验证 `WarCommandExecutor` 依然能正确产出 `Command` 并被 `RuleEngine` 校验执行。这条测试是本版交付给 0.4 的核心回归基线，未来玩家 UI 接入时应该能直接复用这个验证逻辑。
3. **Codable 向后兼容测试**（仅当 4.2 节确实新增了字段时才需要）：旧版 JSON（不含新字段）仍能正确解码并取到合理默认值。

所有测试命令必须带 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 前缀。如果真实模拟器跑不通，必须在最终汇报中明确说明原因，不能用 `build-for-testing` 的结果包装成"已验证"。

---

## 8. 文档更新要求

- **`README.md`**：更新版本状态为 v0.37；在"当前完成进度"表格补充本版交付；新增一条说明——撤退/突破/闪电战已确认推迟至 1.x 系列，附简短原因；写明 `WarCommandExecutor` issuer-agnostic 能力的确认结论（"本来就支持"或"已做最小改造"，二选一，按实际情况）。
- **`md/xcode测试规范.md`**：同步新增的测试数量与测试命令。
- **新建阶段文档** `md/v0.3/v0.37-命令层整合/0.37-审计与整改记录.md`，内容至少包含：
  - 阶段 A 的完整发现清单（哪怕结论是"一切正常，无需改动"也要写清楚依据）。
  - 阶段 B 实际做了哪些改动（如果什么都没改，写明原因）。
  - 撤退/突破推迟到 1.x 的决策记录（可直接引用本提示词第 1 节）。

---

## 9. 验收标准

- "命令层已收口为单一路径"不是一句汇报结论，而是有对应 Probe 测试断言支撑。
- "0.4 所需的 issuer-agnostic 接口能力是否就位"有明确结论（是/否，以及如果做了改造改了什么），并有对应测试背书。
- 没有出现任何 retreat / breakthrough / intensity 分流 / 装甲差异化相关的新代码。
- README、测试规范、阶段文档与代码实际状态口径一致。

---

## 10. 最终汇报格式

按 `AGENT.md` 第 13 节执行：改了什么、关键文件、跑了哪些验证及具体结果、哪些测试没跑及原因、已知风险或后续建议。如果阶段 B 的结论是"经审计无需改动"，这本身就是一个合法且有价值的交付结果，请在汇报里明确这样陈述，不要为了显得"做了很多事"而虚增改动。
