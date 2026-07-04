import Foundation

struct WarDeploymentDiagnostics: Codable, Equatable {
    var scannedZoneCount: Int
    var scannedRegionCount: Int
    var assignedUnitCount: Int
    var updatedZoneIds: [FrontZoneId]

    init(
        scannedZoneCount: Int = 0,
        scannedRegionCount: Int = 0,
        assignedUnitCount: Int = 0,
        updatedZoneIds: [FrontZoneId] = []
    ) {
        self.scannedZoneCount = max(0, scannedZoneCount)
        self.scannedRegionCount = max(0, scannedRegionCount)
        self.assignedUnitCount = max(0, assignedUnitCount)
        self.updatedZoneIds = updatedZoneIds.sorted { $0.rawValue < $1.rawValue }
    }
}

struct WarDeploymentState: Codable, Equatable {
    var frontZones: [FrontZoneId: FrontZone]
    var hexToFrontZone: [HexCoord: FrontZoneId]
    var regionToFrontZone: [RegionId: FrontZoneId]
    var dirtyRegionIds: Set<RegionId>
    var lastUpdatedTurn: Int?
    var diagnostics: WarDeploymentDiagnostics

    private enum CodingKeys: String, CodingKey {
        case frontZones
        case hexToFrontZone
        case regionToFrontZone
        case dirtyRegionIds
        case lastUpdatedTurn
        case diagnostics
    }

    init(
        frontZones: [FrontZoneId: FrontZone] = [:],
        hexToFrontZone: [HexCoord: FrontZoneId] = [:],
        regionToFrontZone: [RegionId: FrontZoneId] = [:],
        dirtyRegionIds: Set<RegionId> = [],
        lastUpdatedTurn: Int? = nil,
        diagnostics: WarDeploymentDiagnostics = WarDeploymentDiagnostics()
    ) {
        self.frontZones = frontZones
        self.hexToFrontZone = hexToFrontZone
        self.regionToFrontZone = regionToFrontZone
        self.dirtyRegionIds = dirtyRegionIds
        self.lastUpdatedTurn = lastUpdatedTurn
        self.diagnostics = diagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frontZones = try container.decodeIfPresent([FrontZoneId: FrontZone].self, forKey: .frontZones) ?? [:]
        hexToFrontZone = try container.decodeIfPresent([HexCoord: FrontZoneId].self, forKey: .hexToFrontZone) ?? [:]
        regionToFrontZone = try container.decodeIfPresent([RegionId: FrontZoneId].self, forKey: .regionToFrontZone) ?? [:]
        dirtyRegionIds = try container.decodeIfPresent(Set<RegionId>.self, forKey: .dirtyRegionIds) ?? []
        lastUpdatedTurn = try container.decodeIfPresent(Int.self, forKey: .lastUpdatedTurn)
        diagnostics = try container.decodeIfPresent(WarDeploymentDiagnostics.self, forKey: .diagnostics) ?? WarDeploymentDiagnostics()
    }

    static var empty: WarDeploymentState {
        WarDeploymentState()
    }

    func zone(for regionId: RegionId) -> FrontZone? {
        guard let zoneId = regionToFrontZone[regionId] else { return nil }
        return frontZones[zoneId]
    }

    func zoneId(for hex: HexCoord, map: MapState) -> FrontZoneId? {
        if let zoneId = hexToFrontZone[hex] {
            return zoneId
        }
        guard let regionId = map.region(for: hex) else {
            return nil
        }
        return regionToFrontZone[regionId]
    }

    static func bootstrapFrontZones(
        from theaterState: TheaterState,
        map: MapState,
        divisions: [Division],
        turn: Int? = nil
    ) -> WarDeploymentState {
        WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: turn
        )
    }

    func preservingGeneralAssignments(from previous: WarDeploymentState) -> WarDeploymentState {
        var next = self
        for zoneId in next.frontZones.keys {
            guard let previousAssignment = previous.frontZones[zoneId]?.generalAssignment,
                  let zone = next.frontZones[zoneId] else {
                continue
            }
            let divisionIds = stableUnique(zone.unitsFront + zone.unitsDepth + zone.unitsGarrison)
            next.frontZones[zoneId]?.generalAssignment = previousAssignment.withAssignedDivisionIds(divisionIds)
        }
        return next
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result.sorted()
    }
}
