import Foundation

struct CommandValidator {
    private let movementRules = MovementRules()

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
        case .electronicWarfare(let divisionId, let target):
            return validateAwarenessCommand(divisionId: divisionId, target: target, in: state, rangeBonus: 1)
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
        switch state.phase {
        case .germanAI:
            return state.activeFaction.usesAICommandPhase
        case .alliedPlayer:
            return state.activeFaction.usesPlayerCommandPhase
        case .resolution:
            return false
        }
    }
}
