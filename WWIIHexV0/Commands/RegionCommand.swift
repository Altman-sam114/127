import Foundation

enum RegionCommand: Codable, Equatable {
    case move(divisionId: String, from: RegionId, to: RegionId)
    case attack(attackerId: String, from: RegionId, targetDivisionId: String, targetRegionId: RegionId?)
    case hold(divisionId: String, regionId: RegionId?)
    case resupply(divisionId: String, regionId: RegionId?)

    var displayName: String {
        switch self {
        case .move(let divisionId, let from, let to):
            return "Move \(Self.formationDisplay(divisionId)) from \(Self.objectiveDisplay(from)) to \(Self.objectiveDisplay(to))"
        case .attack(let attackerId, let from, let targetDivisionId, let targetRegionId):
            let target = targetRegionId.map(Self.objectiveDisplay) ?? "an unknown objective"
            return "Attack from \(Self.objectiveDisplay(from)) with \(Self.formationDisplay(attackerId)) against \(Self.formationDisplay(targetDivisionId)) at \(target)"
        case .hold(let divisionId, let regionId):
            let objective = regionId.map(Self.objectiveDisplay) ?? "an assigned objective"
            return "Hold \(objective) with \(Self.formationDisplay(divisionId))"
        case .resupply(let divisionId, let regionId):
            let objective = regionId.map(Self.objectiveDisplay) ?? "an assigned objective"
            return "Resupply \(Self.formationDisplay(divisionId)) near \(objective)"
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

    private static func objectiveDisplay(_ id: RegionId) -> String {
        let cleaned = id.rawValue
            .replacingOccurrences(of: "region_", with: "")
            .replacingOccurrences(of: "objective_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "objective area" : "objective \(cleaned.capitalized)"
    }

    private static func formationDisplay(_ id: String) -> String {
        let cleaned = id
            .replacingOccurrences(of: "division_", with: "")
            .replacingOccurrences(of: "unit_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "formation" : "formation \(cleaned.capitalized)"
    }
}
