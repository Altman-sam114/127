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
            return "Move(\(divisionId) -> \(destination.q),\(destination.r))"
        case .attack(let attackerId, let targetId):
            return "Attack(\(attackerId) -> \(targetId))"
        case .hold(let divisionId):
            return "Hold(\(divisionId))"
        case .allowRetreat(let divisionId):
            return "AllowRetreat(\(divisionId))"
        case .resupply(let divisionId):
            return "Resupply(\(divisionId))"
        case .recon(let divisionId, let target):
            return "Recon(\(divisionId) -> \(target.q),\(target.r))"
        case .uavRecon(let divisionId, let target):
            return "UAVRecon(\(divisionId) -> \(target.q),\(target.r))"
        case .electronicWarfare(let divisionId, let target):
            return "EW(\(divisionId) -> \(target.q),\(target.r))"
        case .fireMission(let issuerId, let target, let munitionClass):
            return "FireMission(\(issuerId) -> \(target.displayName), \(munitionClass.displayName))"
        case .suppressAirDefense(let divisionId, let target):
            return "SuppressAD(\(divisionId) -> \(target.q),\(target.r))"
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
}
