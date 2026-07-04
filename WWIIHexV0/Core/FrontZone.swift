import Foundation

struct FrontZone: Codable, Equatable, Identifiable {
    let id: FrontZoneId
    var name: String
    var faction: Faction
    var regionIds: [RegionId]
    var neighbors: [FrontZoneId]
    var frontSegments: [FrontZoneSegment]
    var unitsFront: [String]
    var unitsDepth: [String]
    var unitsGarrison: [String]
    var pressure: Int
    var state: WarState
    var isCoreZone: Bool
    var generalAssignment: GeneralAssignment?

    init(
        id: FrontZoneId,
        name: String,
        faction: Faction,
        regionIds: [RegionId] = [],
        neighbors: [FrontZoneId] = [],
        frontSegments: [FrontZoneSegment] = [],
        unitsFront: [String] = [],
        unitsDepth: [String] = [],
        unitsGarrison: [String] = [],
        pressure: Int = 0,
        state: WarState = .peace,
        isCoreZone: Bool = false,
        generalAssignment: GeneralAssignment? = nil
    ) {
        self.id = id
        self.name = name
        self.faction = faction
        self.regionIds = regionIds.sorted { $0.rawValue < $1.rawValue }
        self.neighbors = neighbors.sorted { $0.rawValue < $1.rawValue }
        self.frontSegments = frontSegments.sorted {
            if $0.regionId.rawValue == $1.regionId.rawValue {
                return $0.neighborEnemyZone.rawValue < $1.neighborEnemyZone.rawValue
            }
            return $0.regionId.rawValue < $1.regionId.rawValue
        }
        self.unitsFront = unitsFront.sorted()
        self.unitsDepth = unitsDepth.sorted()
        self.unitsGarrison = unitsGarrison.sorted()
        self.pressure = max(0, pressure)
        self.state = state
        self.isCoreZone = isCoreZone
        self.generalAssignment = generalAssignment
    }
}
