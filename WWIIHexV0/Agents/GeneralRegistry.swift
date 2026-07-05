import Foundation

struct GeneralCatalogDefinition: Codable, Equatable {
    let schemaVersion: Int
    let generals: [GeneralData]
}

struct GeneralData: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let localizedName: String
    let rank: String
    let faction: Faction
    let commandStyle: ZoneCommanderAgentConfig.CommandStyle
    let skills: [String]
    let portrait: String?
    let biography: String
    let preferredTheaterIds: [TheaterId]
    let preferredRegionIds: [RegionId]
    let baseLoyalty: Int
    let baseSatisfaction: Int

    init(
        id: String,
        name: String,
        localizedName: String,
        rank: String,
        faction: Faction,
        commandStyle: ZoneCommanderAgentConfig.CommandStyle,
        skills: [String],
        portrait: String? = nil,
        biography: String,
        preferredTheaterIds: [TheaterId] = [],
        preferredRegionIds: [RegionId] = [],
        baseLoyalty: Int = 70,
        baseSatisfaction: Int = 70
    ) {
        self.id = id
        self.name = name
        self.localizedName = localizedName
        self.rank = rank
        self.faction = faction
        self.commandStyle = commandStyle
        self.skills = skills.sorted()
        self.portrait = portrait
        self.biography = biography
        self.preferredTheaterIds = preferredTheaterIds.sorted { $0.rawValue < $1.rawValue }
        self.preferredRegionIds = preferredRegionIds.sorted { $0.rawValue < $1.rawValue }
        self.baseLoyalty = Self.clampPercent(baseLoyalty)
        self.baseSatisfaction = Self.clampPercent(baseSatisfaction)
    }

    func commanderConfig(zoneId: FrontZoneId) -> ZoneCommanderAgentConfig {
        ZoneCommanderAgentConfig(
            id: id,
            name: name,
            faction: faction,
            assignedZoneId: zoneId,
            skills: skills,
            commandStyle: commandStyle
        )
    }

    func defaultAssignment(hqRegionId: RegionId?, divisionIds: [String]) -> GeneralAssignment {
        GeneralAssignment(
            generalId: id,
            hqRegionId: hqRegionId,
            assignedDivisionIds: divisionIds,
            loyalty: baseLoyalty,
            satisfaction: baseSatisfaction
        )
    }

    private static func clampPercent(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}

struct GeneralRegistry: Equatable {
    let generalsById: [String: GeneralData]

    init(generals: [GeneralData]) {
        generalsById = Dictionary(uniqueKeysWithValues: generals.map { ($0.id, $0) })
    }

    static var empty: GeneralRegistry {
        GeneralRegistry(generals: [])
    }

    var allGenerals: [GeneralData] {
        generalsById.values.sorted { $0.id < $1.id }
    }

    func general(id: String?) -> GeneralData? {
        guard let id else {
            return nil
        }
        return generalsById[id]
    }

    func generals(for faction: Faction) -> [GeneralData] {
        allGenerals.filter { $0.faction == faction }
    }
}

struct GeneralDispatcher {
    let registry: GeneralRegistry

    init(registry: GeneralRegistry) {
        self.registry = registry
    }

    func assignGenerals(
        to deploymentState: WarDeploymentState,
        map: MapState,
        seedAssignments: [RegionId: String] = [:]
    ) -> WarDeploymentState {
        var next = deploymentState
        var usedGeneralIds: Set<String> = []
        var unassignedZoneIds: [FrontZoneId] = []

        let zones = next.frontZones.values.sorted { $0.id.rawValue < $1.id.rawValue }
        for zone in zones {
            guard var editableZone = next.frontZones[zone.id] else {
                continue
            }

            let divisionIds = unitIds(in: editableZone)
            if let current = editableZone.generalAssignment,
               let general = registry.general(id: current.generalId),
               general.faction == editableZone.faction,
               !usedGeneralIds.contains(current.generalId) {
                editableZone.generalAssignment = current.withAssignedDivisionIds(divisionIds)
                next.frontZones[zone.id] = editableZone
                usedGeneralIds.insert(current.generalId)
                continue
            }

            editableZone.generalAssignment = nil
            next.frontZones[zone.id] = editableZone
            unassignedZoneIds.append(zone.id)
        }

        for zoneId in unassignedZoneIds {
            guard var editableZone = next.frontZones[zoneId],
                  let general = seededGeneral(
                for: editableZone,
                seedAssignments: seedAssignments,
                usedGeneralIds: usedGeneralIds
            ) else {
                continue
            }

            let divisionIds = unitIds(in: editableZone)
            editableZone.generalAssignment = general.defaultAssignment(
                hqRegionId: hqRegion(for: editableZone, map: map),
                divisionIds: divisionIds
            )
            next.frontZones[zoneId] = editableZone
            usedGeneralIds.insert(general.id)
        }

        for zoneId in unassignedZoneIds {
            guard var editableZone = next.frontZones[zoneId],
                  editableZone.generalAssignment == nil,
                  let general = firstAvailableGeneral(for: editableZone, usedGeneralIds: usedGeneralIds) else {
                continue
            }

            editableZone.generalAssignment = general.defaultAssignment(
                hqRegionId: hqRegion(for: editableZone, map: map),
                divisionIds: unitIds(in: editableZone)
            )
            next.frontZones[zoneId] = editableZone
            usedGeneralIds.insert(general.id)
        }

        return next
    }

    func commanderPool(for state: GameState) -> TheaterCommanderPool {
        let commanders: [any ZoneCommanderProviding] = state.warDeploymentState.frontZones.values
            .compactMap { zone -> ZoneCommanderAgent? in
                guard let general = registry.general(id: zone.generalAssignment?.generalId),
                      general.faction == zone.faction else {
                    return nil
                }
                return ZoneCommanderAgent(config: general.commanderConfig(zoneId: zone.id))
            }
            .sorted { $0.config.assignedZoneId.rawValue < $1.config.assignedZoneId.rawValue }

        return TheaterCommanderPool(commanders: commanders)
    }

    func reassignGeneral(
        generalId: String,
        to zoneId: FrontZoneId,
        in deploymentState: WarDeploymentState,
        map: MapState
    ) -> WarDeploymentState {
        guard let general = registry.general(id: generalId),
              let targetZone = deploymentState.frontZones[zoneId],
              targetZone.faction == general.faction else {
            return deploymentState
        }

        var next = deploymentState
        for existingZoneId in next.frontZones.keys {
            if next.frontZones[existingZoneId]?.generalAssignment?.generalId == generalId {
                next.frontZones[existingZoneId]?.generalAssignment = nil
            }
        }

        guard var zone = next.frontZones[zoneId] else {
            return next
        }
        zone.generalAssignment = general.defaultAssignment(
            hqRegionId: hqRegion(for: zone, map: map),
            divisionIds: unitIds(in: zone)
        )
        next.frontZones[zoneId] = zone
        return next
    }

    func isHQUnderAttack(zone: FrontZone, map: MapState) -> Bool {
        guard let hqRegionId = zone.generalAssignment?.hqRegionId,
              let region = map.region(id: hqRegionId) else {
            return false
        }
        return region.controller != zone.faction
    }

    private func seededGeneral(
        for zone: FrontZone,
        seedAssignments: [RegionId: String],
        usedGeneralIds: Set<String>
    ) -> GeneralData? {
        let candidates = zone.regionIds.compactMap { seedAssignments[$0] }
        for generalId in candidates.sorted() {
            if let general = registry.general(id: generalId),
               general.faction == zone.faction,
               !usedGeneralIds.contains(general.id) {
                return general
            }
        }

        return registry.generals(for: zone.faction)
            .first { general in
                guard !usedGeneralIds.contains(general.id) else {
                    return false
                }
                return general.preferredTheaterIds.contains(TheaterId(zone.id.rawValue))
                    || !Set(general.preferredRegionIds).isDisjoint(with: Set(zone.regionIds))
            }
    }

    private func firstAvailableGeneral(
        for zone: FrontZone,
        usedGeneralIds: Set<String>
    ) -> GeneralData? {
        registry.generals(for: zone.faction)
            .first { !usedGeneralIds.contains($0.id) }
    }

    private func hqRegion(for zone: FrontZone, map: MapState) -> RegionId? {
        let regions = zone.regionIds.compactMap { map.region(id: $0) }
        let friendlyCities = regions
            .filter { $0.controller == zone.faction && $0.city != nil }
            .sorted { lhs, rhs in
                if lhs.supplyValue == rhs.supplyValue {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhs.supplyValue > rhs.supplyValue
            }
        if let city = friendlyCities.first {
            return city.id
        }

        return regions
            .sorted {
                if $0.displayHexes.count == $1.displayHexes.count {
                    return $0.id.rawValue < $1.id.rawValue
                }
                return $0.displayHexes.count > $1.displayHexes.count
            }
            .first?
            .id
    }

    private func unitIds(in zone: FrontZone) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for unitId in zone.unitsFront + zone.unitsDepth + zone.unitsGarrison where !seen.contains(unitId) {
            seen.insert(unitId)
            result.append(unitId)
        }
        return result.sorted()
    }
}
