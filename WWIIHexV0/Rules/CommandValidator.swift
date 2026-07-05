import Foundation

struct CommandValidator {
    private let movementRules = MovementRules()
    private let fireSupportRules = FireSupportRules()

    func validate(_ command: Command, in state: GameState) -> CommandValidation {
        switch command {
        case .move(let divisionId, let destination):
            return validateMove(divisionId: divisionId, destination: destination, in: state)
        case .attack(let attackerId, let targetId):
            return validateAttack(attackerId: attackerId, targetId: targetId, in: state)
        case .hold(let divisionId):
            return validateUnitCommand(divisionId: divisionId, in: state)
        case .allowRetreat(let divisionId):
            return validateUnitCommand(divisionId: divisionId, in: state)
        case .resupply(let divisionId):
            return validateRecoveryCommand(divisionId: divisionId, in: state)
        case .recon(let divisionId, let target):
            return validateAwarenessCommand(divisionId: divisionId, target: target, in: state, rangeBonus: 2)
        case .uavRecon(let divisionId, let target):
            return validateUAVRecon(divisionId: divisionId, target: target, in: state)
        case .electronicWarfare(let divisionId, let target):
            return validateAwarenessCommand(divisionId: divisionId, target: target, in: state, rangeBonus: 1)
        case .fireMission(let issuerId, let target, let munitionClass):
            return validateFireMission(issuerId: issuerId, target: target, munitionClass: munitionClass, in: state)
        case .suppressAirDefense(let divisionId, let target):
            return validateSuppressAirDefense(divisionId: divisionId, target: target, in: state)
        case .queueProduction(let kind):
            return validateProduction(kind: kind, in: state)
        case .endTurn:
            return validateEndTurn(in: state)
        }
    }

    private func validateMove(divisionId: String, destination: HexCoord, in state: GameState) -> CommandValidation {
        let unitValidation = validateUnitCommand(divisionId: divisionId, in: state)
        guard unitValidation.isValid,
              let division = state.division(id: divisionId) else {
            return unitValidation
        }

        guard state.map.contains(destination) else {
            return .invalid(.destinationOutOfBounds)
        }

        guard state.map.tile(at: destination)?.isPassable == true else {
            return .invalid(.noPath)
        }

        if state.division(at: destination) != nil {
            return .invalid(.destinationOccupied)
        }

        if let path = movementRules.shortestPathIgnoringMovement(for: division, to: destination, in: state),
           path.cost > division.movement {
            return .invalid(.insufficientMovement)
        }

        guard movementRules.shortestPath(for: division, to: destination, in: state) != nil else {
            return .invalid(.noPath)
        }

        return .valid
    }

    private func validateAttack(attackerId: String, targetId: String, in state: GameState) -> CommandValidation {
        let unitValidation = validateUnitCommand(divisionId: attackerId, in: state)
        guard unitValidation.isValid,
              let attacker = state.division(id: attackerId) else {
            return unitValidation
        }

        guard let target = state.division(id: targetId) else {
            return .invalid(.targetNotFound)
        }

        guard target.faction != attacker.faction else {
            return .invalid(.invalidTargetFaction)
        }

        guard attacker.coord.distance(to: target.coord) <= attacker.range else {
            return .invalid(.targetOutOfRange)
        }

        return .valid
    }

    private func validateUnitCommand(divisionId: String, in state: GameState) -> CommandValidation {
        guard phaseAllowsCommands(in: state) else {
            return .invalid(.wrongPhase)
        }

        guard let division = state.division(id: divisionId) else {
            return .invalid(.divisionNotFound)
        }

        guard division.faction == state.activeFaction else {
            return .invalid(.wrongFaction)
        }

        guard !division.hasActed, !division.isRetreating else {
            return .invalid(.alreadyActed)
        }

        guard division.canAct else {
            return .invalid(.alreadyActed)
        }

        return .valid
    }

    private func validateRecoveryCommand(divisionId: String, in state: GameState) -> CommandValidation {
        guard phaseAllowsCommands(in: state) else {
            return .invalid(.wrongPhase)
        }

        guard let division = state.division(id: divisionId) else {
            return .invalid(.divisionNotFound)
        }

        guard division.faction == state.activeFaction else {
            return .invalid(.wrongFaction)
        }

        guard !division.hasActed, !division.isDestroyed, !division.isRetreating else {
            return .invalid(.alreadyActed)
        }

        return .valid
    }

    private func validateAwarenessCommand(
        divisionId: String,
        target: HexCoord,
        in state: GameState,
        rangeBonus: Int
    ) -> CommandValidation {
        let unitValidation = validateUnitCommand(divisionId: divisionId, in: state)
        guard unitValidation.isValid,
              let division = state.division(id: divisionId) else {
            return unitValidation
        }

        guard state.map.contains(target) else {
            return .invalid(.destinationOutOfBounds)
        }

        let range = max(1, division.vision / 2 + rangeBonus)
        guard division.coord.distance(to: target) <= range else {
            return .invalid(.targetOutOfRange)
        }

        return .valid
    }

    private func validateUAVRecon(
        divisionId: String,
        target: HexCoord,
        in state: GameState
    ) -> CommandValidation {
        let unitValidation = validateAwarenessCommand(
            divisionId: divisionId,
            target: target,
            in: state,
            rangeBonus: 3
        )
        guard unitValidation.isValid,
              let division = state.division(id: divisionId) else {
            return unitValidation
        }
        return fireSupportRules.validateUAVRecon(issuer: division, target: target, in: state)
    }

    private func validateFireMission(
        issuerId: String,
        target: FireMissionTarget,
        munitionClass: MunitionClass,
        in state: GameState
    ) -> CommandValidation {
        let unitValidation = validateUnitCommand(divisionId: issuerId, in: state)
        guard unitValidation.isValid,
              let issuer = state.division(id: issuerId) else {
            return unitValidation
        }
        return fireSupportRules.validateFireMission(
            issuer: issuer,
            target: target,
            munitionClass: munitionClass,
            in: state
        )
    }

    private func validateSuppressAirDefense(
        divisionId: String,
        target: HexCoord,
        in state: GameState
    ) -> CommandValidation {
        let unitValidation = validateAwarenessCommand(
            divisionId: divisionId,
            target: target,
            in: state,
            rangeBonus: 2
        )
        guard unitValidation.isValid,
              let division = state.division(id: divisionId) else {
            return unitValidation
        }
        return fireSupportRules.validateSuppressAirDefense(issuer: division, target: target, in: state)
    }

    private func validateEndTurn(in state: GameState) -> CommandValidation {
        phaseAllowsCommands(in: state) ? .valid : .invalid(.wrongPhase)
    }

    private func validateProduction(kind: ProductionKind, in state: GameState) -> CommandValidation {
        guard phaseAllowsCommands(in: state) else {
            return .invalid(.wrongPhase)
        }

        guard EconomyRules().canQueueProduction(kind: kind, faction: state.activeFaction, in: state) else {
            return .invalid(.insufficientResources)
        }

        return .valid
    }

    private func phaseAllowsCommands(in state: GameState) -> Bool {
        state.activeFaction.canCommand(in: state.phase)
    }
}
