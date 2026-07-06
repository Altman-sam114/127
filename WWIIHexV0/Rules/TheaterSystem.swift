import Foundation

struct TheaterSystem {
    let formalizationThreshold: Double

    init(formalizationThreshold: Double = 0.70) {
        self.formalizationThreshold = formalizationThreshold
    }

    func makeInitialFixedTheaters(map: MapState, divisions: [Division], turn: Int? = nil) -> TheaterState {
        guard !map.regions.isEmpty else {
            return .empty
        }

        var regionToTheater: [RegionId: TheaterId] = [:]
        var hexToTheater: [HexCoord: TheaterId] = [:]
        var groupedRegions: [TheaterId: [RegionId]] = [:]

        for region in map.regions.values {
            let theaterId = fixedTheaterId(for: region, map: map)
            regionToTheater[region.id] = theaterId
            for hex in region.displayHexes {
                hexToTheater[hex] = theaterId
            }
            groupedRegions[theaterId, default: []].append(region.id)
        }

        var theaters: [TheaterId: TheaterNode] = [:]
        for kind in FixedTheaterKind.allCases {
            let theaterId = kind.id
            let regionIds = (groupedRegions[theaterId] ?? []).sorted { $0.rawValue < $1.rawValue }
            theaters[theaterId] = TheaterNode(
                id: theaterId,
                name: kind.rawValue,
                status: .active,
                regionIds: regionIds
            )
        }

        var state = TheaterState(theaters: theaters, hexToTheater: hexToTheater, regionToTheater: regionToTheater, lastUpdatedTurn: turn)
        refreshDerivedFields(state: &state, map: map, divisions: divisions)
        state.initialSnapshot = TheaterInitialSnapshot.capture(from: state)
        return state
    }

    func updateTheaters(
        state: TheaterState,
        map: MapState,
        divisions: [Division],
        turn: Int,
        force: Bool = false
    ) -> TheaterState {
        guard force || state.lastUpdatedTurn != turn else {
            return state
        }

        var next = state
        refreshDerivedFields(state: &next, map: map, divisions: divisions)
        next.lastUpdatedTurn = turn
        return next
    }

    func expandTheater(
        state: TheaterState,
        map: MapState,
        divisions: [Division],
        breakthroughRegionId: RegionId,
        faction: Faction
    ) -> TheaterExpansionResult {
        guard map.regions[breakthroughRegionId] != nil else {
            return TheaterExpansionResult(state: state, transition: .none, affectedTheaterId: nil)
        }

        var next = state
        let targetTheaterId = next.regionToTheater[breakthroughRegionId]
            ?? fixedTheaterId(for: map.regions[breakthroughRegionId]!, map: map)

        if next.theaters[targetTheaterId] == nil {
            next.theaters[targetTheaterId] = TheaterNode(
                id: targetTheaterId,
                name: targetTheaterId.rawValue,
                status: .provisional
            )
        }

        if !next.theaters[targetTheaterId]!.regionIds.contains(breakthroughRegionId) {
            next.theaters[targetTheaterId]!.regionIds.append(breakthroughRegionId)
            next.theaters[targetTheaterId]!.regionIds.sort { $0.rawValue < $1.rawValue }
        }
        next.regionToTheater[breakthroughRegionId] = targetTheaterId

        refreshDerivedFields(state: &next, map: map, divisions: divisions)
        let ratio = next.theaters[targetTheaterId]?.controlRatios[faction] ?? 0

        if ratio >= formalizationThreshold {
            next.theaters[targetTheaterId]?.status = .active
            next.theaters[targetTheaterId]?.controllingFaction = faction
            refreshDerivedFields(state: &next, map: map, divisions: divisions)
            return TheaterExpansionResult(
                state: next,
                transition: .formalized(theaterId: targetTheaterId, faction: faction, ratio: ratio),
                affectedTheaterId: targetTheaterId
            )
        }

        next.theaters[targetTheaterId]?.status = .provisional
        return TheaterExpansionResult(
            state: next,
            transition: .provisional(theaterId: targetTheaterId, ratio: ratio),
            affectedTheaterId: targetTheaterId
        )
    }

    func expandDynamicTheater(
        state: TheaterState,
        map: MapState,
        divisions: [Division],
        breakthroughRegionId: RegionId,
        advancingTheaterId: TheaterId,
        faction: Faction
    ) -> TheaterExpansionResult {
        guard let breakthroughHex = map.region(id: breakthroughRegionId)?.representativeHex else {
            return TheaterExpansionResult(state: state, transition: .none, affectedTheaterId: nil)
        }

        return expandDynamicTheater(
            state: state,
            map: map,
            divisions: divisions,
            breakthroughHex: breakthroughHex,
            advancingTheaterId: advancingTheaterId,
            faction: faction
        )
    }

    func expandDynamicTheater(
        state: TheaterState,
        map: MapState,
        divisions: [Division],
        breakthroughHex: HexCoord,
        advancingTheaterId: TheaterId,
        faction: Faction
    ) -> TheaterExpansionResult {
        guard map.tile(at: breakthroughHex) != nil,
              let breakthroughRegionId = map.region(for: breakthroughHex),
              state.theaters[advancingTheaterId] != nil else {
            return TheaterExpansionResult(state: state, transition: .none, affectedTheaterId: nil)
        }

        var next = state
        seedMissingHexAssignments(state: &next, map: map)
        next.hexToTheater[breakthroughHex] = advancingTheaterId

        refreshDerivedFields(state: &next, map: map, divisions: divisions)
        let ratio = controlRatio(
            for: faction,
            inBasicRegionOf: breakthroughRegionId,
            state: next,
            map: map
        )
        if ratio >= formalizationThreshold {
            next.theaters[advancingTheaterId]?.status = .active
            next.theaters[advancingTheaterId]?.controllingFaction = faction
            refreshDerivedFields(state: &next, map: map, divisions: divisions)
            return TheaterExpansionResult(
                state: next,
                transition: .formalized(theaterId: advancingTheaterId, faction: faction, ratio: ratio),
                affectedTheaterId: advancingTheaterId
            )
        }

        next.theaters[advancingTheaterId]?.status = .provisional
        return TheaterExpansionResult(
            state: next,
            transition: .provisional(theaterId: advancingTheaterId, ratio: ratio),
            affectedTheaterId: advancingTheaterId
        )
    }

    func retireTheaters(
        state: TheaterState,
        map: MapState,
        divisions: [Division],
        faction: Faction
    ) -> TheaterState {
        var next = state
        rebuildNeighborTheaters(state: &next, map: map)

        let activeTheaters = next.theaters.values
            .filter { $0.status == .active }
            .sorted { $0.id.rawValue < $1.id.rawValue }

        for theater in activeTheaters {
            guard theater.controllingFaction == faction,
                  !theater.neighborTheaterIds.isEmpty else {
                continue
            }

            let allNeighborsFriendly = theater.neighborTheaterIds.allSatisfy {
                next.theaters[$0]?.controllingFaction == faction && next.theaters[$0]?.status == .active
            }

            guard allNeighborsFriendly else {
                continue
            }

            retire(theaterId: theater.id, state: &next)
        }

        refreshDerivedFields(state: &next, map: map, divisions: divisions)
        return next
    }

    func requestSupport(
        from theaterId: TheaterId,
        to targetTheaterId: TheaterId,
        in state: TheaterState,
        policy: SpilloverPolicy = .interfaceOnly,
        reason: String = "Support requested by operational zone interface."
    ) -> TheaterSupportRequest? {
        guard let source = state.theaters[theaterId],
              state.theaters[targetTheaterId] != nil else {
            return nil
        }

        return TheaterSupportRequest(
            id: "\(theaterId.rawValue)_to_\(targetTheaterId.rawValue)_support",
            fromTheaterId: theaterId,
            toTheaterId: targetTheaterId,
            availableUnitIds: getAvailableForces(theaterId, in: state),
            policy: policy,
            reason: source.status == .inactive ? "Inactive operational zone has no available support." : reason
        )
    }

    func getAvailableForces(_ theaterId: TheaterId, in state: TheaterState) -> [String] {
        guard let theater = state.theaters[theaterId],
              theater.status != .inactive else {
            return []
        }
        return theater.supportEligibleUnitIds
    }

    func notifyThreat(
        theaterId: TheaterId,
        sourceRegionId: RegionId?,
        threatScore: Int,
        message: String,
        in state: TheaterState
    ) -> TheaterState {
        guard state.theaters[theaterId] != nil else {
            return state
        }

        var next = state
        let notification = TheaterThreatNotification(
            id: "\(theaterId.rawValue)_threat_\(next.theaters[theaterId]!.recentThreats.count + 1)",
            theaterId: theaterId,
            sourceRegionId: sourceRegionId,
            threatScore: threatScore,
            message: message
        )
        next.theaters[theaterId]?.recentThreats.append(notification)
        return next
    }

    func aiSummaries(for state: TheaterState) -> [TheaterAISummary] {
        state.theaters.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map {
                TheaterAISummary(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status,
                    regionIds: $0.regionIds,
                    controllingFaction: $0.controllingFaction,
                    controlRatios: $0.controlRatios,
                    threatScore: $0.recentThreats.map(\.threatScore).max() ?? $0.frontWeight,
                    unitCount: $0.unitIds.count
                )
            }
    }

    private func fixedTheaterId(for region: RegionNode, map: MapState) -> TheaterId {
        let qValues = region.displayHexes.map(\.q)
        let rValues = region.displayHexes.map(\.r)
        let averageQ = qValues.isEmpty ? region.representativeHex.q : qValues.reduce(0, +) / qValues.count
        let averageR = rValues.isEmpty ? region.representativeHex.r : rValues.reduce(0, +) / rValues.count
        let west = averageQ < max(1, map.width) / 2
        let north = averageR < max(1, map.height) / 2

        switch (north, west) {
        case (true, true):
            return FixedTheaterKind.northWest.id
        case (true, false):
            return FixedTheaterKind.northEast.id
        case (false, true):
            return FixedTheaterKind.southWest.id
        case (false, false):
            return FixedTheaterKind.southEast.id
        }
    }

    private func refreshDerivedFields(state: inout TheaterState, map: MapState, divisions: [Division]) {
        seedMissingHexAssignments(state: &state, map: map)
        rebuildDynamicRegionMembership(state: &state, map: map)
        rebuildNeighborTheaters(state: &state, map: map)
        assignUnits(state: &state, map: map, divisions: divisions)

        for theaterId in state.theaters.keys {
            guard var theater = state.theaters[theaterId] else { continue }
            let metrics = calculateMetrics(for: theater, state: state, map: map)
            theater.controlRatios = metrics.controlRatios
            theater.controllingFaction = metrics.controllingFaction
            theater.victoryPointArea = metrics.victoryPointArea
            theater.frontWeight = metrics.frontWeight
            state.theaters[theaterId] = theater
        }
    }

    private func seedMissingHexAssignments(state: inout TheaterState, map: MapState) {
        for (regionId, region) in map.regions {
            guard let basicTheaterId = state.regionToTheater[regionId] else {
                continue
            }
            for hex in region.displayHexes where state.hexToTheater[hex] == nil {
                state.hexToTheater[hex] = basicTheaterId
            }
        }
    }

    private func rebuildDynamicRegionMembership(state: inout TheaterState, map: MapState) {
        for theaterId in state.theaters.keys {
            state.theaters[theaterId]?.regionIds = []
        }

        var regionsByTheater: [TheaterId: Set<RegionId>] = [:]
        for (hex, theaterId) in state.hexToTheater {
            guard state.theaters[theaterId] != nil,
                  let regionId = map.region(for: hex) else {
                continue
            }
            regionsByTheater[theaterId, default: []].insert(regionId)
        }

        for (theaterId, regionIds) in regionsByTheater {
            state.theaters[theaterId]?.regionIds = regionIds.sorted { $0.rawValue < $1.rawValue }
        }
    }

    private func rebuildNeighborTheaters(state: inout TheaterState, map: MapState) {
        var neighbors: [TheaterId: Set<TheaterId>] = [:]

        for (hex, theaterId) in state.hexToTheater {
            for neighborHex in hex.neighbors {
                guard map.tile(at: neighborHex) != nil,
                      let neighborTheaterId = state.dynamicTheaterId(for: neighborHex, map: map),
                      neighborTheaterId != theaterId else {
                    continue
                }
                neighbors[theaterId, default: []].insert(neighborTheaterId)
            }
        }

        for theaterId in state.theaters.keys {
            state.theaters[theaterId]?.neighborTheaterIds = (neighbors[theaterId] ?? [])
                .sorted { $0.rawValue < $1.rawValue }
        }
    }

    private func assignUnits(state: inout TheaterState, map: MapState, divisions: [Division]) {
        for theaterId in state.theaters.keys {
            state.theaters[theaterId]?.unitIds = []
            state.theaters[theaterId]?.supportEligibleUnitIds = []
        }

        var inactiveRedistributionIndexes: [TheaterId: Int] = [:]

        for division in divisions {
            guard let theaterId = state.dynamicTheaterId(for: division.coord, map: map),
                  state.theaters[theaterId] != nil else {
                continue
            }

            let targetTheaterId: TheaterId
            if state.theaters[theaterId]?.status == .inactive {
                let activeNeighbors = state.theaters[theaterId]?.neighborTheaterIds.filter {
                    state.theaters[$0]?.status == .active
                } ?? []
                guard !activeNeighbors.isEmpty else {
                    continue
                }
                let index = inactiveRedistributionIndexes[theaterId, default: 0]
                targetTheaterId = activeNeighbors[index % activeNeighbors.count]
                inactiveRedistributionIndexes[theaterId] = index + 1
            } else {
                targetTheaterId = theaterId
            }

            state.theaters[targetTheaterId]?.unitIds.append(division.id)
            if division.canAct && division.supplyState == .supplied {
                state.theaters[targetTheaterId]?.supportEligibleUnitIds.append(division.id)
            }
        }

        for theaterId in state.theaters.keys {
            state.theaters[theaterId]?.unitIds.sort()
            state.theaters[theaterId]?.supportEligibleUnitIds.sort()
        }
    }

    private func calculateMetrics(
        for theater: TheaterNode,
        state: TheaterState,
        map: MapState
    ) -> (
        controlRatios: [Faction: Double],
        controllingFaction: Faction?,
        victoryPointArea: Int,
        frontWeight: Int
    ) {
        let theaterHexes = map.tiles.keys.filter {
            state.dynamicTheaterId(for: $0, map: map) == theater.id
        }
        let regions = theater.regionIds.compactMap { map.regions[$0] }
        let totalArea = max(1, theaterHexes.reduce(0) { total, hex in
            guard let regionId = map.region(for: hex),
                  let region = map.region(id: regionId) else {
                return total
            }
            return total + hexWeight(hex, in: region, map: map)
        })
        var areaByFaction: [Faction: Int] = [:]
        var victoryPointArea = 0
        var frontWeight = 0

        for region in regions {
            for hex in region.displayHexes where state.dynamicTheaterId(for: hex, map: map) == theater.id {
                guard let controller = map.tile(at: hex)?.controller else { continue }
                areaByFaction[controller, default: 0] += hexWeight(hex, in: region, map: map)
            }
            if let city = region.city {
                victoryPointArea += max(1, city.victoryPoints) * max(1, region.displayHexes.count)
            }
            frontWeight += region.displayHexes.count { hex in
                guard state.dynamicTheaterId(for: hex, map: map) == theater.id else {
                    return false
                }
                return hex.neighbors.contains { neighborHex in
                    guard map.tile(at: neighborHex) != nil,
                          let neighborTheaterId = state.dynamicTheaterId(for: neighborHex, map: map),
                          neighborTheaterId != theater.id else {
                        return false
                    }
                    return state.theaters[neighborTheaterId]?.controllingFaction != theater.controllingFaction
                }
            }
        }

        var ratios: [Faction: Double] = [:]
        for faction in Faction.allCases {
            ratios[faction] = Double(areaByFaction[faction] ?? 0) / Double(totalArea)
        }

        let sortedControl = Faction.allCases.sorted {
            let lhs = ratios[$0] ?? 0
            let rhs = ratios[$1] ?? 0
            return lhs == rhs ? $0.rawValue < $1.rawValue : lhs > rhs
        }
        let controllingFaction: Faction?
        if let top = sortedControl.first,
           let topRatio = ratios[top],
           topRatio > 0,
           sortedControl.dropFirst().allSatisfy({ (ratios[$0] ?? 0) < topRatio }) {
            controllingFaction = top
        } else {
            controllingFaction = nil
        }

        return (ratios, controllingFaction, victoryPointArea, frontWeight)
    }

    private func controlRatio(
        for faction: Faction,
        inBasicRegionOf regionId: RegionId,
        state: TheaterState,
        map: MapState
    ) -> Double {
        guard let baseTheaterId = state.initialSnapshot?.regionToTheater[regionId] ?? state.regionToTheater[regionId] else {
            return 0
        }

        let regionIds = (state.initialSnapshot?.regionToTheater ?? state.regionToTheater)
            .filter { $0.value == baseTheaterId }
            .map(\.key)
        var owned = 0
        var total = 0
        for regionId in regionIds {
            guard let region = map.region(id: regionId) else { continue }
            for hex in region.displayHexes {
                let weight = hexWeight(hex, in: region, map: map)
                total += weight
                if map.tile(at: hex)?.controller == faction {
                    owned += weight
                }
            }
        }
        return total == 0 ? 0 : Double(owned) / Double(total)
    }

    private func weightedArea(for region: RegionNode, map: MapState) -> Int {
        max(1, region.displayHexes.reduce(0) { $0 + hexWeight($1, in: region, map: map) })
    }

    private func hexWeight(_ hex: HexCoord, in region: RegionNode, map: MapState) -> Int {
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

    private func retire(theaterId: TheaterId, state: inout TheaterState) {
        state.theaters[theaterId]?.status = .inactive
        state.theaters[theaterId]?.unitIds = []
        state.theaters[theaterId]?.supportEligibleUnitIds = []
    }
}
