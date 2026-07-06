# WWIIHexV0 核心流程文档（v6.10 发布候选准备）

> 本文是项目当前核心逻辑的接手文档。目标不是复述历史设计，而是按当前代码真实链路说明：数据如何进入游戏，hex / region / theater / front / deploy 如何派生，主游戏和地图编辑器如何共同维护同一套地图语义，AI / 玩家命令如何落到规则系统。

资料依据：`AGENTS.md`、`README.md`、`update_log.md`、`md/test/test.md`、v0.355/v0.36/v0.37 阶段文档、最近 git 记录，以及当前源码中的 `Core/`、`Rules/`、`Commands/`、`Agents/`、`Turn/`、`App/`、`SpriteKit/`、`UI/`、`MapEditor/` 与关键测试。

---

## 0. 一句话总览

当前主链路是：

```text
MapEditor / JSON 数据
  -> DataLoader
  -> GameState
  -> Hex controller / Division coord
  -> Region 聚合
  -> EconomyState 收入 / 生产 / 补员
  -> Initial Theater snapshot + runtime hexToTheater
  -> FrontLine 动态 hex 接触
  -> WarDeployment hexToFrontZone + FRONT/DEPTH/GARRISON
  -> MarshalAgent / Operational Directive JSON (`TheaterDirective` schema)
  -> TheaterDirectiveDecoder
  -> ModernCommandChainOrchestrator / ModernCommandChainDecoder
  -> TheaterDirectiveCompiler
  -> ZoneCommanderAgent fallback / 手写 ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> CommandExecutor
  -> StrategicStateSynchronizer
  -> UI overlay / 日志 / WarDirectiveRecord

Player Mission Planning
  -> ModernMissionPanelView
  -> AppContainer
  -> Command / ZoneDirective
  -> RuleEngine / WarCommandExecutor

Modern C2 Presentation
  -> ModernCommandDesignTokens
  -> HUDView C2 status strip
  -> ModernMissionPanelView tokenized controls
  -> BoardScene sensor / contact / EW / fire overlays

Playtest Loop
  -> ModernPlaytestPanelView
  -> New Operation Side / Player Side / Opposition / Control Mode
  -> AppContainer local snapshot save / load / clear
  -> observer AI toggle / map layer setting
  -> short guidance / last command feedback

Release Candidate Readiness
  -> app display name = Modern Command Agent
  -> Assets.xcassets/AppIcon.appiconset
  -> HexNode logistics markers = LOG B / LOG R
  -> v6.10 residual scan report
  -> runtime validation requires human authorization
```

最关键的铁律：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 region 内 hex controller 加权聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区归属，不是运行时推进层。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- `EconomyState` 是 faction 级经济总账；收入来自受控 region、城市、工厂、基础设施和补给值，但战术占领仍以 hex 为准。
- 玩家、AI、后续聊天命令最终都必须经过 `Command` / `ZoneDirective -> WarCommandExecutor -> RuleEngine`，不能直接改 `GameState`。
- v6.6 默认战争 AI 上游是 `MarshalAgent -> Operational Directive JSON (TheaterDirective schema) -> ModernCommandChain advisory JSON -> TheaterDirectiveCompiler`，下游执行收口到 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- `ModernCommandChainPlan` 只做可审计分解、JSON 校验和复盘展示；ISR / Fires / Air / EW / Logistics / Brigade sub-directive 当前不直接执行。
- v6.7 玩家现代任务 UI 只调用 `AppContainer` 方法；任务最终落成 `Command` 或 `ZoneDirective`，不得在 SwiftUI View 里直接改 `GameState`。
- v6.8 只新增现代 C2 展示层和地图态势 overlay；HUD、任务面板和 SpriteKit 标记只读 `GameState`，不绕过规则系统写状态。
- v6.9 Playtest tab 只通过 `AppContainer` 做新局、保存/继续本地快照、observer 和图层设置；本地快照是带 schemaVersion 的 envelope，不污染默认 JSON 资源，并兼容旧裸 `GameState` 快照读取。
- v6.10 发布候选准备收口玩家可见命名、App 图标资产、玩家扮演方说明、主目标控制摘要、地图补给源标签、残留扫描和发布前重验证清单；未获授权前不声明正式发布或运行时发布级已验证。
- 统治者层只作为后续方向预留；当前执行主链路不调用 `RulerAgent`，也不写统治者决策记录。

## 0.1 云端协作与验证闭环

本项目的协作制度已升级为 `main` 直推和 GitHub Actions 云端结果包验收。该流程只改变协作和验证骨架，不改变战斗、地图、经济、AI 或 UI 业务语义。

当前默认协作链路：

```text
人工提出目标
  -> Agent A 读取 AGENTS / update_log / flow / test / prompt，写版本化提示词
  -> Agent B 基于最新 origin/main 切到 main 小步实现
  -> Agent B 默认不在本机跑检查命令
  -> Agent B commit 并 push 到 origin/main
  -> GitHub Actions 运行 .github/workflows/ci-results.yml
  -> Actions 上传未加密 CI 结果包
  -> Agent C gh auth login 后下载 artifact
  -> Agent C 核对 manifest / junit / xcodebuild.log / failure summary
      -> 有问题：退回 Agent B 在 main 上追加修复 commit 并重新 push
      -> 无问题：确认 origin/main 最新 run 通过并同步核心文档
```

分支边界：

- `main` 是当前唯一上传、提交、推送和云端验证分支。
- 暂不把 `smalldata_test`、`develop`、`codeb/...`、候选分支或 PR 合并流写入默认流程。
- 既有历史分支只作为历史状态记录，不参与本轮默认协作制度。

云端结果包：

- workflow：`.github/workflows/ci-results.yml`
- 触发：`push` 到 `main` 或手动 `workflow_dispatch`
- artifact：`WWIIHexV0-ci-cloud-flow-v1-main-<short_sha>-run<run_id>-attempt<run_attempt>`
- 必含：`ci-artifact-manifest.json`、`ci-failure-summary.md`、`junit.xml`、`xcodebuild.log`、`git-diff-check.log`、`plutil.log`、`xmllint.log`、`grey-tide-data.log`、`modern-visible-text.log`，以及可生成时的 `WWIIHexV0.xcresult`
- Agent C 缓存：`/private/tmp/wwiihexv0-c-review-<run_id>/`

AITRANS 可复用项与不照搬项：

- 可复用：main 直推、云端重验证、未加密结果包、Agent C 下载复判、云端失败后在 main 追加修复 commit。
- 不照搬：漫画探针、GGUF/模型 Release、`test/1.png`、`smalldata_test` 分支、大数据/密钥/密码包和项目专属输出。

## 0.2 v6.0 现代战争迁移兼容层

v6.0 当前只完成“迁移审计 + 玩家可见显示名兼容层”，没有改变底层规则权威、JSON raw value 或默认剧本加载。

当前兼容策略：

```text
旧源码 / 旧 JSON 兼容名
  Faction.germany / Faction.allies
  GamePhase.germanAI / GamePhase.alliedPlayer
  Division.name
  ProductionKind.panzerDivision / motorizedDivision
  MapDisplayLayer.province / initialTheater / dynamicTheater
        |
        v
玩家可见显示层
  Red Operational Group / Blue Joint Task Force
  Red Command / Blue Command
  operationalDisplayName
  Armored Task Force / Mechanized Task Force / Logistics Package
  Sector / Baseline / Operational / Contact / Brigade
```

必须注意：

- `Faction.displayName` 现在是现代作战显示名；旧名保存在 `legacyDisplayName`，只作兼容说明或迁移审计使用。
- `GamePhase.displayName` 现在是通用回合显示名；旧名保存在 `legacyDisplayName`。
- `Division.operationalDisplayName` 只替换 UI 显示，不改 `Division.name` 编码字段。
- `Faction.opponent` 仅作为旧接口兼容属性保留；当前主路径敌我判断走 ROE / `isHostile(to:)` helper。`GamePhase.germanAI/alliedPlayer` 和旧阿登 fallback JSON 仍是后续命名与兼容风险。
- v6.0 当轮没有新增 ISR / ContactTrack / EW / FireMission / AirTasking / LogisticsNetwork 状态；v6.4 已加入第一版作战感知状态，详见下文 v6.4 小节。

## 0.3 v6.1 作战方与 ROE 兼容层

v6.1 第一批实现让现代作战方进入底层模型，但仍不切换默认剧本。

当前 `Faction` 支持：

```text
旧兼容 raw value：
  germany / allies

现代 raw value：
  redForce / blueForce / greenForce / neutral

alignment：
  red / blue / green / neutral
```

数据加载现在通过 `Faction.dataValue(_:)` 解析旧值和现代 alias，例如 `power_blue -> blueForce`、`civilian -> neutral`。`DiplomacyState` 通过 `defaultROEStatus(toward:)` 建立初始关系，最小状态包含 `allied`、`coBelligerent`、`neutral`、`restricted`、`hostile`、`atWar`。

已替换的核心二元敌我判断：

- `CommandValidator` / `RegionCommandValidator` 攻击目标校验
- `MovementRules` ZOC 判定
- `SupplyRules`
- `RegionSupplyRules`
- `RegionCombatRules`
- `EconomyRules` 邻敌补员 / 部署判定
- `AgentContexts`
- `WarCommandExecutor` 目标排序
- `FrontLineManager` 前线对手推导
- `WarDeploymentManager` enemy zone / enemy presence 判定
- `FireSupportRules` 防空威胁判定
- `ZoneCommanderAgent` lost objective 摘要
- `AppContainer` 直接点击攻击目标和玩家宏观攻击 zone 判定

`RegionDataSet.toRegions()` 已修正历史 fallback：

```text
controller 缺省 -> owner
owner/controller 都缺省 -> neutral
```

经济层初始化已收窄：缺省只回退到旧双阵营 `legacyBelligerents`，bootstrap 时按实际单位阵营加旧双阵营 fallback 建账本，避免 `Faction.allCases` 扩容后让 green / neutral 默认进入旧剧本经济循环。

仍未完成：

- `GamePhase` Swift case 仍保留 `.germanAI` / `.alliedPlayer` 兼容旧代码和测试，但 Codable 与 `GamePhase.dataValue(_:)` 已支持现代 `redCommand` / `blueCommand` alias；新保存的 `GameState` phase 和灰潮默认 `initialPhase` 使用现代 alias，旧阿登 fallback 的 `alliedPlayer` 仍可解码。
- v6.2 已切入 `grey_tide_2030` 默认剧本种子；v6.10 已扩展为 120 hex / 30 region 的发布候选规模，但仍需运行时验证。
- `Faction.opponent` 仍保留为旧接口兼容属性，但火力、可见性、前线和其他当前主路径 fallback 不再调用二元 opponent。
- restricted / civilian region 已有首版火力门禁：non-hostile 控制区内 tube / rocket area fires 会被 `restrictedFireZone` 拒绝，precision / loitering 只有解析到 linked hostile target 时才允许并以 restricted fire zone 风险降级结算；完整 no-fire zone、collateral 和授权链仍待后续版本细化。

## 0.4 v6.2 灰潮行动默认剧本种子

v6.2 第一批实现把默认新局入口切到现代虚构剧本 `grey_tide_2030`；v6.10 已把该默认剧本扩到发布候选规模，并加入现代目标控制胜负判断。

当前新增默认资源：

```text
WWIIHexV0/Data/grey_tide_2030_scenario.json
WWIIHexV0/Data/grey_tide_2030_regions.json
```

规模与内容：

- 120 个 hex，30 个 region，覆盖 6 个 operational sector。
- Blue Force / Red Force / Neutral 三方数据值。
- 关键点：East Airport、Harbor Terminal、Radar Ridge、River Bridge、Industrial Hub、Comms Center、Fuel Depot、Rail Junction、Coastal Battery、Highland Pass 等。
- 初始任务编组：蓝/红各 8 个现代 formation，覆盖侦察、机械化、火力、防空/工程、后勤、特战与安全分队。
- `VictoryRules` / `RegionVictoryRules` 对 `grey_tide_2030` 使用十个主目标判定：蓝方提前控制 7 个主目标获胜；最终回合蓝方控制至少 6 个主目标获胜，否则红方防御网络守成。
- 十个主目标中有 6 个初始由 Neutral / Civilian 控制，必须通过地面移动占领进入胜负计数：Harbor Terminal、River Bridge、Comms Center、Fuel Depot、Rail Junction、Refinery District。
- neutral / civilian 关键地点但不计入十个主目标的 key-only 节点包括 Industrial Hub、Urban Core、Civic Center、River Ford、Southern Causeway、Civilian Evac Zone；它们可影响态势、区域语义或后续任务设计，但不应被写成灰潮即时 / 终局胜利阈值来源。
- v6.3 起默认单位改用 `modern_unit_templates.json`，旧 `unit_templates.json` 只作阿登数据集和 fallback 兼容。
- `scripts/check_grey_tide_data.rb` 提供灰潮默认剧本的可复现静态一致性检查：只读取 JSON 和 `VictoryRules.swift`，核对 tile、region、objective、key location、initial unit、unit template、supply source、victory condition 引用；校验 objective 与 key location 一一链接且坐标 / 名称一致、region edges 与 neighbors 集合一致、补给源 tile / region faction 与 controller 不冲突、初始单位不落敌控 hex；并校验 `VictoryRules.greyTideMainObjectiveIds`、scenario victoryConditions 的 `objectiveIds` 和 region `mainObjective=true` 三套主目标集合一致，不启动 app。

默认启动顺序现在是：

```text
grey_tide_2030_scenario + grey_tide_2030_regions
  -> 失败时回退 ardennes_v0_scenario + ardennes_v02_regions
  -> 再失败时回退 GameState.initial() + 旧 region 叠加
```

MapEditor 默认资源桥也切到 `grey_tide_2030`，导出时默认写 `blueForce` / `redForce` / `neutral`，不再把现代地图导回 `allies/germany`。

## 0.5 v6.3 现代单位、移动、战斗和后勤基础

v6.3 第一批实现把默认现代剧本从旧二战模板迁到现代合成作战模板，同时保持 hex 权威和统一命令管线不变。

当前默认模板入口：

```text
DataLoader.loadUnitTemplates()
  -> 优先 modern_unit_templates.json
  -> 缺失时 fallback unit_templates.json

DataLoader.loadArdennesDataSet()
  -> 固定读取 unit_templates.json
  -> 保持旧阿登数据集和历史测试 fixture 的模板集合不变
```

`ComponentType` 现在支持现代组件：

```text
armor / mechanizedInfantry / lightInfantry / recon
artillery / rocketArtillery / airDefense
engineer / logistics / uav / loiteringMunition
specialForces / electronicWarfare
```

旧 `tank`、`motorizedInfantry`、`infantry`、`artillery` raw value 仍可解码，用于旧 JSON、旧测试和 fallback。玩家默认路径不再通过旧模板 id 生成灰潮单位。

现代规则差异首版：

- 装甲：开阔地强，进入森林、城市、工事、山地仍受机动惩罚。
- 机械化：道路上有进攻效率，复杂地形机动较装甲轻但仍受限。
- 轻步兵 / 特战：城市、森林、工事沿用步兵防御加成，山地额外加强。
- 工程：降低渡河、工事进入/突破相关移动或攻击惩罚。
- 火力 / 火箭炮 / 巡飞弹：作为 fires family 提高远程火力与补员工业成本。
- 防空 / 电子战：降低无人系统攻击效果，并提升面对无人系统时的防御。
- 后勤：在低补给和包围时减轻 attack / movement / defense 衰减，并提高补员补给成本。
- 侦察 / UAV：提高 vision，默认剧本侦察屏卫使用 ISR 类组件。

战术 raw value 仍保持历史兼容，例如 `blitzkrieg`、`fireCoverage`、`pincerMovement` 继续可被 AI JSON 解码；玩家可见展示名已映射为 `Armored Thrust`、`Suppression`、`Envelopment` 等现代术语。`WarDirectiveRecord.tacticDisplayName` 是当前 UI 展示入口。

仍未完成：

- FireMission / AirTasking / 精确火力命令已在 v6.5 做抽象首版；真实武器库、真实 fuel 消耗、独立 readiness / signature 规则仍未完整建模。
- ammo 已在 `FireSupportState` 中抽象为 side 预算；readiness / fuel posture / signature posture 目前从 `Division` 既有 strength、supply、行动/撤退状态和组件权重派生显示，尚未作为独立字段落库；electronicProtection 尚未作为独立字段落库。
- 现代战役地图已扩到 120-hex / 30-region 发布候选规模，但未做运行时长回合验证。

## 0.6 v6.4 ISR、ContactTrack 和电子战基础

v6.4 第一批实现把现代战争的“发现目标再打击”前半段接入状态和命令管线；v6.5 已在此基础上加入第一版 FireMission / AirTasking，见下一节。

新增运行时状态：

```text
GameState.operationalAwareness: OperationalAwarenessState
  contacts: [String: ContactTrack]
  sensorCoverage: [SensorCoverage]
  ewEffects: [EWEffect]
```

Contact 模型：

```text
ContactTrack
  ownerFaction / observerSide
  lastKnownCoord
  confidence: low / medium / high / confirmed
  estimatedType: armor / infantry / artillery / airDefense / logistics / unknown
  source: groundRecon / uav / signal / visual / fireObservation
  ageInTurns
  linkedDivisionId: only rules-internal, not exposed by AI/UI summaries
```

规则链路：

- `VisibilityRules.refreshAwareness(in:)` 从友军单位 vision、recon、UAV、防空、EW 组件生成 `SensorCoverage`，再为覆盖内敌军生成或刷新 contact。
- `Command.recon` 经过 `CommandValidator` 校验单位、阶段、阵营、目标 hex 和侦察距离后，由 `CommandExecutor -> VisibilityRules.performRecon` 刷新目标周边 contact，并写入 `intelligence` 日志。
- `Command.electronicWarfare` 经过同一命令管线校验，由 `VisibilityRules.applyElectronicWarfare` 生成持续若干回合的 `EWEffect`，降低受影响 side 的传感器质量，并写入 `electronicWarfare` 日志。
- 回合推进时 `VisibilityRules.advanceTurn` 会让 EW 递减、contact 老化、可信度降级，low contact 继续老化后消失。
- `VisibilityRules.targetQuality(contactId:for:in:)` 和 `contactStrengthEstimate(_:)` 是 v6.5 火力任务接入前的目标质量/强度估算 helper。

信息隔离：

- `AgentContextBuilder` 不再把真实敌军 `enemyDivisions` 放进 AI 摘要，改为 `contactSummaries`；legacy prompt 也展示 Visible contacts，而不是 Known enemy divisions。
- `ZoneCommanderAgent`、`MarshalBattlefieldSummarizer` 和 `MockAICommander` 的可见敌情强度改由 visible contacts 估算。
- `WarCommandExecutor.visibleEnemyDivision` 只会把 medium+ contact 的内部 `linkedDivisionId` 解析成真实攻击目标；没有 contact 时不凭空选择隐藏敌军。
- 普通 UI 视角不再显示敌军 `Division` 兵牌；Region inspector 显示 contact 类型、可信度、来源和年龄，不显示敌军真实单位名。Observer mode 仍保留调试全显。

仍未完成：

- 当前 contact overlay 只在 Region inspector 和攻击高亮中首版可见，还不是完整地图图层。
- `linkedDivisionId` 仍存于 `OperationalAwarenessState` 供规则内部解析，AI/UI 摘要默认不暴露该字段。

## 0.7 v6.5 精确火力、空地协同、无人系统和防空抽象

v6.5 第一批实现把“侦察 -> 确认 contact -> 防空压制 / 火力打击 -> 地面推进”的现代作战闭环接入统一命令管线。它是抽象任务模型，不做真实武器数据库、复杂实时空战、独立 fuel/readiness/signature 规则或完整空域模拟。

新增运行时状态：

```text
GameState.fireSupportState: FireSupportState
  ammoBudgetBySide: [OperationalSideAlignment: FireSupportAmmoBudget]
  cooldownsByAsset: [String: Int]
  scheduledMissions: [FireMission]
  lastMissionResults: [FireMissionResult]
  airTaskingState: AirTaskingState
    sorties
    airDefenseThreat
    airSuperiority
    suppressionEffects
    missionResults
```

新增命令：

- `Command.fireMission(issuerId:target:munitionClass:)`：由火力单位或无人/巡飞弹载具发起，target 支持 contact / hex / region，但必须能解析到本方可见 contact。
- `Command.uavRecon(divisionId:target:)`：强制以 UAV source 刷新目标周边 contact；高防空 / EW 风险会让任务降级或失败。
- `Command.suppressAirDefense(divisionId:target:)`：消耗可用火力弹药，在目标周边写入持续若干回合的 `AirDefenseSuppression`，降低后续空中/无人任务风险。

规则链路：

- 三类新命令全部经过 `CommandValidator -> CommandExecutor -> FireSupportRules`，不得绕过 `RuleEngine` 直接改 `GameState`。
- validator 检查阶段、阵营、单位行动权、目标 hex、射程、source asset、目标质量、弹药、冷却、防空威胁和友军邻近风险。
- fire mission 只对 medium+ contact 或 region/hex 内 medium+ contact 放行；low / missing contact 会被拒绝。
- neutral / green / 同阵营协同方控制区会被视作 restricted fire zone：tube / rocket area fires 被拒绝，precision / loitering 需要 linked hostile target，且结算时加入 `restrictedFireZone` risk flag 和轻量效果惩罚。
- restricted fire gate 只限制火力任务，不改变 Civilian Evac Zone 等 key-only / civilian 节点的胜负身份，也不把它们纳入十个主目标阈值。
- executor 会消耗对应 `MunitionClass` 弹药、设置 source cooldown、记录 `FireMissionResult` / `AirSortie`，并写入 `fireSupport` 日志。
- 命中目标时只施加有限 `strength` damage，必要时触发撤退或消灭；不会占领 hex，也不会替代地面推进。
- `fireCoverage` 战术在 `WarCommandExecutor` 中会先尝试生成一次 contact-gated `fireMission`，再继续现有 ground attack / hold fallback。

仍未完成：

- 真实武器库、弹种库存分层、真实 fuel 消耗、独立 readiness、独立 signature、electronic protection 尚未独立字段落库；UI 只展示从现有单位状态派生的 readiness / fuel posture / signature posture。
- Air superiority 当前是抽象占位，未做持续空域争夺、截击、CAP 或机场出动率。
- 火力 UI 仍主要通过日志可见，还没有独立火力范围 / 空中任务 overlay。
- AI 只通过 `fireCoverage` 首版生成火力任务，尚未引入 FiresCoordinator / ISRCoordinator 独立 Agent。

## 0.8 v6.6 现代 AI Agent 指挥链和审计复盘

v6.6 第一批实现把现代联合指挥层接到元帅 AI 与既有执行管线之间。它不替代 `TheaterDirectiveCompiler`、`ZoneDirective`、`WarCommandExecutor` 或 `RuleEngine`，而是在元帅 JSON 成功解码后生成一份可审计的现代指挥链 JSON。

新增 AI 指挥链模型：

```text
StrategicConstraintEnvelope
  schemaVersion / issuerId / turn / faction / role=nationalCommand
  roeSummary / riskTolerance / priorityObjectives / prohibitedActions

JointCommandPlan
  schemaVersion / issuerId / turn / faction / role=jointCommand
  strategicIntent / theaterDirectiveIds / subDirectives

ModernSubDirective
  role: nationalCommand / jointCommand / chiefOfStaff / isrCoordinator
        firesCoordinator / airTasking / ewCoordinator / logistics / brigadeCommander
  missionType: setROE / theaterObjective / deconflict / reconArea
               confirmContact / fireMission / suppressAirDefense / airRecon
               electronicWarfare / resupply / assault / hold / reserve
  optional zoneId / regionId / contactId

ModernCommandChainPlan
  strategicConstraints + jointPlan + chiefOfStaffNotes
  compiledZoneDirectiveCount / summary
```

运行链路：

- `MarshalAgent` 先按既有流程生成并解码 `TheaterDirectiveEnvelope`。
- `ModernCommandChainOrchestrator` 根据元帅摘要、TheaterDirective 和当前 `GameState` 生成 deterministic `ModernCommandChainPlan`，并输出 fenced JSON。
- `ModernCommandChainDecoder` 重新解析该 JSON，校验顶层和嵌套 envelope 的 schemaVersion、issuerId、turn、faction、role。
- decoder 逐条校验 sub-directive：role 是否允许 missionType、zone 是否存在且属于该 faction、region 是否存在、contact 是否存在且对该 faction 可见。
- 校验成功后，plan 写入 `MarshalDirectiveResolution.commandChainPlan`；校验失败只添加 diagnostics，不执行半成品。operational directive 或 advisory JSON 失败时，`MarshalDirectiveResolution` 仍尽量保留原始 JSON，供 `AgentPanelView` 审计。
- `TheaterDirectiveCompiler` 仍把元帅 TheaterDirective 编译成 `ZoneDirective`，再由 `WarCommandExecutor -> RuleEngine` 执行。
- `TurnManager` 将 Operational Directive JSON、Modern Command Chain JSON 和最终 Compiled ZoneDirective JSON 合并写入 `AgentDecisionRecord.rawJSON`，`parsedIntent` 增加现代指挥链 summary，并把已验证 sub-directive 派生成 `ModernCommandChainReplayItem`。
- `AgentPanelView` 默认展示结构化 Command Chain 回放项：角色、任务、优先级、可读目标和 rationale；卡片标注 `Advisory`，只读 `AgentDecisionRecord`，不执行 sub-directive。完整 Operational Directive 明细、diagnostics 和 raw JSON 保留在折叠的 Technical Replay 区，供审计和排错使用。

安全边界：

- 现代 sub-directive 当前是 advisory，不直接改 `GameState`，不直接发 `Command`。
- 任何模型输出失败、schema 不匹配、turn/faction/issuer 不匹配、引用不存在或 role/mission 不合法时，都不会执行半成品。
- 没有新增 API key、模型路径或网络依赖；真实本地 LLM 多 Agent 接入仍留给后续单独版本。

仍未完成：

- UI 已能通过现有 AI 面板查看结构化 Command Chain 摘要，并在折叠 Technical Replay 中查看 directive 明细和 raw JSON；但还没有专门的多 Agent 决策复盘全屏视图。
- sub-directive 还没有独立调参 UI，也不会直接编译成 FireMission / Recon / EW command。
- ChiefOfStaff 当前是 deterministic notes / deconflict 说明，未做复杂冲突仲裁搜索。

## 0.9 v6.7 玩家现代指挥 UI、任务计划和人机协同

v6.7 第一批实现把玩家侧从单纯 `Hold / Retreat / Reinforce` 扩展为现代任务面板。它不新增旁路执行器，不在 SwiftUI View 里改状态，而是把任务按钮接到 `AppContainer`，再由现有 `Command` 或 `ZoneDirective` 管线执行。

新增 UI 入口：

```text
RootGameView
  -> CompactInfoPanel.mission / "Tasks"
  -> ModernMissionPanelView
      - Formation / Target / Logistics / Contacts / Ammo 摘要
      - Mission Status：解释 observer、未选单位、非玩家 phase、已行动、Ready Tasks、缺少 fire target、各任务 validator 拒绝原因或宏观指令可用状态
      - ISR: Recon Area / UAV Orbit
      - Fires: Fire Mission / Air Support / SEAD
      - Maneuver: Assault Objective / Hold / Delay
      - Sustainment / EW: Resupply / Repair / Jam / Counter-Drone
```

任务落点：

- `Recon Area` -> `Command.recon` -> `CommandValidator` -> `VisibilityRules.performRecon`。
- `UAV Orbit` -> `Command.uavRecon` -> `FireSupportRules.validateUAVRecon` / `executeUAVRecon`。
- `Fire Mission` -> `Command.fireMission`，优先使用选中 hex / region 命中的 visible contact；否则落到 selected region / hex，仍由 validator 判定目标质量和弹药；不再在未选目标时自动回退到第一个 visible contact。
- `Air Support / SEAD` -> `Command.suppressAirDefense` -> `FireSupportRules.validateSuppressAirDefense` / `executeSuppressAirDefense`。
- `Jam / Counter-Drone` -> `Command.electronicWarfare` -> `VisibilityRules.applyElectronicWarfare`。
- `Resupply / Repair` -> `Command.resupply` -> `SupplyRules.applyResupplyRest`。
- `Assault Objective` -> 既有玩家 `ZoneDirective attack` -> `WarCommandExecutor -> RuleEngine`。
- `Hold / Delay` -> 既有玩家 `ZoneDirective defense` -> `WarCommandExecutor -> RuleEngine`。

交互边界：

- 面板按钮根据 `AppContainer` 暴露的 `canIssueSelectedReconMission`、`canIssueSelectedUAVMission`、`canIssueSelectedFireMission`、`canIssueSelectedSuppressAirDefenseMission`、`canIssueSelectedElectronicWarfareMission`、`canIssueSelectedResupplyRepairMission`、`canOrderModernAssaultObjective`、`canOrderModernHoldDelay` 和 observer mode 启用/禁用；这些任务按钮均复用 `CommandValidator` 预检当前 selected formation / target / preferred munition 和规则状态。Mission Status 会列出可用的 Ready Tasks 和可用 sector directive，或提前解释弹药、冷却、目标质量、ROE、防空、目标缺失、友邻风险等首个可读拒绝原因，避免宏观指令或 Fire Mission 缺目标遮住可用的侦察、EW 或后勤任务。
- 任务拒绝同步写入 `lastCommandMessage`、`lastCommandFeedbackTone` 和 interaction log；`CommandValidationError.displayMessage` 是玩家、AI 回放和 directive diagnostics 的统一可读拒绝文案来源，避免 UI 直接显示 `targetOutOfRange`、`restrictedFireZone` 等 enum raw value。Command / RegionCommand / FireMissionTarget 的玩家显示、directive decoder、Modern Command Chain decoder 和 command intent mapping 诊断也继续收口为 Sector / Zone / Objective / Formation / Contact Track / tactic display 文案，避免 AI 回放或事件日志把主要 `region_*`、`front_zone_*`、`theater_*`、command debug string 直接推给玩家。玩家宏观 directive 部分失败时，`lastCommandMessage` 会带出第一条规则拒绝原因，完整细节继续保留在 `WarDirectiveRecord`。
- Commander、Unit Inspector、Diplomacy 和 MapEditor 默认导出文案只显示现代 display 文案：planned operation、commander fallback 名称、selection feedback、country/bloc relation、contact line 和无名 logistics node 都避免直接展示 `region_*`、`front_zone_*`、`blue_coalition` 等 raw id；底层 record id、Codable raw value、排序和映射仍保持兼容。
- 计划线仍复用 v0.4 `PlayerPlannedOperation` 的 attack / defend 可视化；v6.8 已加入 sensor / contact / EW / fire support 只读态势 overlay 首版。
- Playtest 面板已有 C2 Overlay 独立显示开关和只读图例，复用 C2 token 色标解释 sensor、jammed sensor、EW area、fire result、contact confidence、contact type code 和 logistics 标记；开关只控制 `BoardScene` 是否绘制现代态势 overlay，不写 `GameState`、不改变命令或规则。

仍未完成：

- 没有专门 readiness / fuel / signature 字段；`Division` 现在只读派生 readiness、fuel posture 和 signature posture，任务面板、单位详情和 tooltip 会展示这些态势，同时继续显示 logistics 状态、visible contact 数和 fire support ammo 摘要。
- 任务按钮没有单独的 plan edit / preview / cancel 流程；点击即提交到规则系统。
- Recon / Fires / EW 的地图 overlay 仍是首版轻量标记；Playtest 面板已有 C2 Overlay 显示开关和只读图例，但未做 tooltip、动画、Reduce Motion 策略或视觉截图验收。
- 未做本机 UI 点击或模拟器烟测，等待云端 build 和后续人工授权。

---

## 0.10 v6.8 发布级现代 C2 UI、美术和交互收口首轮

v6.8 第一批实现只收口现代 C2 展示层，不新增命令执行器，不改变战术权威和 AI 指挥链。新增 UI token 和 overlay 都从现有 `GameState` 派生，仍由规则系统负责产生 contact、EW、fire result、air tasking 和 supply 状态。

新增展示链路：

```text
GameState
  -> OperationalAwarenessState.contacts / sensorCoverage / ewEffects
  -> FireSupportState.lastMissionResults / AirTaskingState / ammoBudgetBySide
  -> EconomyState / Division.supplyState
  -> HUDView C2 status strip
  -> ModernMissionPanelView tokenized mission controls
  -> BoardScene.drawModernC2Overlays
```

SwiftUI 首轮：

- `ModernCommandDesignTokens` 统一 8pt 圆角、间距、44pt 最小触控区，以及 blue/red/green/neutral、sensor、fires、EW、sustainment、warning 和 contact confidence 色标。
- `HUDView` 从旧资源格子升级为现代 C2 状态条，显示 turn、side、phase、victory、visible contacts、EW zones、ammo、air、logistics risk 和 C2 queue。
- `ModernMissionPanelView` 继续只调用 `AppContainer` 的任务方法，但使用 token 化样式、`Label` / SF Symbols、44pt 按钮和更清晰的 Logistics / Contacts / Ammo 摘要。
- `NewGameButton` 使用同一触控尺寸约束。

SpriteKit 首轮：

- `BoardScene.drawModernC2Overlays` 在非 frontLine 图层绘制只读态势标记。
- Sensor coverage 以青色半透明 hex heatmap 表示，jammed coverage 用 EW 色描边。
- EW effects 以紫色 hex 区域表示。
- Fire support 最近结果以火力环和 `F` / `!` 标记表示。
- Visible contacts 以稳定尺寸圆点标记，按 confidence 改变颜色，并用 A/I/F/AD/L/? 表示估计类型。
- `ModernPlaytestPanelView` 的 C2 Overlay toggle 独立控制 `BoardScene.drawModernC2Overlays`，Legend 对上述 sensor / jammed / EW / fire / contact / logistics 标记做只读解释。

边界和未完成：

- overlay 当前已有独立显示开关和只读 legend；仍没有 tooltip、Reduce Motion 动画策略或截图验收。
- v6.8 没有新增 readiness / fuel / signature / electronicProtection 字段；后续 v6.10 收口增加的是派生显示，不是独立持久字段。
- 没有改 `Command`、`ZoneDirective`、`WarCommandExecutor` 或 `RuleEngine` 执行语义。
- 未在本机启动 app、模拟器或 UI 点击烟测；视觉正确性等待后续人工授权或专门 UI 验收。

---

## 0.11 v6.9 新手引导、继续和试玩闭环首轮

v6.9 第一批实现把“能打开局面”推进到“能在主界面继续试玩”。v6.10 后续收口补上红/蓝新局选择器：`ModernPlaytestPanelView` 可选择 Blue Force 或 Red Force 后开新局，`AppContainer` 会把 `playerFaction` 与初始 active faction / phase 一起设置到所选阵营。当前仍不设计完整存档浏览器、文件导入导出或多存档槽。

新增试玩链路：

```text
RootGameView
  -> CompactInfoPanel.playtest / "Playtest"
  -> ModernPlaytestPanelView
      - Operation / Player / Turn 摘要
      - New Operation Side
      - Action Gate
      - Main Objective Control 摘要
      - New Operation
      - Save / Continue / Clear Snapshot
      - Observer AI toggle
      - Default Layer picker
      - C2 Overlay toggle
      - C2 Overlay Legend
      - Field Prompts / last command feedback tone
  -> AppContainer
      - resetGame(playerFaction:)
      - saveLocalSnapshot()
      - loadLocalSnapshot()
      - clearLocalSnapshot()
      - playtestActionGateTitle / playtestActionGateDetail
      - playtestObjectiveSummaryText / playtestObjectiveThresholdText
      - playtestGuidanceItems
```

本地快照边界：

- 快照内容是 `LocalPlaytestSnapshot` envelope，存入 `UserDefaults` 的 `modernCommandAgent.localSnapshot.v1` key；当前 schemaVersion 为 2，包含 `savedAt`、`playerFaction` 和 `gameState`。
- 快照摘要单独存入 `modernCommandAgent.localSnapshot.summary.v1`，用于 UI 显示。
- 玩家方 raw value 仍冗余写入 `modernCommandAgent.localSnapshot.playerFaction.v1`，用于兼容旧裸 `GameState` 快照；新 envelope 以 `playerFaction` 字段为准，`GamePhase` 通过自定义 Codable 写出现代 `blueCommand` / `redCommand` alias。
- `decodeLocalSnapshot(_:)` 先按 envelope 解码，schemaVersion 不高于当前版本时直接恢复；若失败则按旧裸 `GameState` 解码，并从旧 playerFaction key 或当前默认作战方推断玩家方。
- `loadLocalSnapshot()` 解码后仍经过 `StrategicStateBootstrapper().bootstrapIfNeeded` 和 `refreshGeneralAssignments`，并清空选择、高亮、临时交互日志和最近 AI/指令记录。
- 保存/继续失败会写 `lastCommandMessage`、`lastCommandFeedbackTone` 和 interaction log，给玩家可读反馈。
- 本地快照不修改 `grey_tide_2030_scenario.json`、`grey_tide_2030_regions.json` 或旧阿登 fallback 资源。

引导边界：

- `playtestActionGateTitle` 与 `playtestActionGateDetail` 根据 victory、observer、玩家可下令状态和 `shouldRunAI` 派生，告诉玩家当前是哪个阵营 orders open、哪个 active faction 可由 AI 解析、需要 advance turn，还是胜负已达成；它只读状态，不执行 AI 或命令。
- `playtestObjectiveSummaryText` 与 `playtestObjectiveThresholdText` 从 `VictoryRules.greyTideObjectiveControlCounts(in:)` 派生，显示 Blue / Red / Neutral 对十个主目标的控制数；Blue 玩家看到 Blue 胜利阈值，Red 玩家看到阻止 Blue 达标的阈值口径。它只读 `GameState`，不写胜负状态。
- `playtestGuidanceItems` 根据当前选择、可行动状态、visible contacts、fire support result 和 phase 生成最多 4 条短提示。
- `ModernPlaytestPanelView` 对 command feedback 使用 success / warning / failure tone 区分图标、颜色和 VoiceOver 标签；Field Prompts 默认使用 info 图标，只对 Ready Tasks / ready 状态使用完成态图标；New / Save / Continue / Clear Snapshot 带 accessibility hint，Clear Snapshot 使用 destructive role。
- 提示显示在 Playtest tab 内，不遮挡地图核心交互。
- 本轮不做全屏 onboarding、弹窗教程、截图检查或 UI 点击自动化。

仍未完成：

- 没有多步骤新局向导或完整 AI 控制矩阵；当前只支持 Playtest tab 中的 Blue / Red 新局选择、observer mode 和只读 Action Gate。
- 没有多存档槽、文件导出、iCloud、版本迁移 UI 或存档损坏修复面板。
- 没有本机启动 app、模拟器、UI 点击、10-20 回合观察者模式或截图验收。
- v6.10 已补发布候选残留扫描、资源检查口径和人工授权重验证清单。

## 0.12 v6.10 发布候选准备和残留扫描

v6.10 当前不是正式发布，而是把现代战争迁移路线收口到可提交发布候选的状态：代码和文档准备好后继续通过 `origin/main` GitHub Actions artifact 做云端 build 复核；本机仍不主动跑 Xcode、模拟器、UI 点击、截图、observer 长回合或性能检查。`v6.10_release_candidate_evidence.md` 现在作为发布候选证据矩阵，逐项记录总提示词要求、代码依据、已核对 artifact 和未授权运行时风险。

本轮明确处理的玩家可见项：

- iOS / macOS 主游戏 target 的 `INFOPLIST_KEY_CFBundleDisplayName` 已统一为 `Modern Command Agent`。
- `WWIIHexV0/Assets.xcassets/AppIcon.appiconset` 已提供 iPhone、iPad、macOS 和 iOS marketing 所需尺寸，并通过 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 接入 iOS / macOS 主游戏 target。
- Playtest 面板提供 `New Operation Side` segmented control，可用 Blue Force 或 Red Force 新开灰潮局；状态区继续显示 `Player Side`、`Opposition`、`Control Mode` 和 `Action Gate`，对手由当前局面 hostile faction 推导，Action Gate 只读解释玩家 / AI / observer / end-turn 的当前推进状态。
- `HexNode` 的补给源标签从旧 `SUP A` / `SUP G` 先改为 Blue / Red 口径，当前继续收口为按 `Faction.alignment` 派生的 `LOG B` / `LOG R`；旧 `.allies` / `.germany` 兼容阵营也会显示为现代 Blue / Red 后勤标记。
- AI 面板空态、Commander / Unit / Region / Economy 面板继续收口玩家可见旧口径：`guderian` / `MockAI` 占位改为现代 planner 文案，默认 `generals.json` 改为灰潮虚构 Blue / Red commander，`GeneralDispatcher` 的 seed 匹配会排除已分配 commander，ruler / theater / front zone / division / IC / supplies 标签改为 national command / operational zone / command sector / formation / contact line / personnel / materiel / logistics。
- `scripts/check_modern_visible_text.rb` 提供可复现的现代玩家可见文案防回归检查：扫描主应用 App / UI / SpriteKit Swift 字符串、会进入命令结果 / 日志 / diagnostics 的 Swift 字符串、若干 Core 可见 displayName 映射和默认现代 JSON 显示字段；旧阿登 fallback、历史文档、测试 fixture、target/module 名和源码 raw value 兼容名不纳入默认 hard fail。
- 灰潮默认剧本扩展到 120 hex / 30 region / 16 初始 formation / 25 objectives，并通过十个主目标接入现代胜负判断。
- `md/prompt/v6.0-现代战争迁移/v6.10_release_candidate_progress.md` 记录发布候选矩阵、残留扫描、保留的源码兼容名和人工授权重验证清单。
- `md/prompt/v6.0-现代战争迁移/v6.10_release_candidate_evidence.md` 记录发布候选验收证据矩阵，并引用最近已核对的 `main` 云端 artifact。

仍保留的兼容残留：

- `WWIIHexV0` / `WWIIHexV0Mac` target、module、scheme 和 bundle id 未在 v6.10 改名，避免引入 Xcode 工程级重命名风险。
- `GamePhase.germanAI/alliedPlayer`、`Division`、`ProductionKind.panzerDivision` 等源码兼容名仍保留，但玩家可见显示层走现代 display name。
- `ardennes_*`、`unit_templates.json`、`general_agents.json` 和旧 agent 配置继续作为 fallback / 历史测试 fixture，不是默认现代剧本主路径；默认 `generals.json` 当前提供虚构现代 Blue / Red commander。

发布前仍需人工授权：

- Xcode build、iOS Simulator 或真机启动、macOS target 启动。
- 基础 UI 点击烟测、SpriteKit 截图或人工视觉检查。
- App 图标在 Dock / SpringBoard / 安装包中的真实显示。
- 至少 10-20 回合 observer 模式和性能体感检查。

---

## 1. 核心状态对象

### 1.1 GameState

源码：`WWIIHexV0/Core/GameState.swift`

`GameState` 是运行时总状态，主要字段：

```text
scenarioId
turn / maxTurns
activeFaction
phase
map: MapState
theaterState: TheaterState
frontLineState: FrontLineState
warDeploymentState: WarDeploymentState
economyState: EconomyState
fireSupportState: FireSupportState
divisions: [Division]
victoryState
eventLog
warDirectiveRecords
playerCommandState
operationalAwareness
```

状态含义：

- `map` 保存地图、hex、region、补给源和目标点。
- `divisions` 保存所有单位。单位当前位置在 `Division.coord`，不是 region 或 theater。
- `theaterState` 保存初始战区快照与运行时动态战区。
- `frontLineState` 从动态战区相邻 hex 派生。
- `warDeploymentState` 从动态战区/前线/单位位置派生，供 AI 调度单位。
- `economyState` 保存 manpower、industry、supplies、生产队列、上回合收入/维护费/补员消耗，不直接改变战术占领权。
- `operationalAwareness` 保存 contact、sensor coverage 和 EW effects，是 v6.4 后 UI/AI 可见敌情的入口；真实敌军 `Division` 仍只供规则内部解析。
- `fireSupportState` 保存火力弹药、source cooldown、fire mission result、air sortie、防空威胁快照和防空压制效果，是 v6.5 后火力/空中任务的入口。
- `eventLog` 给 UI 和调试看。
- `warDirectiveRecords` 记录战争指令执行回放，供 v0.36+ 后续接 LLM / 聊天命令审计。

### 1.2 MapState / Hex

源码：`WWIIHexV0/Core/MapState.swift`、`WWIIHexV0/Core/Terrain.swift`

`MapState` 的底层是 hex：

```text
width / height
tiles: [HexCoord: HexTile]
supplySources: [SupplySource]
objectives: [Objective]
regions: [RegionId: RegionNode]
hexToRegion: [HexCoord: RegionId]
regionEdges: Set<RegionEdge>
```

`HexTile` 关键字段：

```text
coord
baseTerrain
hasRoad
riverEdges
controller: Faction?
cityName / fortressName
isPassable
regionId: RegionId?
```

当前语义：

- `HexCoord` 是 axial q/r 坐标，移动、攻击、距离、邻接都基于 hex。
- `HexTile.controller` 是真实占领权威；中立 hex 的 controller 为 `nil`。
- `HexTile.regionId` 是聚合标记，不参与寻路/战斗权威判断。
- `MapState.region(for:)` 优先读 `hexToRegion`，fallback 读 `tile.regionId`。
- `MapState.supplySources(for:)` 会通过 `controllingFaction(for:)` 判断补给源当前归属，优先看 supply hex 的 controller，再 fallback region controller，再 fallback 原始 supply faction。

### 1.3 Region

源码：`WWIIHexV0/Core/Region.swift`

`RegionNode` 是省份/区块规则层：

```text
id / name
owner
controller
terrain
neighbors
displayHexes
representativeHex
city
infrastructure / supplyValue / factories / resources
coreOf
occupationState
isPassable
```

当前语义：

- Region 是战略聚合层，不替代 hex。
- `displayHexes` 声明该 region 覆盖哪些 hex。
- `representativeHex` 是 UI 和某些 region->hex 转换的默认点。
- `neighbors` / `regionEdges` 是省份邻接图，但 v0.358 后不能单独拿它判断动态前线。前线必须看真实 hex 邻接。
- `RegionNode.controller` 不是直接推进权威。它由 `RegionOccupationRules.aggregateControl` 从 hex controller 加权派生。

### 1.4 Theater

源码：`WWIIHexV0/Core/Theater.swift`、`WWIIHexV0/Rules/TheaterSystem.swift`

`TheaterState` 关键字段：

```text
initialSnapshot: TheaterInitialSnapshot?
theaters: [TheaterId: TheaterNode]
hexToTheater: [HexCoord: TheaterId]
regionToTheater: [RegionId: TheaterId]
lastUpdatedTurn
```

`TheaterNode` 关键字段：

```text
id / name / status
regionIds
neighborTheaterIds
controllingFaction
controlRatios
victoryPointArea
frontWeight
unitIds
supportEligibleUnitIds
spilloverPolicy
recentThreats
```

当前语义必须分清三件事：

1. `initialSnapshot.regionToTheater`
   - 开局时捕获。
   - 只读初始战区布局。
   - UI 的 `initialTheater` 图层读取这里。
   - 地图编辑器导出的 region->theater assignment 会进入这里。

2. `regionToTheater`
   - 当前基础/初始战区单位。
   - 作为动态战区生成、合并、formalization、退役的参照。
   - 不代表运行时推进结果。
   - 不允许“占领一个 hex 后把整个 region 的 `regionToTheater` 改掉”。

3. `hexToTheater`
   - 运行时动态战区权威。
   - 单位突破进入某个 hex 后，只把这个 hex 改到进攻方动态战区。
   - 前线、动态战区图层、部署层都应以它为准。

`TheaterSystem.updateTheaters` 的派生刷新包括：

```text
seedMissingHexAssignments
  -> 给未填的 hexToTheater 填基础 regionToTheater
rebuildDynamicRegionMembership
  -> TheaterNode.regionIds 变为“该动态战区当前覆盖到的 region 集合”
rebuildNeighborTheaters
  -> 按 hexToTheater 的真实 hex 邻接生成战区邻接
assignUnits
  -> 按单位所在 hex 的 dynamicTheaterId 分配 theater.unitIds
calculateMetrics
  -> 按动态 theater 内 hex controller 计算 controlRatios / controllingFaction / frontWeight
```

`formalizationThreshold` 当前默认 0.70。它用于 formalized / provisional 状态判断，不阻止前线按单个 hex 推进。

### 1.5 FrontLine

源码：`WWIIHexV0/Core/FrontLine.swift`、`WWIIHexV0/Core/FrontSegment.swift`、`WWIIHexV0/Core/FrontLineState.swift`、`WWIIHexV0/Rules/FrontLineManager.swift`

`FrontLineState` 关键字段：

```text
frontLines: [FrontLineId: FrontLine]
regionStates: [RegionId: RegionFrontState]
enemyNeighborCache: [RegionId: [RegionId]]
dirtyRegionIds
diagnostics
```

`FrontLine`：

```text
id
theaterId
opposingTheaterIds
factionA / factionB
segments: [FrontSegment]
type: normal / breakthrough / encirclement
state: stable / pressured / collapsing 等
```

`FrontSegment`：

```text
regionA
regionB
edgeType
pressureLevel
supplyImpact
isEncirclementCandidate
```

当前前线生成逻辑：

```text
对每个 active theater:
  对 theater.regionIds 中的每个 region:
    只看该 region 内 dynamicTheaterId == theater.id 的 hex
    扫描这些 hex 的六向邻接 hex
    如果邻接 hex 属于另一个 dynamic theater
       且对方 theater 的 sourceFaction 不是 friendlyFaction:
         形成 enemy region 接触
         生成 FrontSegment(regionA: friendly region, regionB: enemy region)
```

重要结论：

- 前线不是 region 边界。
- 前线不是 initial theater 边界。
- 前线不是 `regionToTheater` 的邻接。
- 前线是真实动态战区 hex 接触。
- 同一个 region 被两个动态战区切开时，允许出现 `regionA == regionB` 的突破前线。这是 v0.358 后确认的合法状态。
- `FrontLine.type == .breakthrough` 的一个来源是：segment 的 `regionA` 仍由敌方 region controller 控制，但已有我方动态 theater hex 突入。

### 1.6 WarDeployment / FrontZone

源码：`WWIIHexV0/Core/WarDeploymentState.swift`、`WWIIHexV0/Core/FrontZone.swift`、`WWIIHexV0/Core/FrontZoneSegment.swift`、`WWIIHexV0/Rules/WarDeploymentManager.swift`

`WarDeploymentState` 关键字段：

```text
frontZones: [FrontZoneId: FrontZone]
hexToFrontZone: [HexCoord: FrontZoneId]
regionToFrontZone: [RegionId: FrontZoneId]
dirtyRegionIds
diagnostics
```

`FrontZone`：

```text
id / name
faction
regionIds
neighbors
frontSegments
unitsFront
unitsDepth
unitsGarrison
pressure
state
isCoreZone
```

当前部署层权威：

- `hexToFrontZone` 是动态部署归属权威。
- `regionToFrontZone` 是 dominant / fallback，不是突破推进权威。
- `FrontZoneId` 当前通常复用 `TheaterId.rawValue`。
- `WarDeploymentManager.advanceHex` 只推进一个 hex 的 zone 归属。
- `DeploymentLayer` / `UnitDeploymentRole` 当前落地为：
  - `frontUnit`
  - `depthUnit`
  - `garrisonUnit`

单位分配逻辑要点：

```text
每个 division:
  先按 division.coord 查 hexToFrontZone，fallback regionToFrontZone
  如果该 zone.faction == division.faction:
    使用该 zone
  否则如果所在 region 周边有己方 zone:
    分到相邻己方 zone
  否则 fallback 到该 faction 的 primary combat zone

  如果 hex 接触敌 zone
     或 assignedZoneId != 当前 hex zoneId
     或所在 hex controller != assignedZone.faction:
       unitsFront
  否则如果 zone.isCoreZone 或 region 有 city/factory/core:
       unitsGarrison
  否则:
       unitsDepth
```

这层是 AI 调度能否“看见部队”的关键。历史上的“AI 看起来不动”根因之一就是突破后的单位被误判成 garrison，从 `unitsFront` 调度池消失。现在前线/敌区/敌控 hex 会强制把这种单位归到 front。

### 1.7 后续统治者层预留

v0.5 当前不接入统治者层。工作树中可能存在 `WWIIHexV0/Core/DiplomacyState.swift`、`WWIIHexV0/Agents/RulerAgent.swift` 等其他版本方向文件，但它们不是本 v0.5 分支的默认战争 AI 主链路，`TurnManager` 当前不调用 `RulerAgent`。

后续若加入统治者层，必须满足这些边界：

- 统治者只能位于元帅上游，输出国家级姿态、优先方向或约束条件。
- 统治者不得直接生成底层 `Command`，不得绕过 `MarshalAgent` / `ZoneDirective`。
- 统治者不得直接修改 `HexTile.controller`、`Division.coord`、`regionToTheater`、`hexToTheater` 或 `hexToFrontZone`。
- 若需要审计记录，必须单独设计数据 schema，并在 `md/flow/*`、`README.md`、`update_log.md` 中同步说明。

### 1.8 EconomyState / EconomyRules

源码：`WWIIHexV0/Core/EconomyState.swift`、`WWIIHexV0/Rules/EconomyRules.swift`

v0.8 新增初级回合经济层。它是 faction 级总账，不是第三套地图权威。

`EconomyState`：

```text
ledgers: [Faction: FactionEconomyLedger]
lastResolvedTurn
```

`FactionEconomyLedger`：

```text
faction
stockpile: EconomyResources
lastIncome
lastUpkeep
lastReinforcementSpend
productionQueue: [ProductionOrder]
lastUpdatedTurn
```

`EconomyResources` 只包含三项：

```text
manpower
industry
supplies
```

收入算法：

```text
对 faction 控制且 passable 的每个 region:
  如果该 region 没有任何真实己方控制 hex，跳过
  cityLevel = EconomyRules.cityLevel(region, map)
  coreBonus = region.coreOf 为空或包含 faction ? 1 : 0
  manpower = max(1, cityLevel.manpowerGrowth + coreBonus * 4 + infrastructure)
  industry = max(0, factories + cityLevel.industryValue + infrastructure / 3)
  supplies = max(1, supplyValue * 3 + factories + infrastructure / 2)
```

城市等级不是单独 JSON schema，当前从既有字段推导：

- capital、victoryPoints >= 5 或 factories >= 5 -> `metropolis`。
- victoryPoints >= 2、factories >= 2 或 supplyValue >= 3 -> `town`。
- 有 city / fortress / factory 但不满足上面条件 -> `village`。
- 没有城市、堡垒或工厂信号 -> `none`。

生产队列由 `Command.queueProduction(kind:)` 进入规则系统：

```text
EconomyPanelView
  -> AppContainer.queueProduction
  -> Command.queueProduction
  -> RuleEngine
  -> CommandValidator.validateProduction
  -> CommandExecutor.executeQueueProduction
  -> EconomyRules.queueProduction
```

排产时预付资源，完成时才部署单位或发放 supply stockpile。完成单位只能放到本方控制、passable、空置、非敌邻，且位于首都、城镇/大都会、工厂、高基建、高补给 region 或 supply source 的后方 hex。找不到安全部署点时订单保留到下回合继续尝试。

自动补员在 active faction 结束回合时发生，只处理：

```text
本阵营
未毁灭
未撤退
supplied
strength < maxStrength
不与敌军相邻
```

每个单位每回合最多恢复 2 strength，并按装甲、摩托化、火炮权重扣 manpower / industry / supplies。v0.8 不恢复 organization。

---

## 2. 数据启动流程

### 2.1 默认启动路径

源码：`WWIIHexV0/Data/DataLoader.swift`、`WWIIHexV0/App/AppContainer.swift`

主入口：

```text
AppContainer.bootstrap()
  -> DataLoader().loadInitialGameState()
  -> RuleEngine()
  -> GameAgent.guderian(...) legacy .germany fallback bridge
  -> StrategicStateBootstrapper().bootstrapIfNeeded(...)
  -> TurnManager(... commanderPool: buildCommanderPool(state: bootstrappedState))
  -> AppContainer(...)
```

默认 `grey_tide_2030` 主路径的玩家可见 AI / commander 文案由 `generals.json`、`GeneralRegistry` 和面板 display name 提供，显示为现代 Blue / Red commander 或 Local Planner；`GameAgent.guderian(...)` 只保留为旧 `.germany` fallback / source compatibility bridge，不代表 v6.10 默认 UI 文案。

`DataLoader.loadInitialGameState()` 当前优先走编辑器兼容 JSON：

```text
loadGameState(
  scenarioName: "grey_tide_2030_scenario",
  regionName: "grey_tide_2030_regions"
)
```

如果失败，先 fallback 到 `ardennes_v0_scenario` + `ardennes_v02_regions`，再 fallback 到老的 `GameState.initial()` + v0.2 region 叠加路径。

### 2.2 loadGameState 的完整链条

源码：`WWIIHexV0/Data/DataLoader.swift`

```text
loadScenarioDefinition(named:)
loadRegionDataSet(named:)
  -> makeMapState(from: scenario)
     - ScenarioTileDefinition -> HexTile
     - tile.controller 字符串通过 Faction.dataValue 转 Faction
     - tile.regionId 写入 HexTile.regionId
     - supply source / objective 写入 MapState
  -> apply(regionData, to: map)
     - regionData.toRegions()
     - regionData.toHexToRegion()
     - regionData.toRegionEdges()
     - 反填 HexTile.regionId
     - validateRegionGraph()
  -> RegionOccupationRules().mapByAggregatingControllers(in: map)
     - 从 hex controller 派生 region controller
  -> makeDivisions(from: scenario.initialUnits)
  -> makeTheaterState(map, regionData, divisions, turn)
     - 优先使用 regionData.regions[].theaterId
     - 没有 assignment 时使用 TheaterSystem.makeInitialFixedTheaters
     - TheaterSystem.updateTheaters seed hexToTheater 并刷新派生字段
     - capture initialSnapshot
  -> FrontLineManager.makeInitialState(...)
  -> WarDeploymentManager.makeInitialState(...)
  -> GameState(...)
```

DEBUG 下资源读取优先源码目录 `WWIIHexV0/Data/*.json`，不是旧 bundle。旧 simulator 进程不会自动重载，改默认地图后需要重新运行 app。

### 2.3 StrategicStateBootstrapper

源码：`WWIIHexV0/Core/StrategicStateBootstrapper.swift`

它有两个用途：

1. `bootstrapIfNeeded`
   - 只补缺失层。
   - 先用 `EconomyRules.bootstrapIfNeeded` 为旧状态补 faction 经济总账。
   - 如果 state 有 region 但缺 theater/front/deployment，会从当前 map/divisions 生成。
   - App 初始化、命令提交后会用它兜底。

2. `refreshRuntimeState`
   - 强制刷新运行时派生层。
   - 先聚合 region controller。
   - 强制 `TheaterSystem.updateTheaters(force: true)`。
   - 重新 `FrontLineManager.makeInitialState`。
   - 重新 `WarDeploymentState.bootstrapFrontZones`。
   - AI 行动前会调用，确保指令读取的是当前动态层。

---

## 3. 地图编辑器流程

### 3.1 MapEditorDocument

源码：`MapEditor/MapEditorDocument.swift`

编辑器自己的文档模型：

```text
id / displayName
width / height
hexes: [HexCoord: MapEditorHex]
regions: [RegionId: MapEditorRegionDraft]
theaters: [TheaterId: MapEditorTheaterDraft]
regionTheaterAssignments: [RegionId: TheaterId]
initialUnits: [MapEditorUnitDraft]
backgroundImage
```

四种编辑模式：

```text
hexPainter         地块
regionBuilder      区域
theaterAssignment  作战区
unitPlanner        任务编组
```

编辑动作：

```text
idle
adding
deleting
```

地块工具：

```text
paint   覆盖已有 hex
extend  在已有 hex 邻位扩展稀疏地图
```

关键行为：

- `MapEditorDocument.contains(_:)` 判断实际存在的 hex，支持稀疏地图。
- `addHex(at:)` 只能在已有 hex 邻位扩展，避免凭空造孤岛。
- `deleteHex(at:)` 会删除该 hex 上初始部队；如果某 region 已无 hex，会删除 region 和 theater assignment。
- `resize` 会裁剪外部 hex、清理无效 region assignment 和越界单位。
- 底图 `backgroundImage` 只存在编辑器文档，不写入游戏 JSON。

### 3.2 编辑会话

源码：`MapEditor/MapEditorViewModel.swift`

典型流程：

```text
选择 mode
  -> beginAdding / beginDeleting
  -> 点击或拖拽 canvas
  -> applyPrimaryAction(at:)
  -> stage 或直接编辑
  -> finishEditing
  -> commitPendingRegion / commitPendingTheater / commitPendingUnits
```

不同模式行为：

- `hexPainter`
  - adding + paint：写 terrain、road、controller、supply。
  - adding + extend：尝试在相邻空位生成 plain hex。
  - deleting：删除 hex。

- `regionBuilder`
  - adding：把点击 hex 先放进 `pendingRegionHexes`，完成时统一 assign 到选中或新建 region。
  - deleting / erase：把 hex 的 regionId 清空。

- `theaterAssignment`
  - 点击 hex 后先取该 hex 的 regionId。
  - adding：把 region 放进 `pendingTheaterRegions`，完成时统一 assign 到选中或新建 theater。
  - deleting：清除 region 的 theater assignment。

- `unitPlanner`
  - adding：点击 hex 放入 `pendingUnitHexes`，完成时按模板、阵营、朝向、HP 生成初始单位。
  - 同一 hex 新 stamp 会先删除原单位。
  - deleting / erase：删除该 hex 上初始单位。

快捷键：

- `N`：添加。
- `M`：完成。

### 3.3 导出链路

源码：`MapEditor/MapEditorExporter.swift`

导出产物：

```text
ScenarioDefinition JSON
RegionDataSet JSON
```

导出前校验：

- 所有 hex 必须有 regionId，否则 `unassignedHex`。
- 所有被引用 region 必须在 `document.regions` 里定义。
- 每个导出的 region 必须至少有一个 hex，否则 `emptyRegion`。

`ScenarioDefinition` 写入：

- map width/height/isSparse。
- 每个 `MapEditorHex` 写为 `ScenarioTileDefinition`。
- terrain / road / controller / city / fortress / supply / objective / regionId。
- factions、initialTurn、initialPhase、playerFaction、aiFaction。
- `initialUnits` 从 `MapEditorUnitDraft` 写入。
- 底图不写入。
- 通用 `MapEditorExporter.export` 不表达 `riverEdges`、复杂 victory condition、region city victoryPoints、occupationState、edge river crossing 或 objective main flag；这些字段在普通导出中使用简化默认值。

`RegionDataSet` 写入：

```text
hexToRegion:
  每个 hex 的 coord key -> regionId

regions:
  每个 MapEditorRegionDraft -> RegionNodeDefinition
  theaterId = document.regionTheaterAssignments[draft.id]
  displayHexes = 属于该 region 的 hex
  representativeHex = displayHexes 几何中心最近 hex
  terrain = region 内 dominant terrain
  city = 第一处 city / fortress / city terrain
  neighbors = 从 hex 邻接自动推导

edges:
  从跨 region hex 邻接自动推导
  两侧 hex 都有 road 时 hasRoad = true

supplySources / objectives:
  从对应 hex 自动归到 region
```

重要：region 邻接和 edge 不是人工手填权威，而是在导出时从真实 hex 邻接推导。这和运行时前线必须看 hex 邻接是一致的。

### 3.4 默认资源桥

源码：`MapEditor/MapEditorGameResourceBridge.swift`

默认读写路径：

```text
WWIIHexV0/Data/grey_tide_2030_scenario.json
WWIIHexV0/Data/grey_tide_2030_regions.json
```

流程：

```text
loadDefaultDocument()
  -> 读取默认 ScenarioDefinition + RegionDataSet
  -> makeDocument(...)
     - scenario tile -> MapEditorHex
     - regionData.toHexToRegion 优先填 regionId
     - region definitions -> MapEditorRegionDraft
     - region theaterId -> regionTheaterAssignments
     - scenario initialUnits -> MapEditorUnitDraft

overwriteDefaultGameResources(document:)
  -> MapEditorExporter.export(... 固定默认文件名)
  -> 读取既有 grey_tide_2030 默认 JSON
  -> 回填编辑器未表达的默认元数据
  -> 写回 WWIIHexV0/Data
```

覆盖默认灰潮资源时，`MapEditorGameResourceBridge` 会保留现有 `maxTurns`、初始 phase、player/AI faction、victory conditions、scenario objective points、tile `riverEdges`、region city victoryPoints / isCapital、resources、occupationState、isPassable、edge `hasRiverCrossing` / movementCostModifier 以及 region objective victoryPoints / mainObjective。当前 MapEditor 只负责几何、区域归属、初始作战区、控制方、补给点和初始任务编组；若未来要编辑上述高级字段，需要扩展 `MapEditorDocument` schema 和 UI，而不是由 exporter 静默重写。

相关测试确认：

- 编辑器 document、导出 JSON、游戏加载后的 `hexToRegion` / `regionToTheater` / `tile.regionId` / `region.name` 必须一致。
- 游戏和编辑器 hex layout 的垂直方向必须一致。
- 默认开局单位不能出现在敌对初始 theater 中。
- App bootstrap 不应自动跑 AI 或移动开局单位。

---

## 4. 主游戏 UI 与输入流程

### 4.1 AppContainer

源码：`WWIIHexV0/App/AppContainer.swift`

`AppContainer` 是 SwiftUI 和规则层之间的中介。它持有：

```text
@Published gameState
selectedUnitId / selectedHex / selectedRegionId
movementHighlights / attackHighlights
interactionLog
lastCommandMessage
lastAgentDecisionRecord
lastWarDirectiveRecords
observerModeEnabled
mapDisplayLayer
```

玩家提交命令：

```text
submit(command)
  -> commandHandler.execute(command, in: gameState)
  -> StrategicStateBootstrapper.bootstrapIfNeeded(result.state)
  -> lastCommandMessage = result.message
  -> appendInteractionEvent(...)
  -> refreshSelectionAfterStateChange()
  -> runAIIfNeeded()
```

点击地图：

```text
handleBoardTap(coord)
  -> selectedHex = coord
  -> selectedRegionId = MapDisplayAdapter.regionId(for: coord)
  -> 如果已有己方可行动单位选中，且点击处有敌军:
       submit(.attack)
     else 如果点击处有单位:
       handleDivisionTap
     else 如果已有己方可行动单位选中:
       submit(.move)
     else:
       清空选择
```

玩家可行动单位必须满足：

- 非 observer mode。
- 单位属于 `playerFaction`。
- 当前 activeFaction 是 `playerFaction`。
- 当前 phase 必须匹配 `playerFaction.commandPhase`；Blue Force / Allies 对应 `.alliedPlayer`，Red Force / Germany 对应 `.germanAI`。
- 未行动。

### 4.2 RootGameView

源码：`WWIIHexV0/UI/RootGameView.swift`

主界面元素：

- `BoardSceneView`：SpriteKit 地图。
- `HUDView`：回合、下一步、新游戏。
- `MapDisplayLayer` segmented picker：
  - `Hex`
  - `Sector`
  - `Baseline`
  - `Operational`
  - `Contact`
  - `Brigade`
- `Observer` toggle。
- `Info` / `Hide Info` toggle：44pt 最小触控区，只打开/关闭信息面板，不覆盖整张地图点击区。
- Info 面板 tabs：
  - Formation
  - Tasks
  - Playtest
  - Sector
  - Command
  - Log
  - Sustainment
  - ROE
  - AI
- `UnitTooltipView`。

当前开局不会在 `RootGameView` 自动 `.task { runAIIfNeeded() }`。AI 行动由 `advanceOrRunAI()` 或命令提交后的 `runAIIfNeeded()` 触发。

### 4.3 v1.1 主游戏 macOS target

源码：

- `WWIIHexV0/App/WWIIHexV0MacApp.swift`
- `WWIIHexV0/SpriteKit/BoardSceneView.swift`
- `WWIIHexV0/SpriteKit/BoardScene.swift`
- `WWIIHexV0/UI/PlatformStyles.swift`

v1.1 新增独立 macOS 主游戏 target：

```text
WWIIHexV0Mac
  -> WWIIHexV0MacApp
  -> AppContainer.bootstrap()
  -> RootGameView(container:)
  -> BoardSceneView
  -> BoardScene
```

这个 target 和既有 target 的边界：

- `WWIIHexV0`：iOS 主游戏 target。
- `WWIIHexV0Mac`：macOS 主游戏 target。
- `MapEditorMac`：macOS 地图编辑器 target，不是主游戏入口。

`WWIIHexV0Mac` 复用主游戏数据和规则，不新增一套 mac 专用规则。resource phase 包含：

```text
ardennes_v0_scenario.json
ardennes_v02_regions.json
general_agents.json
generals.json
terrain_rules.json
unit_templates.json
```

DEBUG 下 `DataLoader` 仍优先读源码目录 `WWIIHexV0/Data/*.json`；bundle resources 是 release / fallback 路径。

`BoardSceneView` 现在有平台分支：

```text
iOS:
  UIViewRepresentable
  -> SKView
  -> BoardScene touch input

macOS:
  NSViewRepresentable
  -> BoardEventSKView
  -> BoardScene mouse / scroll / magnify input
```

macOS 输入桥接逻辑：

```text
鼠标点击
  -> BoardScene.mouseDown / mouseUp
  -> layout.pixelToHex
  -> onHexTapped(coord)
  -> AppContainer.handleBoardTap

鼠标拖拽
  -> BoardScene.mouseDragged
  -> camera.position 更新
  -> clampCamera

滚轮 / 触控板缩放
  -> BoardEventSKView.scrollWheel / magnify
  -> scene.convertPoint(fromView:)
  -> BoardScene.handleScrollWheel / handleMagnify
  -> zoomCamera(anchor:)
  -> clampCamera
```

注意：macOS 点击仍只进入 `AppContainer.handleBoardTap`。移动、攻击、结束回合和 AI 行动仍由 `RuleEngine` / `WarCommandExecutor` 处理；v1.1 不允许通过 AppKit 或 SpriteKit 直接修改 `GameState`。

---

## 5. 命令执行流程

### 5.1 Command / RuleEngine

源码：`WWIIHexV0/Commands/Command.swift`、`WWIIHexV0/Rules/RuleEngine.swift`、`WWIIHexV0/Rules/CommandValidator.swift`、`WWIIHexV0/Rules/CommandExecutor.swift`

底层 `Command` 当前包括：

```text
move(divisionId, destination)
attack(attackerId, targetId)
hold(divisionId)
allowRetreat(divisionId)
resupply(divisionId)
queueProduction(kind)
endTurn
```

执行总入口：

```text
RuleEngine.execute(command, in: state)
  -> EconomyRules.bootstrapIfNeeded(state)
  -> CommandValidator.validate(command, in: preparedState)
  -> invalid: 返回 CommandResult，state 不变
  -> valid: CommandExecutor.execute(command, in: preparedState)
```

### 5.2 校验规则

`CommandValidator` 的关键校验：

移动：

```text
phaseAllowsCommands
division exists
division.faction == activeFaction
division 未行动、未撤退、canAct
destination 在地图内
destination passable
destination 没有其他单位
忽略 movement 的最短路径 cost <= division.movement
真实 shortestPath 存在
```

攻击：

```text
attacker 可行动
target exists
target.faction != attacker.faction
distance <= attacker.range
```

恢复/姿态：

```text
phase 合法
division exists
faction 匹配 activeFaction
未行动、未毁灭、未撤退
```

结束回合：

```text
phaseAllowsCommands
```

生产排队：

```text
phaseAllowsCommands
active faction economy ledger 有足够 manpower / industry / supplies
```

### 5.3 移动与占领

`CommandExecutor.executeMove` 真实链路：

```text
记录 origin
sourceZoneId = warDeploymentState.zoneId(for: origin)
更新 facing
division.coord = destination
division.hasActed = true

if OccupationRules.canOccupy(division, destination, state):
  tile.controller = division.faction
  map.setTile(tile)

  if destinationRegionId && sourceZoneId:
    applyStrategicAdvance(
      regionId: destinationRegionId,
      hex: destination,
      sourceZoneId: sourceZoneId,
      faction: division.faction
    )

  StrategicStateSynchronizer.synchronizeAfterOccupationChange(
    affectedRegionIds: [destinationRegionId]
  )

appendEvent("moved")
```

`OccupationRules.canOccupy` 很小，但非常关键：

```text
tile exists
tile.isCapturable
tile.controller != division.faction
destination 没有其他单位
```

注意：

- 只有移动会触发占领。
- 攻击造成伤害/撤退/消灭，不会自动把攻击者推进到目标 hex。
- 移动进敌控空 hex 时，先改 hex controller，再同步战略层。
- 灰潮主目标里存在显式 neutral 控制区；地面移动可把这类 capturable 目标转为己方目标控制，但 neutral / green / 同阵营协同单位不能因此被攻击、生成敌 ZOC、阻断补给或算作敌防空威胁。
- 移动进有敌单位的 hex 会在 validator 被 `destinationOccupied` 拒绝。

### 5.4 动态战区推进

`CommandExecutor.applyStrategicAdvance` 的语义：

```text
advancingTheaterId = TheaterId(sourceZoneId.rawValue)
如果 theater 不存在，return
如果 destination hex 已经属于 advancingTheater，return
如果 shouldAdvanceDynamicTheater == false，return

TheaterSystem.expandDynamicTheater(
  breakthroughHex: destination,
  advancingTheaterId,
  faction
)

oldZoneId = warDeploymentState.zoneId(for: destination)
如果 oldZoneId != sourceZoneId:
  WarDeploymentManager.advanceHex(destination, from: oldZoneId, to: sourceZoneId)

appendEvent("Hex q,r reassigned to operational zone ...")
```

`shouldAdvanceDynamicTheater` 当前判断：

- 如果目标 hex 当前 zone 属于其他 faction，则可以推进。
- 否则如果目标 hex controller 不是本方，也可以推进。
- 否则不推进。

这确保动态推进是 hex 级，不会把整个 region 拉走。

### 5.5 Region / Theater / Front / Deploy 同步

源码：`WWIIHexV0/Rules/StrategicStateSynchronizer.swift`

占领变化后：

```text
RegionOccupationRules.aggregateControl(in: &state)
  -> changedRegionIds

affected = affectedRegionIds + changedRegionIds

TheaterSystem.updateTheaters(force: true)

FrontLineManager.update(
  events:
    changed -> regionControllerChanged
    unchanged -> occupationChanged
)

WarDeploymentManager.update(
  events: affected.map(regionControllerChanged)
)

可选写 region owner change event
```

Region controller 聚合权重：

- 每个已控制 hex 基础权重 1。
- `representativeHex` 加 region city VP。
- city / fortress / city terrain / fortress terrain 再加权。
- 中立 hex 不计入。
- 并列第一时不改 region controller。

### 5.6 攻击、撤退、补给、结束回合

攻击流程：

```text
计算 attackDamage
attacker.hasActed = true
attacker.facing = 面向 defender
对 defender 扣 strength
resolveCombatResult
  -> retreatable 且 lossRatio >= 0.35 时 shouldRetreat
  -> hold 模式追加损失
  -> encircled 且撤退触发追加损失
  -> destroyed 则 removeDivision + victory record
如果 defender 没撤退且可反击:
  defender counterattack
  attacker 也可能撤退/毁灭
```

结束回合：

```text
SupplyRules.updateSupplyStates
EconomyRules.resolveFactionTurn(for: activeFaction)
  -> 收入入账
  -> 支付战略补给维护费
  -> supplies 短缺时 supplied 单位降为 lowSupply
  -> 安全后方自动补员
  -> 推进生产队列并部署完成单位
SupplyRules.advanceRetreats
SupplyRules.applyEncirclementAttrition
VictoryRules.updateVictoryState

activeFaction:
  当前阵营按 GamePhase / Faction.commandPhase 兼容推进
  Blue / Red 玩家方由 AppContainer.playerFaction 决定
  非玩家敌对方由 AI 或 observer 接管；完整轮转后 turn += 1

resetActionsForActiveFaction
StrategicStateBootstrapper.refreshRuntimeState
appendEvent("Turn advanced ...")
```

---

## 6. AI / 战争指令流程

### 6.1 v6.10 默认 AI 指挥链

源码：`WWIIHexV0/Turn/TurnManager.swift`、`WWIIHexV0/Agents/ZoneCommanderAgent.swift`、`WWIIHexV0/Commands/WarDirective.swift`、`WWIIHexV0/Commands/WarCommandExecutor.swift`

当前默认路径：

```text
AppContainer.runAIIfNeeded
  -> runAISequence
  -> TurnManager.runAITurn(... pipelineMode: .marshalDirective)
  -> MarshalAgent.resolve
  -> MarshalBattlefieldSummarizer.summary
  -> SimulatedMarshalLLMClient.completeTheaterDirectiveJSON
  -> TheaterDirectiveDecoder.parse
  -> ModernCommandChainOrchestrator.makePlan
  -> ModernCommandChainDecoder.parse
  -> TheaterDirectiveCompiler.compile
  -> DirectiveEnvelope / ZoneDirective
  -> WarCommandExecutor.execute(directive, in: state)
  -> RuleEngine.execute(Command)
  -> WarDirectiveRecord
  -> RuleEngine.execute(.endTurn)
```

`MarshalAgent` 是元帅层，不是单位，也不是新规则执行器。它只读取降维摘要并输出 `TheaterDirectiveEnvelope` JSON：

```text
TheaterDirectiveEnvelope
  schemaVersion = 5
  issuerId / turn / faction
  strategicIntent
  directives: [TheaterDirective]

TheaterDirective
  zoneId
  category offense/defense
  tactic
  priority
  targetTheaterId
  weightedRegions / focusRegionId / supportRegionIds
  reserveBias
  intensity / maxCommittedUnits / exploitDepth
  rationale
```

`TheaterDirectiveDecoder` 负责从模拟 LLM 文本中提取 fenced JSON，使用 `JSONDecoder` 解码，并校验 schemaVersion、issuerId、turn、faction、zone 存在性、zone 阵营、region id、target theater/front zone 与 tactic/category 一致性。解码或校验失败时，不执行半成品 JSON，`MarshalAgent` fallback 到 `TheaterCommanderPool`。

`TheaterDirectiveCompiler` 把元帅意图降级到现有 `ZoneDirective`：

- offense -> `ZoneDirective.attack`，保留 target theater、weighted/focus/support regions、intensity、maxCommittedUnits、exploitDepth。
- defense -> `ZoneDirective.defend`，把 reserveBias 转成 targetReserves，把 focus/weighted regions 转成 strongpointRegionIds，把 supportRegionIds 转成 fallbackRegionIds。
- 某个 zone 没有元帅 directive 或编译失败时，使用 `TheaterCommanderPool` 给该 zone 的旧 directive。

最终执行由 `TurnManager.executeDirectiveEnvelope` 统一完成。`.marshalDirective` 和显式 `.zoneDirective` 共享同一段 WarCommandExecutor 执行、WarDirectiveRecord 记录、endTurn 推进逻辑。

统治者层是后续预留方向，当前 v0.5 主路径不调用 `RulerAgent`，也不在 `DirectiveEnvelope` 与执行层之间插入姿态塑形。

Legacy Agent D 仍存在，但只在显式 `.legacyAgentOrder` 分支运行：

```text
AgentContextBuilder
  -> DecisionProvider
  -> AgentDecisionParser
  -> AgentCommandMapper
  -> RuleEngine
```

默认不得把 Legacy 管线接回战争 AI 主路径。

v0.37 直接将军池路径仍可显式使用：

```text
TurnManager.runAITurn(... pipelineMode: .zoneDirective)
  -> TheaterCommanderPool.envelope
  -> ZoneCommanderAgent.makeDirective
  -> DirectiveEnvelope
  -> WarCommandExecutor
```

### 6.2 AI 触发条件

`AppContainer.shouldRunAI`：

```text
guard activeFaction.canCommand(in: phase)

if activeFaction == playerFaction:
  observerModeEnabled

else:
  activeFaction.isHostile(to: playerFaction)
```

`runAISequence`：

- 非 observer mode：最多跑 1 个 AI step。
- observer mode：最多跑 2 个 AI step，因此一次按钮推进可让当前 AI 阵营行动，若回合切到另一个 AI 控制阵营，也继续行动一次。
- Blue / Red 新局选择只改变玩家控制方；AI 继续通过 `TurnManager -> MarshalAgent -> ZoneDirective -> RuleEngine` 驱动当前非玩家敌对阵营。

### 6.3 ZoneCommanderAgent 如何做决策

`TheaterCommanderPool` 会对当前 faction 的每个有 `frontSegments` 的 `FrontZone` 生成 directive。

每个 zone：

```text
visibleEnemyStrengthByRegion
friendlyFrontStrength
mobileFriendlyStrength
artillerySupportStrength
friendlyDepthStrength
pressure / supplyWarningCount
hasContestedForwardPresence
hasRecentStaticDefense
  -> BinaryTacticClassifier.classify
```

`BinaryTacticClassifier`：

```text
ratio = friendlyStrength / visibleEnemyStrength
如果 visibleEnemyStrength == 0，则 ratio = friendlyStrength
styleBoost:
  aggressive +0.15
  balanced 0
  cautious -0.15

shouldAttack =
  adjustedRatio >= attackThreshold(默认 1.2)
  或 hasContestedForwardPresence
  或 hasStaticDefense
```

分类结果：

- offense：
  - `blitzkrieg`：机动兵力占比高且 adjustedRatio >= 1.65。
  - `spearhead`：机动兵力可用，adjustedRatio >= 1.35，且有可见敌 region；用于定点矛头。
  - `breakthrough`：adjustedRatio >= 1.35，向弱点突破。
  - `fireCoverage`：炮兵/远程支援可用但优势不足，先火力覆盖。
  - `feint`：优势不足但需要牵制时少量佯攻。
  - `guerrillaWarfare`：机动兵力可用、敌 region 多、优势有限时袭扰纵深。
  - `standardAttack`：普通进攻 fallback。
- defense：
  - `lastStand`：极端劣势、无纵深预备队且压力高时死守。
  - `defenseInDepth`：有纵深预备队且压力/劣势明显时纵深防御。
  - `elasticDefense`：压力、补给警告或劣势时弹性防御。
  - `holdPosition`：普通防御 fallback。

`TacticConditionChecker` 不再恒放行：闪电战/游击战要求机动单位，火力覆盖要求炮兵或远程单位，佯攻要求前线单位，纵深防御要求 depth 预备队；不满足条件会降级为 `holdPosition`。

进攻 directive：

```text
ZoneDirective(
  zoneId,
  attack: AttackParameters(
    targetTheaterId,
    weightedRegions,
    intensity,
    focusRegionId,
    supportRegionIds,
    convergenceRegionId,
    coordinatedZoneIds,
    maxCommittedUnits,
    exploitDepth
  ),
  category: .offense,
  tactic: blitzkrieg / spearhead / breakthrough / pincerMovement / fireCoverage / feint / guerrillaWarfare / standardAttack,
  commandTarget: .region(focusRegionId) 或 .theater(target)
)
```

定点突破目标选择：

```text
priorityRegions =
  focusRegionId
  + commandTarget.region
  + convergenceRegionId
  + weightedRegions
  + supportRegionIds

若 tactic weakPointFocus:
  对候选 region 评分：
    enemyStrength 越低越优先
    terrain.movementCost 越低越优先
    region 内有 road 越优先
    city victoryPoints + supplyValue + factories + infrastructure 越高越优先
  最优 region 放到候选首位
```

钳形攻势数据层：

```text
pincerMovement 使用 convergenceRegionId + coordinatedZoneIds
每个 zone 仍各自编译成一条 ZoneDirective
执行器只推进本 zone 成功移动的具体 hex
会师/包围效果仍交给补给、前线、动态战区同步派生
```

防御 directive：

```text
ZoneDirective(
  zoneId,
  defense: DefenseParameters(
    targetReserves,
    stance,
    fallbackRegionIds,
    counterattackRegionIds,
    strongpointRegionIds,
    maxFrontCommitment
  ),
  category: .defense,
  tactic: holdPosition / elasticDefense / defenseInDepth / lastStand,
  commandTarget: .theater(self)
)
```

`AttackIntensity` 仍是参数字段；v0.7/v1.0 的真实分流主要由 `tactic` 决定。v1.0 已把 `.infiltration` 解释为默认低投入上限，但执行器不绕过 `RuleEngine` 给强度加直接伤害。

### 6.4 WarCommandExecutor 如何翻译指令

入口：

```swift
func execute(_ directive: ZoneDirective, in state: GameState) -> WarCommandExecutionResult
```

它不需要 `ZoneCommanderAgent` 实例，不需要 issuer。手写合法 `ZoneDirective` 可以直接执行，这是 v0.4 玩家命令 UI / 聊天命令要复用的后端能力。

执行路由：

```text
如果 directive.tactic 存在:
  standardAttack / blitzkrieg / spearhead / breakthrough / pincerMovement / fireCoverage / feint / guerrillaWarfare
    -> executeAttack(tactic)
  holdPosition / elasticDefense / defenseInDepth / lastStand
    -> executeDefense(tactic)
否则按 parameters:
  attack -> executeAttack
  defend -> executeDefense
```

防御翻译：

```text
zone 必须存在且有 frontSegments
lastStand:
  不保留 depth，全力 holdLine
elasticDefense:
  stance 强制 flexible，前线单位优先 allowRetreat
defenseInDepth:
  前线单位 allowRetreat
  保留 targetReserves 个 depth 预备队
  其余 depth 机动单位优先反击可见敌军，否则向 fallback/strongpoint region 移动
普通防御:
  unitIds = unitsFront + 部分 unitsDepth（保留 targetReserves）
对每个可行动单位:
  找 lightestFrontRegion
  如果单位已在该 region:
    holdLine -> .hold
    flexible -> .allowRetreat
  否则如果能找到 tacticalDestination:
    .move
  否则:
    hold / allowRetreat
  run(command, fallback: hold)
```

进攻翻译：

```text
zone 必须存在
targetZoneId = AttackParameters.targetTheaterId.rawValue
segments = 指向 targetZone 的 frontSegments，若为空则用全部 frontSegments

按 tactic 得到 AttackTacticProfile:
  blitzkrieg / spearhead:
    includeDepthUnits = true
    mobileOnlyWhenAvailable = true
    weakPointFocus = true
    holdNonCommittedFront = true
  breakthrough:
    includeDepthUnits = true
    weakPointFocus = true
  pincerMovement:
    includeDepthUnits = true
    mobileOnlyWhenAvailable = true
    convergenceRegionId 可作为深目标
  fireCoverage:
    artilleryFirst = true
    attackOnly = true；没有射程目标则 hold，不主动推进
  feint:
    只投入 maxCommittedUnits 或默认约 1/3 前线单位
  guerrillaWarfare:
    mobileOnlyWhenAvailable = true
    allowDeepTarget = true
    默认只投入约半数前线+纵深单位

attackingUnitIds =
  unitsFront
  + profile.includeDepthUnits ? unitsDepth : unitsFront 为空时 fallback unitsDepth
  -> 过滤可行动单位
  -> 需要时优先机动单位
  -> 按 artillery / mobile / attack / movement / strength 排序
  -> 应用 maxCommittedUnits

对每个可行动单位:
  targetEnemyRegion =
    focus / commandTarget.region / convergence / weighted / support 中仍相邻或允许深目标的 region
    或 front segment 相邻敌 region
    weakPointFocus 时用敌军强度、地形、道路、战略价值重排
  如果射程内有 visible enemy division:
    .attack
  否则如果 fireCoverage:
    .hold
  否则如果能找到 tacticalDestination:
    .move
  否则:
    .hold
  run(command, fallback: hold)
```

`run` 包装层会：

- 先记录 acting division 的 logical source zone。
- 调 `RuleEngine.execute(command, in: state)`。
- 如果被拒绝，写日志；如果原命令非法但 fallback hold 合法，则执行 fallback。
- 成功后做防御性同步：
  - 计算 affected region。
  - 尝试 `applyDirectiveOccupation`（通常普通 `CommandExecutor` 已处理过）。
  - 尝试 `applyStrategicAdvance`（确保 directive move 也推进 dynamic theater）。
  - `StrategicStateSynchronizer.synchronizeAfterOccupationChange`。
  - 记录 region owner change / front change event。

TurnManager 外层会为每条 directive 生成 `WarDirectiveRecord`：

```text
issuerId
turn
faction
zoneId
directiveType
targetRegionIds
commandResults
diagnostics
category
tactic
commanderAgentId
commandTarget
```

直接调用 `WarCommandExecutor.execute` 不会自动写 `WarDirectiveRecord`；记录职责在 `TurnManager.runDirectiveTurn` 外层。

---

## 7. UI / 地图显示流程

### 7.1 BoardScene

源码：`WWIIHexV0/SpriteKit/BoardScene.swift`

绘制顺序：

```text
drawTiles
drawLayerOverlay
drawRegionOverlays（仅 hex layer）
drawRoads
drawRivers
drawUnits（frontLine layer 隐藏单位）
```

点击：

```text
touchesEnded
  -> layout.pixelToHex(point)
  -> state.map.contains(coord)
  -> onHexTapped(coord)
```

平移：

- 触摸移动 camera。
- `clampCamera` 限制在地图边界附近。

### 7.2 MapDisplayAdapter

源码：`WWIIHexV0/SpriteKit/MapDisplayAdapter.swift`

职责：

- hex -> region 查询。
- 视野判断。
- 单位显示位置/堆叠。
- Region inspector state。
- Unit inspector strategic state。

Inspector 中关键字段：

```text
selectedHexController
selectedHexDynamicTheaterId
selectedHexFrontZoneId
theaterId = dominantDynamicTheaterId(region)
frontZoneId = dominantDynamicFrontZoneId(region)
frontPressure
friendlyDivisions
visibleContacts
```

单位 strategic state：

```text
coord
regionId
dynamicTheaterId
frontLineIds
frontZoneId
deploymentRole
```

### 7.3 MapDisplayLayer

源码：`WWIIHexV0/Core/MapDisplayLayer.swift`、`WWIIHexV0/SpriteKit/MapLayerOverlayCalculator.swift`、`WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift`

当前 layer：

```text
hex
province
initialTheater
dynamicTheater
frontLine
deployment
```

bucket 来源：

| Layer | 数据来源 |
|---|---|
| `hex` | 每个 hex 自己 |
| `province` | `map.region(for: hex)` |
| `initialTheater` | `theaterState.initialSnapshot?.regionToTheater[regionId]` |
| `dynamicTheater` | `theaterState.dynamicTheaterId(for: hex, map:)` |
| `frontLine` | `frontLineState.regionStates[regionId].frontLines` |
| `deployment` | 该 hex 上单位的 `WarDeploymentManager.deploymentRole` |

前线 overlay 的线段来源：

```text
frontLineSegments()
  -> 遍历 FrontLine.segments
  -> friendlyBoundaryHexes(
       friendlyRegionId: segment.regionA,
       enemyRegionId: segment.regionB,
       friendlyTheaterId: frontLine.theaterId
     )
  -> 只取 friendly region 内、且 dynamicTheaterId == friendly theater 的 hex
  -> 这些 hex 必须邻接 enemy region 中另一个 dynamic theater 的 hex
  -> 用这些 friendly hex center 画线
```

这意味着前线视觉画在我方动态战区侧，不画敌我中间共用边，也不画初始 theater 边界。

`frontLineChains()` 会把相邻 hex 点串成拓扑链。不同 segment 起点有分隔符，多敌 theater 接触会加 dashed overlay。

---

## 8. 关键链路示例

### 8.1 玩家移动占领一个敌控空 hex

```text
玩家点击己方单位
  -> AppContainer.selectDivision
  -> MovementRules 生成 movementHighlights

玩家点击敌控空 hex
  -> AppContainer.submit(.move)
  -> RuleEngine.validate(move)
  -> CommandExecutor.executeMove
     - division.coord = destination
     - tile.controller = division.faction
     - TheaterSystem.expandDynamicTheater 只推进 destination hex
     - WarDeploymentManager.advanceHex 只推进 destination hex 的 FrontZone
     - StrategicStateSynchronizer
       - RegionOccupationRules 聚合 region controller
       - TheaterSystem.updateTheaters
       - FrontLineManager.update dirty region
       - WarDeploymentManager.update dirty region
  -> AppContainer.bootstrapIfNeeded
  -> UI 刷新 dynamic theater / front / deployment overlay
  -> 如果现在轮到 AI，则 runAIIfNeeded
```

不得发生：

- 不得把 destination 所在整个 region 的 `regionToTheater` 改成进攻方。
- 不得绕过 `OccupationRules.canOccupy`。
- 不得只改 region controller 而不改 hex controller。

### 8.2 AI 进攻一个前线 zone

```text
用户点下一回合 / AI faction active
  -> AppContainer.runAIIfNeeded
  -> StrategicStateBootstrapper.refreshRuntimeState
  -> TurnManager.runAITurn(.zoneDirective)
  -> TheaterCommanderPool 选出该 faction 有 frontSegments 的 FrontZone
  -> ZoneCommanderAgent 计算兵力比/可见敌军/前沿存在
  -> 生成 standardAttack ZoneDirective
  -> WarCommandExecutor.execute
     - 找 zone.unitsFront
     - 选 targetEnemyRegion
     - 能打则 attack，不能打则 move，不能 move 则 hold
     - 每个 command 都走 RuleEngine
     - 同步占领/动态战区/前线/部署
  -> TurnManager 写 WarDirectiveRecord
  -> RuleEngine.execute(.endTurn)
  -> AppContainer 写 lastAgentDecisionRecord / lastWarDirectiveRecords
```

AI 看到的前线单位池来自 `WarDeploymentState`。如果某单位没有进入 `unitsFront` / `unitsDepth`，该 zone 的 AI 就不会调度它。

### 8.3 地图编辑器改默认地图后进入游戏

```text
MapEditorGameResourceBridge.loadDefaultDocument
  -> 读现有 scenario + region JSON
  -> 用户编辑 hex / region / theater / unit
  -> overwriteDefaultGameResources
     - MapEditorExporter.export
       - 校验所有 hex 有 region
       - 从 hex 邻接推导 region neighbors / edges
       - 写 scenario JSON
       - 写 region JSON
     - 覆盖 WWIIHexV0/Data 默认资源

重新运行游戏 app
  -> DataLoader DEBUG 优先读源码 JSON
  -> loadGameState
  -> map / regions / theater initialSnapshot / front / deploy 全部重建
```

注意：已经启动的旧 simulator app 不会自动重新加载默认 JSON。

---

## 9. 调试断点与排查顺序

遇到“AI 不动、前线不对、地图不一致、占领不同步、拒绝率异常”时，按这条链查，不要直接改大块逻辑：

```text
1. 数据加载
   - DataLoader 是否读的是源码 JSON 还是旧 bundle？
   - ScenarioDefinition tiles / initialUnits 是否正确？
   - RegionDataSet.hexToRegion / regions[].theaterId 是否正确？
   - map.validateRegionGraph() 是否为空？

2. Hex 层
   - Division.coord 是否真的变化？
   - HexTile.controller 是否真的变化？
   - 目标 hex 是否被其他单位占据？
   - OccupationRules.canOccupy 是否允许？

3. Region 层
   - state.map.region(for: hex) 是否正确？
   - RegionOccupationRules.aggregateControl 后 region.controller 是否改变？
   - 是否出现权重并列导致 controller 不变？

4. Theater 层
   - initialSnapshot.regionToTheater 是否保持不变？
   - regionToTheater 是否被错误当成动态推进层？
   - hexToTheater[destination] 是否只改了目标 hex？
   - dynamicTheaterId(for:) 是否 fallback 到 regionToTheater 造成误读？

5. Front 层
   - FrontLineManager 是否扫描到真实相邻 hex？
   - fixture 是否只写了 Region.neighbors 但没有真实 hex 邻接？
   - split region 是否需要允许 regionA == regionB？
   - frontLineState.diagnostics.updatedRegionIds 是否包含目标 region？

6. Deploy 层
   - hexToFrontZone[destination] 是否更新？
   - regionToFrontZone 是否只是 dominant/fallback？
   - 单位为什么是 front/depth/garrison？
   - zone.unitsFront 是否包含应该行动的单位？

7. Directive 层
   - TheaterCommanderPool 是否为该 faction 生成 directive？
   - ZoneCommanderAgent 是否因为 zone.frontSegments 为空而返回 nil？
   - visibleEnemyStrength / friendlyFrontStrength 是否合理？
   - tactic/category 是否被记录？

8. Executor / RuleEngine 层
   - WarCommandExecutor.generatedCommands 是否为空？
   - CommandValidator 拒绝原因是什么？
   - fallback hold 是否执行？
   - WarDirectiveRecord.diagnostics 是否记录了拒绝？

9. UI 层
   - 当前 MapDisplayLayer 读的是 initial 还是 dynamic？
   - frontLine overlay 是否画在 friendlyBoundaryHexes？
   - observerMode 是否导致玩家不能选中行动单位？
```

---

## 10. 当前已知边界

- 真 LLM 尚未接入；当前只用 `SimulatedMarshalLLMClient` 模拟 fenced JSON 输出和解码流程。
- 默认 AI 上游已是 `MarshalAgent -> TheaterDirectiveEnvelope -> TheaterDirectiveDecoder -> ModernCommandChain advisory JSON -> TheaterDirectiveCompiler`，下游执行必须是 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- 元帅层不能直接输出底层 `Command`，不能直接修改地图、单位、hex controller 或动态战区权威。
- 统治者层只作为未来方向预留，当前 v6.10 不在主链路调用。
- v6.10 主线已包含外交、经济、现代 UI、ISR/EW/fire support 和 Playtest 闭环；继续并发修改时仍要审查文件归属、public API、JSON schema 和文档口径冲突。
- `AttackIntensity.infiltration` 已在 `WarCommandExecutor` 中解释为默认低投入上限；`.limitedCounter` 和 `.allOut` 仍主要依赖 tactic profile 与显式 `maxCommittedUnits`。
- `TacticConditionChecker` 当前总是允许现有战术。
- 战区互助接口 `requestSupport` / `getAvailableForces` / `notifyThreat` 有模型但没有主流程调用方。
- 攻击不会自动占领目标 hex，只有移动会占领。
- Legacy Agent D 管线仍保留，不应删除，也不应默认接回主战争 AI。
- `RegionCommand` / AgentOrder v2 仍可桥接到 hex command，但当前默认战争 AI 是 ZoneDirective。
- 地图编辑器的 theater assignment 是初始战区划分，不是运行时动态战区脚本。
- 历史回退的 Cabinet/Minister/StrategicDirective 管线仍不得恢复；v0.5 当前实现没有把内阁或部长塞进 `GameState`。

---

## 11. 轻量检查入口与历史回归参考

检查规范以 `md/test/test.md` 为准。当前默认不跑 Xcode / XCTest / 模拟器 / 性能类验证，只做轻量语法、格式和配置检查。

历史上这些回归曾用于守住核心语义，但现在只作只读参考，不作为每轮默认执行项：

- Probe：`WWIIHexV0Probes`
  - 数据启动、region graph、theater、frontline、deployment。
  - v0.358 动态 hex 战区推进。
  - v0.36 tactic/directive。
  - v0.37 手写 directive issuer-agnostic 执行。
- Dynamic Theater Regression：`WWIIHexV0Tests/Stage0355DynamicTheaterTests`
  - 守住 `regionToTheater` 不动态推进、`hexToTheater` 单 hex 推进、split region front、deployment split。
- MapEditor：`WWIIHexV0Tests/MapEditorOutputTests`
  - 守住编辑器输出与游戏加载一致、默认资源一致、视角一致、开局不自动 AI。
- Stage Regression：
  - Theater / FrontLine / WarDeployment / CommandSystem / Agent / Observer / LayeredMap。

默认允许的检查方向：

- 文档改动：尾随空白、旧测试口径残留、人工阅读一致性。
- JSON 改动：对改动文件运行 `jq empty`。
- Xcode project / scheme 改动：运行 `plutil -lint` 或 `xmllint --noout`。
- 少量 Swift 改动：仅在不会触发全项目构建时，对直接改动文件做单文件语法检查。

多分支或多子 Agent 并发后，即使不跑测试，也必须检查文件重叠、public API 分叉、数据 schema 分叉、Xcode project 冲突和文档口径冲突。未完成冲突检查前，不得声称候选分支可合并。

---

## 12. v1.0 UI / AI / Playtest 分支收口

v1.0 分支名：`v1.0-ui-ai-playtest`。

该分支不改变战术权威和命令权威，只让当前主游戏更适合人工初版试玩和后续调参：

```text
GameState / WarDirectiveRecord / EventLog
  -> RootGameView
  -> HUD + Info tabs
  -> AgentPanelView 展示 command chain / command results / 折叠 Technical Replay
  -> EventLogView 展示最近 60 条分类日志

BoardScene
  -> 缓存 unit display hex
  -> 排序绘制单位
  -> deployment 图层复用 WarDeploymentManager 计算 role

Marshal / ZoneDirective
  -> AttackParameters.intensity
  -> WarCommandExecutor.attackTacticProfile
  -> infiltration 低投入上限
  -> RuleEngine 仍是唯一执行权威
```

算法变化：

- AI 面板从只展示 `AgentDecisionRecord` 扩展为同时展示 `WarDirectiveRecord`；默认主视图显示结构化 command chain、command results 和 errors，完整 directive 明细、diagnostics 与 raw JSON 收在 Technical Replay 中。
- 日志面板用 `LogDisplayEntry` 保存 entry + category，避免 body 内对同一条日志重复分类。
- 单位绘制先缓存 `unitDisplayHex` 再排序，避免 comparator 重复计算。
- `AttackIntensity.infiltration` 在无显式 `maxCommittedUnits` 时默认只投入约半数前线/纵深候选单位，避免渗透/袭扰全线压上。

试玩观察重点：

- UI：HUD、Info tabs、Economy、Diplomacy、AI panel 是否可读。
- 地图：hex/province/initial/dynamic/front/deploy 图层是否清晰。
- AI：结构化 command chain、折叠 Technical Replay、directive diagnostics 是否能解释 AI 回合。
- 规则：玩家和 AI 行动是否仍能追溯到 `CommandResultSummary` / `WarDirectiveRecord`。
- 性能体感：地图拖动、图层切换、日志面板滚动是否有明显卡顿。

当前限制：

- 未跑 Xcode / XCTest / 模拟器 / 性能测试。
- 当前工作树含多版本未提交改动，v1.0 合并前必须重新审查 `project.pbxproj`、Swift 新文件引用、AI schema 和文档版本口径。

---

## 13. v0.4 将军养成、将军 UI 与玩家双轨命令

v0.4 分支名：`v0.4-generals-command-ui-final`。

该分支把 0.41-0.48 的将军与玩家命令链路收口到当前代码，仍保持命令权威不变：

```text
Data/generals.json
  -> DataLoader.loadGeneralRegistry
  -> GeneralRegistry / GeneralDispatcher
  -> FrontZone.generalAssignment
  -> AppContainer.selectedGeneral*
  -> GeneralCommandPanelView / GeneralProfileView

玩家微操单位
  -> AppContainer.submit(Command)
  -> RuleEngine
  -> PlayerCommandState.micromanagedDivisionIds
  -> WarCommandExecutor.execute(... excluding: lockedIds)

玩家宏观将军命令
  -> GeneralCommandPanelView 按钮
  -> AppContainer 组装 ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> WarDirectiveRecord + PlayerPlannedOperation
  -> BoardScene 计划线 / 金色微操单位圈
```

核心算法：

- 将军数据：`GeneralData` 从 `generals.json` 读取，包含阵营、军衔、倾向、技能、头像占位、履历、偏好 theater/region、忠诚和满意度基线。
- 初始分配：`RegionNodeDefinition.assignedGeneralId` 可由地图 JSON / MapEditor 写入。`DataLoader` 在生成 `WarDeploymentState` 后收集 region 种子，调用 `GeneralDispatcher.assignGenerals`。
- 指派规则：
  1. 如果 FrontZone 已有合法同阵营 `generalAssignment`，保留该将军，只刷新 `assignedDivisionIds`。
  2. 否则优先使用该 zone 下 region 的 `assignedGeneralId`。
  3. 再按将军 `preferredTheaterIds` / `preferredRegionIds` 匹配。
  4. 最后从同阵营未占用将军池取第一名；没有可用将军时安全空岗。
- HQ 逻辑：不生成占格子的 HQ 单位。`GeneralAssignment.hqRegionId` 指向战区内友方城市或最大 region，`GeneralDispatcher.isHQUnderAttack` 通过 region controller 判断 HQ 是否被夺。
- 将军养成初步：`GeneralAssignment` 保存 `loyalty`、`satisfaction`、`interventionCount`。玩家直接微操某个将军辖下单位时，记录干预次数并轻微降低满意度。
- 微操锁：玩家在己方 phase 对具体师执行 move/attack/hold/resupply/allowRetreat 后，该师 id 写入 `PlayerCommandState.micromanagedDivisionIds`。本回合玩家再下达战区宏观命令时，`WarCommandExecutor.execute(... excluding:)` 会跳过这些师，避免同一回合被将军指令覆盖。`endTurn` 或 active faction / turn 改变时清空锁。
- 半自动指令：`GeneralCommandPanelView` 的 `Hold Line` 生成 defense `ZoneDirective`，`Attack Region` 根据当前选中敌方 region 和相邻玩家 FrontZone 生成 attack `ZoneDirective`，直接复用 `WarCommandExecutor -> RuleEngine`，不通过 `TurnManager.runDirectiveTurn`，因此不会自动结束玩家回合。
- 记录与反馈：玩家宏观命令写入 `WarDirectiveRecord` 和 `PlayerPlannedOperation`。`BoardScene` 只读 `PlayerCommandState.plannedOperations`，画源 region 到目标 region 的箭头；防御命令画源点圆环。玩家微操锁定单位在 `UnitNode` 上显示金色底圈。
- UI：`RootGameView` 新增 `General` tab，Unit tab 也嵌入 `GeneralCommandPanelView`。`GeneralProfileView` 用 sheet 展示将军身份、履历、技能、忠诚/满意度、干预次数、HQ 状态和辖下部队。

边界：

- v0.4 不让将军或 UI 直接修改 `GameState` 战术权威；所有行动仍要走 `Command` / `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- v0.4 没有实现真正抗命、政变、完整 RPG 成长树或真实 LLM 聊天解析；当前是忠诚/满意度和干预次数的可视化与数据底座。
- v0.4 没有做自由手绘前线。采用 region 锚点法：选择战区/目标 region 后自动画箭头，符合 0.44 文档中的移动端妥协方案。
- 当前工作树混有 v0.5、v0.7、v0.9、v1.x 外部改动；合并前必须重新做文件/API/schema/project 冲突审查。
