import Foundation

enum GamePhase: String, Codable, Equatable, CaseIterable {
    case germanAI
    case alliedPlayer
    case resolution

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let phase = GamePhase.dataValue(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown game phase value: \(rawValue)"
            )
        }
        self = phase
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dataValue)
    }

    static func dataValue(_ value: String?) -> GamePhase? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "germanai", "german_ai", "redcommand", "red_command", "aicommand", "ai_command", "redai", "red_ai":
            return .germanAI
        case "alliedplayer", "allied_player", "bluecommand", "blue_command", "playercommand", "player_command", "blueplayer", "blue_player":
            return .alliedPlayer
        case "resolution":
            return .resolution
        default:
            return nil
        }
    }

    var dataValue: String {
        switch self {
        case .germanAI:
            return "redCommand"
        case .alliedPlayer:
            return "blueCommand"
        case .resolution:
            return "resolution"
        }
    }

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
