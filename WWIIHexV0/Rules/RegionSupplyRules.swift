import Foundation

struct RegionSupplyRules {
    let maxSupplyPathCost = 7
    private let pathfinder = RegionPathfinder()

    func supplyState(for division: Division, in state: GameState) -> SupplyState {
        guard let regionId = state.map.region(for: division.coord) else {
            return .lowSupply
        }

        if hasSupplyLine(from: regionId, for: division.faction, in: state) {
            return .supplied
        }

        if isEncircled(regionId, for: division.faction, in: state) {
            return .encircled
        }

        return .lowSupply
    }

    func hasSupplyLine(from regionId: RegionId, for faction: Faction, in state: GameState) -> Bool {
        strategicSupplySources(for: faction, in: state).contains { source in
            supplyPath(from: regionId, to: source, for: faction, in: state) != nil
        }
    }

    func supplyPath(from start: RegionId, to goal: RegionId, for faction: Faction, in state: GameState) -> RegionPath? {
        let graph = state.map.regionGraph
        return pathfinder.shortestPath(from: start, to: goal, in: graph) { fromId, toId, edge in
            guard let from = graph.region(fromId),
                  let to = graph.region(toId),
                  canSupplyPass(through: to, for: faction, in: state) else {
                return nil
            }

            let stepCost = supplyCost(entering: to, edge: edge)
            return from.isPassable ? stepCost : nil
        }.flatMap { path in
            path.cost <= maxSupplyPathCost ? path : nil
        }
    }

    func isEncircled(_ regionId: RegionId, for faction: Faction, in state: GameState) -> Bool {
        guard !hasSupplyLine(from: regionId, for: faction, in: state) else {
            return false
        }

        let safeExits = state.map.neighbors(of: regionId).filter {
            isSafeRetreatRegion($0, for: faction, in: state)
        }
        return safeExits.count < 2
    }

    func isSafeRetreatRegion(_ regionId: RegionId, for faction: Faction, in state: GameState) -> Bool {
        guard let region = state.map.region(id: regionId),
              region.isPassable,
              !region.controller.isHostile(to: faction) else {
            return false
        }
        return hasSupplyLine(from: regionId, for: faction, in: state)
    }

    func strategicSupplySources(for faction: Faction, in state: GameState) -> [RegionId] {
        var sources = Set<RegionId>()

        for source in state.map.supplySources(for: faction) {
            if let regionId = state.map.region(for: source.coord) {
                sources.insert(regionId)
            }
        }

        for (regionId, region) in state.map.regions where region.controller == faction && region.supplyValue > 0 {
            sources.insert(regionId)
        }

        return Array(sources)
    }

    private func canSupplyPass(through region: RegionNode, for faction: Faction, in state: GameState) -> Bool {
        guard region.isPassable else {
            return false
        }

        if region.controller.isHostile(to: faction) {
            let friendlyUnitPresent = state.divisions.contains {
                $0.faction == faction && state.map.region(for: $0.coord) == region.id
            }
            return friendlyUnitPresent
        }

        return true
    }

    private func supplyCost(entering region: RegionNode, edge: RegionEdge?) -> Int {
        var cost: Int
        if edge?.hasRoad == true {
            cost = 1
        } else {
            switch region.terrain {
            case .mountain:
                cost = 3
            default:
                cost = 2
            }
        }

        if edge?.hasRiverCrossing == true {
            cost += 2
        }
        cost += edge?.movementCostModifier ?? 0
        return max(1, cost)
    }
}
