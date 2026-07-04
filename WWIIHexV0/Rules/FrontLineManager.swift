import Foundation

struct FrontLineManager {
    func makeInitialState(
        map: MapState,
        theaterState: TheaterState,
        divisions: [Division],
        turn: Int? = nil
    ) -> FrontLineState {
        rebuildAll(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: turn,
            mode: .turnRebuild
        )
    }

    func tick(
        state: FrontLineState,
        map: MapState,
        theaterState: TheaterState,
        divisions: [Division],
        turn: Int,
        mode: FrontLineUpdateMode = .turnRebuild,
        events: [FrontLineEvent] = []
    ) -> FrontLineState {
        if mode == .eventDriven || !events.isEmpty {
            return update(
                state: state,
                map: map,
                theaterState: theaterState,
                divisions: divisions,
                turn: turn,
                events: events
            )
        }

        guard state.lastUpdatedTurn != turn else {
            return state
        }

        return rebuildAll(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: turn,
            mode: .turnRebuild
        )
    }

    func update(
        state: FrontLineState,
        map: MapState,
        theaterState: TheaterState,
        divisions: [Division],
        turn: Int,
        events: [FrontLineEvent]
    ) -> FrontLineState {
        let dirtyRegions = dirtyRegions(from: events, map: map, theaterState: theaterState)
        guard !dirtyRegions.isEmpty else {
            var next = state
            next.diagnostics = FrontLineDiagnostics(updateMode: .eventDriven)
            return next
        }

        return rebuildDirtyRegions(
            state: state,
            dirtyRegions: dirtyRegions,
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: turn
        )
    }

    func markDirty(
        state: FrontLineState,
        events: [FrontLineEvent],
        map: MapState,
        theaterState: TheaterState
    ) -> FrontLineState {
        var next = state
        next.dirtyRegionIds.formUnion(dirtyRegions(from: events, map: map, theaterState: theaterState))
        return next
    }

    func frontLines(for theaterId: TheaterId, in state: FrontLineState) -> [FrontLine] {
        state.frontLines(for: theaterId)
    }

    func regionFrontState(for regionId: RegionId, in state: FrontLineState) -> RegionFrontState? {
        state.regionState(for: regionId)
    }

    func enemyBoundaryNeighbors(for regionId: RegionId, in state: FrontLineState) -> [RegionId] {
        state.enemyNeighborCache[regionId] ?? []
    }

    private func rebuildAll(
        map: MapState,
        theaterState: TheaterState,
        divisions: [Division],
        turn: Int?,
        mode: FrontLineUpdateMode
    ) -> FrontLineState {
        var cache: [RegionId: [RegionId]] = [:]
        var scannedRegionIds: Set<RegionId> = []
        var scannedNeighborLinkCount = 0
        var segmentsByTheater: [TheaterId: [FrontSegment]] = [:]
        let strengths = divisionStrengthsByRegion(divisions: divisions, map: map)

        for theater in activeTheaters(in: theaterState) {
            let segments = buildSegments(
                theaterId: theater.id,
                sourceRegionIds: theater.regionIds,
                map: map,
                theaterState: theaterState,
                strengths: strengths,
                cache: &cache,
                scannedRegionIds: &scannedRegionIds,
                scannedNeighborLinkCount: &scannedNeighborLinkCount
            )
            segmentsByTheater[theater.id, default: []].append(contentsOf: segments)
        }

        let frontLines = makeFrontLines(from: segmentsByTheater, map: map, theaterState: theaterState)
        let regionStates = makeRegionStates(
            frontLines: frontLines,
            includedEmptyRegionIds: scannedRegionIds,
            turn: turn,
            dirtyRegionIds: []
        )

        return FrontLineState(
            frontLines: Dictionary(uniqueKeysWithValues: frontLines.map { ($0.id, $0) }),
            regionStates: regionStates,
            enemyNeighborCache: cache,
            dirtyRegionIds: [],
            lastUpdatedTurn: turn,
            diagnostics: FrontLineDiagnostics(
                updateMode: mode,
                scannedRegionCount: scannedRegionIds.count,
                scannedNeighborLinkCount: scannedNeighborLinkCount,
                updatedTheaterIds: activeTheaters(in: theaterState).map(\.id),
                updatedRegionIds: Array(scannedRegionIds)
            )
        )
    }

    private func rebuildDirtyRegions(
        state: FrontLineState,
        dirtyRegions: Set<RegionId>,
        map: MapState,
        theaterState: TheaterState,
        divisions: [Division],
        turn: Int
    ) -> FrontLineState {
        let touchedRegions = touchedRegions(from: dirtyRegions, map: map)
        let strengths = divisionStrengthsByRegion(divisions: divisions, map: map)
        var cache = state.enemyNeighborCache
        var scannedRegionIds: Set<RegionId> = []
        var scannedNeighborLinkCount = 0
        var segmentsByTheater: [TheaterId: [FrontSegment]] = [:]

        for regionId in touchedRegions {
            cache[regionId] = []
        }

        for line in state.frontLines.values {
            let keptSegments = line.segments.filter {
                !dirtyRegions.contains($0.regionA) && !dirtyRegions.contains($0.regionB)
            }
            if !keptSegments.isEmpty {
                segmentsByTheater[line.theaterId, default: []].append(contentsOf: keptSegments)
            }
        }

        let touchedTheaterIds = theaterIds(touching: touchedRegions, map: map, theaterState: theaterState)
        for theaterId in touchedTheaterIds {
            let sourceRegionIds = touchedRegions
                .filter { regionContainsDynamicTheater($0, theaterId: theaterId, map: map, theaterState: theaterState) }
                .sorted { $0.rawValue < $1.rawValue }

            let segments = buildSegments(
                theaterId: theaterId,
                sourceRegionIds: sourceRegionIds,
                map: map,
                theaterState: theaterState,
                strengths: strengths,
                cache: &cache,
                scannedRegionIds: &scannedRegionIds,
                scannedNeighborLinkCount: &scannedNeighborLinkCount
            )
            segmentsByTheater[theaterId, default: []].append(contentsOf: segments)
        }

        let frontLines = makeFrontLines(from: segmentsByTheater, map: map, theaterState: theaterState)
        let regionStates = makeRegionStates(
            frontLines: frontLines,
            includedEmptyRegionIds: touchedRegions,
            turn: turn,
            dirtyRegionIds: dirtyRegions
        )

        return FrontLineState(
            frontLines: Dictionary(uniqueKeysWithValues: frontLines.map { ($0.id, $0) }),
            regionStates: regionStates,
            enemyNeighborCache: cache,
            dirtyRegionIds: [],
            lastUpdatedTurn: turn,
            diagnostics: FrontLineDiagnostics(
                updateMode: .eventDriven,
                scannedRegionCount: scannedRegionIds.count,
                scannedNeighborLinkCount: scannedNeighborLinkCount,
                updatedTheaterIds: Array(touchedTheaterIds),
                updatedRegionIds: Array(touchedRegions)
            )
        )
    }

    private func buildSegments(
        theaterId: TheaterId,
        sourceRegionIds: [RegionId],
        map: MapState,
        theaterState: TheaterState,
        strengths: [RegionId: [Faction: Int]],
        cache: inout [RegionId: [RegionId]],
        scannedRegionIds: inout Set<RegionId>,
        scannedNeighborLinkCount: inout Int
    ) -> [FrontSegment] {
        guard let theater = theaterState.theaters[theaterId],
              theater.status != .inactive,
              let sourceFaction = sourceFaction(for: theater, theaterState: theaterState, map: map) else {
            return []
        }

        var segmentsById: [String: FrontSegment] = [:]
        for regionId in sourceRegionIds {
            guard regionContainsDynamicTheater(regionId, theaterId: theaterId, map: map, theaterState: theaterState) else {
                continue
            }

            scannedRegionIds.insert(regionId)
            let neighbors = dynamicEnemyNeighborRegions(
                of: regionId,
                sourceTheaterId: theaterId,
                sourceFaction: sourceFaction,
                map: map,
                theaterState: theaterState
            )
            scannedNeighborLinkCount += neighbors.count
            let enemyNeighbors = neighbors
            cache[regionId] = enemyNeighbors

            for enemyRegionId in enemyNeighbors {
                guard let segment = makeSegment(
                    regionA: regionId,
                    regionB: enemyRegionId,
                    friendlyFaction: sourceFaction,
                    map: map,
                    theaterState: theaterState,
                    strengths: strengths
                ) else {
                    continue
                }
                segmentsById[segment.id] = segment
            }
        }

        return segmentsById.values.sorted {
            if $0.regionA.rawValue == $1.regionA.rawValue {
                return $0.regionB.rawValue < $1.regionB.rawValue
            }
            return $0.regionA.rawValue < $1.regionA.rawValue
        }
    }

    private func enemyNeighbors(
        of regionId: RegionId,
        sourceTheaterId: TheaterId,
        sourceFaction: Faction,
        map: MapState,
        theaterState: TheaterState,
        neighbors: [RegionId]
    ) -> [RegionId] {
        guard map.regions[regionId] != nil else {
            return []
        }

        return neighbors
            .filter { neighborId in
                guard let neighborTheaterId = theaterState.regionToTheater[neighborId],
                      neighborTheaterId != sourceTheaterId,
                      theaterState.theaters[neighborTheaterId]?.status != .inactive else {
                    return false
                }
                if theaterState.theaters[neighborTheaterId]?.controllingFaction != sourceFaction {
                    return true
                }
                return map.regions[neighborId]?.controller != sourceFaction
            }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func dynamicEnemyNeighborRegions(
        of regionId: RegionId,
        sourceTheaterId: TheaterId,
        sourceFaction friendlyFaction: Faction,
        map: MapState,
        theaterState: TheaterState
    ) -> [RegionId] {
        guard let region = map.region(id: regionId) else {
            return []
        }

        var enemyRegions: Set<RegionId> = []
        for hex in region.displayHexes where theaterState.dynamicTheaterId(for: hex, map: map) == sourceTheaterId {
            for neighborHex in hex.neighbors {
                guard map.tile(at: neighborHex) != nil,
                      let neighborRegionId = map.region(for: neighborHex),
                      let neighborTheaterId = theaterState.dynamicTheaterId(for: neighborHex, map: map),
                      neighborTheaterId != sourceTheaterId,
                      let neighborTheater = theaterState.theaters[neighborTheaterId],
                      neighborTheater.status != .inactive,
                      sourceFaction(for: neighborTheater, theaterState: theaterState, map: map) != friendlyFaction else {
                    continue
                }
                enemyRegions.insert(neighborRegionId)
            }
        }

        return enemyRegions.sorted { $0.rawValue < $1.rawValue }
    }

    private func makeSegment(
        regionA: RegionId,
        regionB: RegionId,
        friendlyFaction: Faction,
        map: MapState,
        theaterState: TheaterState,
        strengths: [RegionId: [Faction: Int]]
    ) -> FrontSegment? {
        guard let enemyRegion = map.regions[regionB] else {
            return nil
        }

        let enemyFaction = enemyRegion.controller
        let encirclementCandidate = isEncirclementCandidate(
            enemyRegionId: regionB,
            friendlyFaction: friendlyFaction,
            enemyFaction: enemyFaction,
            map: map
        )
        let pressure = pressureLevel(
            regionA: regionA,
            regionB: regionB,
            friendlyFaction: friendlyFaction,
            enemyFaction: enemyFaction,
            strengths: strengths,
            encirclementCandidate: encirclementCandidate
        )
        let supplyImpact = supplyImpact(
            enemyRegionId: regionB,
            friendlyFaction: friendlyFaction,
            enemyFaction: enemyFaction,
            pressureLevel: pressure,
            encirclementCandidate: encirclementCandidate,
            map: map
        )

        return FrontSegment(
            regionA: regionA,
            regionB: regionB,
            edgeType: edgeType(between: regionA, and: regionB, map: map),
            pressureLevel: pressure,
            supplyImpact: supplyImpact,
            isEncirclementCandidate: encirclementCandidate
        )
    }

    private func makeFrontLines(
        from segmentsByTheater: [TheaterId: [FrontSegment]],
        map: MapState,
        theaterState: TheaterState
    ) -> [FrontLine] {
        segmentsByTheater.compactMap { theaterId, segments in
            guard let theater = theaterState.theaters[theaterId],
                  theater.status != .inactive,
                  let factionA = sourceFaction(for: theater, theaterState: theaterState, map: map) else {
                return nil
            }

            var deduped: [String: FrontSegment] = [:]
            for segment in segments {
                deduped[segment.id] = segment
            }
            let finalSegments = deduped.values.sorted {
                if $0.regionA.rawValue == $1.regionA.rawValue {
                    return $0.regionB.rawValue < $1.regionB.rawValue
                }
                return $0.regionA.rawValue < $1.regionA.rawValue
            }
            guard !finalSegments.isEmpty else {
                return nil
            }

            let opposingTheaterIds = Set(finalSegments.compactMap { theaterState.dominantDynamicTheaterId(for: $0.regionB, map: map) })
            let maxPressure = finalSegments.map(\.pressureLevel).max() ?? 0
            let hasEncirclement = finalSegments.contains { $0.isEncirclementCandidate }
            let hasBreakthrough = finalSegments.contains { segment in
                map.regions[segment.regionA]?.controller != factionA
            }
            let type: FrontLineType = hasEncirclement ? .encirclement : (hasBreakthrough ? .breakthrough : .normal)
            let state = operationalState(maxPressure: maxPressure, hasEncirclement: hasEncirclement)
            let factionB = finalSegments
                .lazy
                .compactMap { map.regions[$0.regionB]?.controller }
                .first { $0.isHostile(to: factionA) } ?? factionA.opponent

            return FrontLine(
                id: frontLineId(theaterId: theaterId, factionA: factionA, factionB: factionB),
                theaterId: theaterId,
                opposingTheaterIds: Array(opposingTheaterIds),
                factionA: factionA,
                factionB: factionB,
                segments: finalSegments,
                type: type,
                state: state
            )
        }
        .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func makeRegionStates(
        frontLines: [FrontLine],
        includedEmptyRegionIds: Set<RegionId>,
        turn: Int?,
        dirtyRegionIds: Set<RegionId>
    ) -> [RegionId: RegionFrontState] {
        var frontLinesByRegion: [RegionId: [FrontLine]] = [:]
        for frontLine in frontLines {
            for segment in frontLine.segments {
                frontLinesByRegion[segment.regionA, default: []].append(frontLine)
                frontLinesByRegion[segment.regionB, default: []].append(frontLine)
            }
        }

        let regionIds = Set(frontLinesByRegion.keys).union(includedEmptyRegionIds)
        var states: [RegionId: RegionFrontState] = [:]
        for regionId in regionIds {
            let lines = (frontLinesByRegion[regionId] ?? []).sorted { $0.id.rawValue < $1.id.rawValue }
            states[regionId] = RegionFrontState(
                regionId: regionId,
                frontLines: lines,
                lastUpdatedTurn: turn,
                dirtyFlag: dirtyRegionIds.contains(regionId)
            )
        }
        return states
    }

    private func activeTheaters(in state: TheaterState) -> [TheaterNode] {
        state.theaters.values
            .filter { $0.status != .inactive }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func sourceFaction(for theater: TheaterNode, theaterState: TheaterState, map: MapState?) -> Faction? {
        if let initialFaction = theaterState.initialSnapshot?.theaters[theater.id]?.controllingFaction {
            return initialFaction
        }

        if let controllingFaction = theater.controllingFaction {
            return controllingFaction
        }

        guard let map else {
            return nil
        }

        var counts: [Faction: Int] = [:]
        for hex in map.tiles.keys where theaterState.dynamicTheaterId(for: hex, map: map) == theater.id {
            guard let controller = map.tile(at: hex)?.controller else {
                continue
            }
            counts[controller, default: 0] += 1
        }
        guard !counts.isEmpty else {
            return nil
        }
        return Faction.allCases.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    private func frontLineId(theaterId: TheaterId, factionA: Faction, factionB: Faction) -> FrontLineId {
        FrontLineId("front_\(theaterId.rawValue)_\(factionA.rawValue)_vs_\(factionB.rawValue)")
    }

    private func divisionStrengthsByRegion(
        divisions: [Division],
        map: MapState
    ) -> [RegionId: [Faction: Int]] {
        var strengths: [RegionId: [Faction: Int]] = [:]
        for division in divisions where !division.isDestroyed {
            guard let regionId = division.location(in: map) else { continue }
            strengths[regionId, default: [:]][division.faction, default: 0] += division.strength
        }
        return strengths
    }

    private func pressureLevel(
        regionA: RegionId,
        regionB: RegionId,
        friendlyFaction: Faction,
        enemyFaction: Faction,
        strengths: [RegionId: [Faction: Int]],
        encirclementCandidate: Bool
    ) -> Double {
        let friendlyStrength = strengths[regionA]?[friendlyFaction] ?? 0
        let enemyStrength = strengths[regionB]?[enemyFaction] ?? 0
        let total = friendlyStrength + enemyStrength
        let basePressure = total == 0 ? 0.5 : Double(enemyStrength) / Double(total)
        return encirclementCandidate ? max(0.8, basePressure) : basePressure
    }

    private func supplyImpact(
        enemyRegionId: RegionId,
        friendlyFaction: Faction,
        enemyFaction: Faction,
        pressureLevel: Double,
        encirclementCandidate: Bool,
        map: MapState
    ) -> FrontSupplyImpact {
        guard let enemyRegion = map.regions[enemyRegionId] else {
            return .none
        }

        let hasLocalSupply = enemyRegion.supplyValue > 0 || map.neighbors(of: enemyRegionId).contains {
            map.regions[$0]?.controller == enemyFaction && (map.regions[$0]?.supplyValue ?? 0) > 0
        }
        let friendlyContacts = map.neighbors(of: enemyRegionId).count {
            map.regions[$0]?.controller == friendlyFaction
        }

        if encirclementCandidate || (!hasLocalSupply && friendlyContacts >= 2) {
            return .high
        }
        if pressureLevel > 0.7 {
            return .medium
        }
        return pressureLevel > 0.4 ? .low : .none
    }

    private func isEncirclementCandidate(
        enemyRegionId: RegionId,
        friendlyFaction: Faction,
        enemyFaction: Faction,
        map: MapState
    ) -> Bool {
        let neighbors = map.neighbors(of: enemyRegionId)
        let friendlyContacts = neighbors.count {
            map.regions[$0]?.controller == friendlyFaction
        }
        let escapeRoutes = neighbors.count {
            map.regions[$0]?.controller == enemyFaction && map.regions[$0]?.isPassable == true
        }
        let hasSupplyPath = (map.regions[enemyRegionId]?.supplyValue ?? 0) > 0 || neighbors.contains {
            map.regions[$0]?.controller == enemyFaction && (map.regions[$0]?.supplyValue ?? 0) > 0
        }

        return friendlyContacts >= 2 && (escapeRoutes < 2 || !hasSupplyPath)
    }

    private func operationalState(
        maxPressure: Double,
        hasEncirclement: Bool
    ) -> FrontLineOperationalState {
        if hasEncirclement && maxPressure >= 0.8 {
            return .collapsing
        }
        return maxPressure > 0.55 ? .shifting : .stable
    }

    private func edgeType(
        between a: RegionId,
        and b: RegionId,
        map: MapState
    ) -> FrontSegmentEdgeType? {
        guard let edge = map.edgeBetween(a, b) else {
            return nil
        }
        if edge.hasRiverCrossing {
            return .riverCrossing
        }
        if edge.hasRoad {
            return .road
        }
        return .standard
    }

    private func dirtyRegions(
        from events: [FrontLineEvent],
        map: MapState,
        theaterState: TheaterState
    ) -> Set<RegionId> {
        var dirty: Set<RegionId> = []
        for event in events {
            switch event {
            case .regionControllerChanged(let regionId),
                 .theaterAssignmentChanged(let regionId),
                 .unitEntered(let regionId),
                 .unitLeft(let regionId),
                 .occupationChanged(let regionId):
                dirty.insert(regionId)
            case .theaterChanged(let theaterId):
                dirty.formUnion(theaterState.theaters[theaterId]?.regionIds ?? [])
            }
        }
        return dirty.filter { map.regions[$0] != nil }
    }

    private func touchedRegions(from dirtyRegions: Set<RegionId>, map: MapState) -> Set<RegionId> {
        var touched = dirtyRegions
        for regionId in dirtyRegions {
            touched.formUnion(map.neighbors(of: regionId))
        }
        return touched.filter { map.regions[$0] != nil }
    }

    private func theaterIds(
        touching regionIds: Set<RegionId>,
        map: MapState,
        theaterState: TheaterState
    ) -> Set<TheaterId> {
        var ids = Set<TheaterId>()
        if theaterState.hexToTheater.isEmpty {
            ids.formUnion(regionIds.compactMap { theaterState.regionToTheater[$0] })
        }
        ids.formUnion(theaterState.theaters.keys.filter { theaterId in
            regionIds.contains { regionContainsDynamicTheater($0, theaterId: theaterId, map: map, theaterState: theaterState) }
        })
        return ids
    }

    private func regionContainsDynamicTheater(
        _ regionId: RegionId,
        theaterId: TheaterId,
        map: MapState?,
        theaterState: TheaterState
    ) -> Bool {
        if theaterState.hexToTheater.isEmpty, theaterState.regionToTheater[regionId] == theaterId {
            return true
        }
        guard let map,
              let region = map.region(id: regionId) else {
            return false
        }
        return region.displayHexes.contains {
            theaterState.dynamicTheaterId(for: $0, map: map) == theaterId
        }
    }
}
