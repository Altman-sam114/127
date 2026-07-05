import Foundation

struct MovementPath: Equatable {
    let coords: [HexCoord]
    let cost: Int
}

struct MovementRules {
    func movementCost(from: HexTile, to: HexTile, direction: HexDirection) -> Int {
        var cost = from.hasRoad && to.hasRoad ? 1 : to.baseTerrain.movementCost
        if hasRiverCrossing(from: from, to: to, direction: direction), !(from.hasRoad && to.hasRoad) {
            cost += 2
        }
        return cost
    }

    func movementRange(for division: Division, in state: GameState) -> Set<HexCoord> {
        Set(shortestPaths(from: division, in: state).keys.filter { state.division(at: $0) == nil })
    }

    func shortestPath(for division: Division, to destination: HexCoord, in state: GameState) -> MovementPath? {
        shortestPaths(from: division, in: state)[destination]
    }

    func shortestPathIgnoringMovement(for division: Division, to destination: HexCoord, in state: GameState) -> MovementPath? {
        shortestPaths(from: division, in: state, movementLimit: Int.max)[destination]
    }

    func isEnemyZoneOfControl(_ coord: HexCoord, for faction: Faction, in state: GameState) -> Bool {
        state.divisions.contains { division in
            division.faction.isHostile(to: faction)
                && !division.isDestroyed
                && division.coord.distance(to: coord) == 1
        }
    }

    func direction(from start: HexCoord, to destination: HexCoord) -> HexDirection? {
        start.direction(to: destination)
    }

    func hasRiverCrossing(from: HexTile, to: HexTile, direction: HexDirection) -> Bool {
        from.riverEdges.contains(direction) || to.riverEdges.contains(direction.opposite)
    }

    private func shortestPaths(from division: Division, in state: GameState) -> [HexCoord: MovementPath] {
        shortestPaths(from: division, in: state, movementLimit: division.movement)
    }

    private func shortestPaths(from division: Division, in state: GameState, movementLimit: Int) -> [HexCoord: MovementPath] {
        var bestCost: [HexCoord: Int] = [division.coord: 0]
        var bestPath: [HexCoord: [HexCoord]] = [division.coord: [division.coord]]
        var frontier: [(coord: HexCoord, cost: Int)] = [(division.coord, 0)]

        while !frontier.isEmpty {
            frontier.sort { $0.cost < $1.cost }
            let current = frontier.removeFirst()

            guard current.cost == bestCost[current.coord] else {
                continue
            }

            if current.coord != division.coord,
               isEnemyZoneOfControl(current.coord, for: division.faction, in: state) {
                continue
            }

            guard let fromTile = state.map.tile(at: current.coord) else {
                continue
            }

            for direction in HexDirection.ordered {
                let next = current.coord.neighbor(in: direction)
                guard let toTile = state.map.tile(at: next),
                      state.map.contains(next),
                      toTile.isPassable else {
                    continue
                }

                if let occupyingDivision = state.division(at: next),
                   occupyingDivision.id != division.id,
                   occupyingDivision.faction != division.faction {
                    continue
                }

                let nextCost = current.cost
                    + tacticalMovementCost(for: division, from: fromTile, to: toTile, direction: direction)
                guard nextCost <= movementLimit else {
                    continue
                }

                if nextCost < bestCost[next, default: Int.max] {
                    bestCost[next] = nextCost
                    bestPath[next] = (bestPath[current.coord] ?? [current.coord]) + [next]
                    frontier.append((next, nextCost))
                }
            }
        }

        var paths: [HexCoord: MovementPath] = [:]
        for (coord, cost) in bestCost where coord != division.coord {
            paths[coord] = MovementPath(coords: bestPath[coord] ?? [division.coord, coord], cost: cost)
        }
        return paths
    }

    private func tacticalTerrainPenalty(for division: Division, entering tile: HexTile) -> Int {
        if division.isArmor {
            return tile.baseTerrain.armorSlowdownCost
        }

        if division.isMechanized {
            switch tile.baseTerrain {
            case .mountain:
                return 1
            case .forest,
                 .fortress:
                return 1
            case .plain,
                 .hill,
                 .city:
                return 0
            }
        }

        return 0
    }

    private func tacticalMovementCost(
        for division: Division,
        from fromTile: HexTile,
        to toTile: HexTile,
        direction: HexDirection
    ) -> Int {
        var cost = movementCost(from: fromTile, to: toTile, direction: direction)
            + tacticalTerrainPenalty(for: division, entering: toTile)

        if division.hasEngineerSupport,
           hasRiverCrossing(from: fromTile, to: toTile, direction: direction) || toTile.baseTerrain == .fortress {
            cost -= 1
        }

        if division.hasLogisticsSupport,
           division.supplyState != .supplied {
            cost -= 1
        }

        return max(1, cost)
    }
}
