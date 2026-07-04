# 阶段 0：v0 测试板最小可玩范围

下面是 v0 测试板的最小可玩范围定义，目标是让后续 agent 可以直接按这个边界做实现，不扩散成完整大战略游戏。

## 1. v0 必须有的系统

### 平台与技术

- iOS App。
- Swift + SwiftUI + SpriteKit。
- SwiftUI 负责面板、按钮、日志、单位详情。
- SpriteKit 负责六角格地图、单位显示、选中、高亮、移动/攻击反馈。

### 测试战役

场景名：**阿登测试战场**

核心设定：

- 德军从东侧进攻。
- 盟军防守西侧和中部城市。
- 地图目标围绕道路、森林、河流、要塞和少量城市展开。
- 玩家控制盟军。
- 德军由 MockAI 将领 agent 控制。

### 六角格地图系统

- 地图规模建议：`11 x 9` 或 `13 x 9`，不要更大。
- 坐标：axial hex 坐标，字段为 `q`, `r`。
- 地形类型：
  - 平原 `plain`
  - 森林 `forest`
  - 山地/丘陵 `hill`
  - 道路 `road`
  - 城市 `city`
  - 河流 `river`
  - 要塞 `fortress`
- 河流建议作为 hex 边属性，而不是单独地块，v0 也可以简化为河流地块。

### 阵营系统

只包含两个阵营：

- 德国 `germany`
- 盟军 `allies`

每个阵营有：

- 控制城市
- 控制补给源
- 单位列表
- 当前胜利进度

### 单位系统

只实现陆军。

单位类型建议：

- 德军：
  - 装甲 `panzer`
  - 机械化步兵 `mechanized`
  - 炮兵 `artillery`
  - 步兵 `infantry`
- 盟军：
  - 步兵 `infantry`
  - 反坦克部队 `antiTank`
  - 炮兵 `artillery`
  - 守备部队 `garrison`

每方 4 个单位以内。v0 不需要兵种树。

### 移动系统

必须支持：

- 点击己方单位。
- 显示可移动范围。
- 点击合法格移动。
- 地形影响移动消耗。
- 道路降低移动消耗。
- 森林、山地、河流增加移动消耗。
- 敌方单位阻挡移动。
- 单格最多一个单位。

### 战斗系统

必须支持：

- 相邻攻击。
- 炮兵 2 格远程攻击。
- 确定性伤害，便于测试。
- 地形防御修正：
  - 森林提高防御。
  - 山地提高防御。
  - 城市提高防御。
  - 要塞大幅提高防御。
- 单位 hp 降到 0 后移除。
- 攻击后单位本回合不能再次行动。

### 占领系统

必须支持：

- 单位进入城市或要塞后改变控制权。
- 控制权影响胜利条件和补给线。
- 城市显示当前归属。

### 补给系统

v0 要做，但保持简单：

- 每方有 1 个主补给源。
- 单位能通过己方控制或中立可通行格连接补给源，则为 `supplied`。
- 如果无法连接，则为 `unsupplied`。
- 如果无补给且周围可撤退格被敌军控制区压制，则为 `encircled`。
- 无补给效果：
  - 移动力降低。
  - 攻击力降低。
- 包围效果：
  - 额外降低防御或每回合轻微损耗。

### 回合系统

一局采用固定回合数。

流程：

1. 德军 AI 回合。
2. 盟军玩家回合。
3. 回合结束。
4. 重算补给、占领、胜利条件。

建议总回合数：`8`。

### AI Agent 系统

v0 只做一个德军将领 agent：

- agent id：`guderian`
- 阵营：德国
- 类型：MockAI
- 风格：装甲突破、优先道路、优先城市、集中火力

AI 每回合需要：

- 读取当前局势摘要。
- 输出结构化 JSON 命令。
- 由规则系统校验。
- 合法命令执行。
- 非法命令记录失败原因。

### 可观察系统

必须有：

- 当前回合显示。
- 当前阵营显示。
- 选中单位详情。
- 单位 hp、补给状态显示。
- AI 决策 JSON 显示。
- 命令校验日志。
- 战斗结果日志。

## 2. v0 明确不做的系统

v0 不做以下内容，只保留接口位置：

- 空军系统。
- 海军系统。
- 天气系统。
- 科技树。
- 完整经济。
- 生产建造。
- 外交。
- 国家政策。
- 指挥链多级系统。
- 多将领并行 agent。
- 将领忠诚、抗命、政变。
- 战争迷雾。
- 复杂士气。
- 弹药、燃料、维修细分。
- 单位升级和经验系统。
- 真实历史大地图。
- 多战役。
- 存档系统。
- 内购。
- 联机。
- 真实本地 LLM 推理。

需要预留接口：

- `AirSystemPlaceholder`
- `NavySystemPlaceholder`
- `WeatherSystemPlaceholder`
- `TechSystemPlaceholder`
- `EconomySystemPlaceholder`
- `DiplomacySystemPlaceholder`
- `CommanderSystemPlaceholder`
- `LLMDecisionProviderPlaceholder`

这些接口 v0 不实现业务逻辑，只避免后续架构重写。

## 3. 一局测试板的胜利条件

场景：**阿登测试战场**

关键地点：

- 德军补给源：东侧 `German Supply Depot`
- 盟军补给源：西侧 `Allied Supply Depot`
- 主要目标城市：`Bastogne`
- 次要城市：`St. Vith`
- 道路节点：`Houffalize`
- 要塞：`Bastogne Fortress`

### 德军胜利

德军在第 8 回合结束前满足任一条件：

- 占领 `Bastogne` 并保持 1 个完整回合。
- 或占领 `Bastogne` + `St. Vith`。
- 或消灭 3 个盟军单位。

### 盟军胜利

盟军满足任一条件：

- 第 8 回合结束时仍控制 `Bastogne`。
- 或消灭 3 个德军单位。
- 或切断所有德军装甲单位补给并维持 1 个完整回合。

### 平局

第 8 回合结束时：

- 德军未达成突破。
- 盟军未消灭足够德军。
- `Bastogne` 控制权刚发生变化，未保持完整回合。

## 4. 玩家每回合能做什么

v0 中玩家控制盟军。

玩家回合可执行：

- 查看地图。
- 查看所有己方单位。
- 点击单位查看属性。
- 查看单位可移动范围。
- 移动一个未行动单位。
- 攻击合法目标。
- 让单位原地防守。
- 查看补给状态。
- 查看城市控制权。
- 查看 AI 上回合 JSON 决策。
- 查看命令执行日志。
- 点击 `End Turn` 结束回合。

每个单位每回合只能执行一种主要行动：

- 移动
- 攻击
- 防守
- 补给/休整

玩家不能：

- 控制德军。
- 修改 AI 输出。
- 生产新单位。
- 召唤空军或海军。
- 改变天气。
- 建造设施。

## 5. AI 每回合能做什么

v0 中德军 AI 由 `guderian` MockAI 控制。

AI 每回合流程：

1. 读取 `GameState`。
2. 生成 `AgentContext`。
3. 根据局势生成 JSON。
4. 解析 JSON。
5. 校验命令。
6. 执行合法命令。
7. 跳过非法命令。
8. 输出日志。

AI 可执行命令：

```swift
move
attack
hold
resupply
```

AI 决策偏好：

- 装甲单位优先沿道路推进。
- 优先攻击低 hp 盟军单位。
- 优先夺取 `Bastogne`。
- 炮兵优先攻击城市或要塞中的防守单位。
- 无补给单位优先后撤或休整。
- 被包围单位优先尝试脱离包围。
- 如果无法安全推进，则 hold。

AI 不允许：

- 作弊读取隐藏信息。v0 没有战争迷雾，所以等同于读取全局状态。
- 越过规则系统直接改状态。
- 生成单位。
- 修改地图。
- 无视行动次数。
- 攻击超出射程目标。

## 6. 最小数据结构清单

### HexCoord

```swift
struct HexCoord: Codable, Hashable {
    let q: Int
    let r: Int
}
```

### TerrainType

```swift
enum TerrainType: String, Codable {
    case plain
    case forest
    case hill
    case road
    case city
    case river
    case fortress
}
```

### Faction

```swift
enum Faction: String, Codable {
    case germany
    case allies
    case neutral
}
```

### HexTile

```swift
struct HexTile: Identifiable, Codable {
    let id: String
    let coord: HexCoord
    let terrain: TerrainType
    var controller: Faction
    var cityName: String?
    var isSupplySource: Bool
}
```

### UnitType

```swift
enum UnitType: String, Codable {
    case infantry
    case mechanized
    case panzer
    case artillery
    case antiTank
    case garrison
}
```

### SupplyState

```swift
enum SupplyState: String, Codable {
    case supplied
    case unsupplied
    case encircled
}
```

### CombatUnit

```swift
struct CombatUnit: Identifiable, Codable {
    let id: String
    let name: String
    let faction: Faction
    let type: UnitType
    var hp: Int
    let maxHP: Int
    let attack: Int
    let defense: Int
    let move: Int
    let range: Int
    var coord: HexCoord
    var supplyState: SupplyState
    var hasActed: Bool
}
```

### GamePhase

```swift
enum GamePhase: String, Codable {
    case germanAI
    case alliedPlayer
    case resolution
    case finished
}
```

### GameState

```swift
struct GameState: Codable {
    var turn: Int
    var maxTurns: Int
    var phase: GamePhase
    var tiles: [HexTile]
    var units: [CombatUnit]
    var logs: [GameLogEntry]
    var victoryState: VictoryState?
}
```

### GameLogEntry

```swift
struct GameLogEntry: Identifiable, Codable {
    let id: String
    let turn: Int
    let message: String
}
```

### VictoryState

```swift
enum VictoryState: Codable {
    case germanyVictory(reason: String)
    case alliedVictory(reason: String)
    case draw(reason: String)
}
```

### AgentContext

```swift
struct AgentContext: Codable {
    let agentId: String
    let faction: Faction
    let turn: Int
    let personality: String
    let visibleTiles: [HexTile]
    let friendlyUnits: [CombatUnit]
    let enemyUnits: [CombatUnit]
    let recentLogs: [GameLogEntry]
    let playerDirective: String?
}
```

### AgentDecisionEnvelope

```swift
struct AgentDecisionEnvelope: Codable {
    let schemaVersion: Int
    let agentId: String
    let turn: Int
    let intent: String
    let orders: [AgentOrder]
}
```

### AgentOrder

```swift
struct AgentOrder: Codable {
    let type: AgentOrderType
    let unitId: String
    let to: HexCoord?
    let targetUnitId: String?
    let stance: String?
    let reason: String
}
```

### AgentOrderType

```swift
enum AgentOrderType: String, Codable {
    case move
    case attack
    case hold
    case resupply
}
```

### CommandValidationResult

```swift
struct CommandValidationResult {
    let order: AgentOrder
    let isValid: Bool
    let reason: String
}
```

### DecisionProvider

```swift
protocol DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope
}
```

### FutureSystemHook

```swift
protocol FutureSystemHook {
    var isEnabled: Bool { get }
    func prepare(gameState: GameState)
}
```

v0 的核心原则：**所有系统都服务于一次小型阿登战场验证，不引入完整大战略复杂度。** AI 只通过结构化命令影响游戏，所有实际状态变化必须经过规则系统。
