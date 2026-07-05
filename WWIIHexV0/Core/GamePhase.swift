import Foundation

enum GamePhase: String, Codable, Equatable, CaseIterable {
    case germanAI
    case alliedPlayer
    case resolution

    var displayName: String {
        switch self {
        case .germanAI:
            return "Red Command"
        case .alliedPlayer:
            return "Blue Command"
        case .resolution:
            return "Resolution"
        }
    }

    var legacyDisplayName: String {
        switch self {
        case .germanAI:
            return "German AI"
        case .alliedPlayer:
            return "Allied Player"
        case .resolution:
            return "Resolution"
        }
    }
}
