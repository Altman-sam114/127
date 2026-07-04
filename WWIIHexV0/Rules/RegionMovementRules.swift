import Foundation

struct RegionMovementRules {
    private let pathfinder = RegionPathfinder()

    func movementCost(from: RegionNode, to: RegionNode, edge: RegionEdge?) -> Int {
        guard from.isPassable, to.isPassable else {
            return Int.max
        }

        var cost = edge?.hasRoad == true ? 1 : to.terrain.movementCost
        if edge?.hasRiverCrossing == true {
            cost += 2
        }
        cost += edge?.movementCostModifier ?? 0
        return max(1, cost)
    }

    func shortestPath(from start: RegionId, to goal: RegionId, in map: MapState) -> RegionPath? {
        let graph = map.regionGraph
        return pathfinder.shortestPath(from: start, to: goal, in: graph) { fromId, toId, edge in
            guard let from = graph.region(fromId),
                  let to = graph.region(toId) else {
                return nil
            }
            return movementCost(from: from, to: to, edge: edge)
        }
    }

    func reachableRegions(from start: RegionId, movementBudget: Int, in map: MapState) -> [RegionId: RegionPath] {
        let graph = map.regionGraph
        return pathfinder.reachableRegions(from: start, in: graph, maxCost: movementBudget) { fromId, toId, edge in
            guard let from = graph.region(fromId),
                  let to = graph.region(toId) else {
                return nil
            }
            return movementCost(from: from, to: to, edge: edge)
        }
    }
}

