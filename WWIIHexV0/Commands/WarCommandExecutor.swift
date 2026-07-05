import Foundation

struct WarCommandExecutionResult: Equatable {
    let directive: ZoneDirective
    let generatedCommands: [Command]
    let commandResults: [CommandResult]
    let finalState: GameState

    var succeeded: Bool {
        !generatedCommands.isEmpty && commandResults.allSatisfy(\.succeeded)
    }
}

struct WarCommandExecutor {
    let commandHandler: GameCommandHandling

    private struct AttackTacticProfile {
        let includeDepthUnits: Bool
        let mobileOnlyWhenAvailable: Bool
        let artilleryFirst: Bool
        let attackOnly: Bool
        let weakPointFocus: Bool
        let allowDeepTarget: Bool
        let holdNonCommittedFront: Bool
        let committedUnitLimit: Int?
    }

    private struct AttackUnitSortKey: Comparable {
        let artilleryPriority: Int
        let mobilePriority: Int
        let attackPower: Int
        let movement: Int
        let strength: Int
        let id: String

        static func < (lhs: AttackUnitSortKey, rhs: AttackUnitSortKey) -> Bool {
            if lhs.artilleryPriority != rhs.artilleryPriority {
                return lhs.artilleryPriority > rhs.artilleryPriority
            }
            if lhs.mobilePriority != rhs.mobilePriority {
                return lhs.mobilePriority > rhs.mobilePriority
            }
            if lhs.attackPower != rhs.attackPower {
                return lhs.attackPower > rhs.attackPower
            }
            if lhs.movement != rhs.movement {
                return lhs.movement > rhs.movement
            }
            if lhs.strength != rhs.strength {
                return lhs.strength > rhs.strength
            }
            return lhs.id < rhs.id
        }
    }

    private struct ReserveSortKey: Comparable {
        let mobilePriority: Int
        let defensePower: Int
        let strength: Int
        let id: String

        static func < (lhs: ReserveSortKey, rhs: ReserveSortKey) -> Bool {
            if lhs.mobilePriority != rhs.mobilePriority {
                return lhs.mobilePriority > rhs.mobilePriority
            }
            if lhs.defensePower != rhs.defensePower {
                return lhs.defensePower > rhs.defensePower
            }
            if lhs.strength != rhs.strength {
                return lhs.strength > rhs.strength
            }
            return lhs.id < rhs.id
        }
    }

    private struct BreakthroughRegionSortKey: Comparable {
        let enemyStrength: Int
        let terrainCost: Int
        let roadPenalty: Int
        let valueScore: Int
        let id: String

        static func < (lhs: BreakthroughRegionSortKey, rhs: BreakthroughRegionSortKey) -> Bool {
            if lhs.enemyStrength != rhs.enemyStrength {
                return lhs.enemyStrength < rhs.enemyStrength
            }
            if lhs.terrainCost != rhs.terrainCost {
                return lhs.terrainCost < rhs.terrainCost
            }
            if lhs.roadPenalty != rhs.roadPenalty {
                return lhs.roadPenalty < rhs.roadPenalty
            }
            if lhs.valueScore != rhs.valueScore {
                return lhs.valueScore > rhs.valueScore
            }
            return lhs.id < rhs.id
        }
    }

    init(commandHandler: GameCommandHandling = RuleEngine()) {
        self.commandHandler = commandHandler
    }

    func execute(
        _ directive: ZoneDirective,
        in state: GameState,
        excluding excludedDivisionIds: Set<String> = []
    ) -> WarCommandExecutionResult {
        if let tactic = directive.tactic {
            return executeTactic(
                directive,
                tactic: tactic,
                in: state,
                excluding: excludedDivisionIds
            )
        }

        switch directive.parameters {
        case .defend(let parameters):
            return executeDefense(
                directive,
                parameters: parameters,
                in: state,
                excluding: excludedDivisionIds
            )
        case .attack(let parameters):
            return executeAttack(
                directive,
                parameters: parameters,
                in: state,
                excluding: excludedDivisionIds
            )
        }
    }

    private func executeTactic(
        _ directive: ZoneDirective,
        tactic: TacticName,
        in state: GameState,
        excluding excludedDivisionIds: Set<String>
    ) -> WarCommandExecutionResult {
        switch tactic {
        case .standardAttack,
             .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .fireCoverage,
             .feint,
             .guerrillaWarfare:
            guard case .attack(let parameters) = directive.parameters else {
                return emptyResult(directive: directive, state: state)
            }
            return executeAttack(
                directive,
                parameters: parameters,
                tactic: tactic,
                in: state,
                excluding: excludedDivisionIds
            )
        case .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            guard case .defend(let parameters) = directive.parameters else {
                return emptyResult(directive: directive, state: state)
            }
            return executeDefense(
                directive,
                parameters: parameters,
                tactic: tactic,
                in: state,
                excluding: excludedDivisionIds
            )
        }
    }

    private func emptyResult(directive: ZoneDirective, state: GameState) -> WarCommandExecutionResult {
        WarCommandExecutionResult(
            directive: directive,
            generatedCommands: [],
            commandResults: [],
            finalState: state
        )
    }

    private func executeDefense(
        _ directive: ZoneDirective,
        parameters: DefenseParameters,
        tactic: TacticName = .holdPosition,
        in state: GameState,
        excluding excludedDivisionIds: Set<String>
    ) -> WarCommandExecutionResult {
        guard let zone = state.warDeploymentState.frontZones[directive.zoneId],
              !zone.frontSegments.isEmpty else {
            return WarCommandExecutionResult(
                directive: directive,
                generatedCommands: [],
                commandResults: [],
                finalState: state
            )
        }

        if tactic == .defenseInDepth {
            return executeDefenseInDepth(
                directive,
                parameters: parameters,
                zone: zone,
                in: state,
                excluding: excludedDivisionIds
            )
        }

        var nextState = state
        var commands: [Command] = []
        var results: [CommandResult] = []
        let relatedRecordId = "war_directive_\(directive.zoneId.rawValue)_\(directive.type.rawValue)"
        var segmentLoads = Dictionary(
            uniqueKeysWithValues: zone.frontSegments.map {
                ($0.regionId, $0.assignedFrontUnitIds.count)
            }
        )
        let availableDepth = zone.unitsDepth.sorted().filter { !excludedDivisionIds.contains($0) }
        let reserveCount = min(tactic == .lastStand ? 0 : parameters.targetReserves, availableDepth.count)
        let depthFillers = Array(availableDepth.dropFirst(reserveCount))
        let frontUnits = limitedFrontUnits(
            zone.unitsFront.filter { !excludedDivisionIds.contains($0) },
            maxCommitment: parameters.maxFrontCommitment
        )
        let unitIds = stableUnique(frontUnits + depthFillers)
        let stance: DefenseStance = (tactic == .elasticDefense) ? .flexible : parameters.stance

        for unitId in unitIds {
            guard let division = nextState.division(id: unitId),
                  division.faction == zone.faction,
                  division.canAct else {
                continue
            }

            guard let targetRegionId = lightestFrontRegion(in: zone, loads: segmentLoads) else {
                continue
            }

            let command: Command
            if division.location(in: nextState.map) == targetRegionId {
                command = stance == .holdLine
                    ? .hold(divisionId: division.id)
                    : .allowRetreat(divisionId: division.id)
            } else if let destination = tacticalDestination(
                in: targetRegionId,
                for: division,
                state: nextState
            ) {
                command = .move(divisionId: division.id, destination: destination)
            } else {
                command = stance == .holdLine
                    ? .hold(divisionId: division.id)
                    : .allowRetreat(divisionId: division.id)
            }

            run(
                command,
                fallback: .hold(divisionId: division.id),
                commands: &commands,
                results: &results,
                state: &nextState,
                relatedRecordId: relatedRecordId
            )
            segmentLoads[targetRegionId, default: 0] += 1
        }

        return WarCommandExecutionResult(
            directive: directive,
            generatedCommands: commands,
            commandResults: results,
            finalState: nextState
        )
    }

    private func executeAttack(
        _ directive: ZoneDirective,
        parameters: AttackParameters,
        tactic: TacticName = .standardAttack,
        in state: GameState,
        excluding excludedDivisionIds: Set<String>
    ) -> WarCommandExecutionResult {
        guard let zone = state.warDeploymentState.frontZones[directive.zoneId] else {
            return WarCommandExecutionResult(
                directive: directive,
                generatedCommands: [],
                commandResults: [],
                finalState: state
            )
        }

        let targetZoneId = FrontZoneId(parameters.targetTheaterId.rawValue)
        let sourceSegments = zone.frontSegments.filter { $0.neighborEnemyZone == targetZoneId }
        let segments = sourceSegments.isEmpty ? zone.frontSegments : sourceSegments
        let profile = attackTacticProfile(for: tactic, parameters: parameters, zone: zone)
        let attackingUnitIds = attackingUnitIds(
            for: zone,
            profile: profile,
            state: state,
            excluding: excludedDivisionIds
        )
        let commandTargetRegionId: RegionId?
        if case .region(let regionId) = directive.commandTarget {
            commandTargetRegionId = regionId
        } else {
            commandTargetRegionId = nil
        }

        var nextState = state
        var commands: [Command] = []
        var results: [CommandResult] = []
        let relatedRecordId = "war_directive_\(directive.zoneId.rawValue)_\(directive.type.rawValue)"

        if tactic == .fireCoverage {
            runPreparatoryFire(
                from: attackingUnitIds,
                targetRegionIds: parameters.weightedRegions,
                commands: &commands,
                results: &results,
                state: &nextState,
                relatedRecordId: relatedRecordId
            )
        }

        for unitId in attackingUnitIds {
            guard let division = nextState.division(id: unitId),
                  division.faction == zone.faction,
                  division.canAct else {
                continue
            }

            guard let targetRegionId = targetEnemyRegion(
                for: division,
                zone: zone,
                targetZoneId: targetZoneId,
                segments: segments,
                parameters: parameters,
                commandTargetRegionId: commandTargetRegionId,
                tactic: tactic,
                profile: profile,
                state: nextState
            ) else {
                continue
            }

            let command: Command
            if let target = visibleEnemyDivision(
                in: [targetRegionId],
                for: division,
                zone: zone,
                state: nextState
            ) {
                command = .attack(attackerId: division.id, targetId: target.id)
            } else if profile.attackOnly {
                command = .hold(divisionId: division.id)
            } else if let destination = tacticalDestination(
                in: targetRegionId,
                for: division,
                state: nextState
            ) {
                command = .move(divisionId: division.id, destination: destination)
            } else {
                command = .hold(divisionId: division.id)
            }

            run(
                command,
                fallback: .hold(divisionId: division.id),
                commands: &commands,
                results: &results,
                state: &nextState,
                relatedRecordId: relatedRecordId
            )
        }

        if profile.holdNonCommittedFront {
            let committed = Set(attackingUnitIds)
            let remainingFrontIds = stableUnique(zone.unitsFront)
                .filter { !committed.contains($0) && !excludedDivisionIds.contains($0) }
            for unitId in remainingFrontIds {
                guard let division = nextState.division(id: unitId),
                      division.faction == zone.faction,
                      division.canAct else {
                    continue
                }
                run(
                    .hold(divisionId: division.id),
                    fallback: .hold(divisionId: division.id),
                    commands: &commands,
                    results: &results,
                    state: &nextState,
                    relatedRecordId: relatedRecordId
                )
            }
        }

        return WarCommandExecutionResult(
            directive: directive,
            generatedCommands: commands,
            commandResults: results,
            finalState: nextState
        )
    }

    private func executeDefenseInDepth(
        _ directive: ZoneDirective,
        parameters: DefenseParameters,
        zone: FrontZone,
        in state: GameState,
        excluding excludedDivisionIds: Set<String>
    ) -> WarCommandExecutionResult {
        var nextState = state
        var commands: [Command] = []
        var results: [CommandResult] = []
        let relatedRecordId = "war_directive_\(directive.zoneId.rawValue)_\(directive.type.rawValue)"
        let frontUnitIds = limitedFrontUnits(
            zone.unitsFront.filter { !excludedDivisionIds.contains($0) },
            maxCommitment: parameters.maxFrontCommitment
        )
        let availableDepth = zone.unitsDepth.filter { !excludedDivisionIds.contains($0) }
        let reserveCount = min(max(1, parameters.targetReserves), availableDepth.count)
        let reserveSorted = availableDepth.sorted {
            reserveSortKey(for: $0, state: nextState) < reserveSortKey(for: $1, state: nextState)
        }
        let counterattackUnitIds = Array(reserveSorted.dropFirst(reserveCount))
        let counterattackRegions = parameters.counterattackRegionIds ?? visibleEnemyRegionIds(
            zone: zone,
            targetZoneId: nil,
            state: nextState
        )

        for unitId in stableUnique(frontUnitIds + counterattackUnitIds) {
            guard let division = nextState.division(id: unitId),
                  division.faction == zone.faction,
                  division.canAct else {
                continue
            }

            let command: Command
            if frontUnitIds.contains(division.id) {
                command = .allowRetreat(divisionId: division.id)
            } else if isMobile(division),
                      let target = visibleEnemyDivision(
                        in: counterattackRegions,
                        for: division,
                        zone: zone,
                        state: nextState
                      ) {
                command = .attack(attackerId: division.id, targetId: target.id)
            } else if let destination = defensiveDestination(
                for: division,
                zone: zone,
                parameters: parameters,
                state: nextState
            ) {
                command = .move(divisionId: division.id, destination: destination)
            } else {
                command = .hold(divisionId: division.id)
            }

            run(
                command,
                fallback: .allowRetreat(divisionId: division.id),
                commands: &commands,
                results: &results,
                state: &nextState,
                relatedRecordId: relatedRecordId
            )
        }

        return WarCommandExecutionResult(
            directive: directive,
            generatedCommands: commands,
            commandResults: results,
            finalState: nextState
        )
    }

    private func attackTacticProfile(
        for tactic: TacticName,
        parameters: AttackParameters,
        zone: FrontZone
    ) -> AttackTacticProfile {
        let explicitLimit = attackCommitmentLimit(
            explicitLimit: parameters.maxCommittedUnits,
            defaultLimit: nil,
            intensity: parameters.intensity,
            zone: zone
        )
        switch tactic {
        case .blitzkrieg:
            return AttackTacticProfile(
                includeDepthUnits: true,
                mobileOnlyWhenAvailable: true,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: true,
                allowDeepTarget: true,
                holdNonCommittedFront: true,
                committedUnitLimit: explicitLimit
            )
        case .breakthrough:
            return AttackTacticProfile(
                includeDepthUnits: true,
                mobileOnlyWhenAvailable: false,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: true,
                allowDeepTarget: (parameters.exploitDepth ?? 0) > 0,
                holdNonCommittedFront: false,
                committedUnitLimit: explicitLimit
            )
        case .spearhead:
            return AttackTacticProfile(
                includeDepthUnits: true,
                mobileOnlyWhenAvailable: true,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: true,
                allowDeepTarget: true,
                holdNonCommittedFront: true,
                committedUnitLimit: explicitLimit
            )
        case .pincerMovement:
            return AttackTacticProfile(
                includeDepthUnits: true,
                mobileOnlyWhenAvailable: true,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: true,
                allowDeepTarget: true,
                holdNonCommittedFront: false,
                committedUnitLimit: explicitLimit
            )
        case .fireCoverage:
            return AttackTacticProfile(
                includeDepthUnits: true,
                mobileOnlyWhenAvailable: false,
                artilleryFirst: true,
                attackOnly: true,
                weakPointFocus: false,
                allowDeepTarget: false,
                holdNonCommittedFront: false,
                committedUnitLimit: explicitLimit
            )
        case .feint:
            let defaultLimit = max(1, max(zone.unitsFront.count, 1) / 3)
            return AttackTacticProfile(
                includeDepthUnits: false,
                mobileOnlyWhenAvailable: false,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: false,
                allowDeepTarget: false,
                holdNonCommittedFront: false,
                committedUnitLimit: attackCommitmentLimit(
                    explicitLimit: parameters.maxCommittedUnits,
                    defaultLimit: defaultLimit,
                    intensity: parameters.intensity,
                    zone: zone
                )
            )
        case .guerrillaWarfare:
            let defaultLimit = max(1, max(zone.unitsFront.count + zone.unitsDepth.count, 1) / 2)
            return AttackTacticProfile(
                includeDepthUnits: true,
                mobileOnlyWhenAvailable: true,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: true,
                allowDeepTarget: true,
                holdNonCommittedFront: false,
                committedUnitLimit: attackCommitmentLimit(
                    explicitLimit: parameters.maxCommittedUnits,
                    defaultLimit: defaultLimit,
                    intensity: parameters.intensity,
                    zone: zone
                )
            )
        case .standardAttack,
             .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            return AttackTacticProfile(
                includeDepthUnits: false,
                mobileOnlyWhenAvailable: false,
                artilleryFirst: false,
                attackOnly: false,
                weakPointFocus: false,
                allowDeepTarget: false,
                holdNonCommittedFront: false,
                committedUnitLimit: explicitLimit
            )
        }
    }

    private func attackCommitmentLimit(
        explicitLimit: Int?,
        defaultLimit: Int?,
        intensity: AttackIntensity,
        zone: FrontZone
    ) -> Int? {
        if let explicitLimit {
            return explicitLimit
        }

        if let defaultLimit {
            return defaultLimit
        }

        switch intensity {
        case .allOut,
             .limitedCounter:
            return nil
        case .infiltration:
            let candidateCount = max(zone.unitsFront.count + zone.unitsDepth.count, 1)
            return max(1, candidateCount / 2)
        }
    }

    private func attackingUnitIds(
        for zone: FrontZone,
        profile: AttackTacticProfile,
        state: GameState,
        excluding excludedDivisionIds: Set<String>
    ) -> [String] {
        let fallbackDepth = zone.unitsFront.isEmpty ? zone.unitsDepth : []
        let baseIds = stableUnique(zone.unitsFront + (profile.includeDepthUnits ? zone.unitsDepth : fallbackDepth))
            .filter { !excludedDivisionIds.contains($0) }
        let activeIds = baseIds.filter { unitId in
            guard let division = state.division(id: unitId) else {
                return false
            }
            return division.faction == zone.faction && division.canAct
        }
        let mobileIds = activeIds.filter { unitId in
            state.division(id: unitId).map { isMobile($0) } == true
        }
        let candidateIds = profile.mobileOnlyWhenAvailable && !mobileIds.isEmpty ? mobileIds : activeIds
        let sortedIds = candidateIds.sorted {
            attackSortKey(for: $0, profile: profile, state: state) <
                attackSortKey(for: $1, profile: profile, state: state)
        }

        if let limit = profile.committedUnitLimit, limit > 0 {
            return Array(sortedIds.prefix(limit))
        }
        return sortedIds
    }

    private func targetEnemyRegion(
        for division: Division,
        zone: FrontZone,
        targetZoneId: FrontZoneId,
        segments: [FrontZoneSegment],
        parameters: AttackParameters,
        commandTargetRegionId: RegionId?,
        tactic: TacticName,
        profile: AttackTacticProfile,
        state: GameState
    ) -> RegionId? {
        let adjacentEnemyRegions = enemyRegions(
            for: segments,
            targetZoneId: targetZoneId,
            zone: zone,
            state: state
        )
        let priorityRegions = orderedUnique(
            [parameters.focusRegionId, commandTargetRegionId, parameters.convergenceRegionId].compactMap { $0 }
            + parameters.weightedRegions
            + (parameters.supportRegionIds ?? [])
        )
        let priorityCandidates = priorityRegions.filter {
            adjacentEnemyRegions.contains($0)
                || (profile.allowDeepTarget && state.map.region(id: $0) != nil)
        }
        var candidates = orderedUnique(priorityCandidates + adjacentEnemyRegions)

        if profile.weakPointFocus,
           let weakPoint = bestBreakthroughRegion(
            candidates: candidates,
            zone: zone,
            tactic: tactic,
            state: state
           ) {
            candidates = orderedUnique([weakPoint] + candidates)
        }

        if let target = visibleEnemyDivision(
            in: candidates,
            for: division,
            zone: zone,
            state: state
        ) {
            return target.location(in: state.map)
        }

        return candidates.first
    }

    private func limitedFrontUnits(_ unitIds: [String], maxCommitment: Int?) -> [String] {
        guard let maxCommitment, maxCommitment > 0 else {
            return unitIds
        }
        return Array(unitIds.prefix(maxCommitment))
    }

    private func visibleEnemyRegionIds(
        zone: FrontZone,
        targetZoneId: FrontZoneId?,
        state: GameState
    ) -> [RegionId] {
        let targetZoneIds = targetZoneId.map { [$0] }
            ?? stableUnique(zone.frontSegments.map(\.neighborEnemyZone))
        return orderedUnique(targetZoneIds.flatMap { enemyZoneId in
            let segments = zone.frontSegments.filter { $0.neighborEnemyZone == enemyZoneId }
            return enemyRegions(for: segments, targetZoneId: enemyZoneId, zone: zone, state: state)
        })
    }

    private func attackSortKey(
        for unitId: String,
        profile: AttackTacticProfile,
        state: GameState
    ) -> AttackUnitSortKey {
        guard let division = state.division(id: unitId) else {
            return AttackUnitSortKey(
                artilleryPriority: 0,
                mobilePriority: 0,
                attackPower: 0,
                movement: 0,
                strength: 0,
                id: unitId
            )
        }

        return AttackUnitSortKey(
            artilleryPriority: profile.artilleryFirst && division.isArtillery ? 1 : 0,
            mobilePriority: isMobile(division) ? 1 : 0,
            attackPower: division.attack,
            movement: division.movement,
            strength: division.strength,
            id: division.id
        )
    }

    private func reserveSortKey(for unitId: String, state: GameState) -> ReserveSortKey {
        guard let division = state.division(id: unitId) else {
            return ReserveSortKey(mobilePriority: 0, defensePower: 0, strength: 0, id: unitId)
        }

        return ReserveSortKey(
            mobilePriority: isMobile(division) ? 1 : 0,
            defensePower: division.defense,
            strength: division.strength,
            id: division.id
        )
    }

    private func bestBreakthroughRegion(
        candidates: [RegionId],
        zone: FrontZone,
        tactic: TacticName,
        state: GameState
    ) -> RegionId? {
        candidates
            .filter { state.map.region(id: $0) != nil }
            .sorted {
                breakthroughSortKey(for: $0, zone: zone, tactic: tactic, state: state) <
                    breakthroughSortKey(for: $1, zone: zone, tactic: tactic, state: state)
            }
            .first
    }

    private func breakthroughSortKey(
        for regionId: RegionId,
        zone: FrontZone,
        tactic: TacticName,
        state: GameState
    ) -> BreakthroughRegionSortKey {
        guard let region = state.map.region(id: regionId) else {
            return BreakthroughRegionSortKey(
                enemyStrength: Int.max,
                terrainCost: Int.max,
                roadPenalty: 1,
                valueScore: 0,
                id: regionId.rawValue
            )
        }

        let enemyStrength = enemyStrength(in: regionId, against: zone.faction, state: state)
        let roadPenalty = region.displayHexes.contains { state.map.tile(at: $0)?.hasRoad == true } ? 0 : 1
        var valueScore = (region.city?.victoryPoints ?? 0) + region.supplyValue + region.factories
        if tactic == .guerrillaWarfare {
            valueScore += region.infrastructure
        }

        return BreakthroughRegionSortKey(
            enemyStrength: enemyStrength,
            terrainCost: region.terrain.movementCost,
            roadPenalty: roadPenalty,
            valueScore: valueScore,
            id: regionId.rawValue
        )
    }

    private func enemyStrength(
        in regionId: RegionId,
        against faction: Faction,
        state: GameState
    ) -> Int {
        state.operationalAwareness.visibleContacts(for: faction)
            .filter { contact in
                state.map.region(for: contact.lastKnownCoord) == regionId
            }
            .reduce(0) { $0 + VisibilityRules().contactStrengthEstimate($1) }
    }

    private func defensiveDestination(
        for division: Division,
        zone: FrontZone,
        parameters: DefenseParameters,
        state: GameState
    ) -> HexCoord? {
        let preferredRegionIds = orderedUnique(
            (parameters.strongpointRegionIds ?? [])
            + (parameters.fallbackRegionIds ?? [])
            + zone.frontSegments.map(\.regionId)
        )
        let movementRange = MovementRules().movementRange(for: division, in: state)
        var candidateHexes: [HexCoord] = []
        for regionId in preferredRegionIds {
            guard let region = state.map.region(id: regionId) else {
                continue
            }
            let regionHexes: [HexCoord] = stableUnique([region.representativeHex] + region.displayHexes)
            for hex in regionHexes where hex != division.coord {
                guard movementRange.contains(hex),
                      state.map.tile(at: hex)?.isPassable == true,
                      state.division(at: hex) == nil else {
                    continue
                }
                candidateHexes.append(hex)
            }
        }

        return candidateHexes.sorted {
            let lhsDefense = state.map.tile(at: $0)?.baseTerrain.defenseBonus ?? 0
            let rhsDefense = state.map.tile(at: $1)?.baseTerrain.defenseBonus ?? 0
            if lhsDefense != rhsDefense {
                return lhsDefense > rhsDefense
            }
            let lhsFriendly = state.map.tile(at: $0)?.controller == division.faction
            let rhsFriendly = state.map.tile(at: $1)?.controller == division.faction
            if lhsFriendly != rhsFriendly {
                return lhsFriendly
            }
            let lhsDistance = division.coord.distance(to: $0)
            let rhsDistance = division.coord.distance(to: $1)
            if lhsDistance == rhsDistance {
                if $0.q == $1.q {
                    return $0.r < $1.r
                }
                return $0.q < $1.q
            }
            return lhsDistance < rhsDistance
        }.first
    }

    private func isMobile(_ division: Division) -> Bool {
        division.isArmor
            || division.isMechanized
            || division.movement >= 5
    }

    private func enemyRegions(
        for segments: [FrontZoneSegment],
        targetZoneId: FrontZoneId,
        zone: FrontZone,
        state: GameState
    ) -> [RegionId] {
        var regionIds: [RegionId] = []
        for segment in segments.sorted(by: { $0.regionId.rawValue < $1.regionId.rawValue }) {
            if state.map.regions[segment.regionId]?.controller != zone.faction ||
                hasEnemyPresence(in: segment.regionId, zone: zone, state: state) {
                regionIds.append(segment.regionId)
            }
            let neighbors = state.map.neighbors(of: segment.regionId).filter { neighborId in
                guard dynamicRegionTouchesZone(
                    sourceRegionId: segment.regionId,
                    neighborRegionId: neighborId,
                    targetZoneId: targetZoneId,
                    state: state
                ),
                    (state.map.regions[neighborId]?.controller != zone.faction ||
                     hasEnemyPresence(in: neighborId, zone: zone, state: state)) else {
                    return false
                }
                return true
            }
            regionIds.append(contentsOf: neighbors.sorted { $0.rawValue < $1.rawValue })
        }
        return stableUnique(regionIds)
    }

    private func dynamicRegionTouchesZone(
        sourceRegionId: RegionId,
        neighborRegionId: RegionId,
        targetZoneId: FrontZoneId,
        state: GameState
    ) -> Bool {
        guard let sourceRegion = state.map.region(id: sourceRegionId),
              let neighborRegion = state.map.region(id: neighborRegionId) else {
            return false
        }
        let neighborHexes = Set(neighborRegion.displayHexes)
        for hex in sourceRegion.displayHexes {
            guard state.warDeploymentState.zoneId(for: hex, map: state.map) != targetZoneId else {
                continue
            }
            for neighborHex in hex.neighbors where neighborHexes.contains(neighborHex) {
                if state.warDeploymentState.zoneId(for: neighborHex, map: state.map) == targetZoneId {
                    return true
                }
            }
        }
        return false
    }

    private func hasEnemyPresence(
        in regionId: RegionId,
        zone: FrontZone,
        state: GameState
    ) -> Bool {
        state.operationalAwareness.visibleContacts(for: zone.faction).contains { contact in
            state.map.region(for: contact.lastKnownCoord) == regionId
        }
    }

    private func visibleEnemyDivision(
        in regionIds: [RegionId],
        for division: Division,
        zone: FrontZone,
        state: GameState
    ) -> Division? {
        let regionSet = Set(regionIds)
        return state.operationalAwareness.visibleContacts(for: zone.faction)
            .compactMap { contact -> (contact: ContactTrack, target: Division)? in
                guard contact.confidence >= .medium,
                      let linkedDivisionId = contact.linkedDivisionId,
                      let target = state.division(id: linkedDivisionId),
                      target.faction.isHostile(to: zone.faction),
                      !target.isDestroyed,
                      let targetRegion = target.location(in: state.map),
                      regionSet.contains(targetRegion) else {
                    return nil
                }
                guard division.coord.distance(to: target.coord) <= division.range else {
                    return nil
                }
                return (contact, target)
            }
            .sorted {
                if $0.contact.confidence != $1.contact.confidence {
                    return $0.contact.confidence > $1.contact.confidence
                }
                if $0.target.strength == $1.target.strength {
                    return $0.target.id < $1.target.id
                }
                return $0.target.strength < $1.target.strength
            }
            .first?
            .target
    }

    private func tacticalDestination(
        in regionId: RegionId,
        for division: Division,
        state: GameState
    ) -> HexCoord? {
        guard let region = state.map.region(id: regionId) else {
            return nil
        }

        let regionTargets = stableUnique([region.representativeHex] + region.displayHexes)
        let candidates = regionTargets
            .filter { state.map.tile(at: $0)?.isPassable == true }
            .filter { hex in
                guard let occupying = state.division(at: hex) else {
                    return true
                }
                return occupying.id == division.id
            }
            .sorted {
                let lhsIsCurrent = $0 == division.coord
                let rhsIsCurrent = $1 == division.coord
                if lhsIsCurrent != rhsIsCurrent {
                    return !lhsIsCurrent
                }
                let lhsEnemyControlled = state.map.tile(at: $0)?.controller?.isHostile(to: division.faction) == true
                let rhsEnemyControlled = state.map.tile(at: $1)?.controller?.isHostile(to: division.faction) == true
                if lhsEnemyControlled != rhsEnemyControlled {
                    return lhsEnemyControlled
                }
                let lhsDistance = division.coord.distance(to: $0)
                let rhsDistance = division.coord.distance(to: $1)
                if lhsDistance == rhsDistance {
                    if $0.q == $1.q {
                        return $0.r < $1.r
                    }
                    return $0.q < $1.q
                }
                return lhsDistance < rhsDistance
            }

        if let destination = candidates.first(where: { $0 != division.coord && division.coord.distance(to: $0) <= division.movement }) {
            return destination
        }

        if let current = candidates.first(where: { $0 == division.coord && state.map.tile(at: $0)?.controller != division.faction }) {
            return current
        }

        return approachDestination(toward: regionTargets, for: division, state: state)
    }

    private func approachDestination(
        toward targets: [HexCoord],
        for division: Division,
        state: GameState
    ) -> HexCoord? {
        let movementRange = MovementRules().movementRange(for: division, in: state)
        return movementRange
            .filter { $0 != division.coord }
            .filter { state.division(at: $0) == nil }
            .sorted {
                let lhsDistance = nearestDistance(from: $0, to: targets)
                let rhsDistance = nearestDistance(from: $1, to: targets)
                if lhsDistance == rhsDistance {
                    let lhsEnemyControlled = state.map.tile(at: $0)?.controller?.isHostile(to: division.faction) == true
                    let rhsEnemyControlled = state.map.tile(at: $1)?.controller?.isHostile(to: division.faction) == true
                    if lhsEnemyControlled != rhsEnemyControlled {
                        return lhsEnemyControlled
                    }
                    if $0.q == $1.q {
                        return $0.r < $1.r
                    }
                    return $0.q < $1.q
                }
                return lhsDistance < rhsDistance
            }
            .first
    }

    private func nearestDistance(from coord: HexCoord, to targets: [HexCoord]) -> Int {
        targets.map { coord.distance(to: $0) }.min() ?? Int.max
    }

    private func lightestFrontRegion(in zone: FrontZone, loads: [RegionId: Int]) -> RegionId? {
        zone.frontSegments
            .map(\.regionId)
            .sorted {
                let lhsLoad = loads[$0, default: 0]
                let rhsLoad = loads[$1, default: 0]
                if lhsLoad == rhsLoad {
                    return $0.rawValue < $1.rawValue
                }
                return lhsLoad < rhsLoad
            }
            .first
    }

    private func run(
        _ command: Command,
        fallback: Command,
        commands: inout [Command],
        results: inout [CommandResult],
        state: inout GameState,
        relatedRecordId: String?
    ) {
        let actingDivisionId = actingDivisionId(for: command)
        let sourceZoneId = actingDivisionId
            .flatMap { logicalZoneId(for: $0, in: state.warDeploymentState) }
            ?? actingDivisionId
                .flatMap { state.division(id: $0) }
                .flatMap { $0.location(in: state.map) }
                .flatMap { state.warDeploymentState.regionToFrontZone[$0] }
        let beforeControllers = state.map.regions.mapValues(\.controller)
        let originalValidation = CommandValidator().validate(command, in: state)
        let result = commandHandler.execute(command, in: state)
        commands.append(command)
        results.append(result)

        if !result.succeeded {
            let rejectionReasons = result.validation.errors.map(\.rawValue).joined(separator: ", ")
            state.appendEvent(
                "Directive command rejected: \(rejectionReasons) for \(command.displayName).",
                category: .frontChange,
                relatedRecordId: relatedRecordId
            )
            let fallbackValidation = CommandValidator().validate(fallback, in: state)
            if !originalValidation.isValid,
               fallbackValidation.isValid,
               fallback != command {
                let fallbackResult = commandHandler.execute(fallback, in: state)
                commands.append(fallback)
                results.append(fallbackResult)
                state = fallbackResult.state
            }
            return
        }

        state = result.state
        let affectedRegionIds = affectedRegionIds(for: command, state: state)
        let occupiedRegionIds = occupiedRegionIds(for: command, state: state)
        let dynamicAdvancedRegionIds = stableUnique((affectedRegionIds + occupiedRegionIds).compactMap { regionId in
            applyStrategicAdvance(
                regionId: regionId,
                hex: moveDestination(for: command),
                sourceZoneId: sourceZoneId,
                command: command,
                state: &state,
                relatedRecordId: relatedRecordId
            )
        })
        let syncResult = StrategicStateSynchronizer().synchronizeAfterOccupationChange(
            in: &state,
            affectedRegionIds: stableUnique(affectedRegionIds + occupiedRegionIds + dynamicAdvancedRegionIds),
            relatedRecordId: relatedRecordId,
            emitRegionOwnerEvents: false
        )
        let changedRegionIds = stableUnique(
            syncResult.changedRegionIds + controllerChanges(from: beforeControllers, to: state.map)
        )
        for regionId in changedRegionIds {
            guard let region = state.map.region(id: regionId) else {
                continue
            }
            state.appendEvent(
                "Region \(regionId.rawValue) controller changed to \(region.controller.displayName) via \(command.displayName).",
                category: .regionOwnerChange,
                relatedRecordId: relatedRecordId
            )
        }
        if !syncResult.affectedRegionIds.isEmpty {
            state.theaterState = TheaterSystem().updateTheaters(
                state: state.theaterState,
                map: state.map,
                divisions: state.divisions,
                turn: state.turn,
                force: true
            )
            state.frontLineState = FrontLineManager().update(
                state: state.frontLineState,
                map: state.map,
                theaterState: state.theaterState,
                divisions: state.divisions,
                turn: state.turn,
                events: syncResult.affectedRegionIds.map { regionId in
                    changedRegionIds.contains(regionId)
                        ? FrontLineEvent.regionControllerChanged(regionId)
                        : FrontLineEvent.occupationChanged(regionId)
                }
            )
            let deploymentEvents = syncResult.affectedRegionIds.map(WarDeploymentEvent.regionControllerChanged)
                + (sourceZoneId.map { [WarDeploymentEvent.frontZoneChanged($0)] } ?? [])
            let deploymentBeforeUpdate = state.warDeploymentState
            state.warDeploymentState = WarDeploymentManager().update(
                state: state.warDeploymentState,
                map: state.map,
                divisions: state.divisions,
                turn: state.turn,
                events: deploymentEvents
            )
            .preservingGeneralAssignments(from: deploymentBeforeUpdate)
        }
    }

    private func runPreparatoryFire(
        from unitIds: [String],
        targetRegionIds: [RegionId],
        commands: inout [Command],
        results: inout [CommandResult],
        state: inout GameState,
        relatedRecordId: String?
    ) {
        guard let source = unitIds
            .compactMap({ state.division(id: $0) })
            .first(where: { $0.canAct && ($0.isArtillery || $0.hasUnmannedSupport) }),
            let contact = state.operationalAwareness.visibleContacts(for: source.faction)
                .first(where: { contact in
                    guard contact.confidence >= .medium,
                          let linkedDivisionId = contact.linkedDivisionId,
                          let targetDivision = state.division(id: linkedDivisionId),
                          targetDivision.faction.isHostile(to: source.faction) else {
                        return false
                    }
                    if targetRegionIds.isEmpty {
                        return true
                    }
                    return state.map.region(for: contact.lastKnownCoord).map { targetRegionIds.contains($0) } ?? false
                }) else {
            return
        }

        let munitionClass: MunitionClass = source.componentWeight(where: { $0 == .rocketArtillery }) >= 0.20
            ? .rocket
            : .tubeArtillery
        let command = Command.fireMission(
            issuerId: source.id,
            target: .contact(id: contact.id),
            munitionClass: munitionClass
        )
        run(
            command,
            fallback: .hold(divisionId: source.id),
            commands: &commands,
            results: &results,
            state: &state,
            relatedRecordId: relatedRecordId
        )
    }

    @discardableResult
    private func applyStrategicAdvance(
        regionId: RegionId,
        hex: HexCoord?,
        sourceZoneId: FrontZoneId?,
        command: Command,
        state: inout GameState,
        relatedRecordId: String?
    ) -> RegionId? {
        guard case .move = command,
              let advancingZoneId = sourceZoneId,
              let hex else {
            return nil
        }

        let advancingTheaterId = TheaterId(advancingZoneId.rawValue)
        guard state.theaterState.theaters[advancingTheaterId] != nil else {
            return nil
        }

        guard state.theaterState.dynamicTheaterId(for: hex, map: state.map) != advancingTheaterId else {
            return regionId
        }
        guard shouldAdvanceDynamicTheater(
            hex: hex,
            advancingZoneId: advancingZoneId,
            state: state
        ) else {
            return nil
        }

        let expansion = TheaterSystem().expandDynamicTheater(
            state: state.theaterState,
            map: state.map,
            divisions: state.divisions,
            breakthroughHex: hex,
            advancingTheaterId: advancingTheaterId,
            faction: state.warDeploymentState.frontZones[advancingZoneId]?.faction ?? .germany
        )
        state.theaterState = expansion.state

        let oldZoneId = state.warDeploymentState.zoneId(for: hex, map: state.map)
        if oldZoneId != advancingZoneId {
            state.warDeploymentState = WarDeploymentManager().advanceHex(
                hex,
                from: oldZoneId,
                to: advancingZoneId,
                state: state.warDeploymentState,
                map: state.map,
                divisions: state.divisions,
                turn: state.turn
            )
        }
        state.appendEvent(
            "Hex \(hex.q),\(hex.r) reassigned to operational zone \(advancingTheaterId.rawValue).",
            category: .theaterChange,
            relatedRecordId: relatedRecordId
        )
        state.appendEvent(
            "Front changed around region \(regionId.rawValue).",
            category: .frontChange,
            relatedRecordId: relatedRecordId
        )
        return regionId
    }

    private func shouldAdvanceDynamicTheater(
        hex: HexCoord,
        advancingZoneId: FrontZoneId,
        state: GameState
    ) -> Bool {
        guard let advancingFaction = state.warDeploymentState.frontZones[advancingZoneId]?.faction else {
            return false
        }

        let destinationZoneId = state.warDeploymentState.zoneId(for: hex, map: state.map)
        if let destinationZoneId,
           destinationZoneId != advancingZoneId,
           let destinationFaction = state.warDeploymentState.frontZones[destinationZoneId]?.faction {
            return destinationFaction != advancingFaction
        }

        if let controller = state.map.tile(at: hex)?.controller {
            return controller != advancingFaction
        }

        return false
    }

    private func actingDivisionId(for command: Command) -> String? {
        switch command {
        case .move(let divisionId, _),
             .hold(let divisionId),
             .allowRetreat(let divisionId),
             .resupply(let divisionId),
             .recon(let divisionId, _),
             .uavRecon(let divisionId, _),
             .electronicWarfare(let divisionId, _),
             .suppressAirDefense(let divisionId, _):
            return divisionId
        case .fireMission(let issuerId, _, _):
            return issuerId
        case .attack(let attackerId, _):
            return attackerId
        case .queueProduction,
             .endTurn:
            return nil
        }
    }

    private func logicalZoneId(for divisionId: String, in state: WarDeploymentState) -> FrontZoneId? {
        state.frontZones.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .first {
                $0.unitsFront.contains(divisionId)
                    || $0.unitsDepth.contains(divisionId)
                    || $0.unitsGarrison.contains(divisionId)
            }?
            .id
    }

    private func affectedRegionIds(for command: Command, state: GameState) -> [RegionId] {
        switch command {
        case .move(_, let destination):
            return state.map.region(for: destination).map { [$0] } ?? []
        case .fireMission(_, let target, _):
            switch target {
            case .contact(let id):
                return state.operationalAwareness.contacts[id]
                    .flatMap { state.map.region(for: $0.lastKnownCoord) }
                    .map { [$0] } ?? []
            case .hex(let coord):
                return state.map.region(for: coord).map { [$0] } ?? []
            case .region(let regionId):
                return [regionId]
            }
        case .suppressAirDefense(_, let target),
             .uavRecon(_, let target):
            return state.map.region(for: target).map { [$0] } ?? []
        default:
            return []
        }
    }

    private func moveDestination(for command: Command) -> HexCoord? {
        if case .move(_, let destination) = command {
            return destination
        }
        return nil
    }

    private func controllerChanges(
        from beforeControllers: [RegionId: Faction],
        to map: MapState
    ) -> [RegionId] {
        map.regions.compactMap { regionId, region in
            beforeControllers[regionId] == region.controller ? nil : regionId
        }
    }

    private func stableUnique(_ values: [RegionId]) -> [RegionId] {
        var seen: Set<RegionId> = []
        var result: [RegionId] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    private func occupiedRegionIds(for command: Command, state: GameState) -> [RegionId] {
        guard case .move(let divisionId, let destination) = command,
              let division = state.division(id: divisionId),
              let tile = state.map.tile(at: destination),
              division.coord == destination,
              tile.isCapturable,
              tile.controller == division.faction else {
            return []
        }

        return state.map.region(for: destination).map { [$0] } ?? []
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
