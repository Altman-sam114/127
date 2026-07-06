# Modern Command Agent — iOS / macOS AI 战略战棋迁移工程

> **当前状态：v6.10 发布候选准备。工程底座仍来自 WWIIHexV0，源码兼容名、target/module 名和旧阿登 fallback 数据仍保留；已完成 v6.0-v6.9 的现代作战方、灰潮种子、现代单位、ISR/EW/contact、火力/空中任务、现代 AI 指挥链、玩家任务入口、现代 C2 UI 和试玩闭环首轮。本轮把主游戏 iOS / macOS display name 收口为 `Modern Command Agent`，新增现代 C2 AppIcon 资产，Playtest 面板支持红/蓝新局选择并显示 Player Side / Opposition / Control Mode / Action Gate / 十个主目标控制摘要，任务面板显示 Mission Status 并按 Recon、UAV、Fire Mission、SEAD、EW 和 Resupply 各自的 validator 预检启用按钮，Playtest 命令反馈区分 success / warning / failure tone，HUD、任务、单位和事件日志主路径使用 Logistics / sustainment 口径，默认 commander 数据改为虚构 Blue / Red C2 staff，commander seed 会排除已分配 commander，地图补给源标签改为现代 Blue/Red 口径，灰潮默认剧本扩到 120 hex / 30 region，并加入现代目标控制胜负判断；同时新增发布候选残留扫描、验收证据矩阵与人工授权重验证清单。玩家任务仍经 `AppContainer -> Command / ZoneDirective -> WarCommandExecutor / RuleEngine`，Mission Status 会复用 validator 预检列出 Ready Tasks 或解释弹药、冷却、目标质量、ROE、防空、目标缺失和友邻风险等拒绝原因；玩家、AI 和 directive 回放的规则拒绝反馈使用可读文案和 tone，不再把 enum raw value 暴露给玩家。AI 失败路径尽量保留 raw JSON 供复盘。历史测试基线曾达到 v0.37 Probe 18/0、Stage Regression 69/0、Full 226/0；当前工作流默认不跑 Xcode / XCTest / 模拟器测试，只按 `md/test/test.md` 做轻量检查，重验证看 GitHub Actions artifact。**

---

## 协作与云端验证

当前协作流程固定为 `main` 直推：Agent B 在本机只跑轻量检查，commit 后 push 到 `origin/main` 触发 GitHub Actions；Agent C 通过未加密 CI 结果包核对 `ci-artifact-manifest.json`、`junit.xml`、`xcodebuild.log` 和失败摘要。详细规则见 `AGENTS.md`、`md/test/test.md`、`md/prompt/README.md`。

灰潮默认剧本的静态数据一致性可用 `ruby scripts/check_grey_tide_data.rb` 复查；该脚本只读取 JSON，核对 tile / region / objective / unit template 引用，不启动 app。

---

## 项目定位

一款正在从 WWIIHexV0 迁移而来的 iOS / macOS 回合制现代战争 AI Agent 策略游戏。目标是在保留 hex 战术权威、region 战略聚合、动态战区、前线、部署和统一规则管线的基础上，迁移到现代联合作战：合成营/任务编组、无人系统、侦察 contact、电子战、精确火力、后勤和可审计 AI Agent 指挥链。

当前 v6.10 是发布候选准备态，不是正式发布。`grey_tide_2030` 目前是 120-hex / 30-region 的可加载现代发布候选剧本，用于替换默认阿登入口并验证现代数据链；它包含机场、港口、雷达/防空、河桥、铁路、燃料、通信、民用缓冲和蓝/红补给入口，`VictoryRules` / `RegionVictoryRules` 对 `grey_tide_2030` 使用十个主目标的现代目标控制判定，Civilian Evac Zone 等 key-only 地点不计入十个主目标。MapEditor 默认桥接读写灰潮资源，编辑器可见模式收口为区域、作战区和任务编组；覆盖默认资源时会保留灰潮已有 `maxTurns`、胜负条件、河流边、VP、occupation 和 river crossing 等编辑器未表达的高级元数据。`modern_unit_templates.json` 已提供现代组件并通过现有 `strength + supplyState + components` 影响移动、战斗和补员成本，灰潮剧本未知模板不再静默回退为 infantry。玩家任务面板可以发起 Recon Area、UAV Orbit、Fire Mission、Air Support / SEAD、Assault Objective、Hold / Delay、Resupply / Repair、Jam / Counter-Drone；实际行动仍由 `Command` 或 `ZoneDirective` 进入 `RuleEngine`。任务面板会显示 Mission Status 来解释按钮不可用原因，Recon / UAV / Fire Mission / SEAD / EW / Resupply 按钮分别复用 `CommandValidator` 预检当前 formation、target、munition 和规则状态；Mission Status 会列出可用 Ready Tasks，或显示首个可读阻塞原因，避免 Fire Mission 缺目标遮住可用的侦察、EW 或后勤任务；Fire Mission 只使用选中 hex / region 命中的 visible contact、选中 region 或选中 hex，不再无选择地回退到第一个 visible contact。在 neutral / green / co-belligerent 控制区内，tube / rocket area fires 会被 `restrictedFireZone` 拒绝，precision / loitering 只有解析到 linked hostile target 时才允许并以 restricted fire zone 风险降级结算；拒绝反馈会进入 `lastCommandMessage` 和 interaction log，Playtest 面板按 success / warning / failure tone 显示图标、颜色和 VoiceOver 标签，Field Prompts 只对 Ready Tasks 使用完成态图标，主 UI 后勤文案使用 Logistics 口径。Playtest tab 支持选择 Blue Force 或 Red Force 新开灰潮局、保存/继续本地快照、清除快照、切换 observer AI 和地图图层；本地快照使用带 schemaVersion 的 envelope 保存 `GameState` 与玩家方，并保留旧裸 `GameState` 快照兼容读取。Playtest 状态区显示 Player Side、Opposition、Control Mode、Action Gate、十个主目标控制摘要、不遮挡地图的短引导和错误反馈；Action Gate 只读解释当前是哪个阵营可下令、AI 可解析、observer 自动化还是需要结束回合，红方玩家会看到阻止 Blue 达标的目标阈值口径，不直接执行命令。非 observer 模式下 AI 只接管当前非玩家敌对阵营。fuel / readiness / signature / 真实武器库 / 复杂实时空战 / 真本地 LLM 多 Agent 并发仍未独立建模。`GamePhase.germanAI/alliedPlayer`、`Division` 源码名、旧 unit template id、target/module 名和若干二战测试 fixture 仍按兼容层保留。发布前仍需人工授权运行时验证：Xcode build、iOS/macOS 启动、UI 点击烟测、SpriteKit 截图、10-20 回合 observer 和性能体感。

**核心参考：**
- 《统一指挥2》：六角格战棋、补给、攻击（战术层参照）
- 《钢铁雄心4》：大战略、省份占领、前线、补给、生产、国家管理（战略层参照）
- EasyTech《钢铁命令》：战役推进、将领、战术操作
- 《世界征服者4》：移动端轻量化策略体验

**核心创新：本地部署 LLM 驱动游戏 AI**
- 元帅、国家约束、联合司令部、Chief of Staff、ISR / Fires / Air / EW / Logistics / Brigade advisory roles 已进入当前指挥链
- agent 根据视野、战况摘要、性格和历史背景输出结构化 JSON 命令
- 游戏规则系统负责校验并执行，LLM 不直接绕过规则修改状态

---

## 地图 / 战区架构（核心决策）

**分层叠加，不是替换。** 六角格保留作战术/战斗层，省份与战区负责战略聚合。

```
Hex（战术层 / 真实占领与移动）
  ↓ hexToRegion
Region（省份规则层 / 资源、人力、补给、胜利点聚合）
  ↓ regionToTheater（初始战区基本单位，只读基准）
Initial Theater Layout（地图编辑器初始划分 / 只读 snapshot）
  ↓ hexToTheater
Dynamic Theater State（运行时动态战区 / 随 hex 推进变化）
  ↓ 动态 hex 邻接
FrontLine / FrontSegment（前线与分段，按动态战区接触生成）
  ↓
WarDeploymentState（FRONT / DEPTH / GARRISON 部署池）
  ↓
ZoneDirective / WarCommandExecutor / RuleEngine
```

**为什么分层：**
- 全球地图纯 hex ≈ 16 万节点，iOS 跑不动（尤其带 LLM agent）
- HOI4 证明：省是规则原子，全球 ~1-2 万省可实时跑
- 战术级 hex（UC2 风格）提供精细操作，战略级省提供全球性能
- **同一局内可切换**：大战略模式看省，zoom 进某省切 hex 板战术微操
- **v0.358 之后的关键语义**：
  - `regionToTheater` = 初始战区基本单位，服务地图编辑器、动态战区生成/合并/消亡的参照，不是运行时推进层。
  - `hexToTheater` = 运行时动态战区权威映射。单位占领一个 hex，只推进这个 hex 的动态战区归属，不能把整个 region 拉走。
  - 前线 = 我方动态战区与敌方动态战区的 hex 邻接接触，按 region 形成 `FrontSegment`。

**v0.2 以来的长期原则**：省份作为战略层叠加，**不替换** hex 坐标系。现有 hex 规则全保留，省作为聚合视图 + 省级规则并行运行。

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 平台 | iOS；v1.1 新增 macOS 主游戏 target `WWIIHexV0Mac`；主游戏 display name 为 `Modern Command Agent`；AppIcon 已接入主游戏 iOS / macOS targets |
| 语言 | Swift |
| UI 框架 | SwiftUI（面板、按钮、日志、单位详情） |
| 地图渲染 | SpriteKit（六角格地图、单位显示、移动/攻击反馈） |
| AI 接口 | `DecisionProvider` 协议（Local Planner / `MockAIClient` 已实现，预留本地 LLM） |

---

## 项目架构

```
WWIIHexV0/
├── Core/          — 核心数据模型（Division、GameState、HexTile、HexCoord、MapState 等）
├── Commands/      — 命令系统（Command、CommandResult、CommandValidation、GameCommandHandling）
├── Rules/         — 规则引擎（RuleEngine、CombatRules、SupplyRules、MovementRules、VictoryRules、CommandExecutor、CommandValidator）
├── Agents/        — AI Agent 管线（旧 Agent D + ZoneCommanderAgent / MarshalAgent / ModernCommandChain）
├── Turn/          — 回合管理器（TurnManager，按玩家方 / 敌对方 / observer 编排 AI）
├── SpriteKit/     — 地图渲染（BoardScene、UnitNode、HexNode、HexLayout、TerrainStyle、BoardSceneAdapter）
├── UI/            — 界面组件（UnitInspectorView、EventLogView、HUDView、CommandPanelView、ModernMissionPanelView、AgentPanelView、RootGameView）
├── App/           — 入口（AppContainer、WWIIHexV0App、WWIIHexV0MacApp）
├── Data/          — 场景数据（DataLoader、ScenarioDefinition JSON、grey_tide_2030、modern_unit_templates.json、general_agents.json、generals.json、unit_templates.json、terrain_rules.json）
├── Probes/        — 历史高速探针测试 target（默认不执行）
└── Tests/         — 历史单元测试 / 集成测试 / 真实战局模拟（默认不执行）
```

### 核心架构原则

- **规则与 UI 解耦**：游戏状态只能由 `RuleEngine` 修改，UI 只读取状态
- **命令管线**：玩家 / AI → `Command` → `CommandValidator` 校验 → `CommandExecutor` 执行 → 日志
- **AI 接口可替换**：`DecisionProvider` 协议，Local Planner / `MockAIClient` 已实现，未来可插入本地 LLM
- **地图分层**：hex（战术层，`HexCoord`）+ region（省份层，`RegionId`）+ dynamic theater（运行时战区，`hexToTheater`），不替换
- **AI 命令与玩家命令共用同一管线**：都经 `RuleEngine` 校验执行

---

## AI / 指令管线接口（已落地）

当前同时保留两条管线：

- **Legacy Agent D 管线**：`AgentContextBuilder → DecisionProvider → AgentDecisionParser → AgentCommandMapper → RuleEngine`。已保留作回归参考，默认不再作为战争 AI 主路径。
- **ZoneDirective 管线（执行权威）**：`ZoneDirective → WarCommandExecutor → RuleEngine → WarDirectiveRecord`。`WarCommandExecutor.execute(_ directive:in:)` 不依赖具体 `ZoneCommanderAgent` 实例，手写合法 `ZoneDirective` 也可执行。
- **v0.5 元帅管线（默认上游）**：`MarshalAgent → MarshalBattlefieldSummarizer → SimulatedMarshalLLMClient → TheaterDirectiveDecoder → TheaterDirectiveCompiler → DirectiveEnvelope / ZoneDirective`。它只做战略意图、JSON I/O、解码校验和 fallback，不直接修改 `GameState`。
- **v6.6 现代指挥链 advisory 层**：`ModernCommandChainOrchestrator → ModernCommandChainPlan → ModernCommandChainDecoder`。它把元帅 `TheaterDirectiveEnvelope` 拆成国家约束、联合计划、Chief of Staff notes、ISR / Fires / Air / EW / Logistics / Brigade sub-directive，并校验 schemaVersion、issuerId、turn、faction、zone、region、contact 和 role/mission 组合；失败时只记录 diagnostics，不执行半成品。
- **后续统治者层（未接入当前执行主链路）**：未来只能位于元帅上游，输出国家级姿态或约束条件；不得绕过 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。

| 文件 | 职责 | 关键类型/协议 |
|------|------|--------------|
| `Agents/DecisionProvider.swift` | 统一 AI 接口 | `protocol DecisionProvider { func decide(context:) async throws -> AgentDecisionEnvelope }` |
| `Agents/GameAgent.swift` | 运行时 agent 模型 | `GameAgent`（精简版，无 Cabinet/DirectiveDomain，v0.5 污染已剔除） |
| `Agents/AgentConfiguration.swift` | legacy agent bridge | 旧 `general_agents.json` 兼容路径；现代默认回合使用当前 faction 的 local planner fallback |
| `Agents/AgentContexts.swift` | agent 能看到的摘要 | `AgentContext` + `AgentContextBuilder`（无 organization，适配 v0.1） |
| `Agents/AgentDecision.swift` | 结构化决策 DTO | `AgentDecisionEnvelope` / `AgentOrder` / `AgentOrderType`（move/attack/hold/resupply） |
| `Agents/AgentDecisionParser.swift` | JSON → envelope | 校验 schemaVersion / agentId / turn，malformed 抛 typed error |
| `Agents/AgentCommandMapper.swift` | order → Command | `AgentCommandMapper.map(_:agentId:) -> IssuedCommand`，缺字段抛 error |
| `Agents/AgentDecisionRecord.swift` | 决策记录 | `AgentDecisionRecord` / `CommandResultSummary` / `ModernCommandChainReplayItem`（UI 读） |
| `Agents/MockAIClient.swift` | local planner provider | 启发式：resupply → contact attack → objective movement → hold |
| `Agents/LLMClient.swift` | Legacy LLM 接口预留 | `protocol LLMClient` + `LLMRequest`（旧 Agent D 用，默认不启用） |
| `Agents/LocalLLMDecisionProvider.swift` | 本地 LLM provider | 注入 `LLMClient` + `AgentPromptBuilder` + parser，失败由上层 fallback MockAI |
| `Agents/AgentPromptBuilder.swift` | prompt 构造 | system + user prompt，强制 JSON 输出 |
| `Agents/ModernCommandChain.swift` | v6.6 现代指挥链 advisory 层 | `StrategicConstraintEnvelope` / `JointCommandPlan` / `ModernSubDirective` / `ModernCommandChainDecoder` / `ModernCommandChainOrchestrator` |
| `Turn/TurnManager.swift` | AI 回合编排 | `runGermanAITurn(state:) async -> AgentTurnOutcome` legacy 方法名，实际按当前 active faction / player side 判定控制权 |
| `App/AppContainer.swift` | AI 接线 | `runAIIfNeeded()` 按玩家方、observer 和 active faction 判定是否接管，并写入 state / decision record |
| `UI/ModernCommandDesignTokens.swift` | v6.8 C2 设计 token | 面板间距、圆角、44pt 触控尺寸、side / sensor / fires / EW / sustainment 色标 |
| `UI/ModernMissionPanelView.swift` | v6.7+ 玩家任务面板 | Recon / UAV / FireMission / SEAD / Assault / Hold / Resupply / EW 任务入口，v6.8 使用 C2 token 统一样式，所有 action 交给 `AppContainer` |
| `UI/ModernPlaytestPanelView.swift` | v6.9 试玩闭环面板 | 新局、保存/继续本地快照、observer AI、地图图层和短引导入口，所有 action 交给 `AppContainer` |
| `UI/AgentPanelView.swift` | 决策展示 | 读 `record`（agent/provider/intent/context/command-chain replay/command results/errors/raw JSON） |
| `UI/RootGameView.swift` | 主界面接线 | HUD / command panels call `advanceOrRunAI()`；命令提交、重置和继续后由 `AppContainer.runAIIfNeeded()` 受控触发 |

**Local Planner 行为：**
跳过已行动 formation → 低补给/包围优先 resupply → contact-gated 目标优先 attack / fire support → 依据当前 objective 和态势推进 → 否则 hold。

**v0.7 ZoneDirective 战术行为：**
`ZoneCommanderAgent` 读取所属 `FrontZone` 的前线/部署摘要，`BinaryTacticClassifier` 会结合兵力比、机动兵力、炮兵支援、纵深预备队、压力和补给警告，在 `standardAttack`、`blitzkrieg`、`spearhead`、`breakthrough`、`pincerMovement`、`fireCoverage`、`feint`、`guerrillaWarfare`、`holdPosition`、`elasticDefense`、`defenseInDepth`、`lastStand` 之间分类；`WarCommandExecutor` 将这些战术降级为 `move / attack / hold / allowRetreat`，仍统一交给 `RuleEngine` 校验执行。`WarDirectiveRecord` 记录 `category` / `tactic` / `commanderAgentId` / `commandTarget`，便于后续接真 LLM 回放与审计。

**v0.5 MarshalDirective 行为：**
`MarshalBattlefieldSummarizer` 把 `GameState` 降维为元帅摘要，只包含 front zone、strength ratio、补给警告、目标和事件，不把全量 hex 网格喂给模型。`SimulatedMarshalLLMClient` 生成 fenced JSON 形式的 `TheaterDirectiveEnvelope`；`TheaterDirectiveDecoder` 提取并校验 JSON；`TheaterDirectiveCompiler` 把元帅意图编译成现有 `ZoneDirective`。v0.7 后 `TheaterDirective` 可携带 `convergenceRegionId` / `coordinatedZoneIds` 支持钳形会师意图；解码或编译失败时 fallback 到 `TheaterCommanderPool`，不执行半成品 LLM 输出。

**v6.6 ModernCommandChain 行为：**
`MarshalAgent` 在成功解码 operational directive envelope 后生成 `ModernCommandChainPlan`，并把 fenced JSON 交给 `ModernCommandChainDecoder` 复核。decoder 会检查顶层和嵌套 envelope 的 schema、issuer、turn、faction、role，以及每条 sub-directive 的 zone / region / contact / mission 合法性；失败只写 diagnostics。`TurnManager` 将 Operational Directive JSON、Modern Command Chain JSON 和最终 Compiled ZoneDirective JSON 一起写入 `AgentDecisionRecord.rawJSON`；即使 operational 或 advisory JSON 校验失败，原始 JSON 也会尽量保留给 AI 面板审计。已验证的 sub-directive 会派生成 `ModernCommandChainReplayItem`，让 AI 面板直接列出 ISR / Fires / Air / EW / Logistics / Brigade 任务、目标和理由。

**后续 Ruler / Diplomacy 边界：**
统治者层不在当前执行主链路中。后续如要加入国家、集团、外交关系或统治者 agent，必须先设计独立 schema，并保持底层战争规则仍由 `Faction`、`ZoneDirective`、`WarCommandExecutor` 和 `RuleEngine` 收口。

---

## 历史里程碑 / Legacy Baseline

以下 v0-v1.x 条目是 WWIIHexV0 历史基线和源码兼容背景，不代表 v6.10 当前默认剧本、主 UI 文案或玩家可见命名；当前默认入口仍是 `grey_tide_2030` 和现代 Blue / Red 口径。

### ✅ v0：六角格测试板（已完成）

**历史基线场景**：阿登测试战场（legacy Ardennes fixture），11×9 六角格地图。当前默认发布候选入口已切到 `grey_tide_2030`。

| 功能模块 | 状态 |
|----------|------|
| 六角格 axial 坐标系统 | ✅ |
| 地形系统（平原/森林/山地/城市/道路/河流/要塞） | ✅ |
| 移动系统（地形消耗、道路加成、跨河惩罚、敌方阻挡） | ✅ |
| 战斗系统（近战/炮兵远程、地形防御修正、反击） | ✅ |
| 侧翼/背后加成 | ✅ |
| 占领系统（城市控制权变更） | ✅ |
| 补给系统（supplied / lowSupply / encircled） | ✅ |
| 包围判定与惩罚 | ✅ |
| 回合系统（legacy：德军 AI 先手 → 盟军玩家 → 结算；v6.10 当前由玩家方 / 敌对方 / observer 判定控制权） | ✅ |
| Legacy Local Planner / MockAI 将领 agent | ✅ |
| 结构化 JSON 命令解析与校验 | ✅ |
| AI 决策日志面板（AgentPanelView 读 AgentDecisionRecord） | ✅ |
| 胜利条件（巴斯托涅占领 / 消灭 3 单位 / 切断补给） | ✅ |

---

### ✅ v0.1：strength、撤退与补员（已完成）

| 功能模块 | 状态 |
|----------|------|
| `Division` 升级为 strength/maxStrength，保留 hp/maxHP 兼容 | ✅ |
| 战斗改为 strength 伤害（organization 已移除） | ✅ |
| 撤退状态：自动寻找安全相邻格撤退 | ✅ |
| 撤退失败施加额外惩罚 | ✅ |
| `resupply/rest` 恢复 strength | ✅ |
| 包围每回合扣 strength | ✅ |
| UI 显示 Strength、Retreating 状态 | ✅ |
| 日志按 combat/retreat/reinforce/encircle/supply 分类 | ✅ |
| 死守 / 允许撤退（RetreatMode）按钮与 HOLD 防御加成 | ✅ |

**v0.1 最终模型：** 只看兵力，无 organization。`RetreatMode`（retreatable/hold）控制撤退：HOLD 防御 +20%，RETREATABLE 单次损失比例 ≥ 35% 自动撤退。

---

### ✅ Agent D：AI/Agent 决策管线（已完成）

| 功能模块 | 状态 |
|----------|------|
| `DecisionProvider` 协议（MockAI + LocalLLM 共用） | ✅ |
| `AgentContext` / `AgentContextBuilder`（Codable 摘要，无 UI/SpriteKit 对象） | ✅ |
| `AgentDecisionEnvelope` / `AgentOrder` JSON schema | ✅ |
| `AgentDecisionParser`（校验 schema/agent/turn） | ✅ |
| `AgentCommandMapper`（order → Command，缺字段抛 error） | ✅ |
| `MockAIClient` legacy heuristic provider | ✅ |
| `LLMClient` / `LocalLLMDecisionProvider` / `AgentPromptBuilder`（预留，v0 默认关） | ✅ |
| `TurnManager`（按玩家方 / 敌对方 / observer 编排 AI，含 endTurn） | ✅ |
| `AppContainer.runAIIfNeeded()`（启动自动跑 AI 回合） | ✅ |
| `AgentDecisionRecord` + `AgentPanelView`（UI 读决策记录） | ✅ |
| `AgentPipelineTests`（8 测试：context/MockAI/parser/mapper/provider 失败/非法命令） | ✅ |

---

### ✅ v0.2 Agent 1：省份图架构（已完成）

省份图规则层模型。**叠加，不替换 hex。** hex 仍战术层权威坐标，province 是战略层聚合。

| 文件 | 职责 |
|------|------|
| `Core/Region.swift` | `RegionId`（RawRepresentable<String>）、`RegionNode`、`RegionEdge`、`RegionGraph`、`CityInfo`、`ResourceAmount`、`ResourceType`、`OccupationState`、`RegionEdgeKey`（对称键）、`RegionValidationError`（9 case） |
| `Core/MapState.swift`（改） | 加 `regions`/`hexToRegion`/`regionEdges` 字段（默认空）；加 province 查询：`region(for:)`/`region(id:)`/`neighbors(of:)`/`areAdjacent`/`edgeBetween`/`representativeHex`/`regionDistance`/`regionGraph`；加 `validateRegionGraph()` |
| `Core/Terrain.swift`（改） | `HexTile` 加 `regionId: RegionId?`（默认 nil） |
| `RegionGraph.validate()` | idMismatch/emptyDisplayHexes/representativeHexNotInDisplayHexes/neighborNotFound/neighborNotBidirectional/edgeEndpointNotFound/edgeNotInNeighbors |
| `MapState.validateRegionGraph()` | 复用上图校验 + hexToRegionPointsToMissingRegion + displayHexesOverlap |
| `Tests/RegionGraphTests.swift` | 19 测试：编解码/neighbors/areAdjacent/hexToRegion/representativeHex/validate 全错误类型+valid+empty |

**设计约束（Agent 1 已守）：**
- hex 规则全保留，province 默认空不破现有行为
- `MapState.ardennesV0()` 不改（保持纯 hex，测试用）
- 省份挂载在 Data 层（DataLoader），Core 不依赖 Data

---

### ✅ v0.2 Agent 2：省份数据层（已完成）

阿登 v0.2 省份图数据 + 加载。17 省覆盖全部 99 hex，零重叠，邻接双向一致。

| 文件 | 职责 |
|------|------|
| `Data/ardennes_v02_regions.json` | 17 省/41 边/99 hex 映射/2 补给源/4 目标。schemaVersion 2 |
| `Data/RegionDataSet.swift` | `RegionDataSet` + Codable 定义（`RegionNodeDefinition`/`CityInfoDefinition`/`ResourceAmountDefinition`/`OccupationStateDefinition`/`RegionEdgeDefinition`/`RegionSupplySourceDefinition`/`RegionObjectiveDefinition`）+ 映射 `toRegions()`/`toRegionEdges()`/`toHexToRegion()` |
| `Data/DataLoader.swift`（改） | 加 `loadArdennesV02Regions()` + `validate(_ regionData:)`（复用 validateRegionGraph）；`loadInitialGameState()` 叠加省份数据（try? 失败 fallback 纯 hex）+ 反向填 HexTile.regionId |

**省份设计：**
- 德方控制：german_east_depot（补给源）、eifel_approach、schnee_eifel
- 盟方控制：allied_west_depot（补给源）、bastogne（主目标 VP5）、bastogne_fortress、st_vith、western_approach
- 中立（原 allies 领土中立化，owner/controller null 映射回退 .allies）：meuse_approach、houffalize、luxembourg_road、ardennes_forest_north/central/south、northern_ridge、southern_ridge、northern_frontier
- 路径：german_east_depot→bastogne=2，allied_west_depot→bastogne=3

| `Tests/ArdennesV02DataTests.swift` | 17 测试：解码/region 数/hexToRegion 覆盖/validate/邻接双向/repHex/路径连通/补给源/目标/关键省/控制权 |

---

### ✅ v0.3：战区、前线、部署、战争指令（当前主线，已推进至 v0.37）

| 版本 | 主题 | 关键内容 |
|------|------|----------|
| **v0.31** | Theater 战区层 | 四战区初始化、控制比例、70% 阈值、扩张/退役接口 |
| **v0.32** | FrontLine 前线层 | 动态前线、segment、dirty 更新、简化包围识别 |
| **v0.33** | WarDeployment 部署层 | FRONT / DEPTH / GARRISON 分层，FrontZone 单元池 |
| **v0.34** | 地图编辑器 | 默认地图与项目 schema 打通 |
| **v0.351** | 初级战争指令 | `ZoneDirective` / `WarCommandExecutor` / `MockAICommander` |
| **v0.352** | 新管线唯一化 | `WarPipelineMode.zoneDirective` 默认，观察者模式，分层战略 UI |
| **v0.353** | 默认地图验收 | hex controller 成为归属权威，补给归属跟随占领者 |
| **v0.354** | 联动修复 | 占领→region→theater→frontline 同回合联动，ZOC 友军穿越修正，拒绝率治理 |
| **v0.355** | 动态/初始战区分离 | `initialSnapshot` 与运行时动态战区分离，前线 overlay 与观察者 UI |
| **v0.356-v0.357** | 地图/前线 UI 修正 | 编辑器与游戏视角统一、开局单位越界检查、前线按战区/segment 着色 |
| **v0.358** | hex 动态战区语义收口 | 动态战区改跟 `hexToTheater`，region 基础战区只作初始/生成参照；AI/部署/前线测试同步更新 |
| **v0.36** | 命令层扩展与多将领 MockAI | `CommandCategory` / `TacticName` / `DirectiveTarget` / `ZoneCommanderAgent` / `TheaterCommanderPool` |
| **v0.37** | 命令层统一整合 | 移除 `TurnManager` 的 `MockAICommander` fallback，默认路径收口到 `TheaterCommanderPool`；补 issuer-agnostic executor 探针 |
| **v0.5** | 元帅层与模拟 LLM JSON | `MarshalAgent` / `TheaterDirectiveEnvelope` / decoder / compiler / marshal fallback |
| **v0.7** | 高级战术与命令扩展 | 闪电战、定点矛头、突破、钳形攻势、火力覆盖、佯攻、游击战、弹性防御、纵深防御、死守 |

### ⏳ 后续方向

| 版本 | 主题 | 关键内容 |
|------|------|----------|
| **v0.4** | 聊天命令与角色服从 | 玩家通过聊天框命令将领；将领根据性格/忠诚回应；命令可被质疑/拖延/抗命 |
| **v0.5** | 元帅决策链与模拟 LLM JSON | `MarshalAgent`、`TheaterDirectiveEnvelope`、JSON decoder、compiler、fallback；统治者只预留为后续上游，不恢复 Cabinet/Minister |
| **v1.0** | 大战略原型 | 经济/科技/生产；空军实体化；简化海军；天气；多国家多战区；全球地图；美术资源 |
| **v1.x** | 多回合战术行动 | 撤退命令、突破/闪电战、装甲差异化、`AttackIntensity` 深度分流等复杂多回合行动骨架 |

**v0.37 决策记录：** 撤退、突破、闪电战、装甲差异化和 `AttackIntensity` 深度分流推迟至 1.x。v1.0 只先把 `infiltration` 解释为默认低投入上限，不引入额外伤害、绕规则推进或多回合追踪行动。

---

## 核心设计约束

**LLM 使用原则（必须始终遵守）：**
1. 不让每个单位每回合都调用 LLM
2. LLM 只读取摘要，不读取完整地图
3. LLM 输出必须经过 `CommandValidator` 校验才能执行
4. 非法命令先尝试自动修复，修复失败则丢弃并记录日志
5. 没有 LLM 时，Local Planner / `MockAIClient` 接管所有决策

**架构扩展约束（后续 agent 必须遵守）：**
- 不要跳过命令管线直接修改 `GameState`
- **不要替换 HexCoord 坐标系**：hex 是战术层，province 是叠加的战略层，两者共存
- **不要把 `regionToTheater` 当动态战区推进层**：运行时战区归属看 `hexToTheater`，突破只推进 hex。
- **不要给 Division 加回 organization**：v0.1 已移除，只看兵力
- **不要引入 v0.5 Cabinet/StrategicDirective/Minister 污染**：v0.5 误删事件已发生，GameAgent 保持精简版
- 新增系统通过 `DecisionProvider` / `RuleEngine` / `Command` 接入，不直接改核心规则
- 保持核心语义不退步；默认只做轻量检查，Xcode / XCTest / 模拟器等重测试必须由人工明确授权。

---

## 文档索引

```
md/
├── 项目总规划.md                    — 整体设计目标、地图方案、LLM 架构、长期路线图
├── v0测试/
│   ├── phase0_v0_minimum_scope.md   — v0 最小可玩范围定义、数据结构清单
│   ├── phase1_hex_core_rules.md     — 六角格坐标、地形、战斗、补给、包围详细规则
│   ├── phase3_v0_engineering_architecture.md — v0 工程架构设计
│   ├── 阶段性4:第一版可玩测试板任务拆解.md  — v0 任务拆解和实现步骤
│   └── 误删agentD/                  — Agent D 打捞代码 + jsonl 会话记录（历史归档）
└── v0.1～1.0提示词/
    ├── 总体长期规划.md              — v0 至 v1.0 路线图全览
    ├── v0.1.md                      — v0.1 子 agent 提示词（已完成）
    ├── v0.2.md                      — v0.2 提示词（⚠️ 旧版纯省份替换方案，已废弃；新版见下方）
    ├── v0.3.md                      — v0.3 前线系统提示词
    ├── v0.4.md                      — v0.4 聊天命令与角色服从提示词
    ├── v0.5.md                      — v0.5 国家与部长 agent 提示词
    └── v1.0.md                      — v1.0 大战略原型提示词
```

> ⚠️ `v0.2.md` 是旧的"纯省份替换 hex"方案，已废弃。v0.2 新方向见本文档"地图架构"与"v0.2"行：**省份叠加，不替换 hex**。

---

## 给后续 Claude Code 的提示

**你接手时的代码库状态：**
- v0.5 分支已引入元帅层与模拟 LLM JSON/decoder/ compiler；历史测试基线曾达到 v0.37 Probe 18/0、Stage Regression 69/0、Full 226/0。当前默认不跑重测试，只做 `md/test/test.md` 允许的轻量检查。
- 战斗模型：兵力伤害为主，`RetreatMode`（retreatable/hold）控制撤退，无 organization。
- 默认战争 AI 管线：`MarshalAgent` 读取摘要并模拟输出 `TheaterDirectiveEnvelope` JSON，经 `TheaterDirectiveDecoder` 校验后进入 `ModernCommandChainOrchestrator / ModernCommandChainDecoder` 生成只读 advisory 复盘，再由 `TheaterDirectiveCompiler` 降级成 `ZoneDirective`，最后走 `WarCommandExecutor`。`TheaterCommanderPool` / `ZoneCommanderAgent` 仍作为 fallback 和显式 `.zoneDirective` 路径。
- Legacy Agent D 管线保留但默认不调用。
- 地图坐标系：hex 仍是战术权威；Region 是省份规则层；动态战区看 `hexToTheater`。

**继续开发前请先阅读：**
1. 本 README（地图架构三层决策 + Agent D 接口表）
2. `WWIIHexV0/Core/Division.swift`（当前 Division 模型）
3. `WWIIHexV0/Core/MapState.swift` / `Region.swift` / `Theater.swift`
4. `WWIIHexV0/Rules/TheaterSystem.swift` / `FrontLineManager.swift` / `WarDeploymentManager.swift`
5. `WWIIHexV0/Commands/WarDirective.swift` / `WarCommandExecutor.swift`
6. `WWIIHexV0/Agents/ZoneCommanderAgent.swift` / `MockAICommander.swift`
7. `md/prompt/anti生成/v0.5/anti/0.50_v0.5_marshal_implementation_record.md`

**当前必须遵守：**
- 不删 `HexCoord`，不把运行时战区推进退回 region 粒度。
- `Initial Theater Layout` / `regionToTheater` 是地图编辑器与动态演化基准，不是实时前线。
- `Dynamic Theater State` / `hexToTheater` 是游戏战区层权威。
- 前线 UI 和 AI target 选择必须基于动态 hex 邻接；历史测试 fixture / 语义文档也必须构造真实相邻 hex，不能只声明 region 邻接。
- `ZoneDirective` 新字段必须保持 Codable 向后兼容。
- 元帅层和未来统治者层不得绕过 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- 当前 v0.5 只模拟 LLM JSON 接口，不接真实模型；真实 LLM 接入必须保留 decoder 校验与 fallback。

**轻量检查**（每轮先读 [`md/test/test.md`](md/test/test.md)，默认禁止 Xcode / XCTest / 模拟器 / 性能类测试）：
```bash
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md
```
旧测试口径残留、JSON / project / scheme 检查按 `md/test/test.md` 追加执行。未获人工授权时，不跑历史 Probe / Stage / Full。
