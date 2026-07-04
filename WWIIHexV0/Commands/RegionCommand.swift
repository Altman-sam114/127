import Foundation

enum RegionCommand: Codable, Equatable {
    case move(divisionId: String, from: RegionId, to: RegionId)
    case attack(attackerId: String, from: RegionId, targetDivisionId: String, targetRegionId: RegionId?)
    case hold(divisionId: String, regionId: RegionId?)
    case resupply(divisionId: String, regionId: RegionId?)

    var displayName: String {
        switch self {
        case .move(let divisionId, let from, let to):
            return "RegionMove(\(divisionId): \(from.rawValue) -> \(to.rawValue))"
        case .attack(let attackerId, let from, let targetDivisionId, let targetRegionId):
            let target = targetRegionId?.rawValue ?? "unknown"
            return "RegionAttack(\(attackerId) @ \(from.rawValue) -> \(targetDivisionId) @ \(target))"
        case .hold(let divisionId, let regionId):
            return "RegionHold(\(divisionId) @ \(regionId?.rawValue ?? "unknown"))"
        case .resupply(let divisionId, let regionId):
            return "RegionResupply(\(divisionId) @ \(regionId?.rawValue ?? "unknown"))"
        }
    }

    var actingDivisionId: String {
        switch self {
        case .move(let divisionId, _, _),
             .hold(let divisionId, _),
             .resupply(let divisionId, _):
            return divisionId
        case .attack(let attackerId, _, _, _):
            return attackerId
        }
    }
}

