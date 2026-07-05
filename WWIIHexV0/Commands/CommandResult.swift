import Foundation

enum CommandResultLogKind: String, Codable, Equatable {
    case movement
    case combat
    case recovery
    case retreat
    case supply
    case intelligence
    case electronicWarfare
    case fireSupport
    case airTasking
    case turn
    case system
}

struct CommandResultLogEntry: Codable, Equatable {
    var kind: CommandResultLogKind
    var message: String
    var actorDivisionId: String?
    var targetDivisionId: String?
    var strengthDamage: Int

    init(
        kind: CommandResultLogKind,
        message: String,
        actorDivisionId: String? = nil,
        targetDivisionId: String? = nil,
        strengthDamage: Int = 0
    ) {
        self.kind = kind
        self.message = message
        self.actorDivisionId = actorDivisionId
        self.targetDivisionId = targetDivisionId
        self.strengthDamage = max(0, strengthDamage)
    }
}

struct CommandResult: Codable, Equatable {
    let command: Command
    let validation: CommandValidation
    let state: GameState
    let message: String
    let logEntries: [CommandResultLogEntry]

    private enum CodingKeys: String, CodingKey {
        case command
        case validation
        case state
        case message
        case logEntries
    }

    init(
        command: Command,
        validation: CommandValidation,
        state: GameState,
        message: String,
        logEntries: [CommandResultLogEntry] = []
    ) {
        self.command = command
        self.validation = validation
        self.state = state
        self.message = message
        self.logEntries = logEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(Command.self, forKey: .command)
        self.validation = try container.decode(CommandValidation.self, forKey: .validation)
        self.state = try container.decode(GameState.self, forKey: .state)
        self.message = try container.decode(String.self, forKey: .message)
        self.logEntries = try container.decodeIfPresent([CommandResultLogEntry].self, forKey: .logEntries) ?? []
    }

    var succeeded: Bool {
        validation.isValid
    }
}
