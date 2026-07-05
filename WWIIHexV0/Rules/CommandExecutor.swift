import Foundation

struct CommandExecutor {
    private let movementRules = MovementRules()
    private let combatRules = CombatRules()
    private let supplyRules = SupplyRules()
    private let occupationRules = OccupationRules()
    private let strategicSynchronizer = StrategicStateSynchronizer()
    private let visibilityRules = VisibilityRules()
    private let fireSupportRules = FireSupportRules()
    private let retreatLossThreshold = 0.35

    func execute(_ command: Command, in state: GameState) -> GameState {
        var nextState = state

        switch command {
        case .move(let divisionId, let destination):
            executeMove(divisionId: divisionId, destination: destination, in: &nextState)
        case .attack(let attackerId, let targetId):
            executeAttack(attackerId: attackerId, targetId: targetId, in: &nextState)
        case .hold(let divisionId):
            executeHold(divisionId: divisionId, in: &nextState)
        case .allowRetreat(let divisionId):
            executeAllowRetreat(divisionId: divisionId, in: &nextState)
        case .resupply(let divisionId):
            executeResupply(divisionId: divisionId, in: &nextState)
        case .recon(let divisionId, let target):
            executeRecon(divisionId: divisionId, target: target, in: &nextState)
        case .uavRecon(let divisionId, let target):
            executeUAVRecon(divisionId: divisionId, target: target, in: &nextState)
        case .electronicWarfare(let divisionId, let target):
            executeElectronicWarfare(divisionId: divisionId, target: target, in: &nextState)
        case .fireMission(let issuerId, let target, let munitionClass):
            executeFireMission(issuerId: issuerId, target: target, munitionClass: munitionClass, in: &nextState)
        case .suppressAirDefense(let divisionId, let target):
            executeSuppressAirDefense(divisionId: divisionId, target: target, in: &nextState)
        case .queueProduction(let kind):
            executeQueueProduction(kind: kind, in: &nextState)
        case .endTurn:
            executeEndTurn(in: &nextState)
        }

        return nextState
    }

    private func executeMove(divisionId: String, destination: HexCoord, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        let origin = state.divisions[index].coord
        let sourceZoneId = state.warDeploymentState.zoneId(for: origin, map: state.map)
        if let direction = directionForMove(from: origin, to: destination, division: state.divisions[index], in: state) {
            state.divisions[index].facing = direction
        }
        state.divisions[index].coord = destination
        state.divisions[index].hasActed = true

        if occupationRules.canOccupy(division: state.divisions[index], destination: destination, in: state),
           var tile = state.map.tile(at: destination) {
            tile.controller = state.divisions[index].faction
            state.map.setTile(tile)
            if let destinationRegionId = state.map.region(for: destination),
               let sourceZoneId {
                applyStrategicAdvance(
                    regionId: destinationRegionId,
                    hex: destination,
                    sourceZoneId: sourceZoneId,
                    faction: state.divisions[index].faction,
                    state: &state
                )
            }
            _ = strategicSynchronizer.synchronizeAfterOccupationChange(
                in: &state,
                affectedRegionIds: state.map.region(for: destination).map { [$0] } ?? []
            )
        }

        state.appendEvent("\(state.divisions[index].name) moved to \(destination.q),\(destination.r).")
    }

    private func executeAttack(attackerId: String, targetId: String, in state: inout GameState) {
        guard let attackerIndex = state.divisionIndex(id: attackerId),
              let targetIndex = state.divisionIndex(id: targetId) else {
            return
        }

        let attacker = state.divisions[attackerIndex]
        let defender = state.divisions[targetIndex]
        let damage = combatRules.attackDamage(attacker: attacker, defender: defender, in: state)
        let attackerFacing = attacker.coord.direction(to: defender.coord) ?? attacker.facing

        state.divisions[attackerIndex].hasActed = true
        state.divisions[attackerIndex].facing = attackerFacing
        applyCombatDamage(damage, to: targetId, in: &state)

        let attackOutcome = resolveCombatResult(for: defender, damage: damage, in: &state)
        state.appendEvent(
            combatLog(
                prefix: "\(attacker.name) attacked \(defender.name)",
                subjectName: defender.name,
                damage: damage,
                outcome: attackOutcome
            )
        )

        if attackOutcome.wasDestroyed {
            return
        }

        if attackOutcome.shouldRetreat {
            supplyRules.resolveRetreat(for: targetId, in: &state)
        }

        guard let updatedDefender = state.division(id: targetId),
              let updatedAttacker = state.division(id: attackerId) else {
            return
        }

        if !attackOutcome.shouldRetreat,
           combatRules.canCounterAttack(defender: updatedDefender, attacker: updatedAttacker) {
            let counterDamage = combatRules.counterAttackDamage(defender: updatedDefender, attacker: updatedAttacker, in: state)
            applyCombatDamage(counterDamage, to: attackerId, in: &state)

            let counterOutcome = resolveCombatResult(for: updatedAttacker, damage: counterDamage, in: &state)
            state.appendEvent(
                combatLog(
                    prefix: "\(updatedDefender.name) counterattacked \(updatedAttacker.name)",
                    subjectName: updatedAttacker.name,
                    damage: counterDamage,
                    outcome: counterOutcome
                )
            )

            if counterOutcome.shouldRetreat && !counterOutcome.wasDestroyed {
                supplyRules.resolveRetreat(for: attackerId, in: &state)
            }
        }
    }

    private func executeHold(divisionId: String, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        state.divisions[index].retreatMode = .hold
        state.divisions[index].hasActed = true
        state.appendEvent("\(state.divisions[index].name) set stance to HOLD: no retreat, +20% defense, +20% losses.")
    }

    private func executeAllowRetreat(divisionId: String, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        state.divisions[index].retreatMode = .retreatable
        state.divisions[index].hasActed = true
        state.appendEvent("\(state.divisions[index].name) set stance to RETREATABLE: auto-retreat after severe losses.")
    }

    private func executeResupply(divisionId: String, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        supplyRules.applyResupplyRest(to: divisionId, in: &state)
        state.divisions[index].hasActed = true
    }

    private func executeRecon(divisionId: String, target: HexCoord, in state: inout GameState) {
        state = visibilityRules.performRecon(
            divisionId: divisionId,
            target: target,
            in: state
        ).state
    }

    private func executeUAVRecon(divisionId: String, target: HexCoord, in state: inout GameState) {
        state = fireSupportRules.executeUAVRecon(
            divisionId: divisionId,
            target: target,
            in: state
        )
    }

    private func executeElectronicWarfare(divisionId: String, target: HexCoord, in state: inout GameState) {
        state = visibilityRules.applyElectronicWarfare(
            divisionId: divisionId,
            target: target,
            in: state
        )
    }

    private func executeFireMission(
        issuerId: String,
        target: FireMissionTarget,
        munitionClass: MunitionClass,
        in state: inout GameState
    ) {
        state = fireSupportRules.executeFireMission(
            issuerId: issuerId,
            target: target,
            munitionClass: munitionClass,
            in: state
        )
    }

    private func executeSuppressAirDefense(divisionId: String, target: HexCoord, in state: inout GameState) {
        state = fireSupportRules.executeSuppressAirDefense(
            divisionId: divisionId,
            target: target,
            in: state
        )
    }

    private func executeQueueProduction(kind: ProductionKind, in state: inout GameState) {
        _ = EconomyRules().queueProduction(kind: kind, faction: state.activeFaction, in: &state)
    }

    private func executeEndTurn(in state: inout GameState) {
        let supplyRules = SupplyRules()
        let victoryRules = VictoryRules()
        let economyRules = EconomyRules()

        supplyRules.updateSupplyStates(in: &state)
        economyRules.resolveFactionTurn(for: state.activeFaction, in: &state)
        supplyRules.advanceRetreats(in: &state)
        supplyRules.applyEncirclementAttrition(in: &state)
        victoryRules.updateVictoryState(in: &state)
        state.operationalAwareness = visibilityRules.advanceTurn(state.operationalAwareness)
        state.fireSupportState = fireSupportRules.advanceTurn(state.fireSupportState)

        switch state.activeFaction {
        case .germany:
            state.activeFaction = .allies
            state.phase = .alliedPlayer
        case .allies:
            state.activeFaction = .germany
            state.phase = .germanAI
            state.turn += 1
        case .redForce:
            state.activeFaction = .blueForce
            state.phase = .alliedPlayer
        case .blueForce:
            state.activeFaction = .redForce
            state.phase = .germanAI
            state.turn += 1
        case .greenForce,
             .neutral:
            state.activeFaction = .redForce
            state.phase = .germanAI
            state.turn += 1
        }

        resetActionsForActiveFaction(in: &state)
        state = StrategicStateBootstrapper().refreshRuntimeState(state)
        state.appendEvent("Turn advanced to \(state.turn), \(state.activeFaction.displayName) active.")
    }

    private func resetActionsForActiveFaction(in state: inout GameState) {
        for index in state.divisions.indices where state.divisions[index].faction == state.activeFaction {
            state.divisions[index].hasActed = false
        }
    }

    private func directionForMove(
        from origin: HexCoord,
        to destination: HexCoord,
        division: Division,
        in state: GameState
    ) -> HexDirection? {
        if let path = movementRules.shortestPath(for: division, to: destination, in: state),
           path.coords.count >= 2 {
            let previous = path.coords[path.coords.count - 2]
            return previous.direction(to: destination)
        }

        return origin.direction(to: destination)
    }

    private func applyCombatDamage(_ damage: CombatDamage, to divisionId: String, in state: inout GameState) {
        guard let index = state.divisionIndex(id: divisionId) else {
            return
        }

        state.divisions[index].receiveStrengthDamage(damage.strengthDamage)
    }

    private func resolveCombatResult(
        for originalDivision: Division,
        damage: CombatDamage,
        in state: inout GameState
    ) -> CombatResultSummary {
        guard let index = state.divisionIndex(id: originalDivision.id) else {
            return CombatResultSummary(shouldRetreat: false, wasDestroyed: true, extraStrengthDamage: 0)
        }

        let shouldRetreat = state.divisions[index].retreatMode == .retreatable &&
            !state.divisions[index].isDestroyed &&
            damage.lossRatio >= retreatLossThreshold
        var extraStrengthDamage = 0

        if state.divisions[index].retreatMode == .hold && !state.divisions[index].isDestroyed {
            extraStrengthDamage += max(1, Int((Double(damage.strengthDamage) * 0.2).rounded()))
            state.divisions[index].receiveStrengthDamage(extraStrengthDamage)
        }

        if shouldRetreat && state.divisions[index].supplyState == .encircled && !state.divisions[index].isDestroyed {
            extraStrengthDamage = max(1, damage.strengthDamage / 2)
            state.divisions[index].receiveStrengthDamage(extraStrengthDamage)
        }

        if state.divisions[index].isDestroyed {
            eliminateDivision(originalDivision, in: &state)
            return CombatResultSummary(
                shouldRetreat: shouldRetreat,
                wasDestroyed: true,
                extraStrengthDamage: extraStrengthDamage
            )
        }

        if shouldRetreat {
            state.divisions[index].hasActed = true
        }

        return CombatResultSummary(
            shouldRetreat: shouldRetreat,
            wasDestroyed: false,
            extraStrengthDamage: extraStrengthDamage
        )
    }

    private func eliminateDivision(_ division: Division, in state: inout GameState) {
        state.victoryState.recordEliminatedDivision(faction: division.faction)
        state.removeDivision(id: division.id)
    }

    private func applyStrategicAdvance(
        regionId: RegionId,
        hex: HexCoord,
        sourceZoneId: FrontZoneId,
        faction: Faction,
        state: inout GameState
    ) {
        let advancingTheaterId = TheaterId(sourceZoneId.rawValue)
        guard state.theaterState.theaters[advancingTheaterId] != nil,
              state.theaterState.dynamicTheaterId(for: hex, map: state.map) != advancingTheaterId else {
            return
        }
        guard shouldAdvanceDynamicTheater(
            hex: hex,
            sourceZoneId: sourceZoneId,
            faction: faction,
            state: state
        ) else {
            return
        }

        state.theaterState = TheaterSystem().expandDynamicTheater(
            state: state.theaterState,
            map: state.map,
            divisions: state.divisions,
            breakthroughHex: hex,
            advancingTheaterId: advancingTheaterId,
            faction: faction
        ).state

        let oldZoneId = state.warDeploymentState.zoneId(for: hex, map: state.map)
        if oldZoneId != sourceZoneId {
            state.warDeploymentState = WarDeploymentManager().advanceHex(
                hex,
                from: oldZoneId,
                to: sourceZoneId,
                state: state.warDeploymentState,
                map: state.map,
                divisions: state.divisions,
                turn: state.turn
            )
        }

        state.appendEvent(
            "Hex \(hex.q),\(hex.r) reassigned to dynamic theater \(advancingTheaterId.rawValue).",
            category: .theaterChange,
            relatedRecordId: nil
        )
    }

    private func shouldAdvanceDynamicTheater(
        hex: HexCoord,
        sourceZoneId: FrontZoneId,
        faction: Faction,
        state: GameState
    ) -> Bool {
        let destinationZoneId = state.warDeploymentState.zoneId(for: hex, map: state.map)
        if let destinationZoneId,
           destinationZoneId != sourceZoneId,
           let destinationFaction = state.warDeploymentState.frontZones[destinationZoneId]?.faction {
            return destinationFaction != faction
        }

        if let controller = state.map.tile(at: hex)?.controller {
            return controller != faction
        }

        return false
    }

    private func combatLog(
        prefix: String,
        subjectName: String,
        damage: CombatDamage,
        outcome: CombatResultSummary
    ) -> String {
        var parts = [
            "\(prefix): strength -\(damage.strengthDamage)"
        ]

        if outcome.shouldRetreat {
            parts.append("\(subjectName) triggered automatic retreat")
        }

        if outcome.extraStrengthDamage > 0 {
            parts.append("extra strength -\(outcome.extraStrengthDamage)")
        }

        if outcome.wasDestroyed {
            parts.append("\(subjectName) was destroyed")
        }

        return parts.joined(separator: "; ") + "."
    }
}

private struct CombatResultSummary: Equatable {
    let shouldRetreat: Bool
    let wasDestroyed: Bool
    let extraStrengthDamage: Int
}
