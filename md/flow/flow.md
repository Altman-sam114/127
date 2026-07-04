# WWIIHexV0 核心流程文档（v0.5 元帅决策链分支）

> 本文是项目当前核心逻辑的接手文档。目标不是复述历史设计，而是按当前代码真实链路说明：数据如何进入游戏，hex / region / theater / front / deploy 如何派生，主游戏和地图编辑器如何共同维护同一套地图语义，AI / 玩家命令如何落到规则系统。

资料依据：`AGENT.md`、`README.md`、`update_log.md`、`md/test/test.md`、v0.355/v0.36/v0.37 阶段文档、最近 git 记录，以及当前源码中的 `Core/`、`Rules/`、`Commands/`、`Agents/`、`Turn/`、`App/`、`SpriteKit/`、`UI/`、`MapEditor/` 与关键测试。

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
  -> MarshalAgent / TheaterDirective JSON
  -> TheaterDirectiveDecoder
  -> TheaterDirectiveCompiler
  -> ZoneCommanderAgent fallback / 手写 ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> CommandExecutor
  -> StrategicStateSynchronizer
  -> UI overlay / 日志 / WarDirectiveRecord
```

最关键的铁律：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 region 内 hex controller 加权聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区归属，不是运行时推进层。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- `EconomyState` 是 faction 级经济总账；收入来自受控 region、城市、工厂、基础设施和补给值，但战术占领仍以 hex 为准。
- 玩家、AI、后续聊天命令最终都必须经过 `Command` / `ZoneDirective -> WarCommandExecutor -> RuleEngine`，不能直接改 `GameState`。
- v0.5 默认战争 AI 上游是 `MarshalAgent -> TheaterDirective JSON -> TheaterDirectiveDecoder -> TheaterDirectiveCompiler`，下游执行收口到 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- 统治者层只作为后续方向预留；当前 v0.5 主链路不调用 `RulerAgent`，也不写统治者决策记录。

## 0.1 云端协作与验证闭环

本项目的协作制度已升级为 `main` 直推和 GitHub Actions 云端结果包验收。该流程只改变协作和验证骨架，不改变战斗、地图、经济、AI 或 UI 业务语义。

当前默认协作链路：

```text
人工提出目标
  -> Agent A 读取 AGENTS / update_log / flow / test / prompt，写版本化提示词
  -> Agent B 基于最新 origin/main 切到 main 小步实现
  -> Agent B 本机只跑 md/test/test.md 允许的轻量检查
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
- 必含：`ci-artifact-manifest.json`、`ci-failure-summary.md`、`junit.xml`、`xcodebuild.log`、`git-diff-check.log`、`plutil.log`、`xmllint.log`，以及可生成时的 `WWIIHexV0.xcresult`
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
  AI Command / Player Command
  operationalDisplayName
  Armored Task Force / Mechanized Task Force / Logistics Package
  Sector / Baseline / Operational / Contact / Brigade
```

必须注意：

- `Faction.displayName` 现在是现代作战显示名；旧名保存在 `legacyDisplayName`，只作兼容说明或迁移审计使用。
- `GamePhase.displayName` 现在是通用回合显示名；旧名保存在 `legacyDisplayName`。
- `Division.operationalDisplayName` 只替换 UI 显示，不改 `Division.name` 编码字段。
- `Faction.opponent`、`GamePhase.germanAI/alliedPlayer`、旧阿登 fallback JSON 仍是后续迁移风险。
- 当前没有新增 ISR / ContactTrack / EW / FireMission / AirTasking / LogisticsNetwork 状态。

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

- `SupplyRules`
- `RegionSupplyRules`
- `RegionCombatRules`
- `AgentContexts`
- `WarCommandExecutor` 目标排序
- `FrontLineManager` 前线对手推导
- `ZoneCommanderAgent` lost objective 摘要

`RegionDataSet.toRegions()` 已修正历史 fallback：

```text
controller 缺省 -> owner
owner/controller 都缺省 -> neutral
```

经济层初始化已收窄：缺省只回退到旧双阵营 `legacyBelligerents`，bootstrap 时按实际单位阵营加旧双阵营 fallback 建账本，避免 `Faction.allCases` 扩容后让 green / neutral 默认进入旧剧本经济循环。

仍未完成：

- `GamePhase` raw value 尚未重命名，当前只用 helper 把 red 映射到 AI phase、blue 映射到 player phase。
- v6.2 已切入 `grey_tide_2030` 默认剧本种子，但不是最终发布级地图。
- `Faction.opponent` 仍保留为旧接口 fallback。
- FireMission / ISR / EW / restricted fire zone 尚未进入命令系统。

## 0.4 v6.2 灰潮行动默认剧本种子

v6.2 第一批实现把默认新局入口切到现代虚构剧本 `grey_tide_2030`，但它仍是发布前种子，不是最终 100-220 hex 规模地图。

当前新增默认资源：

```text
WWIIHexV0/Data/grey_tide_2030_scenario.json
WWIIHexV0/Data/grey_tide_2030_regions.json
```

规模与内容：

- 60 个 hex，10 个 region / operational zone。
- Blue Force / Red Force / Neutral 三方数据值。
- 关键点：East Airport、Harbor Terminal、Radar Ridge、River Bridge、Industrial Hub、Comms Center、Northern Pass。
- 仍复用旧 `unit_templates.json` 和旧 `ComponentType`，只在默认剧本显示名上使用现代任务编组。

默认启动顺序现在是：

```text
grey_tide_2030_scenario + grey_tide_2030_regions
  -> 失败时回退 ardennes_v0_scenario + ardennes_v02_regions
  -> 再失败时回退 GameState.initial() + 旧 region 叠加
```

MapEditor 默认资源桥也切到 `grey_tide_2030`，导出时默认写 `blueForce` / `redForce` / `neutral`，不再把现代地图导回 `allies/germany`。

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
divisions: [Division]
victoryState
eventLog
warDirectiveRecords
playerCommandState
```

状态含义：

- `map` 保存地图、hex、region、补给源和目标点。
- `divisions` 保存所有单位。单位当前位置在 `Division.coord`，不是 region 或 theater。
- `theaterState` 保存初始战区快照与运行时动态战区。
- `frontLineState` 从动态战区相邻 hex 派生。
- `warDeploymentState` 从动态战区/前线/单位位置派生，供 AI 调度单位。
- `economyState` 保存 manpower、industry、supplies、生产队列、上回合收入/维护费/补员消耗，不直接改变战术占领权。
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
  -> GameAgent.guderian(...)
  -> StrategicStateBootstrapper().bootstrapIfNeeded(...)
  -> TurnManager(... commanderPool: buildCommanderPool(state: bootstrappedState))
  -> AppContainer(...)
```

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
regionBuilder      省份
theaterAssignment  战区
unitPlanner        部队
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
  -> 写回 WWIIHexV0/Data
```

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
- 当前 phase 是 `.alliedPlayer`。
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
- `[ INFO ]` 面板，内含：
  - Formation + Sector + Command
  - Sector
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

appendEvent("Hex q,r reassigned to dynamic theater ...")
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
  germany -> allies, phase alliedPlayer
  allies -> germany, phase germanAI, turn += 1

resetActionsForActiveFaction
StrategicStateBootstrapper.refreshRuntimeState
appendEvent("Turn advanced ...")
```

---

## 6. AI / 战争指令流程

### 6.1 v0.5 默认元帅决策链

源码：`WWIIHexV0/Turn/TurnManager.swift`、`WWIIHexV0/Agents/ZoneCommanderAgent.swift`、`WWIIHexV0/Commands/WarDirective.swift`、`WWIIHexV0/Commands/WarCommandExecutor.swift`

v0.5 分支默认路径：

```text
AppContainer.runAIIfNeeded
  -> runAISequence
  -> TurnManager.runAITurn(... pipelineMode: .marshalDirective)
  -> MarshalAgent.resolve
  -> MarshalBattlefieldSummarizer.summary
  -> SimulatedMarshalLLMClient.completeTheaterDirectiveJSON
  -> TheaterDirectiveDecoder.parse
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
germany:
  phase == .germanAI

allies:
  observerModeEnabled && phase == .alliedPlayer
```

`runAISequence`：

- 非 observer mode：最多跑 1 个 AI step。
- observer mode：最多跑 2 个 AI step，因此一次按钮推进可让当前 AI 阵营行动，若回合切到另一个 AI 控制阵营，也继续行动一次。

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
visibleEnemyDivisions
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
- 默认 AI 上游已是 `MarshalAgent -> TheaterDirectiveEnvelope -> TheaterDirectiveDecoder -> TheaterDirectiveCompiler`，下游执行必须是 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- 元帅层不能直接输出底层 `Command`，不能直接修改地图、单位、hex controller 或动态战区权威。
- 统治者层只作为未来方向预留，当前 v0.5 不在主链路调用。
- 当前工作树存在外交/经济/UI 等非 v0.5 方向残留，合并前需要单独审查文件归属和 public API 冲突。
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
  -> AgentPanelView 展示 raw JSON / command results / zone directives
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

- AI 面板从只展示 `AgentDecisionRecord` 扩展为同时展示 `WarDirectiveRecord`，每条 directive 可看到 zone、attack/defend、tactic、命令成功/拒绝数量和目标 region。
- 日志面板用 `LogDisplayEntry` 保存 entry + category，避免 body 内对同一条日志重复分类。
- 单位绘制先缓存 `unitDisplayHex` 再排序，避免 comparator 重复计算。
- `AttackIntensity.infiltration` 在无显式 `maxCommittedUnits` 时默认只投入约半数前线/纵深候选单位，避免渗透/袭扰全线压上。

试玩观察重点：

- UI：HUD、Info tabs、Economy、Diplomacy、AI panel 是否可读。
- 地图：hex/province/initial/dynamic/front/deploy 图层是否清晰。
- AI：raw JSON、zone directive、diagnostics 是否能解释 AI 回合。
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
