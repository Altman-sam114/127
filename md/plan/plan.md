# WWIIHexV0 项目 md 大纲：现代战争 AI Agent 迁移路线

> 本大纲根据 `md/prompt/v6.0-现代战争迁移/codex-v6.0-现代战争aiagent迁移总提示词.md` 更新。它是后续文档和实现拆分的索引，不代表本轮已经完成源码迁移。

## 1. 当前工程基线

当前工程仍是 Swift + SwiftUI + SpriteKit 的 WWIIHexV0 战棋项目，但已经沉淀出可迁移到现代战争题材的核心骨架：

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

必须保留的架构铁律：

- Hex 是战术权威：移动、攻击、占领、视野、补给落点以 `HexTile.controller` 和 `Division.coord` 为准。
- Region 是战略聚合层，不替代 hex。
- `regionToTheater` 是初始/基础战区归属，不是运行时推进权威。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、聊天命令和 MockAI 必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- Legacy Agent D 保留作回归参考，默认战争 AI 主路径不得退回旧管线。

## 2. 现代战争产品目标

目标产品暂定为 `现代联合指挥 Agent`，英文工作名可用 `Modern Command Agent` 或 `Joint Operations Agent`。

首发体验建议：

- 直接进入可玩的现代战争战役，不做营销落地页。
- 默认虚构近未来局部冲突：`灰潮行动 2030`。
- 玩家在现代 C2 / 态势图上指挥合成营、无人系统、精确火力、空地协同、电子战、后勤节点。
- AI Agent 以可审计 JSON 指令协作决策，所有行动仍受统一规则系统约束。
- 首发闭环必须体现：侦察发现目标、ContactTrack、电子战影响、火力打击、地面推进、关键节点占领、AI 回合、战报复盘、胜负判断。

首发剧本规格：

```text
scenarioId: grey_tide_2030
displayName: 灰潮行动 2030
地图范围：沿海港城、机场、山地雷达站、跨河桥梁、郊区工业带、补给入口
主要阵营：Blue Joint Task Force、Red Operational Group、Neutral / Civilian
首版规模：约 100-220 个 hex，24-50 个 region，5-10 个 operational zone / brigade sector
首版回合：12-24 回合，代表 24-72 小时局部行动窗口
```

## 3. 迁移原则

### 3.1 保留工程骨架

- Hex / Region / Theater / FrontLine / WarDeployment 分层。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord`、`RulerDecisionRecord` 等审计记录。
- MapEditor 的稀疏 hex、region、theater、unit 编辑和导出能力。
- iOS 主游戏、macOS 主游戏、macOS 地图编辑器三方向。
- 当前轻量检查和云端验证规范。

### 3.2 替换或抽象二战语义

- `Faction.germany/allies` -> `blueForce`、`redForce`、`greenForce`、`neutral`，或数据驱动 `PowerId` / `OperationalSideId`。
- `Faction.opponent` -> `DiplomacyState` / `OperationalRelation` / `RulesOfEngagement` helper。
- `GamePhase.germanAI/alliedPlayer` -> `playerCommand`、`aiCommand`、`resolution` 等通用 phase。
- `Division` 玩家可见语义 -> task force / battle group / formation / 合成营 / 旅战斗队。
- `tank/motorizedInfantry/infantry/artillery` -> armor、mechanizedInfantry、lightInfantry、artillery、rocketArtillery、airDefense、engineer、recon、uav、loiteringMunition、specialForces、logistics、ew。
- `manpower/industry/supplies` 玩家可见语义 -> personnel、materiel、fuel、ammo、spares、command bandwidth。
- 阿登、Germany、Allies、Bastogne、Panzer、Guderian、Montgomery 等默认数据和 UI 文案必须逐步退出玩家可见层。

### 3.3 现代战争玩法优先级

1. 侦察与目标不确定性：unknown / suspected contact / confirmed contact。
2. 无人系统：UAV / loitering munition 作为侦察、目标指示或轻量打击资源。
3. 电子战：干扰、通信压制、传感器降效、无人机失联风险。
4. 精确火力：火力任务必须检查目标质量、ROE、弹药/冷却和风险。
5. 防空与空域风险：空中支援受防空、制空、天气或 EW 影响。
6. 合成营与特战差异：装甲、机械化、步兵、工程、侦察、特战、后勤各有解释。
7. 后勤：fuel、ammo、supply corridor、resupply convoy。
8. 命令摩擦：AI 指令可被拒绝、延迟、降级或部分执行，并记录原因。

## 4. 现代战争设计合同

现代化后仍保持：

```text
HexTile.controller + Unit.coord
  -> region / objective / sensor / supply / front / deploy 聚合
  -> AI 读取摘要
  -> directive / command
  -> RuleEngine 校验执行
```

可分阶段新增的状态：

- `OperationalAwarenessState`：contact tracks、sensor coverage。
- `FireSupportState`：fire missions、cooldown、ammo budget、no-fire zone。
- `AirTaskingState`：air superiority、air defense threat、sorties。
- `ElectronicWarfareState`：jamming zones、comms degraded zones、drone risk。
- `LogisticsNetworkState`：supply routes、fuel/ammo status、convoy plans。

新增状态必须 Codable / Equatable，有旧存档 fallback，由 manager 或规则层刷新，不由 UI 直接写。

现代命令方向：

- `recon`
- `fireMission`
- `assignUAV`
- `jam`
- `airSupport`
- `deployCounterDrone`
- `resupplyConvoy`
- `evacuate`

新增命令必须先有 validator 和 executor，不能只写 UI 或 Agent JSON。

## 5. v6.0-v6.10 版本路线

| 版本 | 主题 | 关键交付 |
|---|---|---|
| v6.0 | 迁移审计、兼容合同和现代战争产品定义 | 二战硬编码审计、现代战争词汇表、首发剧本定义、风险清单、并发分工 |
| v6.1 | 作战方、多方敌我、ROE 和通用回合阶段 | `blueForce/redForce/neutral` 或 `PowerId` 桥接、弃用 `Faction.opponent`、ROE helper、中立不 fallback 到 allies |
| v6.2 | 首发现代剧本、数据资源和地图编辑器迁移 | `grey_tide_2030` 剧本、现代 region/unit/terrain/commander JSON、MapEditor 术语迁移、默认新局入口 |
| v6.3 | 现代部队、装备、移动、战斗和后勤基础 | 现代 unit components、地形/战斗/移动修正、fuel/ammo/supply 基础、现代 tactic 显示 |
| v6.4 | ISR、战争迷雾、ContactTrack 和电子战基础 | `OperationalAwarenessState`、ContactTrack、sensor coverage、EW effects、AI 可见性隔离 |
| v6.5 | 精确火力、空地协同、无人系统和防空抽象 | FireSupportState、FireMission、UAV recon、SEAD / suppress air defense、air tasking 抽象 |
| v6.6 | 现代 AI Agent 指挥链和并发协作 | National / Joint / ISR / Fires / Air / EW / Logistics / Brigade Agent 分层，JSON directive 和 fallback |
| v6.7 | 玩家现代指挥 UI、任务计划和人机协同 | Recon、UAV、Fire Mission、Assault、Hold、Resupply、Jam、Air Support 等任务 UI 和计划线 |
| v6.8 | 发布级现代 C2 UI、美术和交互收口 | 现代态势图视觉、单位/contact/sensor/fire/EW/logistics 图层、设计 token、移动端/macOS 布局 |
| v6.9 | 新手引导、存档、设置、试玩闭环 | 新局、继续、设置、短提示、AI 回放、错误恢复、完整短战役试玩路径 |
| v6.10 | 发布候选和发布前验收 | 发布候选文档、残留扫描、资源检查、人工授权重验证清单、玩家可见二战残留清零 |

## 6. 每阶段文档落点

后续每个版本完成后至少更新：

- `update_log.md`：版本号、完成日期、核心变更、关键文件、轻量检查、云端 run、未跑重测试和遗留风险。
- `md/flow/flow.md`：当前真实核心逻辑，不写未实现行为。
- `md/flow/flowchart.md`：数据加载、动态战区、AI 指令、ISR/EW/火力链路图。
- `README.md`：当前项目定位、玩法、AI 管线、检查规则。
- `md/prompt/v6.0-现代战争迁移/`：阶段提示词、实现记录、审计清单、验收记录。
- `md/test/test.md`：只有检查规范变化时更新。

## 7. 推荐并发 Agent 分工

- Audit / Docs Agent：扫描二战硬编码、迁移词汇表、风险清单、flow/update_log。
- Architecture / API Agent：设计作战方、ROE、contact、sensor、fire、EW、air tasking、logistics 合同。
- Data / Scenario Agent：现代剧本 JSON、unit templates、commanders、terrain rules。
- Rules Agent：多方敌我、现代命令、侦察、火力、EW、后勤规则。
- AI Agent：现代多层指挥官、JSON directive、deterministic fallback。
- UI / SpriteKit Agent：现代 C2 UI、图层、计划线、战报和 AI 复盘。
- MapEditor Agent：现代地图编辑术语、节点、作战区、单位和导出兼容。
- Project / Assets Agent：project 文件、资源引用、asset catalog。
- Reviewer / Integration Agent：文件冲突、API 分叉、JSON schema、project 冲突、文档口径。

主 Agent 必须先分配文件边界；`WWIIHexV0.xcodeproj/project.pbxproj` 只能由一个指定 Agent 修改。

## 8. 发布级验收清单

发布候选前必须确认：

- 默认场景是现代战争剧本，不是阿登。
- 主 UI 第一屏是可操作战场，不是说明页。
- 玩家可选择作战方或至少明确扮演方。
- AI 通过结构化 directive 行动，失败有 fallback。
- 玩家和 AI 都经 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine`。
- `HexTile.controller` 和 `Unit.coord` 仍是战术权威。
- `regionToTheater` 仍是初始/基础映射；`hexToTheater` 和 `hexToFrontZone` 仍是动态权威。
- 侦察、contact、EW、火力、防空、补给至少有一个可解释首版闭环。
- AI 面板能展示 raw JSON、编译后 directive、命令结果、拒绝原因。
- 战报能解释侦察、contact、火力、EW、补给、占领、撤退、命令失败。
- UI 没有主要二战文案残留。
- 新 JSON 都通过 `jq empty`。
- project 文件如改动通过 `plutil -lint`。
- 云端 CI 结果包可被 Agent C 下载并核对。

## 9. 轻量检查边界

本大纲更新属于文档改动，默认只做本地轻量检查。后续源码迁移按 `md/test/test.md` 执行：

- 文档尾随空白检查。
- 冲突标记扫描。
- JSON 改动跑 `jq empty`。
- project 文件改动跑 `plutil -lint`。
- 少量纯 Swift 改动可尝试单文件 `swiftc -parse`。
- 未经人工授权，不在本机跑 Xcode / XCTest / 模拟器 / Probe / Smoke / Stage Regression / Full / 性能测试。

## 10. 主要风险

- `Faction` 二元模型是最大迁移风险，不能一轮内无合同强改全项目。
- `Faction.opponent` 残留会破坏多方、中立和 ROE。
- `GamePhase.germanAI/alliedPlayer` 残留会导致新作战方控制权错误。
- `RegionDataSet.toRegions()` 中 nil owner/controller fallback 到 `.allies` 必须修或隔离。
- `DataLoader` 默认资源、fallback components、validation 仍硬编码阿登和 Guderian。
- `project.pbxproj` 已多次被多分支修改，只能单点处理。
- Contact / fog-of-war 若实现不严谨，AI 可能读取真实敌军状态。
- 火力 / 空中 / EW 任务若直接改状态，会绕过命令权威。
- 现代战争题材容易膨胀，首版必须控制在虚构局部行动闭环内。
