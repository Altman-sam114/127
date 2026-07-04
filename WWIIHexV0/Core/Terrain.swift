import Foundation

enum BaseTerrain: String, Codable, Equatable, CaseIterable {
    case plain
    case forest
    case mountain
    case hill
    case city
    case fortress

    var movementCost: Int {
        switch self {
        case .plain:
            return 1
        case .forest:
            return 2
        case .mountain:
            return 3
        case .hill:
            return 2
        case .city:
            return 1
        case .fortress:
            return 2
        }
    }

    var defenseBonus: Int {
        switch self {
        case .plain:
            return 0
        case .forest:
            return 2
        case .mountain:
            return 3
        case .hill:
            return 1
        case .city:
            return 2
        case .fortress:
            return 4
        }
    }

    var armorSlowdownCost: Int {
        switch self {
        case .plain:
            return 0
        case .hill:
            return 1
        case .forest,
             .city,
             .fortress:
            return 1
        case .mountain:
            return 2
        }
    }

    var supportsInfantryDefenseBonus: Bool {
        switch self {
        case .forest,
             .city,
             .fortress:
            return true
        case .plain,
             .mountain,
             .hill:
            return false
        }
    }

    var isObjectiveTerrain: Bool {
        self == .city || self == .fortress
    }

    var displayName: String {
        switch self {
        case .plain:
            return "Plain"
        case .forest:
            return "Forest"
        case .mountain:
            return "Mountain"
        case .hill:
            return "Hill"
        case .city:
            return "City"
        case .fortress:
            return "Fortress"
        }
    }
}

struct HexTile: Codable, Equatable {
    let coord: HexCoord
    var baseTerrain: BaseTerrain
    var hasRoad: Bool
    var riverEdges: Set<HexDirection>
    var controller: Faction?
    var cityName: String?
    var fortressName: String?
    var isPassable: Bool
    /// v0.2: 该 hex 所属省份。默认 nil（未分配省份），province 层叠加时由数据填充。
    /// hex 仍是战术层权威坐标，regionId 只是聚合归属标记，不影响现有 hex 规则。
    var regionId: RegionId?

    init(
        coord: HexCoord,
        baseTerrain: BaseTerrain = .plain,
        hasRoad: Bool = false,
        riverEdges: Set<HexDirection> = [],
        controller: Faction? = nil,
        cityName: String? = nil,
        fortressName: String? = nil,
        isPassable: Bool = true,
        regionId: RegionId? = nil
    ) {
        self.coord = coord
        self.baseTerrain = baseTerrain
        self.hasRoad = hasRoad
        self.riverEdges = riverEdges
        self.controller = controller
        self.cityName = cityName
        self.fortressName = fortressName
        self.isPassable = isPassable
        self.regionId = regionId
    }

    var isCapturable: Bool {
        isPassable
    }
}
