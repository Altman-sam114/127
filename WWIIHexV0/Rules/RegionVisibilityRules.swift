import Foundation

enum RegionVisibilityState: String, Codable, Equatable {
    case unseen
    case visible
}

struct RegionVisibilityRules {
    func visibleRegions(for faction: Faction, in state: GameState, radius: Int = 1) -> Set<RegionId> {
        let graph = state.map.regionGraph
        var visible = Set<RegionId>()

        for division in state.divisions where division.faction == faction {
            guard let origin = state.map.region(for: division.coord) else {
                continue
            }

            visible.insert(origin)
            for (regionId, _) in graph.regions {
                guard let distance = graph.distance(from: origin, to: regionId),
                      distance <= max(0, radius) else {
                    continue
                }
                visible.insert(regionId)
            }
        }

        return visible
    }

    func visibilityMap(for faction: Faction, in state: GameState, radius: Int = 1) -> [RegionId: RegionVisibilityState] {
        let visible = visibleRegions(for: faction, in: state, radius: radius)
        var result: [RegionId: RegionVisibilityState] = [:]
        for regionId in state.map.regions.keys {
            result[regionId] = visible.contains(regionId) ? .visible : .unseen
        }
        return result
    }
}

