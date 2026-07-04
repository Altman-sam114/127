import Foundation

struct TheaterId: Hashable, Codable, Equatable, RawRepresentable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    init(_ value: String) {
        self.rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum TheaterStatus: String, Codable, Equatable {
    case active
    case provisional
    case inactive
}

enum FixedTheaterKind: String, Codable, Equatable, CaseIterable {
    case northWest = "NorthWest"
    case northEast = "NorthEast"
    case southWest = "SouthWest"
    case southEast = "SouthEast"

    var id: TheaterId {
        TheaterId(rawValue)
    }
}

enum SpilloverPolicy: String, Codable, Equatable {
    case interfaceOnly
    case conservative
    case balanced
}

struct TheaterThreatNotification: Codable, Equatable, Identifiable {
    let id: String
    let theaterId: TheaterId
    let sourceRegionId: RegionId?
    let threatScore: Int
    let message: String

    init(
        id: String,
        theaterId: TheaterId,
        sourceRegionId: RegionId? = nil,
        threatScore: Int,
        message: String
    ) {
        self.id = id
        self.theaterId = theaterId
        self.sourceRegionId = sourceRegionId
        self.threatScore = max(0, threatScore)
        self.message = message
    }
}

struct TheaterSupportRequest: Codable, Equatable, Identifiable {
    let id: String
    let fromTheaterId: TheaterId
    let toTheaterId: TheaterId
    let availableUnitIds: [String]
    let policy: SpilloverPolicy
    let reason: String
}

struct TheaterAISummary: Codable, Equatable, Identifiable {
    let id: TheaterId
    let name: String
    let status: TheaterStatus
    let regionIds: [RegionId]
    let controllingFaction: Faction?
    let controlRatios: [Faction: Double]
    let threatScore: Int
    let unitCount: Int
}

struct TheaterNode: Codable, Equatable, Identifiable {
    let id: TheaterId
    var name: String
    var status: TheaterStatus
    var regionIds: [RegionId]
    var neighborTheaterIds: [TheaterId]
    var controllingFaction: Faction?
    var controlRatios: [Faction: Double]
    var victoryPointArea: Int
    var frontWeight: Int
    var unitIds: [String]
    var supportEligibleUnitIds: [String]
    var spilloverPolicy: SpilloverPolicy
    var recentThreats: [TheaterThreatNotification]

    init(
        id: TheaterId,
        name: String,
        status: TheaterStatus = .active,
        regionIds: [RegionId] = [],
        neighborTheaterIds: [TheaterId] = [],
        controllingFaction: Faction? = nil,
        controlRatios: [Faction: Double] = [:],
        victoryPointArea: Int = 0,
        frontWeight: Int = 0,
        unitIds: [String] = [],
        supportEligibleUnitIds: [String] = [],
        spilloverPolicy: SpilloverPolicy = .interfaceOnly,
        recentThreats: [TheaterThreatNotification] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.regionIds = regionIds
        self.neighborTheaterIds = neighborTheaterIds
        self.controllingFaction = controllingFaction
        self.controlRatios = controlRatios
        self.victoryPointArea = max(0, victoryPointArea)
        self.frontWeight = max(0, frontWeight)
        self.unitIds = unitIds
        self.supportEligibleUnitIds = supportEligibleUnitIds
        self.spilloverPolicy = spilloverPolicy
        self.recentThreats = recentThreats
    }
}

struct TheaterState: Codable, Equatable {
    var initialSnapshot: TheaterInitialSnapshot?
    var theaters: [TheaterId: TheaterNode]
    /// Runtime dynamic theater ownership at hex granularity. `regionToTheater`
    /// remains the immutable basic theater layout after bootstrap.
    var hexToTheater: [HexCoord: TheaterId]
    var regionToTheater: [RegionId: TheaterId]
    var lastUpdatedTurn: Int?

    private enum CodingKeys: String, CodingKey {
        case initialSnapshot
        case theaters
        case hexToTheater
        case regionToTheater
        case lastUpdatedTurn
    }

    init(
        initialSnapshot: TheaterInitialSnapshot? = nil,
        theaters: [TheaterId: TheaterNode] = [:],
        hexToTheater: [HexCoord: TheaterId] = [:],
        regionToTheater: [RegionId: TheaterId] = [:],
        lastUpdatedTurn: Int? = nil
    ) {
        self.initialSnapshot = initialSnapshot
        self.theaters = theaters
        self.hexToTheater = hexToTheater
        self.regionToTheater = regionToTheater
        self.lastUpdatedTurn = lastUpdatedTurn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        initialSnapshot = try container.decodeIfPresent(TheaterInitialSnapshot.self, forKey: .initialSnapshot)
        theaters = try container.decodeIfPresent([TheaterId: TheaterNode].self, forKey: .theaters) ?? [:]
        hexToTheater = try container.decodeIfPresent([HexCoord: TheaterId].self, forKey: .hexToTheater) ?? [:]
        regionToTheater = try container.decodeIfPresent([RegionId: TheaterId].self, forKey: .regionToTheater) ?? [:]
        lastUpdatedTurn = try container.decodeIfPresent(Int.self, forKey: .lastUpdatedTurn)
    }

    static var empty: TheaterState {
        TheaterState()
    }

    func theater(for regionId: RegionId) -> TheaterNode? {
        guard let theaterId = regionToTheater[regionId] else { return nil }
        return theaters[theaterId]
    }

    func dynamicTheaterId(for hex: HexCoord, map: MapState) -> TheaterId? {
        if let theaterId = hexToTheater[hex] {
            return theaterId
        }
        guard let regionId = map.region(for: hex) else {
            return nil
        }
        return regionToTheater[regionId]
    }

    func dominantDynamicTheaterId(for regionId: RegionId, map: MapState) -> TheaterId? {
        guard let region = map.region(id: regionId) else {
            return regionToTheater[regionId]
        }

        var counts: [TheaterId: Int] = [:]
        for hex in region.displayHexes {
            if let theaterId = dynamicTheaterId(for: hex, map: map) {
                counts[theaterId, default: 0] += 1
            }
        }
        return counts.max {
            $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value
        }?.key ?? regionToTheater[regionId]
    }
}

struct TheaterInitialSnapshot: Codable, Equatable {
    let theaters: [TheaterId: TheaterNode]
    let regionToTheater: [RegionId: TheaterId]

    init(theaters: [TheaterId: TheaterNode], regionToTheater: [RegionId: TheaterId]) {
        self.theaters = theaters
        self.regionToTheater = regionToTheater
    }

    static func capture(from state: TheaterState) -> TheaterInitialSnapshot {
        TheaterInitialSnapshot(
            theaters: state.theaters,
            regionToTheater: state.regionToTheater
        )
    }
}

enum TheaterTransition: Codable, Equatable {
    case none
    case provisional(theaterId: TheaterId, ratio: Double)
    case formalized(theaterId: TheaterId, faction: Faction, ratio: Double)
    case retired(theaterId: TheaterId)
}

struct TheaterExpansionResult: Codable, Equatable {
    let state: TheaterState
    let transition: TheaterTransition
    let affectedTheaterId: TheaterId?
}
