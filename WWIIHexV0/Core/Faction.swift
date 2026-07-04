import Foundation

enum Faction: String, Codable, Equatable, CaseIterable {
    case germany
    case allies

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
            return "Germany"
        case .allies:
            return "Allies"
        }
    }
}
