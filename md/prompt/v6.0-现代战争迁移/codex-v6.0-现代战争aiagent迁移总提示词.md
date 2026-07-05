# Codex v6.0-v6.10 任务提示词：从 WWIIHexV0 迁移为 AI Agent 驱动的现代战争策略游戏

> 本文是交给后续实现 Agent 的总提示词。它不是本轮代码实现记录，而是后续多版本迁移的路线、边界、并发分工和发布级验收标准。执行前必须先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。

---

## 0. 当前项目判断

你接手的是 `WWIIHexV0`，当前代码不是一个干净原型，而是一个已经有多条方向沉淀的 Swift + SwiftUI + SpriteKit 战棋工程。现有主链路包括：

```text
MapEditor / JSON
  -> DataLoader
  -> GameState
  -> HexTile.controller + Division.coord
  -> Region 聚合
  -> EconomyState 收入 / 生产 / 补员
  -> Theater / FrontLine / WarDeployment 派生层
  -> General / Marshal / Ruler / Diplomacy 草案
  -> TheaterDirective / ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> UI / SpriteKit / 日志 / WarDirectiveRecord
```

当前代码和文档中已经确认这些事实：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 hex 聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区，不是运行时推进权威。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、聊天命令和 MockAI 都必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- 当前默认 AI 文档口径已是 `MarshalAgent -> Operational Directive JSON (TheaterDirective schema) -> TheaterDirectiveDecoder -> ModernCommandChain advisory JSON -> TheaterDirectiveCompiler -> ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- Legacy Agent D 管线保留作回归参考，默认战争 AI 主路径不得退回旧管线。
- 当前 `Faction` 已支持 `blueForce`、`redForce`、`greenForce`、`neutral`，并以 `OperationalSideAlignment` / ROE helper 处理主路径敌我；`Faction.opponent` 仅作 legacy compatibility 属性保留。
- 当前单位源码类型仍叫 `Division`，但默认灰潮数据和玩家可见 UI 已走 formation / task force / commander display name；旧兵种和模板 id 只作 fallback / fixture 兼容。
- 当前经济源码字段仍是 `manpower / industry / supplies`，但玩家可见 UI 已收口为 PER / MAT / LOG、Facilities、sustainment 和现代 replacement 口径。
- 当前默认数据和主 UI 已切到 `grey_tide_2030`、虚构 Blue / Red commander 和现代显示口径；旧阿登、Bastogne、Guderian、Montgomery、Panzer 等保留在 fallback、测试 fixture 或历史文档中。
- 当前 `DataLoader.loadInitialGameState()` 默认优先加载 `grey_tide_2030_scenario` 与 `grey_tide_2030_regions`，失败才回退旧阿登资源。
- 当前 `RegionDataSet.toRegions()` 对 nil owner/controller fallback 到 `.neutral`，不再把中立 region 错落到 `.allies`。
- 当前工作树可能混有 v0.4、v0.5、v0.7、v0.8、v0.9、v1.0、v1.1、三国迁移、拿战迁移、隋唐迁移、明末迁移等未提交改动。任何实现前必须做分支和文件冲突审查，不能回滚他人改动。

迁移目标不是“把二战文案换成现代文案”，而是把这个工程逐步迁移为一个可发布的 AI Agent 驱动现代战争策略游戏：玩家在现代作战态势图上指挥合成营、无人系统、精确火力、空地协同、电子战和后勤节点；AI Agent 以可审计 JSON 指令协作决策，所有行动仍被统一规则系统约束。

---

## 1. 最终产品目标

暂定产品名：`现代联合指挥 Agent`。英文工作名可用 `Modern Command Agent` 或 `Joint Operations Agent`。不要使用或复制任何现有商业游戏的名称、角色、地图、美术、UI 或武器授权资产；用户提到的“三角洲那样”只作为“现代军事题材、特战与联合火力氛围、精致战术态势表现”的方向参考。

最终首发体验应达到以下效果：

1. 打开应用后直接进入可玩的现代战争战役，不做营销落地页。
2. 第一批可发布战役建议选择虚构近未来局部冲突，避免第一版就绑定现实敏感战场：
   - 首选：`灰潮行动 2030`。蓝方联合特遣队对抗红方区域集团军，含沿海城市、港口、机场、山区雷达站、关键桥梁和无人机走廊。
   - 备选：`北境走廊 2029`。寒区陆地走廊争夺，适合表现装甲、炮兵、无人侦察、电子战和后勤脆弱性。
   - 备选：`群岛封控 2031`。岛链、港口、机场、海空火力支援更明显，但首版复杂度更高。
   - 不要第一版就做全球大战略、完整海空战、核武、真实国家全面战争或实时 FPS 玩法。
3. 玩家可选择蓝方或红方；中立民用区、维和区、机场、港口、通信设施可以作为地图状态表达，但不直接替代战术 hex 权威。
4. 地图以 hex 为战术权威，以城市区块、交通节点、机场/港口/雷达站、山口和补给枢纽为 region 聚合层，以战区、旅战斗队、空域、火力区和电子战区为 AI 调度层。
5. 玩家既能微操具体地面部队，也能通过指挥官面板下达宏观任务：侦察、压制、防空、火力准备、突破、固守、撤离、补给、无人机巡逻、电子压制、空中支援。
6. AI 不直接改 `GameState`。国家指挥层、联合作战司令部、战区司令、旅级指挥官、空中任务官、ISR/EW 协调员、后勤官等 Agent 只能输出结构化 directive，经 decoder / validator / compiler 后落到规则系统。
7. UI 视觉要摆脱当前调试原型感：第一屏应像现代 C2/态势图，而不是纸牌堆砌。地图有卫星/战术底图质感，单位有清晰军标或抽象图标，前线、火力区、传感器覆盖、电子干扰、补给路线、AI 计划线和战报回放都能看懂。
8. UI 不能用大段说明文字解释玩法。核心体验应是地图、部队、任务、战报和 AI 决策复盘。
9. 发布前必须没有主要二战文案残留：Germany、Allies、Ardennes、Bastogne、Panzer、Guderian、WWII、Division 等不应出现在主游戏 UI、默认数据、日志和玩家可见面板中。源码兼容名可分阶段保留，但必须在文档中声明。
10. 发布前必须有一个可演示闭环：开局、选择阵营、查看战区和指挥官、侦察发现目标、无人机或侦察单位建立 contact、电子战影响传感器/通信、火力打击、地面推进、占领关键节点、AI 回合、战报复盘、胜负判断。

首发战役建议规格：

```text
scenarioId: grey_tide_2030
displayName: 灰潮行动 2030
地图范围：沿海港城、机场、山地雷达站、跨河桥梁、郊区工业带、补给入口
主要阵营：Blue Joint Task Force、Red Operational Group、Neutral / Civilian
首版规模：约 100-220 个 hex，24-50 个 region，5-10 个 operational zone / brigade sector
首版回合：12-24 回合，代表 24-72 小时局部行动窗口
胜利条件：蓝方夺取机场/港口/通信节点并维持补给；红方阻滞蓝方、保住防空/雷达节点或切断蓝方补给线
```

最终效果关键词：

- “态势图”：传感器覆盖、已确认目标、疑似目标、干扰区、补给路线、空中任务区、火力支援区。
- “现代兵器推演”：装甲、机械化步兵、炮兵/火箭炮、防空、无人机、特战、电子战、后勤、空中支援，但首版都做轻量抽象。
- “AI Agent 驱动”：每个 Agent 有角色、目标、约束、可读 JSON 输出、失败 fallback 和审计记录。
- “发布级”：默认剧本完整，UI 精致，玩家可理解命令反馈，文档和轻量检查准确，不伪造未跑的重测试。

---

## 2. 迁移总原则

### 2.1 保留的工程骨架

必须保留并迁移这些成熟资产：

- Hex 坐标、移动、攻击、占领、视野、补给落点的战术权威。
- Region 作为战略聚合层，不替代 hex。
- Dynamic Theater、FrontLine、WarDeployment 的派生关系。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord`、`RulerDecisionRecord` 等审计/复盘记录。
- MapEditor 的稀疏 hex、region、theater、unit 编辑与导出能力。
- iOS 主游戏、macOS 主游戏和 macOS 地图编辑器三个方向。
- 当前轻量检查规范和禁止重测试规则。

### 2.2 必须替换或抽象的二战语义

必须逐步替换这些题材绑定点：

- `Faction.germany/allies`：迁移为现代作战方，至少支持 `blueForce`、`redForce`、`greenForce`、`neutral`。如果后续做多国联合行动，再扩展 `CountryId` / `CoalitionId` / `PowerId`。
- `Faction.opponent`：多方敌我必须来自 `DiplomacyState` / `OperationalRelation` / `RulesOfEngagement`，不能继续用二元 opponent。
- `GamePhase.germanAI/alliedPlayer`：迁移为通用 phase，例如 `playerCommand`、`aiCommand`、`resolution`，或至少抽出显示与控制逻辑，避免 Germany/Allies 绑定。
- `Division` 显示语义：源码可短期保留兼容名，但 UI 应显示为 formation、task force、battle group、unit、合成营、旅战斗队、特战小队或无人系统分队。
- `ComponentType.tank/motorizedInfantry/infantry/artillery`：迁移为 `armor`、`mechanizedInfantry`、`lightInfantry`、`artillery`、`rocketArtillery`、`airDefense`、`engineer`、`recon`、`uav`、`loiteringMunition`、`specialForces`、`logistics`、`ew` 等。
- `EconomyResources.manpower/industry/supplies`：战役首版可显示为 personnel、materiel、fuel、ammo、spares、command bandwidth。短期源码字段可兼容，但 UI 不显示 Industry/Panzer 等二战语义。
- `ProductionKind.panzerDivision/motorizedDivision`：短战役首版建议弱化生产，改为 reinforcement package、resupply convoy、UAV sortie、ammo stockpile、air tasking slot。
- `Theater` 显示为 operational zone、task force sector、air defense sector、fires sector。
- `FrontZone` 显示为 brigade sector、battle group sector、front sector。
- `RulerAgent` 显示为 NationalCommandAgent / PoliticalAuthorityAgent，只能位于联合司令部上游。
- `MarshalAgent` 显示为 JointCommandAgent / TheaterCommandAgent / JTF Commander，负责战役意图。
- `ZoneCommanderAgent` 显示为 BrigadeCommanderAgent / BattleGroupCommanderAgent，负责把战役意图转成战术行动。
- 阿登 JSON：迁移为现代虚构剧本 JSON。
- 默认 UI 文案：中文优先，必要时保留英文开发字段和内部 id。

### 2.3 现代战争核心玩法方向

首发版本要体现现代战争特色，但不能一次性把模拟做得过重。优先级如下：

1. **侦察与不确定性**：现代火力必须依赖发现、确认和目标质量。首版至少区分 `unknown`、`suspected contact`、`confirmed contact`。
2. **无人系统**：UAV / loitering munition 作为侦察、目标指示或轻量打击资源，不要第一版做复杂实时飞行。
3. **电子战**：干扰、通信压制、传感器降效、无人机失联概率，必须可解释、可回放。
4. **精确火力**：炮兵/火箭/空中打击是任务或 directive，不是 UI 直接扣血。必须经校验、目标质量、弹药/冷却/风险处理。
5. **防空与空域风险**：空中支援要受防空区、制空状态、天气或电子战影响；首版可做抽象修正。
6. **合成营与特战**：装甲、机械化、步兵、工程、侦察、特战要在移动/战斗/占领/侦察上有差异。
7. **后勤与燃料弹药**：短战役中表现为 fuel、ammo、supply corridor、resupply convoy，不做完整国民经济。
8. **命令摩擦**：AI 指令可以被拒绝、延迟、降级或只部分执行；必须记录原因。
9. **规则约束的 AI Agent**：Agent 可以计划复杂联合作战，但最终只能输出结构化 directive，由规则系统执行。

### 2.4 不能做的事

- 不要一次性大规模重命名所有类型再凭感觉修编译。先建立兼容层和迁移合同，再分版本替换。
- 不要让任何 Agent 直接修改 `HexTile.controller`、`Division.coord`、`regionToTheater`、`hexToTheater`、`hexToFrontZone` 或经济账本。
- 不要绕过 `WarCommandExecutor`、`CommandValidator`、`RuleEngine`。
- 不要恢复旧 Cabinet / Minister / StrategicDirective 污染。现代战争可以有国家指挥层、联合司令部、参谋、空中任务官、后勤官、情报官，但必须是新 schema 和新管线。
- 不要删除 Legacy Agent D；只隔离和保留回归参考。
- 不要把 region 当成战术权威；进军、攻击、侦察、占领仍必须落到 hex 或经 hex 派生状态。
- 不要第一版就做完整海军、全球战略、核武、全面太空战、完整实时空战、真实国家战役复刻。
- 不要使用受版权保护的商业游戏素材、真实现代冲突照片、电影截图、未授权军标包或现成 UI 资源。可使用自制、生成、公共领域或明确授权素材。
- 不要硬编码 API key、模型路径或云端 LLM 请求。真实 LLM 接入必须单独版本，有 deterministic fallback。
- 未获人工授权，不跑 Xcode / XCTest / 模拟器 / macOS app 启动 / Probe / Smoke / Stage Regression / Full / 性能测试。

---

## 3. 现代战争设计合同

### 3.1 战术权威不变

现代化后仍必须保持：

```text
HexTile.controller + Unit.coord
  -> region / objective / sensor / supply / front / deploy 聚合
  -> AI 读取摘要
  -> directive / command
  -> RuleEngine 校验执行
```

如果引入空域、电子战区、火力区、传感器覆盖，它们只能作为派生层或任务层：

- 空域不能直接替代 hex 占领。
- 火力区不能绕过命令系统直接扣单位 strength。
- 传感器覆盖不能暴露不可见敌军完整真实状态给 UI 或 AI。
- 电子战不能直接改写敌方单位位置，只能影响通信、传感器、命令成功率、无人系统效率或火力修正。

### 3.2 现代战场状态建议

可分阶段新增这些状态。不要一轮全部做完：

```text
OperationalAwarenessState
  contactTracks: [ContactTrack]
  sensorCoverage: [HexCoord: SensorCoverage]
  lastUpdatedTurn

FireSupportState
  availableFireMissions
  cooldowns
  ammoBudgets
  noFireZones / restrictedFireZones

AirTaskingState
  airSuperiorityByZone
  airDefenseThreatByZone
  scheduledSorties
  sortieResults

ElectronicWarfareState
  jammingZones
  commsDegradedZones
  droneControlRisk

LogisticsNetworkState
  supplyRoutes
  fuelStatus
  ammoStatus
  convoyPlans
```

这些状态如果进入 `GameState`，必须：

- Codable / Equatable。
- 旧存档缺失时有 `.empty` fallback。
- 由 `StrategicStateBootstrapper` 或对应 manager 补齐。
- 由 `RuleEngine` / manager 刷新，不由 UI 直接写。
- 在 `md/flow/*` 和 `update_log.md` 同步记录。

### 3.3 现代命令方向

底层 `Command` 可保留现有 move / attack / hold / resupply / endTurn，同时逐步增加或由 directive 编译产生：

- `recon(unitId, targetHexOrRegion)`
- `fireMission(sourceIdOrAssetId, target, munition, targetQuality)`
- `assignUAV(assetId, patrolArea)`
- `jam(assetId, targetArea)`
- `airSupport(packageId, targetArea)`
- `deployCounterDrone(unitId, area)`
- `resupplyConvoy(origin, destination)`
- `evacuate(unitId, extractionHex)`

注意：如果新增命令，必须先设计 validator 和 executor。不要只在 UI 或 Agent JSON 中声明命令而无规则入口。

`ZoneDirective` 可扩展为现代 mission 类别：

```text
offense:
  assault
  breach
  isolateObjective
  raid
  reconInForce
  precisionStrike
  suppressAirDefense

defense:
  holdKeyTerrain
  delay
  mobileDefense
  counterRecon
  protectSupplyRoute

support:
  uavRecon
  electronicAttack
  counterBattery
  airInterdiction
  logisticsPush
```

首版不要让 tactic 数量失控。优先保证 6-10 个任务真的有执行路径和日志解释。

### 3.4 AI 可见性合同

AI Agent 读取的摘要必须分层：

- `TruthState`：规则内部真实状态，只给 RuleEngine / managers。
- `PlayerVisibleState`：玩家阵营可见状态。
- `AgentBattlefieldSummary`：Agent 可读的降维摘要。
- `ContactTrack`：目标 id、lastKnownHex、confidence、typeEstimate、age、source、isConfirmed。

AI 不应读到不可见敌军真实位置，除非情报规则允许。所有火力任务必须检查目标质量和 ROE / restricted fire zone。

### 3.5 UI 风格合同

现代战争 UI 应该是克制、密集、可扫描的作战态势界面：

- 主地图是第一屏核心。
- 图层切换使用 segmented controls / icon buttons。
- 命令按钮使用 SF Symbols 或已有图标系统，陌生图标提供 tooltip / accessibility label。
- 不使用一整屏深蓝或荧光绿单色主题；应有卫星灰、海图蓝、战术琥珀、告警红、友军蓝、敌军红、中立灰、电子战紫/洋红、补给绿等分层。
- 文本必须适配移动端和 macOS，不得重叠。
- 不在 UI 里写玩法说明段落；必要提示用短战报、tooltip 或 onboarding。

---

## 4. 多 Agent 并发工作流

主 Agent 负责总体架构、接口合同、冲突整合和最终验收。子 Agent 只能在明确边界内并发，不得同时改同一 public API 或同一文件。

### 4.1 并发前主 Agent 必做

1. 读完必读文档和本文件。
2. 执行轻量只读审计：

```sh
git branch --show-current
git status --short
rg -n "Germany|Allies|germany|allies|Ardennes|ardennes|Bastogne|Panzer|tank|motorized|Division|Guderian|Montgomery|Faction\\.opponent|germanAI|alliedPlayer" WWIIHexV0 MapEditor README.md md
rg -n "enum Faction|struct Division|enum ComponentType|EconomyResources|ProductionKind|DiplomacyState|ZoneDirective|WarCommandExecutor|RuleEngine|DataLoader|RegionDataSet" WWIIHexV0
```

3. 写出本轮实际版本目标和非目标。
4. 定义本轮公共接口合同。没有接口合同前，不要让多个子 Agent 同时改 `Core/`、`Commands/`、`Rules/`。
5. 明确 `WWIIHexV0.xcodeproj/project.pbxproj` 只能由主 Agent 或唯一指定的 Project Agent 修改。
6. 如果当前工作树已有不属于本轮的 dirty 文件，先记录并绕开，不要回滚。
7. 若使用并发子 Agent，先分配互不重叠的文件范围和 schema 责任，再启动。

### 4.2 推荐子 Agent 分工

每轮最多并发 3-5 个子 Agent。优先减少冲突，不追求数量。

#### Audit / Docs Agent

范围：

- `README.md`
- `update_log.md`
- `md/flow/`
- `md/test/test.md`
- `md/prompt/v6.0-现代战争迁移/`

职责：

- 扫描二战硬编码、二元阵营、旧 phase、旧资源、旧单位。
- 维护迁移词汇表、版本审计表、风险清单。
- 更新 flow / flowchart，使它们描述当前真实代码。
- 记录轻量检查和未跑重测试原因。

禁止：

- 不改 Swift 业务逻辑。
- 不把未验证运行时行为写成已验证。

#### Architecture / API Agent

范围：

- 只读全仓。
- 必要时只改主 Agent 指定的接口文档或小范围 Swift 类型。

职责：

- 设计 `PowerId` / `Faction` 兼容策略。
- 设计 contact、sensor、fire、EW、air tasking、logistics 状态的最小合同。
- 规定 Codable schema、旧存档 fallback、manager 刷新边界。

禁止：

- 不直接大规模改实现。
- 不改 project 文件。

#### Data / Scenario Agent

范围：

- `WWIIHexV0/Data/*.json`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/RegionDataSet.swift`
- `WWIIHexV0/Data/DataLoader.swift`

职责：

- 迁移剧本、地图、地形、兵种、装备、指挥官、作战方数据。
- 建立 `grey_tide_2030_scenario.json`、`grey_tide_2030_regions.json`、`modern_unit_templates.json`，并复用当前落地的 `generals.json` 作为现代 commander 数据、`terrain_rules.json` 作为现代地形规则数据；`modern_commanders.json` / `modern_terrain_rules.json` 属早期规划名，不作为 v6.10 当前必建文件。
- 保证 JSON key 稳定，id 使用 ASCII，例如 `power_blue`, `region_airport_east`, `unit_blue_bct_1`, `commander_blue_jtf`.
- 中文只放在 `displayName`、`localizedName`、`biography`、`briefing` 等展示字段。

禁止：

- 不改 `RuleEngine`。
- 不改 UI。
- 不改 project 文件，除非主 Agent 明确指定。

#### Rules Agent

范围：

- `WWIIHexV0/Core/`
- `WWIIHexV0/Commands/`
- `WWIIHexV0/Rules/`

职责：

- 将二元阵营、二战单位、二战补给经济迁移为现代战争可用的规则抽象。
- 保持 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一入口。
- 落地侦察、目标质量、电子战、火力任务、无人系统、后勤时必须先给最小可解释版本。
- 处理 neutral 不再 fallback 到 allies 的历史债。

禁止：

- 不改 SpriteKit/SwiftUI 视觉。
- 不新增真实网络 LLM 调用。
- 不用复杂新引擎替代已有命令管线。

#### AI Agent

范围：

- `WWIIHexV0/Agents/`
- `WWIIHexV0/Turn/`
- 只读 `Core/Commands/Rules`

职责：

- 设计并实现国家指挥层、联合司令部、战区司令、旅级指挥官、ISR/EW 协调员、空中任务官、后勤官等 Agent 分层。
- 所有输出必须是 JSON / Codable directive。
- 上游 Agent 只能调整战略姿态、目标优先级、火力/侦察/补给倾向或 directive envelope，不能直接执行底层命令。
- MockAI 必须有 deterministic fallback，不依赖真实模型。

禁止：

- 不直接改 `GameState`。
- 不绕过 `WarCommandExecutor`。
- 不把真实 API key 或模型路径写进仓库。

#### UI / SpriteKit Agent

范围：

- `WWIIHexV0/UI/`
- `WWIIHexV0/SpriteKit/`
- `Assets.xcassets` 如存在或由主 Agent 创建

职责：

- 迁移为现代作战态势 UI。
- 建立共享 design tokens：字体、颜色、材料、间距、圆角、线宽、动效。
- 地图、单位、传感器、火力区、电子战区、补给线、AI 计划、战报都要有发布级可读性。

要求：

- 44pt 最小触控区。
- 不在 SwiftUI body 内做重复排序、过滤、JSON 格式化。
- 大列表用 `LazyVStack` / `LazyHStack`。
- UI 只读状态，操作仍经 `AppContainer`、`Command` 或 `ZoneDirective`。
- 图标按钮优先使用 SF Symbols；陌生图标需要 tooltip / accessibility label。

禁止：

- 不把规则写进 View。
- 不让 SpriteKit 直接改 `GameState`。
- 不使用商业游戏或影视素材。

#### MapEditor Agent

范围：

- `MapEditor/`
- 只读 `Data/` schema

职责：

- 将编辑器术语迁移为地块、作战区、战区/旅防区、单位/装备、传感器点、机场/港口/通信节点。
- 支持现代地形：城市、郊区、工业区、机场、港口、桥梁、高地、森林、山地、河流、道路、雷达站、补给点。
- 支持初始指挥官、战区归属、增援入口和默认剧本资源切换。

禁止：

- 不破坏主游戏 JSON 加载格式。
- 不单独发明另一套 map schema。

#### Project / Assets Agent

范围：

- `WWIIHexV0.xcodeproj/project.pbxproj`
- `Assets.xcassets`
- 新增资源文件引用

职责：

- 仅在主 Agent 明确指定时修改 project 文件。
- 检查重复 UUID、缺失引用、target membership、bundle resource。
- 接入新 JSON 和资产。

禁止：

- 不同时让其他子 Agent 改 project 文件。
- 不做 Xcode build，除非人工授权。

#### Reviewer / Integration Agent

范围：

- 只读 diff，必要时改文档。

职责：

- 检查文件冲突、public API 分叉、JSON schema 分叉、project 冲突、文档口径冲突。
- 检查是否有人绕过 `RuleEngine` 修改状态。
- 检查是否有玩家可见二战文案残留。

禁止：

- 不做大重构。
- 不把未运行的测试写成通过。

### 4.3 并发整合规则

子 Agent 完成后，主 Agent 必须检查：

- 是否多个子 Agent 改了同一文件。
- 是否出现 public API 分叉。
- 是否出现 JSON schema 分叉。
- 是否出现 `Faction`、`PowerId`、`CountryId`、`CoalitionId`、`OperationalSideId` 多套概念混乱。
- 是否出现 `project.pbxproj` 重复引用、缺失引用或 UUID 冲突。
- 是否出现 README、`md/flow/*`、阶段记录口径不一致。
- 是否有人绕过 `RuleEngine` 修改状态。
- 是否有玩家可见二战文案残留。
- 是否有 AI 读取不可见敌军真实状态。
- 是否有火力 / 空中 / EW 任务绕过 command validator。

没有完成这些检查前，不得声称“多 Agent 工作可合并”。

---

## 5. 版本路线

### v6.0：迁移审计、兼容合同和现代战争产品定义

建议分支：`codex/v6.0-modern-audit-contract`

目标：

- 建立现代战争迁移的工程合同。
- 找出所有二战硬编码和二元阵营假设。
- 明确首发剧本、最终效果、非目标和并发分工。
- 不急着实现完整现代战场玩法。

范围：

- 新增或更新阶段记录：`md/prompt/v6.0-现代战争迁移/v6.0_audit_and_contract.md`。
- 新增迁移词汇表和命名约定：
  - `Faction` 当前源码兼容名，目标语义为 operational side / coalition side。
  - `Division` 当前源码兼容名，目标显示为 task force / battle group / formation。
  - `Theater` 显示为 operational zone / task force area。
  - `Region` 显示为 sector / objective / district / node。
  - `FrontZone` 显示为 brigade sector / battle group sector。
  - `Supply` 显示为 logistics / fuel / ammo / sustainment。
- 抽出 UI 显示名，不要让主要面板继续硬编码 Ardennes、Germany、Allies。
- 记录所有必须在 v6.1-v6.4 处理的硬编码点。

推荐并发：

- Audit / Docs Agent：硬编码扫描、审计表、词汇表。
- UI Agent：只读定位 UI 硬编码，不实现大 UI。
- Rules Agent：只读定位 `Faction.opponent`、二元 switch、二战兵种耦合。
- Data Agent：只读定位默认资源和 JSON schema。

验收：

- 有完整审计清单。
- 有现代战争迁移词汇表。
- 有版本拆分和风险清单。
- 没有大范围重命名导致不确定风险。

轻量检查：

- 文档尾随空白检查。
- 冲突标记扫描。
- 不跑 Xcode / XCTest / 模拟器。

### v6.1：作战方、多方敌我、ROE 和通用回合阶段

建议分支：`codex/v6.1-modern-sides-roe-turns`

目标：

- 从二元 `germany/allies` 迁移到可支持蓝方、红方、中立和未来多国联合行动的现代架构。
- 首发至少支持 Blue Force、Red Force、Neutral / Civilian。
- 为后续 Green Force、Coalition partner、Insurgent、Peacekeeper 等留扩展空间。
- 保持旧数据可兼容加载或有明确迁移 fallback。

设计建议：

1. 审计 `Faction` 的所有使用点。
2. 如果短期发布优先，可先扩展 `Faction` enum：
   - `blueForce`
   - `redForce`
   - `greenForce`
   - `neutral`
3. 如果改为数据驱动 `PowerId` / `OperationalSideId`，必须先做兼容桥，不要一轮内强行改完全项目。
4. 移除或弃用 `Faction.opponent`。敌我必须来自 `DiplomacyState` / `OperationalRelation` / `RulesOfEngagement` helper。
5. `DiplomacyState` 可迁移为现代 ROE / coalition relation：
   - friendly / coalitionPartner / neutral / restricted / hostile / atWar
6. 中立地块/region 不能 fallback 到某个玩家阵营。
7. `GamePhase` 要从 `germanAI/alliedPlayer` 脱钩。可以保留 raw value 兼容旧存档，但 UI 和新数据必须用通用语义。
8. `AppContainer.shouldRunAI` 必须基于 active side 是否由 AI 控制，而不是 germany/allies 写死。
9. 命令校验要考虑 ROE：restricted / civilian region 内火力任务必须被拒绝或降级，并写入日志。

推荐文件：

- `WWIIHexV0/Core/Faction.swift`
- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Core/GamePhase.swift`
- `WWIIHexV0/Core/GameState.swift`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/DataLoader.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/OccupationRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/FrontLineManager.swift`
- `WWIIHexV0/Rules/StrategicStateSynchronizer.swift`
- `WWIIHexV0/App/AppContainer.swift`

推荐并发：

- Rules Agent：敌我判断、phase、active side、ROE helper。
- Data Agent：side / coalition / ROE profile JSON 草案。
- AI Agent：只读确认 agent config 对多方作战的影响。
- Docs / QA Agent：文档和检查。

验收：

- 多作战方可以被 JSON 表达。
- 敌我判断不再依赖 `.opponent`。
- 中立地块/region 不会被错误算给某个势力。
- `CommandValidator` 对玩家与 AI 仍对称。
- 旧二战数据如果仍保留，必须通过兼容路径，不污染新默认剧本。

轻量检查：

- `jq empty` 检查改动 JSON。
- 对直接改动且可单文件 parse 的 Swift 文件运行 `swiftc -parse`；如果跨文件依赖导致不可行，停止并记录。
- `plutil -lint` 仅在 project 文件变更时运行。

### v6.2：首发现代剧本、数据资源和地图编辑器迁移

建议分支：`codex/v6.2-grey-tide-scenario-map`

目标：

- 建立第一张可玩现代战争剧本地图。
- 保留 MapEditor 导出链路。
- 默认新局加载现代剧本，而不是阿登。

默认剧本建议：

```text
id: grey_tide_2030
displayName: 灰潮行动 2030
地图范围：沿海港城、机场、山地雷达站、跨河桥梁、工业区、补给入口
主要作战方：Blue Joint Task Force、Red Operational Group、Neutral / Civilian
主目标：East Airport、Harbor Terminal、Radar Ridge、River Bridge、Industrial Hub、Comms Center、Northern Pass
首版规模：100-220 个 hex，24-50 个 region，5-10 个 operational zone / brigade sector
```

现代地形建议：

- plain -> open ground / 开阔地
- forest -> woodland / 林地
- hill -> ridge / 高地
- mountain -> mountain / 山地
- city -> urban / 城市区
- fortress -> hardened site / fortified position / 加固设施
- road -> highway / road
- river edge -> river / bridge crossing
- 可后置：suburb、industrial、airport、port、rail, wetland、tunnel、radarSite、powerStation

现代 JSON 文件建议：

- `WWIIHexV0/Data/grey_tide_2030_scenario.json`
- `WWIIHexV0/Data/grey_tide_2030_regions.json`
- `WWIIHexV0/Data/modern_unit_templates.json`
- `WWIIHexV0/Data/generals.json`（当前现代 commander 数据落地文件；早期规划名 `modern_commanders.json` 不另建）
- `WWIIHexV0/Data/terrain_rules.json`（当前地形规则落地文件；早期规划名 `modern_terrain_rules.json` 不另建）
- `WWIIHexV0/Data/modern_operational_sides.json` 可后置到 v6.1 或 v6.2。

MapEditor 迁移：

- `province` UI 改为作战区/目标区。
- `theater` UI 改为战区/旅防区/任务区。
- `unit` UI 改为部队/装备/任务编组。
- 支持 `assignedGeneralId` 显示为指挥官。
- 支持机场、港口、雷达站、通信节点、桥梁、补给入口、增援入口；如果 schema 暂不支持，先记录后置，不要塞到无关字段。

推荐并发：

- Data Agent：新 JSON 和 DataLoader 默认入口。
- MapEditor Agent：编辑器中文术语和导出字段兼容。
- UI Agent：地图层显示名和 accessibility label。
- Docs / QA Agent：同步 flow 和 README。

验收：

- 默认新局加载 `grey_tide_2030` 剧本路径。
- `MapEditorExporter` 可以导出现代语义地图而不丢 region/theater/unit。
- 默认数据不再出现阿登主剧本名。
- 所有 id 使用 ASCII，展示名可为中文。

轻量检查：

- 对新/改 JSON 跑 `jq empty`。
- 如果改 project，跑 `plutil -lint WWIIHexV0.xcodeproj/project.pbxproj`。
- 文档尾随空白和冲突标记扫描。

### v6.3：现代部队、装备、移动、战斗和后勤基础

建议分支：`codex/v6.3-modern-units-combat-logistics`

目标：

- 把二战单位和战术转换为现代合成作战规则。
- 保留 hex 战术权威和统一命令管线。
- 首版规则要可解释、可调参，不追求真实军工细节。

单位模型建议：

- 源码可短期保留 `Division`，但 UI 显示为 task force / battle group / company team / SOF team / UAV detachment。
- `ComponentType` 迁移为：
  - armor
  - mechanizedInfantry
  - lightInfantry
  - recon
  - artillery
  - rocketArtillery
  - airDefense
  - engineer
  - logistics
  - uav
  - loiteringMunition
  - specialForces
  - electronicWarfare
- stats 仍可保留 attack / defense / movement / range / vision。
- 新增 readiness / ammo / fuel / signature / electronicProtection 可分阶段；首版若字段风险过大，可先用 strength + supplyState + combat modifiers 兼容。

战术映射建议：

- `standardAttack` -> assault / direct attack
- `spearhead` -> armored thrust
- `breakthrough` -> breach
- `pincerMovement` -> envelopment
- `fireCoverage` -> fire support / suppression
- `feint` -> fixing attack
- `guerrillaWarfare` -> raid / infiltration
- `holdPosition` -> hold key terrain
- `elasticDefense` -> delay
- `defenseInDepth` -> layered defense
- `lastStand` -> hold at all costs

新增或迁移规则：

- 装甲/机械化：开阔地和道路机动强，城市/山地/森林受限。
- 步兵/特战：城市、森林、山地防御和渗透更强。
- 工程：改善跨河、突破加固设施、修复补给路线，可先作为移动/攻击修正。
- 防空：降低空中支援和无人系统效率。
- 后勤：fuel / ammo / supply warning 影响移动、火力和恢复。
- 城市/加固设施：防御强，火力任务可压制但占领仍必须落到地面 hex。

推荐文件：

- `WWIIHexV0/Core/Division.swift`
- `WWIIHexV0/Core/SupplyState.swift`
- `WWIIHexV0/Core/Terrain.swift`
- `WWIIHexV0/Rules/CombatRules.swift`
- `WWIIHexV0/Rules/MovementRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Commands/WarDirective.swift`
- `WWIIHexV0/Commands/WarCommandExecutor.swift`
- `WWIIHexV0/Agents/ZoneCommanderAgent.swift`

推荐并发：

- Rules Agent：部队、战斗、后勤、现代战术修正。
- AI Agent：战术分类器现代化。
- Data Agent：unit templates。
- UI Agent：只做术语显示，不做大 UI。

验收：

- 玩家和 AI 的移动、攻击、防守、补给仍经 `RuleEngine`。
- 装甲、机械化、步兵、炮兵、防空、工程、后勤至少有可解释差异。
- 战术名称在 UI 和 `WarDirectiveRecord` 中现代化。
- 没有 Panzer / tank / motorized 作为玩家可见文本残留。

轻量检查：

- 改 JSON 跑 `jq empty`。
- 少量 Swift 文件可尝试单文件 parse；失败则记录依赖风险。
- 禁止跑全项目 build/test。

### v6.4：ISR、战争迷雾、ContactTrack 和电子战基础

建议分支：`codex/v6.4-modern-isr-ew-fog`

目标：

- 让现代战争不再是“双方全知互打”。
- 建立侦察、传感器覆盖、目标确认、电子干扰和通信降级的第一版规则。
- AI 和 UI 只能读取允许可见的摘要。

最小设计：

```text
ContactTrack
  id
  ownerFaction / observerSide
  lastKnownCoord
  confidence: low / medium / high / confirmed
  estimatedType: armor / infantry / artillery / airDefense / logistics / unknown
  source: groundRecon / uav / signal / visual / fireObservation
  ageInTurns
  linkedDivisionId? 仅规则内部可用，UI/AI 默认不暴露

SensorCoverage
  coord
  side
  quality
  sources
  jammed

EWEffect
  area
  side
  effectType: jamming / commsDegrade / droneDisrupt / sensorSpoof
  strength
  remainingTurns
```

规则要求：

- 侦察命令生成或刷新 contact，不直接造成伤害。
- 火力任务只能打 confirmed 或足够 confidence 的 contact；低 confidence 允许低效果或高偏差，但必须有日志。
- 电子战影响 sensor quality、drone control、command friction 或 fire mission accuracy。
- AI summary 只能包含 visible contacts，不得读取真实敌军列表。
- Contact 过期会降级或消失。

推荐文件：

- `WWIIHexV0/Core/OperationalAwarenessState.swift` 新增。
- `WWIIHexV0/Core/GameState.swift`
- `WWIIHexV0/Core/StrategicStateBootstrapper.swift`
- `WWIIHexV0/Commands/Command.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- `WWIIHexV0/Rules/VisibilityRules.swift` 若新增。
- `WWIIHexV0/Agents/*Summary*`
- `WWIIHexV0/UI/AgentPanelView.swift`
- `WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift`

推荐并发：

- Rules Agent：state、recon command、EW effects、visibility helper。
- AI Agent：summary 降维和不可见信息隔离。
- UI Agent：contact overlay、sensor overlay、EW overlay。
- Docs / QA Agent：flowchart 和风险记录。

验收：

- 玩家和 AI 看到的是 contact，不是全量真实敌军。
- Recon / UAV / EW 行动有日志和可回放记录。
- 火力任务前置目标质量检查存在。
- 不可见信息隔离在文档中明确。

### v6.5：精确火力、空地协同、无人系统和防空抽象

建议分支：`codex/v6.5-modern-fires-air-drone`

目标：

- 建立现代作战核心爽点：发现目标、压制防空、火力打击、地面推进。
- 首版做抽象任务，不做复杂实时空战或真实武器数据库。

设计建议：

```text
FireSupportState
  ammoBudgetBySide
  cooldownsByAsset
  scheduledMissions
  lastMissionResults

FireMission
  id
  issuerId
  side
  sourceAssetId?
  target: contact / hex / region
  munitionClass: tubeArtillery / rocket / precision / loitering
  targetQuality
  expectedEffect
  riskFlags

AirTaskingState
  sorties
  airDefenseThreat
  airSuperiority
  missionResults
```

规则方向：

- `fireMission` 由 `Command` 或 `ZoneDirective` 编译产生。
- validator 检查目标质量、弹药、冷却、ROE、防空威胁、己方邻近风险。
- executor 生成压制、损伤、撤退、暴露、弹药消耗或 mission failed 日志。
- `uavRecon` 增加 contact quality，但在 EW / airDefense / counterDrone 下可能失败或降级。
- `suppressAirDefense` 可降低某 region/zone 的空中风险若干回合。
- 空中支援不直接长期占领 hex，只影响战斗和日志。

推荐并发：

- Rules Agent：FireSupportState、FireMission command、validator/executor。
- AI Agent：fire planning / air tasking directive 编译。
- UI Agent：火力区、空中任务区、mission result overlay。
- Data Agent：现代 asset template。

验收：

- 玩家能看到“侦察 -> 确认 -> 火力打击 -> 地面推进”的闭环。
- 火力任务不会绕过规则直接改状态。
- 防空 / EW 对空中和无人任务有可解释影响。
- 战报能说明成功、失败、拒绝或误差原因。

### v6.6：现代 AI Agent 指挥链和并发协作

建议分支：`codex/v6.6-modern-agent-command-chain`

目标：

- 构建真正有现代作战味道的 AI Agent 层级。
- Agent 之间可以协作，但最终都必须输出结构化 directive。
- 让 AI 行为可审计、可回放、可调参。

推荐层级：

```text
NationalCommandAgent / PoliticalAuthorityAgent
  -> 决定政治约束、ROE、优先目标、升级限制

JointCommandAgent / TheaterCommandAgent
  -> 把战略意图变成战役目标：夺机场、封锁港口、切断补给、压制防空

ChiefOfStaffAgent
  -> 处理优先级、预备队、时间线、风险和任务冲突

ISRCoordinatorAgent
  -> 分配侦察、UAV、SIGINT、contact confirmation

FiresCoordinatorAgent
  -> 分配炮兵/火箭/精确火力、反炮兵、火力准备

AirTaskingAgent
  -> 分配 CAS、interdiction、SEAD、air recon，受防空与空优影响

EWCoordinatorAgent
  -> 分配 jamming、comms degrade、counter-drone、sensor spoof

LogisticsAgent
  -> 分配补给、弹药、燃料、维修、补给线保护

BrigadeCommanderAgent / BattleGroupCommanderAgent
  -> 把方面目标变为 ZoneDirective：进攻、防守、侦察、突破、固守、撤离
```

执行链路要求：

```text
NationalCommandAgent / ROE
  -> StrategicConstraintEnvelope
  -> JointCommandAgent
  -> TheaterDirectiveEnvelope
  -> ISR / Fires / Air / EW / Logistics sub-directives
  -> decoder / validator / compiler
  -> ZoneDirective / Command
  -> WarCommandExecutor / RuleEngine
  -> WarDirectiveRecord / AgentDecisionRecord
```

结构化输出要求：

- 所有 Agent 输出必须 Codable。
- 所有外部模型输出必须 fenced JSON 或纯 JSON，由 decoder 校验。
- decoder 必须校验 schemaVersion、turn、issuerId、side/faction、zone、region、contact、mission type。
- decoder 失败时走安全 fallback，不执行半成品。
- Agent prompt 中不能要求模型“直接修改状态”。
- 多 Agent 冲突由主编排器或 ChiefOfStaffAgent 仲裁，不能让两个 Agent 同时直接执行相互冲突命令。

Mock / 本地 LLM 要求：

- 首版仍可用模拟 LLM / MockAI。
- 真实本地 LLM 接入必须单独版本，不能把 API key 或模型路径硬编码进仓库。
- 网络或本地模型不可用时，必须有 deterministic fallback。

推荐并发：

- AI Agent：Agent schema、prompt builder、fallback、orchestrator。
- Rules Agent：新增 directive 的 validator 和 executor 边界。
- UI Agent：AI 决策复盘面板显示层。
- Docs / QA Agent：更新 flowchart。

验收：

- AI 回合能解释“国家约束是什么、联合司令部想要什么、ISR/EW/火力/旅级指挥官做了什么”。
- 玩家能在 AI 面板看到 raw JSON、编译后的 directive、命令结果和拒绝原因。
- Agent 决策失败不会破坏回合。
- 仍未绕过 `RuleEngine`。

### v6.7：玩家现代指挥 UI、任务计划和人机协同

建议分支：`codex/v6.7-modern-player-command-ui`

目标：

- 让玩家能像现代指挥官一样下达任务，而不是只点 move / attack。
- 保留微操能力，同时提供宏观 mission planning。
- 玩家命令和 AI 命令共用后端 directive 管线。

功能建议：

- 选中部队：显示 readiness、ammo、fuel、supply、signature、visible contacts、可执行任务。
- 选中 region/objective：显示控制权、敌我 contact、传感器覆盖、火力风险、补给价值。
- 任务面板：
  - Recon Area
  - Establish UAV Orbit
  - Suppress / Fire Mission
  - Assault Objective
  - Hold / Delay
  - Protect Supply Route
  - Resupply / Repair
  - Jam / Counter-Drone
  - Air Support / SEAD
- 计划可视化：侦察扇区、火力圈、进攻箭头、防御区域、补给线、撤退路线、AI 计划线。
- 拒绝原因必须可读：目标未确认、弹药不足、防空威胁高、ROE 限制、路径不可达、单位已行动、通信受扰。

设计要求：

- 不要把所有命令做成一排文字按钮；使用图标、分组、segmented controls、short labels。
- 图层和任务面板必须在 iPhone / iPad / macOS 都有可用布局。
- 不要在 View 中直接改 `GameState`，只调用 `AppContainer` 提交命令或 directive。

推荐并发：

- UI Agent：任务面板、选中对象摘要、AI/战报 tabs。
- SpriteKit Agent：计划线、火力区、sensor/EW overlays。
- Rules Agent：玩家 directive helper 和微操锁。
- Docs / QA Agent：交互说明和风险。

验收：

- 玩家能从 UI 发起至少 5 类现代任务。
- 每类任务最终都能追踪到 `Command` / `ZoneDirective` / `RuleEngine`。
- 拒绝和成功都有清晰反馈。
- 地图可读，不被面板遮住。

### v6.8：发布级现代 C2 UI、美术和交互收口

建议分支：`codex/v6.8-modern-ui-polish`

目标：

- 把当前工程从开发调试界面提升到可发布演示界面。
- 不靠说明文字，而靠地图、图层、状态、战报和 AI 复盘让玩家理解战局。

视觉方向：

- 主地图：现代战术态势图 / 卫星地图 / 海图风格。避免纯深蓝或纯绿主题，使用分层色彩。
- 单位：清晰区分 armor、mechanized、infantry、recon、artillery、airDefense、uav、ew、logistics、sof。
- Contact：疑似和确认目标视觉不同，过期 contact 要降级。
- 传感器：覆盖区用半透明扇区或 hex heatmap，不能遮挡单位。
- 火力：火力任务区、压制区、危险区和 no-fire zone 区分明显。
- EW：干扰区、通信降级、无人机风险使用紫/洋红系，但不能铺满导致不可读。
- 补给：补给线、补给节点、convoy route 用绿色/青色虚线，断线有警告。
- 战报：展示本回合关键行动、拒绝原因、contact 更新、火力结果、EW 影响、补给变化、AI 指令。

主界面布局建议：

```text
顶部：回合/时段、当前作战方、命令状态、ammo/fuel/supply 摘要、胜利状态、结束回合
中央：SpriteKit 战场地图，全屏优先
左侧或底部：选中单位/目标/contact 摘要，移动端可折叠
右侧或底部：任务/战区/战报/AI/后勤/情报 tabs
地图上：选中、可移动、可攻击、侦察区、火力区、EW 区、前线、补给线、计划线
```

SwiftUI 要求：

- 建立 `ModernCommandDesignTokens` 或类似共享设计常量。
- 44pt 最小触控区。
- 使用 `Label` 和 SF Symbols；不手写常见图标。
- 避免 body 内重复排序、过滤、JSON 格式化。
- 大列表用 Lazy 容器。
- 复杂面板拆成独立 View，不要继续膨胀 `RootGameView`。
- 不引入第三方框架，除非人工确认。

SpriteKit 要求：

- 地图必须在桌面和移动端都可缩放、平移、点击。
- 文字不能重叠到不可读。
- 单位、contact、目标图标有稳定尺寸，不因状态变化造成跳动。
- 图层切换清晰：地形、控制、动态战区、前线、部署、传感器、火力、EW、补给、AI 计划。
- 视觉资产必须是自制、生成、公共领域或明确授权。

推荐并发：

- UI Agent：SwiftUI 面板、设计 token。
- SpriteKit Agent：地图绘制、单位、图层、箭头和 overlays。
- Data / Art Agent：图标、纹理、指挥官头像占位和 asset catalog。
- Docs / QA Agent：截图检查清单和未跑重测试风险。

验收：

- 主游戏第一屏不再像调试板。
- 主要 UI 无二战文案残留。
- 移动端和 macOS 布局都有明确约束。
- UI 只读状态，操作仍走 `AppContainer` 和规则系统。

### v6.9：新手引导、存档、设置、试玩闭环

建议分支：`codex/v6.9-modern-playtest-loop`

目标：

- 从“系统迁移版”收口到“玩家能理解并完成一局短战役”。
- 补齐新局、继续、设置、重置、战报回放、错误恢复和试玩记录。

范围：

- 新局：选择战役、选择作战方、选择 AI 控制选项。
- 继续：本地存档 schema，保存/加载 GameState 或受控 snapshot。
- 设置：AI 速度、日志详细度、地图图层默认值、Reduce Motion、文字大小适配。
- 引导：第一次选中单位、侦察、火力任务、EW、结束回合时给短提示；不要做大篇说明页面。
- AI 回放：显示联合司令部意图、ISR/EW/火力/旅级命令、执行结果、拒绝原因。
- 错误恢复：JSON 加载失败、AI 解码失败、无可行动单位、命令被拒绝必须有玩家可读反馈。

推荐并发：

- UI Agent：新局/设置/引导/回放。
- Rules/State Agent：存档 schema 与兼容。
- AI Agent：AI 回放摘要。
- Docs / QA Agent：试玩检查单。

验收：

- 玩家能从新局进入 `灰潮行动 2030` 并完成多个回合。
- AI 失败有 fallback，不会卡死。
- 存档/重置不会污染默认资源。
- 引导不遮挡地图核心交互。

### v6.10：发布候选和发布前验收

建议分支：`codex/v6.10-modern-release-candidate`

目标：

- 从“可玩迁移版”收口到“可发布候选版”。
- 补齐版本说明、残留扫描、资源检查、人工授权重验证清单。

发布候选必须具备：

- App 名称、图标、默认剧本、主界面、基础设置。
- 新局 / 继续 / 重置。
- 一个完整可玩的现代战争剧本。
- AI 回合不会卡死或静默失败。
- 玩家可理解的命令反馈。
- 关键 JSON 数据可解析。
- README 和 flow 文档准确描述当前现代战争架构。
- `update_log.md` 记录 v6.0-v6.10 每版完成内容、关键文件、轻量检查和未跑重测试。
- 玩家可见层面无主要二战残留。

发布前需要人工授权的重验证：

- Xcode build。
- iOS Simulator 或真机启动。
- macOS target 启动。
- 至少 10-20 回合观察者模式。
- 基础 UI 点击烟测。
- SpriteKit 截图或人工视觉检查。
- 性能体感检查。

在未获授权前，不得声称“已发布”或“可发布已验证”。只能写“发布候选代码和文档已准备，运行时验证未授权，风险未验证”。

---

## 6. 数据 schema 方向

实际实现可沿用现有结构，但必须在阶段文档写明哪些字段是兼容旧名、哪些字段已经现代化。

### 6.1 作战方 / Coalition

```json
{
  "id": "power_blue",
  "faction": "blueForce",
  "displayName": "Blue Joint Task Force",
  "localizedName": "蓝方联合特遣队",
  "shortName": "Blue",
  "coalitionId": "coalition_blue",
  "rulerAgentId": "national_command_blue",
  "bannerAsset": "banner_blue_jtf",
  "primaryColor": "#2F80ED",
  "secondaryColor": "#00B2A9",
  "warSupport": 78,
  "commandDoctrine": "joint_precision_maneuver",
  "rulesOfEngagement": "restricted_precision"
}
```

### 6.2 指挥官 / Agent

```json
{
  "id": "commander_blue_jtf",
  "name": "Avery Stone",
  "localizedName": "艾弗里·斯通",
  "rank": "Joint Task Force Commander",
  "power": "blueForce",
  "commandStyle": "balanced",
  "attributes": {
    "command": 88,
    "initiative": 82,
    "fires": 86,
    "isr": 90,
    "logistics": 78,
    "riskTolerance": 54
  },
  "skills": ["joint_fires", "sensor_fusion", "risk_control"],
  "portrait": "portrait_blue_commander_generated",
  "biography": "重视侦察融合和精确火力，倾向在确认目标后投入地面部队。",
  "preferredZoneIds": ["zone_blue_center", "zone_blue_airport_axis"],
  "baseLoyalty": 90,
  "baseSatisfaction": 76
}
```

### 6.3 现代单位模板

```json
{
  "id": "blue_mech_company_team",
  "displayName": "Mechanized Company Team",
  "localizedName": "机械化连级战斗队",
  "maxStrength": 10,
  "readiness": 8,
  "signature": 6,
  "components": [
    { "type": "mechanizedInfantry", "weight": 0.55 },
    { "type": "armor", "weight": 0.25 },
    { "type": "recon", "weight": 0.10 },
    { "type": "engineer", "weight": 0.10 }
  ],
  "capabilities": ["assault", "hold", "breach", "recon"],
  "logistics": {
    "fuelUse": 3,
    "ammoUse": 2
  }
}
```

### 6.4 Region / Objective

```json
{
  "id": "region_east_airport",
  "name": "East Airport",
  "localizedName": "东部机场",
  "owner": "neutral",
  "controller": "redForce",
  "terrain": "city",
  "theaterId": "zone_airport_axis",
  "displayHexes": [{ "q": 8, "r": 5 }, { "q": 9, "r": 5 }],
  "representativeHex": { "q": 8, "r": 5 },
  "city": {
    "name": "East Airport",
    "victoryPoints": 5,
    "isCapital": false
  },
  "infrastructure": 5,
  "supplyValue": 4,
  "resources": [
    { "type": "fuel", "amount": 3 },
    { "type": "ammo", "amount": 2 },
    { "type": "commandBandwidth", "amount": 1 }
  ],
  "coreOf": [],
  "isPassable": true
}
```

### 6.5 ContactTrack

```json
{
  "id": "contact_blue_turn_4_003",
  "observerSide": "blueForce",
  "lastKnownCoord": { "q": 11, "r": 6 },
  "confidence": "high",
  "estimatedType": "airDefense",
  "source": "uav",
  "ageInTurns": 0,
  "jammed": false,
  "notes": "Possible short-range air defense near radar ridge."
}
```

### 6.6 Theater Directive 示例

```json
{
  "schemaVersion": 8,
  "issuerId": "joint_command_blue",
  "turn": 6,
  "side": "blueForce",
  "strategicIntent": "Confirm air defense contacts near Radar Ridge, suppress them, then push the mechanized task force toward East Airport.",
  "constraints": ["avoid_restricted_fire_zone", "preserve_uav_assets"],
  "directives": [
    {
      "id": "directive_blue_isr_6",
      "zoneId": "zone_blue_center",
      "category": "support",
      "mission": "uavRecon",
      "priority": 92,
      "targetRegionIds": ["region_radar_ridge"],
      "requiredConfidence": "confirmed",
      "rationale": "Fires require better target quality before the ground assault."
    },
    {
      "id": "directive_blue_fires_6",
      "zoneId": "zone_blue_center",
      "category": "support",
      "mission": "suppressAirDefense",
      "priority": 86,
      "targetContactIds": ["contact_blue_turn_4_003"],
      "maxCommittedAssets": 1,
      "rationale": "Reduce air defense threat before committing CAS and UAV orbit."
    },
    {
      "id": "directive_blue_assault_6",
      "zoneId": "zone_blue_airport_axis",
      "category": "offense",
      "mission": "assault",
      "priority": 80,
      "targetRegionIds": ["region_east_airport"],
      "supportRegionIds": ["region_radar_ridge"],
      "reserveBias": 1,
      "rationale": "Ground force advances after ISR and fires shape the objective."
    }
  ]
}
```

---

## 7. 文档更新要求

每个版本完成后至少更新：

- `update_log.md`：版本号、完成日期、核心变更、关键文件、轻量检查、未跑重测试、遗留风险。
- `md/flow/flow.md`：当前真实核心逻辑。
- `md/flow/flowchart.md`：关键流程图，尤其是数据加载、动态战区、AI 指令链、ISR/EW/火力链路。
- `README.md`：当前项目定位、玩法、AI 管线、检查规则。
- 当前阶段提示词或实现记录：放在 `md/prompt/v6.0-现代战争迁移/`。

若源码行为、检查规则、核心流程、分支策略或版本状态改变，相关文档必须同步更新。

---

## 8. 轻量检查和禁止项

执行前必须读 `md/test/test.md`。当前默认不做 Xcode / XCTest / 模拟器 / 性能类测试。

允许的轻量检查：

```sh
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md md/flow/flowchart.md md/prompt/v6.0-现代战争迁移
rg -n "[<]{7}|[=]{7}|[>]{7}" AGENTS.md README.md update_log.md md/flow WWIIHexV0 MapEditor md/prompt/v6.0-现代战争迁移
rg -n "Germany|Allies|Ardennes|Bastogne|Panzer|tank|motorized|germanAI|alliedPlayer" WWIIHexV0 MapEditor README.md md/flow md/prompt/v6.0-现代战争迁移
jq empty WWIIHexV0/Data/grey_tide_2030_scenario.json
jq empty WWIIHexV0/Data/grey_tide_2030_regions.json
jq empty WWIIHexV0/Data/modern_unit_templates.json
jq empty WWIIHexV0/Data/generals.json
jq empty WWIIHexV0/Data/terrain_rules.json
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
```

Swift 单文件 parse 只在少量纯 Swift 改动且不会触发项目构建时使用：

```sh
swiftc -parse path/to/ChangedFile.swift
```

禁止主动执行：

- `xcodebuild test`
- `xcodebuild build`
- `xcodebuild build-for-testing`
- `xcrun simctl ...`
- Probe / Smoke / Stage Regression / Dynamic Theater Regression / Full
- XCTest、UI test、性能测试、快照测试
- 启动 iOS Simulator
- 启动 app 做人工烟测
- 全项目 Swift 编译、全量 lint、全量格式化

如果某问题必须依赖重测试才能确认，只记录风险，不擅自运行。

---

## 9. 发布级验收清单

发布候选前必须逐项确认：

- 默认场景是现代战争剧本，不是阿登。
- 主 UI 第一屏是可操作战场，不是说明页。
- 玩家可选择作战方或至少明确扮演方。
- AI 能通过结构化 directive 行动，失败有 fallback。
- 玩家和 AI 都经 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine`。
- `HexTile.controller` 和 `Division.coord` 仍是战术权威。
- `regionToTheater` 仍是初始/基础映射，不表示运行时推进。
- `hexToTheater` 和 `hexToFrontZone` 仍是动态权威。
- 侦察、contact、EW、火力、防空、补给至少有一个可解释的首版闭环。
- AI 面板能展示 raw JSON、编译后 directive、命令结果、拒绝原因。
- 战报能解释关键侦察、contact 更新、火力任务、EW 影响、补给变化、占领、撤退、命令失败。
- UI 没有主要二战文案残留。
- 新 JSON 都通过 `jq empty`。
- project 文件如改动通过 `plutil -lint`。
- 文档准确描述当前真实状态。
- 未跑重测试的范围和风险写清楚。

---

## 10. 风险清单

实现前必须主动关注这些风险：

- 当前工作树很脏，且历史记录显示分支多次漂移；合并前必须重新确认分支、基点、dirty 文件和冲突。
- `Faction` 已扩到现代作战方，但旧 raw value / fixture / display fallback 仍存在；继续修改时必须确认 ROE、补给、前线、部署、UI 和数据加载没有退回二元假设。
- `Faction.opponent` 仅作 legacy compatibility 属性保留；主路径不得重新调用它做敌我 fallback。
- `GamePhase.germanAI/alliedPlayer` 残留会让新作战方控制权表现错误。
- `RegionDataSet.toRegions()` 当前 nil owner/controller fallback 到 `.neutral`；后续若改 schema 必须保持中立语义。
- `DataLoader` 默认资源已切灰潮；旧阿登资源和 legacy template fallback 只作兼容，不能重新变成默认主路径。
- `project.pbxproj` 已多次被多分支修改，只能由一个 Agent 处理。
- UI/SpriteKit 改动需要视觉验证，但当前规范禁止主动启动 app；必须记录未验证风险。
- Contact / fog-of-war 若实现不严谨，AI 可能读取真实敌军状态，破坏玩法和架构边界。
- 火力 / 空中 / EW 任务若直接改状态，会绕过命令权威，必须阻止。
- 真实 LLM 接入、模型输出质量、长回合稳定性必须单独版本验证。
- 现代战争题材容易膨胀到海空天电网全系统；首版必须控制范围，先做局部行动闭环。

---

## 11. 给后续 Agent B 的执行口径

你不是在写一个新项目，而是在迁移一个已经有复杂规则和历史包袱的战棋工程。

你的优先级：

1. 保住规则权威：hex 是战术权威，命令必须走规则系统。
2. 先拆二战硬编码，再做现代内容。
3. 先做作战方、ROE 和敌我判断，再做复杂 AI。
4. 先做一个精制可玩虚构局部冲突剧本，不做全球无限沙盒。
5. 先做侦察、contact、EW、火力、补给的最小闭环，不做全量真实武器数据库。
6. 每轮只改当前版本范围，不顺手重构无关文件。
7. 多 Agent 并发时，先约定接口，再分文件实现，最后必须做冲突审查。
8. 轻量检查必须写具体命令和结果；重测试未授权必须明确说明未跑。

最终目标不是“二战换皮成现代”，而是让玩家在第一屏就能感到：这是一张现代联合作战态势图，侦察、电子战、无人系统、精确火力和地面机动相互依赖；AI Agent 通过可审计的 JSON 指令协作决策，而所有决策都被同一套战棋规则约束。
