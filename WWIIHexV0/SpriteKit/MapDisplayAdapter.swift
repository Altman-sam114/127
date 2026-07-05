import SpriteKit

typealias DisplayColor = SKColor

enum VisibilityState: Equatable {
    case unseen
    case explored
    case visible
}

struct HexDisplayState {
    let coord: HexCoord
    let regionId: RegionId?
    let terrain: BaseTerrain
    let controller: Faction?
    let cityName: String?
    let fortressName: String?
    let isRepresentative: Bool
    let visibility: VisibilityState
}

struct UnitDisplayPlacement: Equatable {
    let divisionId: String
    let hex: HexCoord
    let offset: CGPoint
    let stackIndex: Int
    let stackCount: Int
}

extension UnitDisplayPlacement {
    static func == (lhs: UnitDisplayPlacement, rhs: UnitDisplayPlacement) -> Bool {
        lhs.divisionId == rhs.divisionId &&
            lhs.hex == rhs.hex &&
            lhs.offset.x == rhs.offset.x &&
            lhs.offset.y == rhs.offset.y &&
            lhs.stackIndex == rhs.stackIndex &&
            lhs.stackCount == rhs.stackCount
    }
}

struct VisibleContactDisplay: Equatable {
    let id: String
    let lastKnownCoord: HexCoord
    let confidence: ContactConfidence
    let estimatedType: EstimatedContactType
    let source: ContactSource
    let ageInTurns: Int
}

struct RegionInspectorState: Equatable {
    let region: RegionNode
    let selectedHex: HexCoord?
    let selectedHexController: Faction?
    let selectedHexDynamicTheaterId: TheaterId?
    let selectedHexFrontZoneId: FrontZoneId?
    let theaterId: TheaterId?
    let frontZoneId: FrontZoneId?
    let frontPressure: Double
    let friendlyDivisions: [Division]
    let visibleContacts: [VisibleContactDisplay]
    let objectiveNames: [String]
    let objectiveStatus: String
    let cityLevel: CityLevel
    let economicOutput: EconomyResources
}

struct UnitInspectorStrategicState: Equatable {
    let coord: HexCoord
    let regionId: RegionId?
    let dynamicTheaterId: TheaterId?
    let frontLineIds: [FrontLineId]
    let frontZoneId: FrontZoneId?
    let deploymentRole: UnitDeploymentRole
}

struct MapDisplayAdapter {
    let state: GameState
    let revealAll: Bool

    init(state: GameState, revealAll: Bool = false) {
        self.state = state
        self.revealAll = revealAll
    }

    func regionId(for hex: HexCoord) -> RegionId? {
        state.map.region(for: hex)
    }

    func displayHexes(for regionId: RegionId) -> [HexCoord] {
        state.map.region(id: regionId)?.displayHexes ?? []
    }

    func representativeHex(for regionId: RegionId) -> HexCoord? {
        state.map.representativeHex(for: regionId)
    }

    func terrainColor(for hex: HexCoord) -> DisplayColor {
        TerrainStyle.fillColor(for: terrain(for: hex))
    }

    func controllerColor(for hex: HexCoord) -> DisplayColor {
        TerrainStyle.controllerColor(for: controller(for: hex))
    }

    func unitDisplayHex(for division: Division) -> HexCoord? {
        division.coord
    }

    func visibility(for hex: HexCoord, faction: Faction) -> VisibilityState {
        if revealAll {
            return .visible
        }
        guard !state.map.regions.isEmpty,
              let regionId = regionId(for: hex) else {
            return .visible
        }

        let visibleRegions = RegionVisibilityRules().visibleRegions(for: faction, in: state)
        return visibleRegions.contains(regionId) ? .visible : .unseen
    }

    func hexDisplayState(for hex: HexCoord, viewerFaction: Faction) -> HexDisplayState? {
        guard state.map.contains(hex) else {
            return nil
        }

        let regionId = regionId(for: hex)
        let region = regionId.flatMap { state.map.region(id: $0) }
        let tile = state.map.tile(at: hex)
        let terrain = tile?.baseTerrain ?? region?.terrain ?? .plain
        let cityName = tile?.cityName ?? (hex == region?.representativeHex ? region?.city?.name : nil)
        let fortressName = tile?.fortressName

        return HexDisplayState(
            coord: hex,
            regionId: regionId,
            terrain: terrain,
            controller: tile?.controller ?? region?.controller,
            cityName: cityName,
            fortressName: fortressName,
            isRepresentative: hex == region?.representativeHex,
            visibility: visibility(for: hex, faction: viewerFaction)
        )
    }

    func unitPlacements(viewerFaction: Faction) -> [String: UnitDisplayPlacement] {
        let visibleDivisions = state.divisions.filter { isDivisionVisible($0, viewerFaction: viewerFaction) }
        let grouped = Dictionary(grouping: visibleDivisions) { division in
            unitDisplayHex(for: division) ?? division.coord
        }

        var placements: [String: UnitDisplayPlacement] = [:]
        for (hex, divisions) in grouped {
            let sorted = divisions.sorted { lhs, rhs in
                lhs.id < rhs.id
            }
            for (index, division) in sorted.enumerated() {
                placements[division.id] = UnitDisplayPlacement(
                    divisionId: division.id,
                    hex: hex,
                    offset: stackOffset(index: index, count: sorted.count),
                    stackIndex: index,
                    stackCount: sorted.count
                )
            }
        }
        return placements
    }

    func divisions(displayedAt hex: HexCoord, viewerFaction: Faction) -> [Division] {
        let placements = unitPlacements(viewerFaction: viewerFaction)
        return state.divisions
            .filter { placements[$0.id]?.hex == hex }
            .sorted { lhs, rhs in
                if lhs.faction == viewerFaction, rhs.faction != viewerFaction {
                    return true
                }
                if lhs.faction != viewerFaction, rhs.faction == viewerFaction {
                    return false
                }
                return lhs.id < rhs.id
            }
    }

    func isDivisionVisible(_ division: Division, viewerFaction: Faction) -> Bool {
        if revealAll {
            return true
        }

        if division.faction == viewerFaction {
            return true
        }

        return false
    }

    func inspectorState(for regionId: RegionId, selectedHex: HexCoord? = nil, viewerFaction: Faction) -> RegionInspectorState? {
        guard let region = state.map.region(id: regionId) else {
            return nil
        }

        let divisions = state.divisions.filter { division in
            division.location(in: state.map) == regionId
        }
        let friendly = divisions.filter { $0.faction == viewerFaction }
        let visibleContacts = contactDisplays(for: regionId, viewerFaction: viewerFaction)
        let objectiveNames = state.map.objectives
            .filter { objective in
                region.displayHexes.contains(objective.coord)
            }
            .map(\.name)
        let objectiveStatus = objectiveNames.isEmpty
            ? "None"
            : "\(region.controller.displayName) controlled"

        let cityLevel = EconomyRules().cityLevel(for: region, map: state.map)
        let economicOutput = regionalEconomicOutput(for: region, cityLevel: cityLevel)

        return RegionInspectorState(
            region: region,
            selectedHex: selectedHex,
            selectedHexController: selectedHex.flatMap { state.map.tile(at: $0)?.controller },
            selectedHexDynamicTheaterId: selectedHex.flatMap { state.theaterState.dynamicTheaterId(for: $0, map: state.map) },
            selectedHexFrontZoneId: selectedHex.flatMap { state.warDeploymentState.zoneId(for: $0, map: state.map) },
            theaterId: state.theaterState.dominantDynamicTheaterId(for: regionId, map: state.map),
            frontZoneId: dominantDynamicFrontZoneId(for: regionId),
            frontPressure: state.frontLineState.regionStates[regionId]?.frontLines
                .flatMap(\.segments)
                .map(\.pressureLevel)
                .max() ?? 0,
            friendlyDivisions: friendly,
            visibleContacts: visibleContacts,
            objectiveNames: objectiveNames,
            objectiveStatus: objectiveStatus,
            cityLevel: cityLevel,
            economicOutput: economicOutput
        )
    }

    private func contactDisplays(for regionId: RegionId, viewerFaction: Faction) -> [VisibleContactDisplay] {
        state.operationalAwareness.visibleContacts(for: viewerFaction)
            .filter { contact in
                state.map.region(for: contact.lastKnownCoord) == regionId
            }
            .map { contact in
                VisibleContactDisplay(
                    id: contact.id,
                    lastKnownCoord: contact.lastKnownCoord,
                    confidence: contact.confidence,
                    estimatedType: contact.estimatedType,
                    source: contact.source,
                    ageInTurns: contact.ageInTurns
                )
            }
    }

    func unitInspectorState(for division: Division) -> UnitInspectorStrategicState {
        let regionId = division.location(in: state.map)
        let frontLineIds = regionId
            .flatMap { state.frontLineState.regionStates[$0]?.frontLines.map(\.id) } ?? []
        return UnitInspectorStrategicState(
            coord: division.coord,
            regionId: regionId,
            dynamicTheaterId: state.theaterState.dynamicTheaterId(for: division.coord, map: state.map),
            frontLineIds: frontLineIds.sorted { $0.rawValue < $1.rawValue },
            frontZoneId: state.warDeploymentState.zoneId(for: division.coord, map: state.map),
            deploymentRole: WarDeploymentManager().deploymentRole(
                for: division,
                in: state.map,
                state: state.warDeploymentState
            )
        )
    }

    private func dominantDynamicFrontZoneId(for regionId: RegionId) -> FrontZoneId? {
        guard let region = state.map.region(id: regionId) else {
            return state.warDeploymentState.regionToFrontZone[regionId]
        }
        var counts: [FrontZoneId: Int] = [:]
        for hex in region.displayHexes {
            if let zoneId = state.warDeploymentState.zoneId(for: hex, map: state.map) {
                counts[zoneId, default: 0] += 1
            }
        }
        return counts.max {
            $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value
        }?.key ?? state.warDeploymentState.regionToFrontZone[regionId]
    }

    private func terrain(for hex: HexCoord) -> BaseTerrain {
        if let regionId = regionId(for: hex),
           let region = state.map.region(id: regionId) {
            return region.terrain
        }
        return state.map.tile(at: hex)?.baseTerrain ?? .plain
    }

    private func controller(for hex: HexCoord) -> Faction? {
        if let regionId = regionId(for: hex),
           let region = state.map.region(id: regionId) {
            return region.controller
        }
        return state.map.tile(at: hex)?.controller
    }

    private func regionalEconomicOutput(for region: RegionNode, cityLevel: CityLevel) -> EconomyResources {
        let coreBonus = region.coreOf.isEmpty || region.coreOf.contains(region.controller) ? 1 : 0
        return EconomyResources(
            manpower: max(1, cityLevel.manpowerGrowth + coreBonus * 4 + region.infrastructure),
            industry: max(0, region.factories + cityLevel.industryValue + region.infrastructure / 3),
            supplies: max(1, region.supplyValue * 3 + region.factories + region.infrastructure / 2)
        )
    }

    private func stackOffset(index: Int, count: Int) -> CGPoint {
        guard count > 1 else {
            return .zero
        }

        let offsets: [CGPoint] = [
            CGPoint(x: -10, y: 8),
            CGPoint(x: 10, y: -8),
            CGPoint(x: -10, y: -8),
            CGPoint(x: 10, y: 8)
        ]
        return offsets[index % offsets.count]
    }
}
