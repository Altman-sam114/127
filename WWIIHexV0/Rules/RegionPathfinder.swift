import Foundation

struct RegionPath: Equatable {
    let regionIds: [RegionId]
    let cost: Int
}

struct RegionPathfinder {
    func shortestPath(
        from start: RegionId,
        to goal: RegionId,
        in graph: RegionGraph,
        cost: (RegionId, RegionId, RegionEdge?) -> Int?
    ) -> RegionPath? {
        guard graph.region(start) != nil, graph.region(goal) != nil else {
            return nil
        }
        if start == goal {
            return RegionPath(regionIds: [start], cost: 0)
        }

        var bestCost: [RegionId: Int] = [start: 0]
        var bestPath: [RegionId: [RegionId]] = [start: [start]]
        var frontier: [(id: RegionId, cost: Int)] = [(start, 0)]

        while !frontier.isEmpty {
            frontier.sort { $0.cost < $1.cost }
            let current = frontier.removeFirst()

            guard current.cost == bestCost[current.id] else {
                continue
            }

            for neighbor in graph.neighbors(of: current.id) {
                guard let stepCost = cost(current.id, neighbor, graph.edgeBetween(current.id, neighbor)) else {
                    continue
                }

                let nextCost = current.cost + max(0, stepCost)
                guard nextCost < bestCost[neighbor, default: Int.max] else {
                    continue
                }

                bestCost[neighbor] = nextCost
                bestPath[neighbor] = (bestPath[current.id] ?? [current.id]) + [neighbor]
                if neighbor == goal {
                    continue
                }
                frontier.append((neighbor, nextCost))
            }
        }

        guard let totalCost = bestCost[goal],
              let path = bestPath[goal] else {
            return nil
        }
        return RegionPath(regionIds: path, cost: totalCost)
    }

    func reachableRegions(
        from start: RegionId,
        in graph: RegionGraph,
        maxCost: Int,
        cost: (RegionId, RegionId, RegionEdge?) -> Int?
    ) -> [RegionId: RegionPath] {
        guard graph.region(start) != nil, maxCost >= 0 else {
            return [:]
        }

        var bestCost: [RegionId: Int] = [start: 0]
        var bestPath: [RegionId: [RegionId]] = [start: [start]]
        var frontier: [(id: RegionId, cost: Int)] = [(start, 0)]

        while !frontier.isEmpty {
            frontier.sort { $0.cost < $1.cost }
            let current = frontier.removeFirst()

            guard current.cost == bestCost[current.id] else {
                continue
            }

            for neighbor in graph.neighbors(of: current.id) {
                guard let stepCost = cost(current.id, neighbor, graph.edgeBetween(current.id, neighbor)) else {
                    continue
                }

                let nextCost = current.cost + max(0, stepCost)
                guard nextCost <= maxCost,
                      nextCost < bestCost[neighbor, default: Int.max] else {
                    continue
                }

                bestCost[neighbor] = nextCost
                bestPath[neighbor] = (bestPath[current.id] ?? [current.id]) + [neighbor]
                frontier.append((neighbor, nextCost))
            }
        }

        var result: [RegionId: RegionPath] = [:]
        for (id, cost) in bestCost where id != start {
            result[id] = RegionPath(regionIds: bestPath[id] ?? [start, id], cost: cost)
        }
        return result
    }
}

