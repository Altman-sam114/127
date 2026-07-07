import Foundation

enum Command: Codable, Equatable {
    case move(divisionId: String, destination: HexCoord)
    case attack(attackerId: String, targetId: String)
    case hold(divisionId: String)
    case allowRetreat(divisionId: String)
    case resupply(divisionId: String)
    case recon(divisionId: String, target: HexCoord)
    case uavRecon(divisionId: String, target: HexCoord)
    case electronicWarfare(divisionId: String, target: HexCoord)
    case fireMission(issuerId: String, target: FireMissionTarget, munitionClass: MunitionClass)
    case suppressAirDefense(divisionId: String, target: HexCoord)
    case queueProduction(kind: ProductionKind)
    case endTurn

    static func rest(divisionId: String) -> Command {
        .resupply(divisionId: divisionId)
    }

    static func reinforce(divisionId: String) -> Command {
        .resupply(divisionId: divisionId)
    }

    var displayName: String {
        switch self {
        case .move(let divisionId, let destination):
            return "Move \(Self.formationDisplay(divisionId)) to \(Self.coordDisplay(destination))"
        case .attack(let attackerId, let targetId):
            return "Attack with \(Self.formationDisplay(attackerId)) against \(Self.formationDisplay(targetId))"
        case .hold(let divisionId):
            return "Hold \(Self.formationDisplay(divisionId))"
        case .allowRetreat(let divisionId):
            return "Authorize withdrawal for \(Self.formationDisplay(divisionId))"
        case .resupply(let divisionId):
            return "Sustain \(Self.formationDisplay(divisionId))"
        case .recon(let divisionId, let target):
            return "Recon \(Self.coordDisplay(target)) with \(Self.formationDisplay(divisionId))"
        case .uavRecon(let divisionId, let target):
            return "UAV orbit over \(Self.coordDisplay(target)) from \(Self.formationDisplay(divisionId))"
        case .electronicWarfare(let divisionId, let target):
            return "Electronic warfare at \(Self.coordDisplay(target)) from \(Self.formationDisplay(divisionId))"
        case .fireMission(let issuerId, let target, let munitionClass):
            return "\(munitionClass.displayName) fire mission from \(Self.formationDisplay(issuerId)) to \(target.displayName)"
        case .suppressAirDefense(let divisionId, let target):
            return "Suppress air defenses at \(Self.coordDisplay(target)) from \(Self.formationDisplay(divisionId))"
        case .queueProduction(let kind):
            return "Queue \(kind.displayName)"
        case .endTurn:
            return "End Turn"
        }
    }

    var userDisplayName: String { displayName }

    func contextualDisplayName(in state: GameState) -> String {
        switch self {
        case .move(let divisionId, let destination):
            return "Move \(Self.formationDisplay(divisionId, in: state)) to \(Self.coordDisplay(destination))"
        case .attack(let attackerId, let targetId):
            return "Attack with \(Self.formationDisplay(attackerId, in: state)) against \(Self.formationDisplay(targetId, in: state))"
        case .hold(let divisionId):
            return "Hold \(Self.formationDisplay(divisionId, in: state))"
        case .allowRetreat(let divisionId):
            return "Authorize withdrawal for \(Self.formationDisplay(divisionId, in: state))"
        case .resupply(let divisionId):
            return "Sustain \(Self.formationDisplay(divisionId, in: state))"
        case .recon(let divisionId, let target):
            return "Recon \(Self.coordDisplay(target)) with \(Self.formationDisplay(divisionId, in: state))"
        case .uavRecon(let divisionId, let target):
            return "UAV orbit over \(Self.coordDisplay(target)) from \(Self.formationDisplay(divisionId, in: state))"
        case .electronicWarfare(let divisionId, let target):
            return "Electronic warfare at \(Self.coordDisplay(target)) from \(Self.formationDisplay(divisionId, in: state))"
        case .fireMission(let issuerId, let target, let munitionClass):
            return "\(munitionClass.displayName) fire mission from \(Self.formationDisplay(issuerId, in: state)) to \(target.contextualDisplayName(in: state))"
        case .suppressAirDefense(let divisionId, let target):
            return "Suppress air defenses at \(Self.coordDisplay(target)) from \(Self.formationDisplay(divisionId, in: state))"
        case .queueProduction(let kind):
            return "Queue \(kind.displayName)"
        case .endTurn:
            return "End Turn"
        }
    }

    var actingDivisionId: String? {
        switch self {
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
        case .queueProduction:
            return nil
        case .endTurn:
            return nil
        }
    }

    var isRecoveryCommand: Bool {
        switch self {
        case .resupply:
            return true
        case .move,
             .attack,
             .hold,
             .allowRetreat,
             .recon,
             .uavRecon,
             .electronicWarfare,
             .fireMission,
             .suppressAirDefense,
             .queueProduction,
             .endTurn:
            return false
        }
    }

    private static func formationDisplay(_ id: String) -> String {
        let cleaned = id
            .replacingOccurrences(of: "div" + "ision_", with: "")
            .replacingOccurrences(of: "unit_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "formation" : "formation \(cleaned.capitalized)"
    }

    private static func formationDisplay(_ id: String, in state: GameState) -> String {
        state.division(id: id)?.operationalDisplayName ?? formationDisplay(id)
    }

    private static func coordDisplay(_ coord: HexCoord) -> String {
        "hex \(coord.q),\(coord.r)"
    }
}
