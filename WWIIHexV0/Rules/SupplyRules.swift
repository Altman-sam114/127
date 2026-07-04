import Foundation

struct SupplyRules {
    let maxSupplyPathCost = 7
    let suppliedResupplyHPRecovery = 2
    let encircledHPLoss = 1
    let failedRetreatHPLoss = 1
    private let movementRules = MovementRules()

    func updateSupplyStates(in state: inout GameState) {
        let snapshot = state
        for index in state.divisions.indices {
            let division = state.divisions[index]
            state.divisions[index].supplyState = supplyState(for: division, in: snapshot)
        }
    }

    func applyResupplyRest(to divisionId: String, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        state.divisions[index].supplyState = supplyState(for: state.divisions[index], in: state)
        let before = state.divisions[index]

        switch before.supplyState {
        case .supplied:
            recoverDivision(
                at: index,
                hp: suppliedResupplyHPRecovery,
                in: &state
            )
        case .lowSupply:
            break
        case .encircled:
            break
        }

        let after = state.divisions[index]
        let hpRecovered = after.hp - before.hp

        if hpRecovered > 0 {
            state.appendEvent(
                "\(after.name) reinforced in \(after.supplyState.rawValue): +\(hpRecovered) strength."
            )
        } else {
            state.appendEvent("\(after.name) could not recover while \(after.supplyState.rawValue).")
        }
    }

    func resolveRetreat(for divisionId: String, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        let division = state.divisions[index]
        if let destination = retreatDestination(for: division, in: state) {
            let origin = division.coord
            state.divisions[index].coord = destination
            if let direction = origin.direction(to: destination) {
                state.divisions[index].facing = direction
            }
            state.divisions[index].beginRetreat(to: destination)
            state.appendEvent(
                "\(division.name) retreated from \(origin.q),\(origin.r) to \(destination.q),\(destination.r)."
            )
        } else {
            state.divisions[index].hp = max(1, state.divisions[index].hp - failedRetreatHPLoss)
            state.appendEvent(
                "\(division.name) failed to retreat and lost \(failedRetreatHPLoss) strength."
            )
        }
    }

    func advanceRetreats(in state: inout GameState) {
        let retreatingIds = state.divisions
            .filter(\.isRetreating)
            .map(\.id)

        for divisionId in retreatingIds {
            _ = advanceRetreatStatusIfNeeded(for: divisionId, in: &state)
        }
    }

    func applyEncirclementAttrition(in state: inout GameState) {
        for index in state.divisions.indices where state.divisions[index].supplyState == .encircled {
            let beforeHP = state.divisions[index].hp

            state.divisions[index].hp = max(1, beforeHP - encircledHPLoss)

            let hpLost = beforeHP - state.divisions[index].hp
            if hpLost > 0 {
                state.appendEvent(
                    "\(state.divisions[index].name) suffered encirclement attrition: -\(hpLost) strength."
                )
            }
        }
    }

    func hasSupplyLine(for division: Division, in state: GameState) -> Bool {
        state.map.supplySources(for: division.faction).contains { source in
            supplyPathCost(from: division.coord, to: source.coord, for: division.faction, in: state) <= maxSupplyPathCost
        }
    }

    func supplyState(for division: Division, in state: GameState) -> SupplyState {
        if hasSupplyLine(for: division, in: state) {
            return .supplied
        }

        if isEncircled(division, in: state) {
            return .encircled
        }

        return .lowSupply
    }

    func isEncircled(_ division: Division, in state: GameState) -> Bool {
        guard !hasSupplyLine(for: division, in: state) else {
            return false
        }

        let safeExits = division.coord.neighbors.filter {
            isSafeRetreatTile($0, for: division.faction, in: state)
        }
        return safeExits.count < 2
    }

    func isSafeRetreatTile(_ coord: HexCoord, for faction: Faction, in state: GameState) -> Bool {
        guard let tile = state.map.tile(at: coord),
              state.map.contains(coord),
              tile.isPassable,
              state.division(at: coord) == nil else {
            return false
        }

        if tile.isCapturable, let controller = tile.controller, controller.isHostile(to: faction) {
            return false
        }

        if movementRules.isEnemyZoneOfControl(coord, for: faction, in: state) {
            return false
        }

        return state.map.supplySources(for: faction).contains { source in
            supplyPathCost(from: coord, to: source.coord, for: faction, in: state) <= maxSupplyPathCost
        }
    }

    func retreatDestination(for division: Division, in state: GameState) -> HexCoord? {
        let candidates = division.coord.neighbors.filter {
            isSafeRetreatTile($0, for: division.faction, in: state)
        }

        return candidates.min {
            retreatSortKey(for: $0, faction: division.faction, in: state) <
                retreatSortKey(for: $1, faction: division.faction, in: state)
        }
    }

    func supplyPathCost(from start: HexCoord, to goal: HexCoord, for faction: Faction, in state: GameState) -> Int {
        guard state.map.contains(start), state.map.contains(goal) else {
            return Int.max
        }

        var bestCost: [HexCoord: Int] = [start: 0]
        var frontier: [(coord: HexCoord, cost: Int)] = [(start, 0)]

        while !frontier.isEmpty {
            frontier.sort { $0.cost < $1.cost }
            let current = frontier.removeFirst()

            guard current.cost == bestCost[current.coord] else {
                continue
            }

            if current.coord == goal {
                return current.cost
            }

            guard let fromTile = state.map.tile(at: current.coord) else {
                continue
            }

            for direction in HexDirection.ordered {
                let next = current.coord.neighbor(in: direction)
                guard let toTile = state.map.tile(at: next),
                      state.map.contains(next),
                      toTile.isPassable,
                      canSupplyPass(through: next, tile: toTile, for: faction, in: state) else {
                    continue
                }

                var nextCost = current.cost + supplyCost(entering: toTile)
                if movementRules.hasRiverCrossing(from: fromTile, to: toTile, direction: direction) {
                    nextCost += 2
                }

                guard nextCost <= maxSupplyPathCost,
                      nextCost < bestCost[next, default: Int.max] else {
                    continue
                }

                bestCost[next] = nextCost
                frontier.append((next, nextCost))
            }
        }

        return Int.max
    }

    private func canSupplyPass(through coord: HexCoord, tile: HexTile, for faction: Faction, in state: GameState) -> Bool {
        if let division = state.division(at: coord), division.faction != faction {
            return false
        }

        if tile.isCapturable, let controller = tile.controller, controller.isHostile(to: faction) {
            return false
        }

        if movementRules.isEnemyZoneOfControl(coord, for: faction, in: state) {
            if state.division(at: coord)?.faction == faction {
                return true
            }
            return false
        }

        return true
    }

    private func retreatSortKey(for coord: HexCoord, faction: Faction, in state: GameState) -> RetreatSortKey {
        let supplySources = state.map.supplySources(for: faction)
        let pathCost = supplySources
            .map { supplyPathCost(from: coord, to: $0.coord, for: faction, in: state) }
            .min() ?? Int.max
        let sourceDistance = supplySources
            .map { coord.distance(to: $0.coord) }
            .min() ?? Int.max
        let tileCost = state.map.tile(at: coord).map(supplyCost(entering:)) ?? Int.max

        return RetreatSortKey(
            pathCost: pathCost,
            sourceDistance: sourceDistance,
            tileCost: tileCost,
            q: coord.q,
            r: coord.r
        )
    }

    private func recoverDivision(at index: Int, hp: Int, in state: inout GameState) {
        state.divisions[index].reinforceStrength(hp)
    }

    private func advanceRetreatStatusIfNeeded(for divisionId: String, in state: inout GameState) -> Bool {
        guard let index = state.divisionIndex(id: divisionId),
              state.divisions[index].isRetreating else {
            return false
        }

        let wasRetreating = state.divisions[index].isRetreating
        state.divisions[index].advanceRetreatTurn()
        if wasRetreating && !state.divisions[index].isRetreating {
            state.appendEvent("\(state.divisions[index].name) completed retreat recovery.")
        }

        return true
    }

    private func supplyCost(entering tile: HexTile) -> Int {
        if tile.hasRoad {
            return 1
        }

        switch tile.baseTerrain {
        case .mountain:
            return 3
        default:
            return 2
        }
    }
}

private struct RetreatSortKey: Comparable {
    let pathCost: Int
    let sourceDistance: Int
    let tileCost: Int
    let q: Int
    let r: Int

    static func < (lhs: RetreatSortKey, rhs: RetreatSortKey) -> Bool {
        if lhs.pathCost != rhs.pathCost {
            return lhs.pathCost < rhs.pathCost
        }

        if lhs.sourceDistance != rhs.sourceDistance {
            return lhs.sourceDistance < rhs.sourceDistance
        }

        if lhs.tileCost != rhs.tileCost {
            return lhs.tileCost < rhs.tileCost
        }

        if lhs.q != rhs.q {
            return lhs.q < rhs.q
        }

        return lhs.r < rhs.r
    }
}
