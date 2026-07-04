import Foundation

struct RegionOccupationRules {
    func controller(for regionId: RegionId, in map: MapState) -> Faction? {
        map.region(id: regionId)?.controller
    }

    func mapByApplyingController(_ controller: Faction, to regionId: RegionId, in map: MapState) -> MapState {
        var next = map
        setController(controller, for: regionId, in: &next)
        return next
    }

    func setController(_ controller: Faction, for regionId: RegionId, in map: inout MapState) {
        guard var region = map.regions[regionId] else {
            return
        }
        region.controller = controller
        map.regions[regionId] = region
    }

    func mapByAggregatingControllers(in map: MapState) -> MapState {
        var next = map
        aggregateControl(in: &next)
        return next
    }

    @discardableResult
    func aggregateControl(in map: inout MapState) -> [RegionId] {
        var changed: [RegionId] = []
        for (regionId, region) in map.regions {
            guard let resolved = weightedController(for: region, in: map),
                  resolved != region.controller else {
                continue
            }
            setController(resolved, for: regionId, in: &map)
            changed.append(regionId)
        }
        return changed.sorted { $0.rawValue < $1.rawValue }
    }

    /// v0.21/v0.353: 聚合占领。hex controller 是底层权威，
    /// region controller 是由 region 内 hex 控制权 + 胜利点/城市权重派生的战略快照。
    /// 中立 hex 不计入。没有任何已控制 hex 时不改变 region controller。
    /// 返回本轮被改的 region id（供日志/event 用）。
    @discardableResult
    func aggregateControl(in state: inout GameState) -> [RegionId] {
        aggregateControl(in: &state.map)
    }

    func contestedRegions(in state: GameState) -> Set<RegionId> {
        var factionsByRegion: [RegionId: Set<Faction>] = [:]
        for division in state.divisions {
            guard let regionId = state.map.region(for: division.coord) else {
                continue
            }
            factionsByRegion[regionId, default: []].insert(division.faction)
        }
        return Set(factionsByRegion.compactMap { regionId, factions in
            factions.count > 1 ? regionId : nil
        })
    }
}

private extension RegionOccupationRules {
    func weightedController(for region: RegionNode, in map: MapState) -> Faction? {
        var weights: [Faction: Int] = [:]

        for hex in region.displayHexes {
            guard let controller = map.tile(at: hex)?.controller else { continue }
            weights[controller, default: 0] += hexWeight(hex, in: region, map: map)
        }

        guard let top = weights.sorted(by: weightedSort).first,
              top.value > 0 else {
            return nil
        }

        let tiedTopCount = weights.values.filter { $0 == top.value }.count
        return tiedTopCount == 1 ? top.key : nil
    }

    func hexWeight(_ hex: HexCoord, in region: RegionNode, map: MapState) -> Int {
        var weight = 1
        if region.representativeHex == hex {
            weight += max(0, region.city?.victoryPoints ?? 0)
        }
        if let tile = map.tile(at: hex),
           tile.cityName != nil || tile.fortressName != nil || tile.baseTerrain == .city || tile.baseTerrain == .fortress {
            weight += max(1, region.city?.victoryPoints ?? 1)
        }
        return weight
    }

    func weightedSort(_ lhs: (key: Faction, value: Int), _ rhs: (key: Faction, value: Int)) -> Bool {
        lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
    }
}
