import Foundation

struct SupplySource: Codable, Equatable, Identifiable {
    let id: String
    let faction: Faction
    let coord: HexCoord
}

enum ObjectiveType: String, Codable, Equatable {
    case city
    case fortress
    case supply
}

struct Objective: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let coord: HexCoord
    let type: ObjectiveType
}

struct MapState: Codable, Equatable {
    var width: Int
    var height: Int
    var tiles: [HexCoord: HexTile]
    var supplySources: [SupplySource]
    var objectives: [Objective]
    /// v0.2: 省份图（战略层叠加）。默认空，hex 仍是战术层权威坐标。
    /// Agent 2 填 ardennes province 数据后此处非空。
    var regions: [RegionId: RegionNode]
    /// v0.2: hex → 省份映射，UI 点击转换用。
    var hexToRegion: [HexCoord: RegionId]
    /// v0.2: 省份相邻边集合。
    var regionEdges: Set<RegionEdge>

    init(
        width: Int,
        height: Int,
        tiles: [HexCoord: HexTile],
        supplySources: [SupplySource],
        objectives: [Objective],
        regions: [RegionId: RegionNode] = [:],
        hexToRegion: [HexCoord: RegionId] = [:],
        regionEdges: Set<RegionEdge> = []
    ) {
        self.width = width
        self.height = height
        self.tiles = tiles
        self.supplySources = supplySources
        self.objectives = objectives
        self.regions = regions
        self.hexToRegion = hexToRegion
        self.regionEdges = regionEdges
    }

    func contains(_ coord: HexCoord) -> Bool {
        tiles[coord] != nil
    }

    func tile(at coord: HexCoord) -> HexTile? {
        tiles[coord]
    }

    mutating func setTile(_ tile: HexTile) {
        tiles[tile.coord] = tile
    }

    func supplySources(for faction: Faction) -> [SupplySource] {
        supplySources.filter { controllingFaction(for: $0) == faction }
    }

    func controllingFaction(for supplySource: SupplySource) -> Faction? {
        if let controller = tile(at: supplySource.coord)?.controller {
            return controller
        }

        if let regionId = region(for: supplySource.coord),
           let region = regions[regionId] {
            return region.controller
        }

        return supplySource.faction
    }

    func objective(named name: String) -> Objective? {
        objectives.first { $0.name == name }
    }

    func controllerOfObjective(named name: String) -> Faction? {
        guard let coord = objective(named: name)?.coord else {
            return nil
        }
        return tile(at: coord)?.controller
    }

    // MARK: - v0.2 Province 查询（战略层叠加）
    // 所有查询委托给 regionGraph 视图。province 默认空时不影响现有 hex 规则。

    /// 当前省份图视图。regions 为空时返回 empty graph。
    var regionGraph: RegionGraph {
        RegionGraph(regions: regions, edges: regionEdges)
    }

    /// hex 所属省份。优先查 hexToRegion 映射，fallback 查 tile.regionId。
    func region(for hex: HexCoord) -> RegionId? {
        if let mapped = hexToRegion[hex] {
            return mapped
        }
        return tiles[hex]?.regionId
    }

    func region(id: RegionId) -> RegionNode? {
        regions[id]
    }

    func neighbors(of regionId: RegionId) -> [RegionId] {
        regions[regionId]?.neighbors ?? []
    }

    func areAdjacent(_ a: RegionId, _ b: RegionId) -> Bool {
        guard regions[a] != nil, regions[b] != nil else { return false }
        if regionEdges.isEmpty {
            return neighbors(of: a).contains(b)
        }
        return regionEdges.contains { $0.symmetricKey == RegionEdge.key(a, b) }
    }

    func edgeBetween(_ a: RegionId, _ b: RegionId) -> RegionEdge? {
        let key = RegionEdge.key(a, b)
        return regionEdges.first { $0.symmetricKey == key }
    }

    func representativeHex(for regionId: RegionId) -> HexCoord? {
        regions[regionId]?.representativeHex
    }

    /// 两省份图距离（BFS 跳数）。不连通或不存在返回 nil。
    func regionDistance(from start: RegionId, to goal: RegionId) -> Int? {
        regionGraph.distance(from: start, to: goal)
    }

    /// v0.2: 校验省份图 + hexToRegion 一致性。供 Agent 2 数据加载用。
    /// 空 province（regions 为空）返回空错误列表（合法，v0/v0.1 默认状态）。
    func validateRegionGraph() -> [RegionValidationError] {
        var errors = regionGraph.validate()

        // hexToRegion 不指向不存在 region
        for (hex, regionId) in hexToRegion where regions[regionId] == nil {
            errors.append(.hexToRegionPointsToMissingRegion(hex: "\(hex.q),\(hex.r)", regionId: regionId.rawValue))
        }

        // displayHexes 跨 region 不重叠
        var hexOwner: [HexCoord: RegionId] = [:]
        for (regionId, node) in regions {
            for hex in node.displayHexes {
                if let existing = hexOwner[hex] {
                    errors.append(.displayHexesOverlap(hex: "\(hex.q),\(hex.r)", regionA: existing.rawValue, regionB: regionId.rawValue))
                } else {
                    hexOwner[hex] = regionId
                }
            }
        }

        return errors
    }

    static func ardennesV0() -> MapState {
        let width = 11
        let height = 9
        var tiles: [HexCoord: HexTile] = [:]

        for q in 0..<width {
            for r in 0..<height {
                let coord = HexCoord(q: q, r: r)
                let hasRoad = r == 4 || (q == 7 && r == 3)
                let terrain: BaseTerrain
                if (q == 3 && r == 3) || (q == 4 && r == 5) || (q == 6 && r == 5) {
                    terrain = .forest
                } else if (q == 6 && r == 2) || (q == 7 && r == 2) {
                    terrain = .mountain
                } else {
                    terrain = .plain
                }

                tiles[coord] = HexTile(
                    coord: coord,
                    baseTerrain: terrain,
                    hasRoad: hasRoad,
                    controller: nil
                )
            }
        }

        func update(_ coord: HexCoord, _ transform: (inout HexTile) -> Void) {
            guard var tile = tiles[coord] else {
                return
            }
            transform(&tile)
            tiles[coord] = tile
        }

        let alliedSupply = HexCoord(q: 0, r: 4)
        let germanSupply = HexCoord(q: 10, r: 4)
        let bastogneFortress = HexCoord(q: 4, r: 4)
        let bastogne = HexCoord(q: 5, r: 4)
        let houffalize = HexCoord(q: 6, r: 4)
        let stVith = HexCoord(q: 7, r: 3)

        update(alliedSupply) {
            $0.controller = .allies
            $0.hasRoad = true
        }
        update(germanSupply) {
            $0.controller = .germany
            $0.hasRoad = true
        }
        update(bastogneFortress) {
            $0.baseTerrain = .fortress
            $0.controller = .allies
            $0.hasRoad = true
            $0.fortressName = "Bastogne Fortress"
        }
        update(bastogne) {
            $0.baseTerrain = .city
            $0.controller = .allies
            $0.hasRoad = true
            $0.cityName = "Bastogne"
        }
        update(houffalize) {
            $0.baseTerrain = .city
            $0.controller = nil
            $0.hasRoad = true
            $0.cityName = "Houffalize"
        }
        update(stVith) {
            $0.baseTerrain = .city
            $0.controller = .allies
            $0.hasRoad = true
            $0.cityName = "St. Vith"
        }

        let riverWestOfBastogne = HexCoord(q: 5, r: 4)
        update(riverWestOfBastogne) {
            $0.riverEdges.insert(.west)
        }

        return MapState(
            width: width,
            height: height,
            tiles: tiles,
            supplySources: [
                SupplySource(id: "allied_supply", faction: .allies, coord: alliedSupply),
                SupplySource(id: "german_supply", faction: .germany, coord: germanSupply)
            ],
            objectives: [
                Objective(id: "bastogne", name: "Bastogne", coord: bastogne, type: .city),
                Objective(id: "st_vith", name: "St. Vith", coord: stVith, type: .city),
                Objective(id: "bastogne_fortress", name: "Bastogne Fortress", coord: bastogneFortress, type: .fortress)
            ]
        )
    }
}
