import Foundation

enum Faction: String, Codable, Equatable, CaseIterable {
    case germany
    case allies

    /// Legacy two-side compatibility remains until v6.1 migrates rules to ROE.
    var opponent: Faction {
        switch self {
        case .germany:
            return .allies
        case .allies:
            return .germany
        }
    }

    var displayName: String {
        switch self {
        case .germany:
            return "Red Operational Group"
        case .allies:
            return "Blue Joint Task Force"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .germany:
            return "Red Force"
        case .allies:
            return "Blue Force"
        }
    }

    var legacyDisplayName: String {
        switch self {
        case .germany:
            return "Germany"
        case .allies:
            return "Allies"
        }
    }
}
