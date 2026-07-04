import Foundation

enum Command: Codable, Equatable {
    case move(divisionId: String, destination: HexCoord)
    case attack(attackerId: String, targetId: String)
    case hold(divisionId: String)
    case allowRetreat(divisionId: String)
    case resupply(divisionId: String)
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
            return "Move(\(divisionId) -> \(destination.q),\(destination.r))"
        case .attack(let attackerId, let targetId):
            return "Attack(\(attackerId) -> \(targetId))"
        case .hold(let divisionId):
            return "Hold(\(divisionId))"
        case .allowRetreat(let divisionId):
            return "AllowRetreat(\(divisionId))"
        case .resupply(let divisionId):
            return "Resupply(\(divisionId))"
        case .queueProduction(let kind):
            return "QueueProduction(\(kind.displayName))"
        case .endTurn:
            return "End Turn"
        }
    }

    var actingDivisionId: String? {
        switch self {
        case .move(let divisionId, _),
             .hold(let divisionId),
             .allowRetreat(let divisionId),
             .resupply(let divisionId):
            return divisionId
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
             .queueProduction,
             .endTurn:
            return false
        }
    }
}
