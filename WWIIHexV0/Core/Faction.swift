import Foundation

enum Faction: String, Codable, Equatable, Hashable, CaseIterable {
    case germany
    case allies
    case blueForce
    case redForce
    case greenForce
    case neutral

    /// Legacy two-side compatibility remains until v6.1 migrates rules to ROE.
    var opponent: Faction {
        switch alignment {
        case .red:
            return self == .germany ? .allies : .blueForce
        case .blue:
            return self == .allies ? .germany : .redForce
        case .green,
             .neutral:
            return .neutral
        }
    }

    var alignment: OperationalSideAlignment {
        switch self {
        case .germany:
            return .red
        case .allies:
            return .blue
        case .blueForce:
            return .blue
        case .redForce:
            return .red
        case .greenForce:
            return .green
        case .neutral:
            return .neutral
        }
    }

    var usesPlayerCommandPhase: Bool {
        alignment == .blue
    }

    var usesAICommandPhase: Bool {
        alignment == .red
    }

    var commandPhase: GamePhase? {
        switch alignment {
        case .red:
            return .germanAI
        case .blue:
            return .alliedPlayer
        case .green,
             .neutral:
            return nil
        }
    }

    func canCommand(in phase: GamePhase) -> Bool {
        commandPhase == phase
    }

    var isNeutralLike: Bool {
        alignment == .neutral || alignment == .green
    }

    func isHostile(to other: Faction) -> Bool {
        defaultROEStatus(toward: other).isHostile
    }

    func defaultROEStatus(toward other: Faction) -> DiplomaticStatus {
        guard self != other else {
            return .allied
        }

        if alignment == other.alignment {
            return .coBelligerent
        }

        if isNeutralLike || other.isNeutralLike {
            return .restricted
        }

        return .atWar
    }

    var displayName: String {
        switch self {
        case .germany:
            return "Red Operational Group"
        case .allies:
            return "Blue Joint Task Force"
        case .blueForce:
            return "Blue Joint Task Force"
        case .redForce:
            return "Red Operational Group"
        case .greenForce:
            return "Green Force"
        case .neutral:
            return "Neutral / Civilian"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .germany:
            return "Red Force"
        case .allies:
            return "Blue Force"
        case .blueForce:
            return "Blue Force"
        case .redForce:
            return "Red Force"
        case .greenForce:
            return "Green Force"
        case .neutral:
            return "Neutral"
        }
    }

    var legacyDisplayName: String {
        switch self {
        case .germany:
            return "Germany"
        case .allies:
            return "Allies"
        case .blueForce:
            return "Blue Force"
        case .redForce:
            return "Red Force"
        case .greenForce:
            return "Green Force"
        case .neutral:
            return "Neutral"
        }
    }
}

enum OperationalSideAlignment: String, Codable, Equatable, CaseIterable {
    case blue
    case red
    case green
    case neutral

    var displayName: String {
        switch self {
        case .blue:
            return "Blue Force"
        case .red:
            return "Red Force"
        case .green:
            return "Green Force"
        case .neutral:
            return "Neutral / Civilian"
        }
    }
}

extension Faction {
    static let legacyBelligerents: [Faction] = [.germany, .allies]
    static let modernBelligerents: [Faction] = [.redForce, .blueForce]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let faction = Faction.dataValue(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown faction value: \(rawValue)"
            )
        }
        self = faction
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func dataValue(_ value: String?) -> Faction? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "germany", "german", "axis", "red", "red_force", "redforce", "power_red":
            return normalized == "germany" || normalized == "german" || normalized == "axis" ? .germany : .redForce
        case "allies", "allied", "allied_coalition", "blue", "blue_force", "blueforce", "power_blue":
            return normalized == "allies" || normalized == "allied" || normalized == "allied_coalition" ? .allies : .blueForce
        case "green", "green_force", "greenforce", "power_green":
            return .greenForce
        case "neutral", "civilian", "civilians", "none":
            return .neutral
        default:
            return Faction(rawValue: value)
        }
    }
}
