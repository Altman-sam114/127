# 阶段 3：v0 工程架构

本文定义 iOS v0 测试板的工程架构。目标是让后续实现 agent 可以直接按模块落地：规则逻辑与 UI 分离，LLM 接口可替换，MockAI 可独立跑通，所有命令先校验再执行，每回合可查看日志并支持重放。

## 1. 架构原则

- 平台：iOS。
- 技术栈：Swift + SwiftUI + SpriteKit。
- UI 不直接修改游戏状态，只提交 `Command`。
- `RuleEngine` 是唯一允许改变 `GameState` 的规则入口。
- `GeneralAgent` 只能读取 `AgentContext` 并输出结构化命令。
- `LLMClient` 通过协议抽象；无 LLM 时使用 `MockAIClient`。
- 日志采用事件流设计，每条命令、校验结果、状态变更都写入 `GameEvent`。
- 数据文件优先 JSON，v0 不引入数据库。

## 2. 推荐工程目录

```text
ArdennesV0/
  App/
    ArdennesV0App.swift
    AppContainer.swift

  Core/
    GameState.swift
    MapState.swift
    HexCoord.swift
    Terrain.swift
    Division.swift
    Faction.swift
    Visibility.swift
    GameEvent.swift
    VictoryState.swift

  Rules/
    RuleEngine.swift
    MovementRules.swift
    CombatRules.swift
    SupplyRules.swift
    VisibilityRules.swift
    VictoryRules.swift
    CommandValidator.swift
    CommandExecutor.swift

  Commands/
    Command.swift
    CommandResult.swift
    CommandValidation.swift

  Agents/
    GeneralAgent.swift
    AgentContext.swift
    AgentDecision.swift
    DecisionProvider.swift
    MockAIClient.swift
    LLMClient.swift

  Turn/
    TurnManager.swift
    ReplayManager.swift

  UI/
    RootGameView.swift
    HUDView.swift
    UnitInspectorView.swift
    CommandPanelView.swift
    AgentPanelView.swift
    EventLogView.swift

  SpriteKit/
    BoardScene.swift
    HexNode.swift
    UnitNode.swift
    BoardSceneAdapter.swift

  Data/
    DataLoader.swift
    ScenarioDefinition.swift
    ardennes_v0_scenario.json
    terrain_rules.json
    unit_templates.json
    general_agents.json

  Tests/
    HexCoordTests.swift
    MovementRulesTests.swift
    CombatRulesTests.swift
    SupplyRulesTests.swift
    CommandValidationTests.swift
    MockAITests.swift
```

## 3. 模块划分

### App

负责应用启动和依赖装配。

职责：
- 创建初始 `GameState`。
- 注入 `RuleEngine`、`TurnManager`、`DecisionProvider`。
- 选择使用 `MockAIClient` 或未来的真实 `LLMClient`。

### Core

纯数据模型层，不依赖 SwiftUI、SpriteKit、网络或本地 LLM。

职责：
- 定义地图、单位、阵营、坐标、可见性、日志、胜利状态。
- 保证所有模型尽量 `Codable`，方便 JSON 加载和日志重放。

### Rules

核心规则层。

职责：
- 移动范围计算。
- 攻击、反击、射程、侧翼、绕后。
- 战争迷雾与视野。
- 补给线与包围。
- 命令校验。
- 命令执行。
- 胜负判定。

约束：
- 不依赖 UI。
- 不调用 LLM。
- 不读取用户输入。

### Commands

定义玩家和 AI 都使用的统一命令结构。

职责：
- 表示移动、攻击、防守、补给、结束回合等意图。
- 表示校验结果和执行结果。
- 让 AI JSON 和玩家 UI 最终进入同一条规则管线。

### Agents

将领 agent 与 LLM 抽象层。

职责：
- 从 `GameState` 构造 `AgentContext`。
- 通过 `DecisionProvider` 获取结构化决策。
- 将 AI 决策转换为 `Command`。
- 保存原始 JSON、解析结果和失败原因。

### Turn

回合流程协调层。

职责：
- 控制德军 AI 回合、盟军玩家回合、结算阶段。
- 调用 AI。
- 调用规则系统执行命令。
- 每回合追加日志快照。
- 支持回放。

### UI

SwiftUI 界面层。

职责：
- 显示状态。
- 接收用户点击。
- 调用 `TurnManager` 或发送 `CommandIntent`。
- 不直接修改 `GameState`。

### SpriteKit

地图渲染和点击命中层。

职责：
- 绘制六角格、单位、城市、道路、河流、战争迷雾。
- 处理点击坐标转换。
- 把点击事件回传给 SwiftUI/状态层。
- 不直接执行规则。

### Data

JSON 数据加载层。

职责：
- 加载战役、地图、单位模板、将领配置。
- 校验 JSON 基础结构。
- 输出可被 `GameState` 使用的初始状态。

## 4. 核心类型

### GameState

`GameState` 是整局游戏的唯一权威状态。

```swift
struct GameState: Codable, Equatable {
    var scenarioId: String
    var turn: Int
    var maxTurns: Int
    var activeFaction: Faction
    var phase: GamePhase
    var map: MapState
    var divisions: [Division]
    var agents: [GeneralAgent]
    var visibility: [Faction: VisibilityMap]
    var eventLog: [GameEvent]
    var commandHistory: [CommandRecord]
    var victoryState: VictoryState?
}
```

规则：
- `divisions` 中只保存仍在地图上的单位。
- 被消灭单位通过 `GameEvent` 记录，不保留在活跃单位列表。
- `visibility` 每次结算阶段刷新。
- `commandHistory` 用于重放和调试。

### MapState

```swift
struct MapState: Codable, Equatable {
    var width: Int
    var height: Int
    var tiles: [HexCoord: HexTile]
    var supplySources: [SupplySource]
    var objectives: [Objective]
}
```

```swift
struct HexTile: Codable, Equatable {
    let coord: HexCoord
    var baseTerrain: BaseTerrain
    var hasRoad: Bool
    var riverEdges: Set<HexDirection>
    var controller: Faction
    var cityName: String?
    var fortressName: String?
    var isPassable: Bool
}
```

```swift
struct HexCoord: Codable, Hashable, Equatable {
    let q: Int
    let r: Int
}
```

```swift
enum BaseTerrain: String, Codable {
    case plain
    case forest
    case mountain
    case city
    case fortress
}
```

```swift
enum HexDirection: String, Codable, CaseIterable {
    case east
    case northEast
    case northWest
    case west
    case southWest
    case southEast
}
```

说明：
- 道路是覆盖层：`hasRoad`。
- 河流是边属性：`riverEdges`。
- 城市和要塞作为地形，也可通过 `cityName`、`fortressName` 提供显示名称。

### Unit / Division

v0 中地图上的单位统一称为 `Division`。一个师可以由多个兵种权重组成。

```swift
struct Division: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var faction: Faction
    var coord: HexCoord
    var facing: HexDirection
    var hp: Int
    var maxHP: Int
    var organization: Int
    var components: [DivisionComponent]
    var supplyState: SupplyState
    var hasActed: Bool
    var statusEffects: [UnitStatusEffect]
}
```

```swift
struct DivisionComponent: Codable, Equatable {
    let type: UnitComponentType
    let weight: Double
}
```

```swift
enum UnitComponentType: String, Codable {
    case tank
    case motorizedInfantry
    case infantry
    case artillery
}
```

```swift
struct EffectiveStats: Codable, Equatable {
    var attack: Int
    var defense: Int
    var movement: Int
    var range: Int
    var vision: Int
}
```

派生属性由规则层计算，不直接持久化：

```swift
extension Division {
    func effectiveStats(using rules: UnitRuleSet) -> EffectiveStats
}
```

### Faction

```swift
enum Faction: String, Codable, CaseIterable {
    case germany
    case allies
    case neutral
}
```

### Visibility

```swift
enum VisibilityState: String, Codable {
    case unseen
    case explored
    case visible
}
```

```swift
struct VisibilityMap: Codable, Equatable {
    var tiles: [HexCoord: VisibilityState]
    var lastKnownEnemyDivisions: [String: LastKnownDivision]
}
```

```swift
struct LastKnownDivision: Codable, Equatable {
    let id: String
    let faction: Faction
    let coord: HexCoord
    let observedTurn: Int
    let estimatedType: String
}
```

## 5. GeneralAgent

`GeneralAgent` 表示将领本体，不直接调用模型。实际决策由 `DecisionProvider` 提供。

```swift
struct GeneralAgent: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var faction: Faction
    var role: GeneralRole
    var personalityPrompt: String
    var commandStyle: CommandStyle
    var assignedDivisionIds: [String]
    var lastDecisionJSON: String?
    var lastDecisionSummary: String?
}
```

```swift
enum GeneralRole: String, Codable {
    case armyCommander
}
```

```swift
enum CommandStyle: String, Codable {
    case breakthrough
    case defensive
    case balanced
}
```

v0 默认只有：

```text
id: guderian
name: Heinz Guderian
faction: germany
style: breakthrough
```

## 6. Command

玩家与 AI 都必须通过 `Command` 影响游戏状态。

```swift
enum Command: Codable, Equatable {
    case move(MoveCommand)
    case attack(AttackCommand)
    case hold(HoldCommand)
    case resupply(ResupplyCommand)
    case endTurn(EndTurnCommand)
}
```

```swift
struct MoveCommand: Codable, Equatable {
    let id: String
    let issuedBy: CommandIssuer
    let faction: Faction
    let divisionId: String
    let from: HexCoord
    let to: HexCoord
    let reason: String?
}
```

```swift
struct AttackCommand: Codable, Equatable {
    let id: String
    let issuedBy: CommandIssuer
    let faction: Faction
    let attackerId: String
    let defenderId: String
    let stance: AttackStance
    let reason: String?
}
```

```swift
struct HoldCommand: Codable, Equatable {
    let id: String
    let issuedBy: CommandIssuer
    let faction: Faction
    let divisionId: String
    let reason: String?
}
```

```swift
struct ResupplyCommand: Codable, Equatable {
    let id: String
    let issuedBy: CommandIssuer
    let faction: Faction
    let divisionId: String
    let reason: String?
}
```

```swift
struct EndTurnCommand: Codable, Equatable {
    let id: String
    let issuedBy: CommandIssuer
    let faction: Faction
}
```

```swift
enum CommandIssuer: Codable, Equatable {
    case player
    case agent(agentId: String)
    case system
}
```

```swift
enum AttackStance: String, Codable {
    case normal
    case cautious
    case aggressive
}
```

### CommandValidation

```swift
struct CommandValidation: Codable, Equatable {
    let commandId: String
    let isValid: Bool
    let errors: [CommandValidationError]
    let warnings: [String]
}
```

```swift
enum CommandValidationError: String, Codable {
    case wrongPhase
    case wrongFaction
    case divisionNotFound
    case targetNotFound
    case alreadyActed
    case destinationOutOfBounds
    case destinationOccupied
    case noPath
    case insufficientMovement
    case targetOutOfRange
    case targetNotVisible
    case invalidTargetFaction
    case commandSchemaInvalid
}
```

### CommandResult

```swift
struct CommandResult: Codable, Equatable {
    let commandId: String
    let validation: CommandValidation
    let appliedEvents: [GameEvent]
}
```

### CommandRecord

用于重放。

```swift
struct CommandRecord: Codable, Identifiable, Equatable {
    let id: String
    let turn: Int
    let phase: GamePhase
    let command: Command
    let validation: CommandValidation
    let resultEventIds: [String]
}
```

## 7. RuleEngine

`RuleEngine` 是规则系统门面。外部不直接调用子规则修改状态。

```swift
protocol RuleEngine {
    func validate(_ command: Command, in state: GameState) -> CommandValidation
    func execute(_ command: Command, in state: inout GameState) -> CommandResult
    func legalCommands(for divisionId: String, in state: GameState) -> [Command]
    func endPhase(in state: inout GameState) -> [GameEvent]
}
```

推荐实现：

```swift
final class DefaultRuleEngine: RuleEngine {
    private let movementRules: MovementRules
    private let combatRules: CombatRules
    private let supplyRules: SupplyRules
    private let visibilityRules: VisibilityRules
    private let victoryRules: VictoryRules
    private let validator: CommandValidator
    private let executor: CommandExecutor
}
```

执行约束：

```swift
func execute(_ command: Command, in state: inout GameState) -> CommandResult {
    let validation = validate(command, in: state)

    guard validation.isValid else {
        let event = GameEvent.commandRejected(commandId: command.id, errors: validation.errors)
        state.eventLog.append(event)
        state.commandHistory.append(CommandRecord(...))
        return CommandResult(commandId: command.id, validation: validation, appliedEvents: [event])
    }

    let events = executor.apply(command, to: &state)
    state.eventLog.append(contentsOf: events)
    state.commandHistory.append(CommandRecord(...))
    return CommandResult(commandId: command.id, validation: validation, appliedEvents: events)
}
```

### 子规则职责

`MovementRules`：
- 六角格寻路。
- 地形移动消耗。
- 道路和跨河消耗。
- 敌方控制区停步。

`CombatRules`：
- 攻击范围。
- 伤害计算。
- 反击。
- 侧翼/绕后。
- 地形防御修正。

`SupplyRules`：
- 补给源连通。
- 低补给。
- 包围。
- 包围损耗。

`VisibilityRules`：
- 战争迷雾。
- 部队视野。
- 可见敌军。
- 最后已知敌军位置。

`VictoryRules`：
- 回合上限。
- Bastogne 控制权。
- 消灭单位数量。
- 德军突破或盟军守住目标。

## 8. LLMClient 与 MockAI

### DecisionProvider

将领决策统一接口。

```swift
protocol DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope
}
```

### LLMClient

真实 LLM 的底层接口，v0 只定义，不强制启用。

```swift
protocol LLMClient {
    func completeJSON(request: LLMRequest) async throws -> String
}
```

```swift
struct LLMRequest: Codable, Equatable {
    let systemPrompt: String
    let userPrompt: String
    let schemaName: String
    let schemaVersion: Int
    let temperature: Double
}
```

未来实现：

```swift
final class LocalHTTPLLMClient: LLMClient {
    func completeJSON(request: LLMRequest) async throws -> String {
        // Calls local Ollama / LM Studio server from simulator.
    }
}
```

### MockAIClient

v0 默认使用。

```swift
final class MockAIClient: DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope {
        // Deterministic rules:
        // 1. Artillery attacks visible defender in city/fortress if in range.
        // 2. Tank moves toward Bastogne using roads.
        // 3. Low supply divisions resupply or retreat.
        // 4. Infantry follows and attacks adjacent weak enemies.
    }
}
```

### AgentContext

```swift
struct AgentContext: Codable, Equatable {
    let agentId: String
    let faction: Faction
    let turn: Int
    let phase: GamePhase
    let personalityPrompt: String
    let visibleTiles: [HexTile]
    let visibleEnemyDivisions: [Division]
    let friendlyDivisions: [Division]
    let objectives: [Objective]
    let recentEvents: [GameEvent]
    let playerDirective: String?
}
```

### AgentDecisionEnvelope

```swift
struct AgentDecisionEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let agentId: String
    let turn: Int
    let intent: String
    let orders: [AgentOrder]
}
```

```swift
struct AgentOrder: Codable, Equatable {
    let type: AgentOrderType
    let divisionId: String
    let to: HexCoord?
    let targetDivisionId: String?
    let stance: AttackStance?
    let reason: String
}
```

```swift
enum AgentOrderType: String, Codable {
    case move
    case attack
    case hold
    case resupply
}
```

Agent order 转换为 Command：

```swift
func command(from order: AgentOrder, agent: GeneralAgent, state: GameState) throws -> Command
```

转换失败也必须写入日志，不得崩溃。

## 9. TurnManager

`TurnManager` 是回合流程协调器，不直接实现规则细节。

```swift
@MainActor
final class TurnManager: ObservableObject {
    @Published private(set) var state: GameState

    private let ruleEngine: RuleEngine
    private let decisionProvider: DecisionProvider

    func submitPlayerCommand(_ command: Command)
    func stepGermanAI() async
    func endAlliedTurn()
    func advancePhase()
    func replay(commands: [CommandRecord]) -> GameState
}
```

### 回合阶段

```swift
enum GamePhase: String, Codable {
    case germanAI
    case alliedPlayer
    case resolution
    case finished
}
```

### 标准流程

```swift
func stepGermanAI() async {
    guard state.phase == .germanAI else { return }

    let context = AgentContextBuilder.make(agentId: "guderian", state: state)
    let decision = try await decisionProvider.decide(context: context)

    logRawAIDecision(decision)

    for order in decision.orders {
        do {
            let command = try CommandFactory.make(order: order, state: state)
            _ = ruleEngine.execute(command, in: &state)
        } catch {
            state.eventLog.append(.agentOrderRejected(order: order, reason: "\(error)"))
        }
    }

    advancePhase()
}
```

```swift
func endAlliedTurn() {
    guard state.phase == .alliedPlayer else { return }
    let command = Command.endTurn(...)
    _ = ruleEngine.execute(command, in: &state)
    advancePhase()
}
```

```swift
func advancePhase() {
    switch state.phase {
    case .germanAI:
        state.phase = .alliedPlayer
        resetActions(for: .allies)

    case .alliedPlayer:
        state.phase = .resolution
        _ = ruleEngine.endPhase(in: &state)
        state.turn += 1
        state.phase = .germanAI
        resetActions(for: .germany)

    case .resolution:
        state.phase = .germanAI

    case .finished:
        break
    }
}
```

## 10. 每回合日志与重放

### GameEvent

```swift
enum GameEvent: Codable, Identifiable, Equatable {
    case commandAccepted(GameEventCommandAccepted)
    case commandRejected(GameEventCommandRejected)
    case divisionMoved(GameEventDivisionMoved)
    case divisionAttacked(GameEventDivisionAttacked)
    case counterAttack(GameEventCounterAttack)
    case divisionDestroyed(GameEventDivisionDestroyed)
    case tileCaptured(GameEventTileCaptured)
    case supplyChanged(GameEventSupplyChanged)
    case visibilityUpdated(GameEventVisibilityUpdated)
    case agentDecision(GameEventAgentDecision)
    case phaseChanged(GameEventPhaseChanged)
    case victoryAchieved(GameEventVictoryAchieved)
}
```

事件要求：
- 每个事件必须包含 `id`、`turn`、`phase`、`timestamp`。
- UI 展示事件日志。
- 回放优先使用 `commandHistory` 从初始状态重算。
- 调试时可使用 `eventLog` 查看每一步结果。

### ReplayManager

```swift
final class ReplayManager {
    func replay(initialState: GameState, records: [CommandRecord], engine: RuleEngine) -> GameState {
        var state = initialState
        for record in records {
            _ = engine.execute(record.command, in: &state)
        }
        return state
    }
}
```

要求：
- v0 使用确定性规则，不引入随机数。
- 如果未来引入随机数，必须记录 `rngSeed` 和每次随机结果。

## 11. UI 层结构

### RootGameView

主界面容器。

组成：
- `BoardContainerView`
- `HUDView`
- `UnitInspectorView`
- `CommandPanelView`
- `AgentPanelView`
- `EventLogView`

```swift
struct RootGameView: View {
    @StateObject var turnManager: TurnManager

    var body: some View {
        ZStack {
            BoardContainerView(state: turnManager.state)
            VStack {
                HUDView(state: turnManager.state)
                Spacer()
                BottomPanelView(...)
            }
        }
    }
}
```

### BoardContainerView

承载 SpriteKit。

职责：
- 创建 `BoardScene`。
- 接收选中格、选中单位事件。
- 把玩家意图转换为候选 command。

```swift
struct BoardContainerView: View {
    let state: GameState
    let onTileTapped: (HexCoord) -> Void
    let onDivisionTapped: (String) -> Void
}
```

### BoardScene

SpriteKit 渲染层。

职责：
- 绘制 hex。
- 绘制道路、河流、城市、要塞。
- 绘制单位。
- 绘制战争迷雾。
- 绘制移动范围和攻击范围。
- 做点击命中测试。

```swift
final class BoardScene: SKScene {
    var adapter: BoardSceneAdapter?

    func render(state: GameState, selectedDivisionId: String?)
    func highlightReachableTiles(_ coords: Set<HexCoord>)
    func clearHighlights()
}
```

### BoardSceneAdapter

隔离 SpriteKit 与 SwiftUI 状态。

```swift
protocol BoardSceneAdapter: AnyObject {
    func boardScene(_ scene: BoardScene, didTapTile coord: HexCoord)
    func boardScene(_ scene: BoardScene, didTapDivision id: String)
}
```

### HUDView

显示：
- 回合数。
- 当前阶段。
- 当前阵营。
- 胜利目标摘要。

### UnitInspectorView

显示：
- 单位名称。
- 阵营。
- hp。
- 组织度。
- 混编权重。
- 攻击、防御、移动、射程、视野。
- 补给状态。
- 当前地形。

### CommandPanelView

显示：
- Move。
- Attack。
- Hold。
- Resupply。
- End Turn。
- Step German AI。

按钮规则：
- 根据 `RuleEngine.legalCommands` 启用或禁用。
- 禁用状态显示原因。

### AgentPanelView

显示：
- 将领名称。
- personality prompt 摘要。
- 当前 intent。
- 原始 JSON。
- 每条 order 的校验结果。

### EventLogView

显示：
- 命令接受/拒绝。
- 移动。
- 攻击。
- 反击。
- 占领。
- 补给变化。
- 胜利结果。

## 12. 数据文件格式

数据文件统一放在 `Data/`，使用 JSON。

### ardennes_v0_scenario.json

```json
{
  "scenarioId": "ardennes_v0",
  "name": "Ardennes Test Battlefield",
  "maxTurns": 8,
  "map": {
    "width": 11,
    "height": 9,
    "tiles": [
      {
        "q": 0,
        "r": 0,
        "baseTerrain": "plain",
        "hasRoad": false,
        "riverEdges": [],
        "controller": "neutral",
        "cityName": null,
        "fortressName": null,
        "isPassable": true
      },
      {
        "q": 4,
        "r": 4,
        "baseTerrain": "city",
        "hasRoad": true,
        "riverEdges": ["east"],
        "controller": "allies",
        "cityName": "Bastogne",
        "fortressName": null,
        "isPassable": true
      }
    ],
    "supplySources": [
      {
        "id": "german_supply_east",
        "faction": "germany",
        "q": 10,
        "r": 4
      },
      {
        "id": "allied_supply_west",
        "faction": "allies",
        "q": 0,
        "r": 4
      }
    ],
    "objectives": [
      {
        "id": "bastogne",
        "name": "Bastogne",
        "q": 4,
        "r": 4,
        "victoryValue": 5
      }
    ]
  },
  "initialDivisions": [
    {
      "id": "de_panzer_1",
      "name": "1st Panzer Division",
      "faction": "germany",
      "q": 9,
      "r": 4,
      "facing": "west",
      "hp": 10,
      "maxHP": 10,
      "organization": 10,
      "components": [
        { "type": "tank", "weight": 0.55 },
        { "type": "motorizedInfantry", "weight": 0.25 },
        { "type": "infantry", "weight": 0.05 },
        { "type": "artillery", "weight": 0.15 }
      ]
    }
  ],
  "agents": [
    {
      "id": "guderian",
      "name": "Heinz Guderian",
      "faction": "germany",
      "role": "armyCommander",
      "commandStyle": "breakthrough",
      "assignedDivisionIds": ["de_panzer_1"],
      "personalityPrompt": "Aggressive armored breakthrough commander. Prefer roads, concentration of force, and capture of Bastogne."
    }
  ]
}
```

### terrain_rules.json

```json
{
  "terrain": {
    "plain": {
      "moveCost": 1,
      "defenseBonus": 0
    },
    "forest": {
      "moveCost": 2,
      "defenseBonus": 2
    },
    "mountain": {
      "moveCost": 3,
      "defenseBonus": 3
    },
    "city": {
      "moveCost": 1,
      "defenseBonus": 2
    },
    "fortress": {
      "moveCost": 2,
      "defenseBonus": 4
    }
  },
  "roadMoveCost": 1,
  "crossRiverMovePenalty": 2,
  "riverDefenseBonus": 2
}
```

### unit_templates.json

```json
{
  "components": {
    "tank": {
      "attack": 8,
      "defense": 5,
      "movement": 5,
      "range": 1,
      "vision": 2
    },
    "motorizedInfantry": {
      "attack": 5,
      "defense": 4,
      "movement": 5,
      "range": 1,
      "vision": 3
    },
    "infantry": {
      "attack": 4,
      "defense": 5,
      "movement": 3,
      "range": 1,
      "vision": 2
    },
    "artillery": {
      "attack": 7,
      "defense": 2,
      "movement": 2,
      "range": 2,
      "vision": 2
    }
  },
  "supplyPenalties": {
    "supplied": {
      "movementDelta": 0,
      "attackMultiplier": 1.0,
      "defenseDelta": 0,
      "attritionPerTurn": 0
    },
    "lowSupply": {
      "movementDelta": -1,
      "attackMultiplier": 0.75,
      "defenseDelta": -1,
      "attritionPerTurn": 0
    },
    "encircled": {
      "movementDelta": -2,
      "attackMultiplier": 0.5,
      "defenseDelta": -2,
      "attritionPerTurn": 1
    }
  }
}
```

### general_agents.json

```json
{
  "agents": [
    {
      "id": "guderian",
      "name": "Heinz Guderian",
      "faction": "germany",
      "role": "armyCommander",
      "commandStyle": "breakthrough",
      "personalityPrompt": "Aggressive armored breakthrough commander. Prefer rapid movement on roads, concentrated attacks, and decisive capture of Bastogne.",
      "decisionProvider": "mock"
    }
  ]
}
```

## 13. AI JSON 命令格式

AI 输出必须先解析为 `AgentDecisionEnvelope`，再转换成 `Command`。

```json
{
  "schemaVersion": 1,
  "agentId": "guderian",
  "turn": 1,
  "intent": "breakthrough_to_bastogne",
  "orders": [
    {
      "type": "move",
      "divisionId": "de_panzer_1",
      "to": { "q": 7, "r": 4 },
      "targetDivisionId": null,
      "stance": null,
      "reason": "Advance along the main road toward Bastogne."
    },
    {
      "type": "attack",
      "divisionId": "de_artillery_1",
      "to": null,
      "targetDivisionId": "al_infantry_1",
      "stance": "normal",
      "reason": "Suppress the visible defender before armor advances."
    }
  ]
}
```

处理规则：
- JSON 解析失败：记录 `agentDecisionParseFailed`。
- schemaVersion 不支持：拒绝全部命令。
- 单条 order 转 command 失败：只拒绝该 order。
- 命令校验失败：写入 `commandRejected`。
- 命令执行成功：写入具体事件。

## 14. 后续系统接口位置

v0 不实现以下系统，但保留协议位置：

```swift
protocol FutureRuleSystem {
    var isEnabled: Bool { get }
    func prepareTurn(state: inout GameState)
    func resolvePhase(state: inout GameState) -> [GameEvent]
}
```

预留系统：

```swift
final class AirSystemPlaceholder: FutureRuleSystem { ... }
final class NavySystemPlaceholder: FutureRuleSystem { ... }
final class WeatherSystemPlaceholder: FutureRuleSystem { ... }
final class TechSystemPlaceholder: FutureRuleSystem { ... }
final class EconomySystemPlaceholder: FutureRuleSystem { ... }
final class DiplomacySystemPlaceholder: FutureRuleSystem { ... }
```

要求：
- v0 默认 `isEnabled == false`。
- 不参与结算。
- 不污染当前规则代码。

## 15. 最小实现顺序

1. 实现 `Core` 数据结构。
2. 实现 JSON 加载，能生成初始 `GameState`。
3. 实现 hex 坐标、距离、邻居。
4. 实现 `MovementRules` 和移动命令校验。
5. 实现 `CombatRules` 和攻击命令校验。
6. 实现 `SupplyRules`、包围和低补给惩罚。
7. 实现 `VisibilityRules` 和战争迷雾。
8. 实现 `RuleEngine.execute`，保证所有命令先校验。
9. 实现 `TurnManager`。
10. 实现 `MockAIClient`。
11. 实现 `BoardScene` 地图显示。
12. 实现 SwiftUI 面板与日志。
13. 实现重放测试。

## 16. 最小验收标准

- 能加载 `ardennes_v0_scenario.json`。
- 能显示六角格地图、城市、道路、河流、单位、战争迷雾。
- 玩家能选择盟军单位并移动/攻击。
- 德军 `guderian` MockAI 能输出结构化决策并执行。
- 所有命令必须经过 `RuleEngine.validate`。
- 非法命令不改变游戏状态，并写入日志。
- 每回合日志可查看。
- 从初始状态 + `commandHistory` 可以重放到同一结果。
- 无真实 LLM 时游戏仍可完整跑通。
