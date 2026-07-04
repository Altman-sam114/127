import Foundation

struct WarDeploymentManager {
    func makeInitialState(
        map: MapState,
        theaterState: TheaterState,
        divisions: [Division],
        turn: Int? = nil
    ) -> WarDeploymentState {
        var zones: [FrontZoneId: FrontZone] = [:]
        var hexToZone: [HexCoord: FrontZoneId] = [:]
        var regionToZone: [RegionId: FrontZoneId] = [:]

        for theater in theaterState.theaters.values where theater.status != .inactive {
            guard let faction = theaterState.initialSnapshot?.theaters[theater.id]?.controllingFaction
                ?? faction(for: theater, map: map) else { continue }
            let zoneId = FrontZoneId(theater.id.rawValue)
            zones[zoneId] = FrontZone(
                id: zoneId,
                name: theater.name,
                faction: faction,
                regionIds: theater.regionIds,
                isCoreZone: theater.frontWeight == 0
            )
            for regionId in theater.regionIds {
                if regionToZone[regionId] == nil {
                    regionToZone[regionId] = zoneId
                }
                if let region = map.region(id: regionId) {
                    for hex in region.displayHexes {
                        hexToZone[hex] = FrontZoneId(theaterState.dynamicTheaterId(for: hex, map: map)?.rawValue ?? zoneId.rawValue)
                    }
                }
            }
        }

        return rebuild(
            zones: zones,
            hexToZone: hexToZone,
            regionToZone: regionToZone,
            map: map,
            divisions: divisions,
            turn: turn,
            updatedZoneIds: Set(zones.keys)
        )
    }

    func update(
        state: WarDeploymentState,
        map: MapState,
        divisions: [Division],
        turn: Int,
        events: [WarDeploymentEvent] = []
    ) -> WarDeploymentState {
        let dirtyRegions = dirtyRegions(from: events, state: state)
        guard !dirtyRegions.isEmpty else {
            var next = state
            next.lastUpdatedTurn = turn
            next.diagnostics = WarDeploymentDiagnostics()
            return next
        }

        let zoneIds = zoneIds(touching: dirtyRegions, state: state, map: map)
        return rebuild(
            zones: state.frontZones,
            hexToZone: state.hexToFrontZone,
            regionToZone: state.regionToFrontZone,
            map: map,
            divisions: divisions,
            turn: turn,
            updatedZoneIds: zoneIds
        )
    }

    func advanceRegion(
        _ regionId: RegionId,
        from defeatedZoneId: FrontZoneId,
        to advancingZoneId: FrontZoneId,
        state: WarDeploymentState,
        map: MapState,
        divisions: [Division],
        turn: Int
    ) -> WarDeploymentState {
        guard let breakthroughHex = map.region(id: regionId)?.representativeHex else {
            return state
        }

        return advanceHex(
            breakthroughHex,
            from: defeatedZoneId,
            to: advancingZoneId,
            state: state,
            map: map,
            divisions: divisions,
            turn: turn
        )
    }

    func advanceHex(
        _ hex: HexCoord,
        from defeatedZoneId: FrontZoneId?,
        to advancingZoneId: FrontZoneId,
        state: WarDeploymentState,
        map: MapState,
        divisions: [Division],
        turn: Int
    ) -> WarDeploymentState {
        guard state.frontZones[advancingZoneId] != nil,
              let regionId = map.region(for: hex) else {
            return state
        }

        var zones = state.frontZones
        var hexToZone = state.hexToFrontZone
        var regionToZone = state.regionToFrontZone

        if zones[advancingZoneId]?.regionIds.contains(regionId) != true {
            zones[advancingZoneId]?.regionIds.append(regionId)
            zones[advancingZoneId]?.regionIds.sort { $0.rawValue < $1.rawValue }
        }
        regionToZone[regionId] = dominantZoneId(for: regionId, hexOverride: (hex, advancingZoneId), hexToZone: hexToZone, fallback: regionToZone[regionId], map: map)
        hexToZone[hex] = advancingZoneId

        if let defeatedZoneId,
           let defeatedRegionIds = zones[defeatedZoneId]?.regionIds,
           defeatedRegionIds.contains(regionId),
           !regionStillHasHex(regionId, zoneId: defeatedZoneId, hexToZone: hexToZone, map: map) {
            zones[defeatedZoneId]?.regionIds.removeAll { $0 == regionId }
        }

        if let defeatedZoneId,
           zones[defeatedZoneId] != nil,
           !hexToZone.values.contains(defeatedZoneId) {
            zones.removeValue(forKey: defeatedZoneId)
            regionToZone = regionToZone.filter { $0.value != defeatedZoneId }
        }

        let touched = Set([advancingZoneId, defeatedZoneId].compactMap { $0 })
            .union(zoneIds(around: [regionId], hexToZone: hexToZone, regionToZone: regionToZone, map: map))
        return rebuild(
            zones: zones,
            hexToZone: hexToZone,
            regionToZone: regionToZone,
            map: map,
            divisions: divisions,
            turn: turn,
            updatedZoneIds: touched
        )
    }

    func collapseFront(
        zoneId: FrontZoneId,
        state: WarDeploymentState,
        map: MapState,
        divisions: [Division],
        turn: Int
    ) -> WarDeploymentState {
        guard let zone = state.frontZones[zoneId],
              zone.state == .totalWar || zone.pressure > zone.regionIds.count else {
            return state
        }

        let depthZoneIds = friendlyDepthZones(for: zoneId, in: state)
        guard !depthZoneIds.isEmpty else {
            return state
        }

        var zones = state.frontZones
        zones[zoneId]?.state = .highIntensity
        for depthZoneId in depthZoneIds {
            zones[depthZoneId]?.state = .highIntensity
        }

        return rebuild(
            zones: zones,
            hexToZone: state.hexToFrontZone,
            regionToZone: state.regionToFrontZone,
            map: map,
            divisions: divisions,
            turn: turn,
            updatedZoneIds: Set([zoneId]).union(depthZoneIds)
        )
    }

    func deploymentRole(for division: Division, in map: MapState, state: WarDeploymentState) -> UnitDeploymentRole {
        if let role = listedDeploymentRole(for: division.id, state: state) {
            return role
        }

        guard let regionId = division.location(in: map),
              let zoneId = state.zoneId(for: division.coord, map: map),
              let zone = state.frontZones[zoneId] else {
            return .depthUnit
        }

        if zone.unitsFront.contains(division.id) {
            return .frontUnit
        }

        if zone.unitsDepth.contains(division.id) {
            return .depthUnit
        }

        if zone.unitsGarrison.contains(division.id) {
            return .garrisonUnit
        }

        if hexTouchesEnemyZone(
            hex: division.coord,
            zoneId: zoneId,
            faction: zone.faction,
            zones: state.frontZones,
            hexToZone: state.hexToFrontZone,
            map: map
        ) || map.tile(at: division.coord)?.controller != zone.faction {
            return .frontUnit
        }

        if zone.isCoreZone || regionHasCityOrFactory(regionId, map: map) {
            return .garrisonUnit
        }

        return .depthUnit
    }

    private func listedDeploymentRole(for divisionId: String, state: WarDeploymentState) -> UnitDeploymentRole? {
        for zone in state.frontZones.values {
            if zone.unitsFront.contains(divisionId) {
                return .frontUnit
            }
            if zone.unitsDepth.contains(divisionId) {
                return .depthUnit
            }
            if zone.unitsGarrison.contains(divisionId) {
                return .garrisonUnit
            }
        }
        return nil
    }

    private func rebuild(
        zones: [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState,
        divisions: [Division],
        turn: Int?,
        updatedZoneIds: Set<FrontZoneId>
    ) -> WarDeploymentState {
        var nextZones = zones
        let scopedZoneIds = Set(updatedZoneIds.filter { nextZones[$0] != nil })
        rebuildNeighbors(zones: &nextZones, hexToZone: hexToZone, regionToZone: regionToZone, map: map, scopeZoneIds: scopedZoneIds)
        rebuildSegments(
            zones: &nextZones,
            hexToZone: hexToZone,
            regionToZone: regionToZone,
            map: map,
            divisions: divisions,
            scopeZoneIds: scopedZoneIds
        )
        assignUnits(zones: &nextZones, hexToZone: hexToZone, regionToZone: regionToZone, map: map, divisions: divisions, scopeZoneIds: scopedZoneIds)

        let scannedRegionCount = scopedZoneIds.reduce(0) { total, zoneId in
            total + (nextZones[zoneId]?.regionIds.count ?? 0)
        }
        let assignedUnitCount = scopedZoneIds.reduce(0) {
            $0
                + (nextZones[$1]?.unitsFront.count ?? 0)
                + (nextZones[$1]?.unitsDepth.count ?? 0)
                + (nextZones[$1]?.unitsGarrison.count ?? 0)
        }

        return WarDeploymentState(
            frontZones: nextZones,
            hexToFrontZone: hexToZone.filter { nextZones[$0.value] != nil },
            regionToFrontZone: regionToZone.filter { nextZones[$0.value] != nil },
            dirtyRegionIds: [],
            lastUpdatedTurn: turn,
            diagnostics: WarDeploymentDiagnostics(
                scannedZoneCount: scopedZoneIds.count,
                scannedRegionCount: scannedRegionCount,
                assignedUnitCount: assignedUnitCount,
                updatedZoneIds: Array(scopedZoneIds)
            )
        )
    }

    private func rebuildNeighbors(
        zones: inout [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState,
        scopeZoneIds: Set<FrontZoneId>
    ) {
        for zoneId in scopeZoneIds {
            guard let zone = zones[zoneId] else { continue }
            var neighbors: Set<FrontZoneId> = []
            for regionId in zone.regionIds {
                guard let region = map.region(id: regionId) else { continue }
                for hex in region.displayHexes where hexToZone[hex] == zoneId {
                    for neighborHex in hex.neighbors {
                        guard map.tile(at: neighborHex) != nil,
                              let neighborZoneId = hexToZone[neighborHex],
                          neighborZoneId != zoneId,
                          zones[neighborZoneId] != nil else {
                        continue
                        }
                        neighbors.insert(neighborZoneId)
                    }
                }
            }
            zones[zoneId]?.neighbors = neighbors.sorted { $0.rawValue < $1.rawValue }
        }
    }

    private func rebuildSegments(
        zones: inout [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState,
        divisions: [Division],
        scopeZoneIds: Set<FrontZoneId>
    ) {
        for zoneId in scopeZoneIds {
            guard let zone = zones[zoneId] else { continue }
            var segmentsByRegion: [RegionId: FrontZoneSegment] = [:]

            for regionId in zone.regionIds {
                let enemyZoneIds = enemyZoneIdsTouching(
                    regionId: regionId,
                    zoneId: zoneId,
                    faction: zone.faction,
                    zones: zones,
                    hexToZone: hexToZone,
                    map: map
                )

                let hasEnemyPresence = divisions.contains { division in
                    guard !division.isDestroyed,
                          division.faction != zone.faction else {
                        return false
                    }
                    return division.location(in: map) == regionId
                }

                if (map.regions[regionId]?.controller != zone.faction || hasEnemyPresence),
                   let ownerZoneId = enemyZoneIds.sorted(by: { $0.rawValue < $1.rawValue }).first {
                    segmentsByRegion[regionId] = FrontZoneSegment(
                        regionId: regionId,
                        neighborEnemyZone: ownerZoneId,
                        strength: strength(in: regionId, for: zone.faction, map: map),
                        isEncircled: false
                    )
                    continue
                }

                guard let enemyZoneId = enemyZoneIds.sorted(by: { $0.rawValue < $1.rawValue }).first else {
                    continue
                }

                let strength = strength(in: regionId, for: zone.faction, map: map)
                let encircled = isEncircledEnemyContact(
                    from: regionId,
                    zoneId: zoneId,
                    enemyZoneId: enemyZoneId,
                    zones: zones,
                    hexToZone: hexToZone,
                    regionToZone: regionToZone,
                    map: map
                )
                segmentsByRegion[regionId] = FrontZoneSegment(
                    regionId: regionId,
                    neighborEnemyZone: enemyZoneId,
                    strength: strength,
                    isEncircled: encircled
                )
            }

            let segments = segmentsByRegion.values.sorted {
                $0.regionId.rawValue < $1.regionId.rawValue
            }
            let pressure = segments.reduce(0) { $0 + max(1, $1.strength) }
            zones[zoneId]?.frontSegments = segments
            zones[zoneId]?.pressure = pressure
            zones[zoneId]?.state = warState(segmentCount: segments.count, pressure: pressure)
        }
    }

    private func assignUnits(
        zones: inout [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState,
        divisions: [Division],
        scopeZoneIds: Set<FrontZoneId>
    ) {
        for zoneId in scopeZoneIds {
            zones[zoneId]?.unitsFront = []
            zones[zoneId]?.unitsDepth = []
            zones[zoneId]?.unitsGarrison = []
            let resetSegments: [FrontZoneSegment] = zones[zoneId]?.frontSegments.map {
                var segment = $0
                segment.assignedFrontUnitIds = []
                return segment
            } ?? []
            zones[zoneId]?.frontSegments = resetSegments
        }

        for division in divisions where !division.isDestroyed {
            guard let regionId = division.location(in: map),
                  let zoneId = hexToZone[division.coord] ?? regionToZone[regionId],
                  let zone = zones[zoneId] else {
                continue
            }

            let assignedZoneId: FrontZoneId
            if zone.faction == division.faction {
                assignedZoneId = zoneId
            } else if let friendlyZoneId = friendlyZoneTouching(regionId: regionId, faction: division.faction, zones: zones, hexToZone: hexToZone, regionToZone: regionToZone, map: map) {
                assignedZoneId = friendlyZoneId
            } else if let fallbackZoneId = primaryCombatZone(for: division.faction, zones: zones) {
                assignedZoneId = fallbackZoneId
            } else {
                continue
            }

            guard scopeZoneIds.contains(assignedZoneId),
                  let assignedZone = zones[assignedZoneId] else {
                continue
            }

            let isHostileContact = hexTouchesEnemyZone(
                hex: division.coord,
                zoneId: assignedZoneId,
                faction: assignedZone.faction,
                zones: zones,
                hexToZone: hexToZone,
                map: map
            )
            let isInsideEnemyDynamicZone = assignedZoneId != zoneId
            let isOnEnemyControlledHex = map.tile(at: division.coord)?.controller != assignedZone.faction
            if isHostileContact || isInsideEnemyDynamicZone || isOnEnemyControlledHex {
                appendFrontUnit(division.id, to: assignedZoneId, zones: &zones)
            } else if assignedZone.isCoreZone || regionHasCityOrFactory(regionId, map: map) {
                zones[assignedZoneId]?.unitsGarrison.append(division.id)
            } else {
                zones[assignedZoneId]?.unitsDepth.append(division.id)
            }
        }

        for zoneId in scopeZoneIds {
            zones[zoneId]?.unitsFront.sort()
            zones[zoneId]?.unitsDepth.sort()
            zones[zoneId]?.unitsGarrison.sort()
            let sortedSegments: [FrontZoneSegment] = zones[zoneId]?.frontSegments.map {
                var segment = $0
                segment.assignedFrontUnitIds.sort()
                return segment
            } ?? []
            zones[zoneId]?.frontSegments = sortedSegments
        }
    }

    private func appendFrontUnit(_ unitId: String, to zoneId: FrontZoneId, zones: inout [FrontZoneId: FrontZone]) {
        guard var zone = zones[zoneId], !zone.frontSegments.isEmpty else {
            return
        }

        var targetIndex = 0
        for index in zone.frontSegments.indices {
            if zone.frontSegments[index].assignedFrontUnitIds.count < zone.frontSegments[targetIndex].assignedFrontUnitIds.count {
                targetIndex = index
            }
        }

        zone.unitsFront.append(unitId)
        zone.frontSegments[targetIndex].assignedFrontUnitIds.append(unitId)
        zones[zoneId] = zone
    }

    private func friendlyZoneTouching(
        regionId: RegionId,
        faction: Faction,
        zones: [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState
    ) -> FrontZoneId? {
        dynamicNeighborZoneIds(regionId: regionId, hexToZone: hexToZone, regionToZone: regionToZone, map: map)
            .filter { zones[$0]?.faction == faction }
            .sorted { $0.rawValue < $1.rawValue }
            .first
    }

    private func primaryCombatZone(
        for faction: Faction,
        zones: [FrontZoneId: FrontZone]
    ) -> FrontZoneId? {
        let factionZones = zones.values
            .filter { $0.faction == faction }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        return factionZones.first { !$0.frontSegments.isEmpty }?.id ?? factionZones.first?.id
    }

    private func enemyZoneIdsTouching(
        regionId: RegionId,
        zoneId: FrontZoneId,
        faction: Faction,
        zones: [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        map: MapState
    ) -> Set<FrontZoneId> {
        guard let region = map.region(id: regionId) else {
            return []
        }

        var enemyZoneIds: Set<FrontZoneId> = []
        for hex in region.displayHexes where hexToZone[hex] == zoneId {
            for neighborHex in hex.neighbors {
                guard map.tile(at: neighborHex) != nil,
                      let enemyZoneId = hexToZone[neighborHex],
                      enemyZoneId != zoneId,
                      zones[enemyZoneId]?.faction != faction else {
                    continue
                }
                enemyZoneIds.insert(enemyZoneId)
            }
        }
        return enemyZoneIds
    }

    private func dynamicNeighborZoneIds(
        regionId: RegionId,
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState
    ) -> Set<FrontZoneId> {
        var zoneIds: Set<FrontZoneId> = []
        if let region = map.region(id: regionId) {
            for hex in region.displayHexes {
                if let zoneId = hexToZone[hex] {
                    zoneIds.insert(zoneId)
                }
                for neighborHex in hex.neighbors {
                    guard map.tile(at: neighborHex) != nil else {
                        continue
                    }
                    if let zoneId = hexToZone[neighborHex] {
                        zoneIds.insert(zoneId)
                    } else if let neighborRegionId = map.region(for: neighborHex),
                              let zoneId = regionToZone[neighborRegionId] {
                        zoneIds.insert(zoneId)
                    }
                }
            }
        }
        return zoneIds
    }

    private func dominantZoneId(
        for regionId: RegionId,
        hexOverride: (HexCoord, FrontZoneId)?,
        hexToZone: [HexCoord: FrontZoneId],
        fallback: FrontZoneId?,
        map: MapState
    ) -> FrontZoneId? {
        guard let region = map.region(id: regionId) else {
            return fallback
        }

        var counts: [FrontZoneId: Int] = [:]
        for hex in region.displayHexes {
            let zoneId = hexOverride?.0 == hex ? hexOverride?.1 : hexToZone[hex]
            if let zoneId {
                counts[zoneId, default: 0] += 1
            }
        }
        return counts.max {
            $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value
        }?.key ?? fallback
    }

    private func regionStillHasHex(
        _ regionId: RegionId,
        zoneId: FrontZoneId,
        hexToZone: [HexCoord: FrontZoneId],
        map: MapState
    ) -> Bool {
        guard let region = map.region(id: regionId) else {
            return false
        }
        return region.displayHexes.contains { hexToZone[$0] == zoneId }
    }

    private func regionTouchesEnemyZone(
        regionId: RegionId,
        zoneId: FrontZoneId,
        zones: [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState
    ) -> Bool {
        guard let faction = zones[zoneId]?.faction else {
            return false
        }

        return dynamicNeighborZoneIds(regionId: regionId, hexToZone: hexToZone, regionToZone: regionToZone, map: map).contains { neighborZoneId in
            guard
                  neighborZoneId != zoneId,
                  let neighborFaction = zones[neighborZoneId]?.faction else {
                return false
            }
            return neighborFaction != faction
        }
    }

    private func hexTouchesEnemyZone(
        hex: HexCoord,
        zoneId: FrontZoneId,
        faction: Faction,
        zones: [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        map: MapState
    ) -> Bool {
        guard map.tile(at: hex) != nil else {
            return false
        }

        for neighborHex in hex.neighbors where map.tile(at: neighborHex) != nil {
            guard let neighborZoneId = hexToZone[neighborHex],
                  neighborZoneId != zoneId,
                  let neighborFaction = zones[neighborZoneId]?.faction else {
                continue
            }
            if neighborFaction != faction {
                return true
            }
        }
        return false
    }

    private func faction(for theater: TheaterNode, map: MapState) -> Faction? {
        if let controllingFaction = theater.controllingFaction {
            return controllingFaction
        }

        var area: [Faction: Int] = [:]
        for regionId in theater.regionIds {
            guard let region = map.regions[regionId] else { continue }
            area[region.controller, default: 0] += max(1, region.displayHexes.count)
        }
        return Faction.allCases.max { (area[$0] ?? 0) < (area[$1] ?? 0) }
    }

    private func strength(in regionId: RegionId, for faction: Faction, map: MapState) -> Int {
        let region = map.regions[regionId]
        let localArea = max(1, region?.displayHexes.count ?? 1)
        let localSupply = max(0, region?.supplyValue ?? 0)
        return localArea + localSupply + (region?.controller == faction ? 1 : 0)
    }

    private func warState(segmentCount: Int, pressure: Int) -> WarState {
        if segmentCount == 0 {
            return .peace
        }
        if pressure >= segmentCount * 3 {
            return .totalWar
        }
        if pressure >= segmentCount * 2 {
            return .highIntensity
        }
        return .lowIntensity
    }

    private func friendlyDepthZones(for zoneId: FrontZoneId, in state: WarDeploymentState) -> Set<FrontZoneId> {
        guard let zone = state.frontZones[zoneId] else { return [] }
        return Set(zone.neighbors.filter { state.frontZones[$0]?.faction == zone.faction })
    }

    private func regionHasCityOrFactory(_ regionId: RegionId, map: MapState) -> Bool {
        guard let region = map.regions[regionId] else { return false }
        return region.city != nil || region.factories > 0 || region.coreOf.contains(region.controller)
    }

    private func isEncircledEnemyContact(
        from regionId: RegionId,
        zoneId: FrontZoneId,
        enemyZoneId: FrontZoneId,
        zones: [FrontZoneId: FrontZone],
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState
    ) -> Bool {
        let enemyRegions = dynamicEnemyRegionsTouching(
            regionId: regionId,
            enemyZoneId: enemyZoneId,
            hexToZone: hexToZone,
            regionToZone: regionToZone,
            map: map
        )
        guard !enemyRegions.isEmpty else { return false }

        return enemyRegions.contains { enemyRegionId in
            let exits = map.neighbors(of: enemyRegionId).filter { neighborRegionId in
                guard let neighborZoneId = regionToZone[neighborRegionId] else {
                    return false
                }
                return neighborZoneId == enemyZoneId || zones[neighborZoneId]?.faction == zones[enemyZoneId]?.faction
            }
            let hostileContacts = map.neighbors(of: enemyRegionId).count {
                guard let neighborZoneId = regionToZone[$0] else { return false }
                return zones[neighborZoneId]?.faction == zones[zoneId]?.faction
            }
            return exits.isEmpty || (hostileContacts >= 2 && exits.count < 2)
        }
    }

    private func dirtyRegions(from events: [WarDeploymentEvent], state: WarDeploymentState) -> Set<RegionId> {
        var dirty: Set<RegionId> = []
        for event in events {
            switch event {
            case .regionControllerChanged(let regionId),
                 .frontZoneAssignmentChanged(let regionId),
                 .unitEntered(let regionId),
                 .unitLeft(let regionId):
                dirty.insert(regionId)
            case .frontZoneChanged(let zoneId):
                dirty.formUnion(state.frontZones[zoneId]?.regionIds ?? [])
            }
        }
        return dirty
    }

    private func zoneIds(touching regionIds: Set<RegionId>, state: WarDeploymentState, map: MapState) -> Set<FrontZoneId> {
        zoneIds(around: regionIds, hexToZone: state.hexToFrontZone, regionToZone: state.regionToFrontZone, map: map)
    }

    private func zoneIds(
        around regionIds: some Sequence<RegionId>,
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState
    ) -> Set<FrontZoneId> {
        var zoneIds: Set<FrontZoneId> = []
        for regionId in regionIds {
            if let zoneId = regionToZone[regionId] {
                zoneIds.insert(zoneId)
            }
            guard let region = map.region(id: regionId) else {
                continue
            }
            for hex in region.displayHexes {
                if let zoneId = hexToZone[hex] {
                    zoneIds.insert(zoneId)
                }
                for neighborHex in hex.neighbors where map.tile(at: neighborHex) != nil {
                    if let zoneId = hexToZone[neighborHex] {
                        zoneIds.insert(zoneId)
                    } else if let neighborRegionId = map.region(for: neighborHex),
                              let zoneId = regionToZone[neighborRegionId] {
                        zoneIds.insert(zoneId)
                    }
                }
            }
        }
        return zoneIds
    }

    private func dynamicEnemyRegionsTouching(
        regionId: RegionId,
        enemyZoneId: FrontZoneId,
        hexToZone: [HexCoord: FrontZoneId],
        regionToZone: [RegionId: FrontZoneId],
        map: MapState
    ) -> [RegionId] {
        var regions: Set<RegionId> = []
        guard let region = map.region(id: regionId) else {
            return []
        }
        for hex in region.displayHexes {
            for neighborHex in hex.neighbors where map.tile(at: neighborHex) != nil {
                guard let neighborRegionId = map.region(for: neighborHex),
                      (hexToZone[neighborHex] ?? regionToZone[neighborRegionId]) == enemyZoneId else {
                    continue
                }
                regions.insert(neighborRegionId)
            }
        }
        return regions.sorted { $0.rawValue < $1.rawValue }
    }
}
