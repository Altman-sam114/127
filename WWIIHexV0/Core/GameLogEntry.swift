import Foundation

enum GameLogCategory: String, Codable, Equatable {
    case combat
    case retreat
    case reinforce
    case encircle
    case supply
    case frontChange
    case theaterChange
    case regionOwnerChange
    case diplomacy
    case event
}

struct GameLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let turn: Int
    let faction: Faction?
    let phase: GamePhase?
    let category: GameLogCategory
    let relatedRecordId: String?
    let message: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        turn: Int,
        faction: Faction?,
        phase: GamePhase?,
        category: GameLogCategory = .event,
        relatedRecordId: String? = nil,
        message: String,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.id = id
        self.turn = turn
        self.faction = faction
        self.phase = phase
        self.category = category
        self.relatedRecordId = relatedRecordId
        self.message = message
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case turn
        case faction
        case phase
        case category
        case relatedRecordId
        case message
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            turn: try container.decode(Int.self, forKey: .turn),
            faction: try container.decodeIfPresent(Faction.self, forKey: .faction),
            phase: try container.decodeIfPresent(GamePhase.self, forKey: .phase),
            category: try container.decodeIfPresent(GameLogCategory.self, forKey: .category) ?? .event,
            relatedRecordId: try container.decodeIfPresent(String.self, forKey: .relatedRecordId),
            message: try container.decode(String.self, forKey: .message),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        )
    }
}
