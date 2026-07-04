# 阶段 1：v0 六角格战棋核心规则

以下规则按“可直接实现”为目标，优先确定性、可测试、易调参。

## 1. 六角格坐标系统

采用 **axial hex 坐标**：

```swift
struct HexCoord {
    let q: Int
    let r: Int
}
```

隐式 cube 坐标：

```swift
let s = -q - r
```

六个方向：

| 方向 | dq | dr |
|---|---:|---:|
| E | 1 | 0 |
| NE | 1 | -1 |
| NW | 0 | -1 |
| W | -1 | 0 |
| SW | -1 | 1 |
| SE | 0 | 1 |

距离计算：

```swift
func hexDistance(_ a: HexCoord, _ b: HexCoord) -> Int {
    let dq = a.q - b.q
    let dr = a.r - b.r
    let ds = (-a.q - a.r) - (-b.q - b.r)
    return (abs(dq) + abs(dr) + abs(ds)) / 2
}
```

邻居：

```swift
func neighbors(of coord: HexCoord) -> [HexCoord] {
    directions.map { HexCoord(q: coord.q + $0.dq, r: coord.r + $0.dr) }
}
```

## 2. 地形规则

v0 建议把地形拆成两层：

```swift
enum BaseTerrain {
    case plain
    case forest
    case mountain
    case city
    case fortress
}

struct HexTile {
    let coord: HexCoord
    let baseTerrain: BaseTerrain
    var hasRoad: Bool
    var riverEdges: Set<HexDirection>
    var controller: Faction
    var isSupplySource: Bool
}
```

河流作为 **hex 边属性**，道路作为 **地块覆盖层**。这样比把河流、道路做成单独地块更适合战棋。

## 3. 地形移动消耗

所有单位使用整数移动点。

| 地形 | 基础进入消耗 |
|---|---:|
| 平原 | 1 |
| 森林 | 2 |
| 山地 | 3 |
| 城市 | 1 |
| 要塞 | 2 |
| 道路 | 1 |
| 跨河 | +2 |

道路规则：

- 如果当前格和目标格都有道路，则进入消耗固定为 `1`。
- 如果跨河边有道路，视为桥梁，不加跨河惩罚。
- 否则按目标格基础消耗计算。

敌方控制区规则：

- 单位可以进入敌方控制区。
- 进入敌方控制区后必须停止移动。
- 不能穿过敌方单位所在格。
- 不能进入己方单位所在格。

```swift
func movementCost(from: HexTile, to: HexTile, direction: HexDirection) -> Int {
    var cost: Int

    if from.hasRoad && to.hasRoad {
        cost = 1
    } else {
        cost = baseMoveCost(to.baseTerrain)
    }

    if from.riverEdges.contains(direction), !(from.hasRoad && to.hasRoad) {
        cost += 2
    }

    return cost
}
```

## 4. 地形防御修正

| 地形 | 防御修正 |
|---|---:|
| 平原 | 0 |
| 森林 | +2 |
| 山地 | +3 |
| 城市 | +2 |
| 要塞 | +4 |
| 防守方隔河 | +2 |

防御修正直接加到防御值：

```swift
effectiveDefense = unit.defense + terrainDefenseBonus + riverDefenseBonus
```

## 5. 战争迷雾与部队视野

每个阵营维护三种可见状态：

```swift
enum VisibilityState {
    case unseen      // 从未见过
    case explored    // 曾经见过，但当前不可见
    case visible     // 当前可见
}
```

规则：

- `visible`：显示地形、城市控制权、敌军单位。
- `explored`：显示最后已知地形和城市，但不显示敌军实时位置。
- `unseen`：黑色或未知格。

视野半径：

| 单位类型 | 基础视野 |
|---|---:|
| 坦克 | 2 |
| 摩托化步兵 | 3 |
| 步兵 | 2 |
| 炮兵 | 2 |

地形影响：

- 山地上视野 `+1`。
- 森林中的单位视野 `-1`，最低为 `1`。
- 城市/要塞不改变视野。
- v0 不做真实遮挡线，只用距离半径。

```swift
func visibleTiles(for faction: Faction, state: GameState) -> Set<HexCoord> {
    var visible = Set<HexCoord>()

    for unit in state.units where unit.faction == faction {
        let tile = state.tile(at: unit.coord)
        let radius = max(1, unit.baseVision + visionModifier(tile))
        for coord in state.coordsWithinDistance(unit.coord, radius) {
            visible.insert(coord)
        }
    }

    return visible
}
```

AI 只能读取：

- 当前可见敌军。
- 当前可见地形。
- 己方全部单位。
- 已探索但不可见区域的最后已知信息。

## 6. 陆军单位与混编师

v0 中地图上的一个单位代表一个师。师可以由多个兵种权重构成。

```swift
enum ComponentType {
    case tank
    case motorizedInfantry
    case infantry
    case artillery
}

struct DivisionComponent {
    let type: ComponentType
    let weight: Double // 0.0...1.0
}
```

权重总和必须为 `1.0`。

示例：

| 师类型 | 坦克 | 摩托化步兵 | 步兵 | 炮兵 |
|---|---:|---:|---:|---:|
| 装甲师 | 0.55 | 0.25 | 0.05 | 0.15 |
| 摩步师 | 0.15 | 0.55 | 0.15 | 0.15 |
| 步兵师 | 0.00 | 0.10 | 0.70 | 0.20 |
| 炮兵师 | 0.00 | 0.10 | 0.30 | 0.60 |

兵种基础属性：

| 兵种 | 攻击 | 防御 | 移动 | 射程 | 视野 |
|---|---:|---:|---:|---:|---:|
| 坦克 | 8 | 5 | 5 | 1 | 2 |
| 摩托化步兵 | 5 | 4 | 5 | 1 | 3 |
| 步兵 | 4 | 5 | 3 | 1 | 2 |
| 炮兵 | 7 | 2 | 2 | 2 | 2 |

师属性由权重计算：

```swift
division.attack = weightedSum(component.attack)
division.defense = weightedSum(component.defense)
division.move = roundedWeightedSum(component.move)
division.range = max(component.range where weight >= 0.25)
division.vision = max(component.vision where weight >= 0.25)
```

## 7. 攻击、反击、射程

攻击条件：

- 攻击方未行动。
- 目标在射程内。
- 目标可见。
- 攻击方与目标属于敌对阵营。
- 炮兵可射程 2。
- 非炮兵射程 1。

基础伤害公式：

```swift
rawDamage = attacker.attack - defender.effectiveDefense / 2
damage = clamp(rawDamage + bonuses - penalties, min: 1, max: 8)
```

攻击后：

- 攻击方 `hasActed = true`。
- 目标 hp 减少。
- hp <= 0 时移除。

反击规则：

- 只有目标存活才可能反击。
- 目标射程能覆盖攻击者时反击。
- 炮兵被近战攻击时不能反击。
- 炮兵远程攻击不会被普通单位反击，除非目标也是射程足够的炮兵。

反击伤害：

```swift
counterDamage = floor(normalDamage * 0.5)
```

## 8. 侧翼与绕后加成

定义每个单位的正面方向 `facing`。v0 可以在单位移动或攻击后自动设置：

- 移动后：朝向移动方向。
- 攻击后：朝向目标方向。
- 原地防守：保持原方向。

攻击方向判断：

```swift
let attackDirection = direction(from: defender.coord, to: attacker.coord)
```

相对于防守方 `facing`：

| 攻击角度 | 效果 |
|---|---:|
| 正面 | +0 |
| 侧翼 | +2 伤害 |
| 背后 | +4 伤害 |

简化实现：

- 防守方正面方向及相邻两个方向算正面。
- 左右两侧算侧翼。
- 正后方算背后。

```swift
func flankBonus(attacker: Unit, defender: Unit) -> Int {
    let dir = direction(from: defender.coord, to: attacker.coord)

    if isRear(dir, defender.facing) { return 4 }
    if isFlank(dir, defender.facing) { return 2 }
    return 0
}
```

## 9. 补给线判定

每个阵营有至少一个补给源：

```swift
struct SupplySource {
    let faction: Faction
    let coord: HexCoord
}
```

单位有三种补给状态：

```swift
enum SupplyState {
    case supplied
    case lowSupply
    case encircled
}
```

补给线规则：

- 从单位当前位置寻路到己方补给源。
- 可通过：
  - 己方控制格。
  - 中立格。
  - 己方单位所在格。
- 不可通过：
  - 敌方单位所在格。
  - 敌方控制城市/要塞。
  - 敌方控制区，除非该格有己方单位。
- 补给路径最大长度建议 `7`。
- 道路格补给成本 `1`。
- 非道路格补给成本 `2`。
- 山地补给成本 `3`。
- 跨河补给成本 `+2`。

```swift
func hasSupplyLine(unit: Unit, state: GameState) -> Bool {
    let sources = state.supplySources(for: unit.faction)

    for source in sources {
        if supplyPathCost(from: unit.coord, to: source.coord, state: state) <= 7 {
            return true
        }
    }

    return false
}
```

## 10. 包围判定

单位满足以下条件时为包围：

1. 无有效补给线。
2. 相邻 6 格中，可安全撤退格少于 2 个。

安全撤退格定义：

- 地块可通行。
- 没有敌军单位。
- 不在敌方控制区。
- 不是敌方控制城市/要塞。
- 有至少一条路径可以继续连接到己方方向或补给源。

```swift
func isEncircled(unit: Unit, state: GameState) -> Bool {
    if hasSupplyLine(unit: unit, state: state) {
        return false
    }

    let safeExits = neighbors(of: unit.coord).filter {
        isSafeRetreatTile($0, for: unit.faction, state: state)
    }

    return safeExits.count < 2
}
```

## 11. 低补给惩罚

补给状态每回合结束时重算。

| 状态 | 移动 | 攻击 | 防御 | 每回合损耗 |
|---|---:|---:|---:|---:|
| supplied | 正常 | 正常 | 正常 | 0 |
| lowSupply | -1 移动 | -25% 攻击 | -1 防御 | 0 |
| encircled | -2 移动 | -50% 攻击 | -2 防御 | -1 hp |

最低限制：

- 移动最低为 `1`。
- 攻击最低为 `1`。
- 防御最低为 `1`。
- 包围损耗不会直接把单位降到 0，最低保留 `1 hp`，必须被攻击消灭。

```swift
func applySupplyModifiers(unit: Unit) -> EffectiveStats {
    switch unit.supplyState {
    case .supplied:
        return unit.baseStats

    case .lowSupply:
        return EffectiveStats(
            attack: max(1, Int(Double(unit.attack) * 0.75)),
            defense: max(1, unit.defense - 1),
            move: max(1, unit.move - 1),
            range: unit.range,
            vision: unit.vision
        )

    case .encircled:
        return EffectiveStats(
            attack: max(1, Int(Double(unit.attack) * 0.5)),
            defense: max(1, unit.defense - 2),
            move: max(1, unit.move - 2),
            range: unit.range,
            vision: unit.vision
        )
    }
}
```

## 12. 回合结算顺序

固定顺序，避免规则互相覆盖：

```swift
func endTurn(state: inout GameState) {
    updateControlZones(&state)
    updateVisibility(&state)
    updateSupplyStates(&state)
    applyEncirclementAttrition(&state)
    checkVictoryConditions(&state)
    resetUnitActionsForNextFaction(&state)
}
```

攻击执行顺序：

```swift
func resolveAttack(attackerId: String, defenderId: String, state: inout GameState) {
    guard validateAttack(attackerId, defenderId, state) else { return }

    let attackDamage = calculateDamage(attacker, defender, state)
    defender.hp -= attackDamage

    if defender.hp <= 0 {
        remove(defender)
    } else if canCounterAttack(defender, attacker, state) {
        let counterDamage = calculateDamage(defender, attacker, state) / 2
        attacker.hp -= max(1, counterDamage)
    }

    attacker.hasActed = true
    attacker.facing = direction(from: attacker.coord, to: defender.coord)
}
```

核心实现原则：**地图状态只能由规则系统修改；AI 和玩家都只提交命令。** 这样后续接入 LLM、多将领、空军、天气、科技时，不需要重写战棋核心。
