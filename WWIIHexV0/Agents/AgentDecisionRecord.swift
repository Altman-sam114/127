import Foundation

struct CommandResultSummary: Identifiable, Codable, Equatable {
    let id: String
    let orderIndex: Int?
    let divisionId: String?
    let orderType: AgentOrderType?
    let commandDisplayName: String?
    let mappingSucceeded: Bool
    let validationSucceeded: Bool?
    let executed: Bool
    let message: String
    let errors: [String]

    static func mapped(
        orderIndex: Int,
        order: AgentOrder,
        command: Command,
        result: CommandResult
    ) -> CommandResultSummary {
        CommandResultSummary(
            id: "order_\(orderIndex)_\(order.divisionId)_\(order.type.rawValue)",
            orderIndex: orderIndex,
            divisionId: order.divisionId,
            orderType: order.type,
            commandDisplayName: command.userDisplayName,
            mappingSucceeded: true,
            validationSucceeded: result.validation.isValid,
            executed: result.succeeded,
            message: result.message,
            errors: result.validation.displayMessages
        )
    }

    static func mappingFailed(
        orderIndex: Int,
        order: AgentOrder,
        error: Error
    ) -> CommandResultSummary {
        CommandResultSummary(
            id: "order_\(orderIndex)_\(order.divisionId)_mapping_failed",
            orderIndex: orderIndex,
            divisionId: order.divisionId,
            orderType: order.type,
            commandDisplayName: nil,
            mappingSucceeded: false,
            validationSucceeded: nil,
            executed: false,
            message: "Mapping failed.",
            errors: [error.localizedDescription]
        )
    }

    static func endTurn(result: CommandResult) -> CommandResultSummary {
        CommandResultSummary(
            id: "end_turn",
            orderIndex: nil,
            divisionId: nil,
            orderType: nil,
            commandDisplayName: Command.endTurn.userDisplayName,
            mappingSucceeded: true,
            validationSucceeded: result.validation.isValid,
            executed: result.succeeded,
            message: result.message,
            errors: result.validation.displayMessages
        )
    }

    static func directiveCommand(
        directiveIndex: Int,
        commandIndex: Int,
        directive: ZoneDirective,
        command: Command,
        result: CommandResult
    ) -> CommandResultSummary {
        CommandResultSummary(
            id: "directive_\(directiveIndex)_command_\(commandIndex)_\(directive.type.rawValue)",
            orderIndex: commandIndex,
            divisionId: command.actingDivisionId,
            orderType: nil,
            commandDisplayName: command.userDisplayName,
            mappingSucceeded: true,
            validationSucceeded: result.validation.isValid,
            executed: result.succeeded,
            message: result.message,
            errors: result.validation.displayMessages
        )
    }
}

struct ModernCommandChainReplayItem: Identifiable, Codable, Equatable {
    let id: String
    let role: ModernCommandAgentRole
    let missionType: ModernMissionType
    let zoneId: FrontZoneId?
    let regionId: RegionId?
    let contactId: String?
    let priority: Int
    let rationale: String

    init(
        id: String,
        role: ModernCommandAgentRole,
        missionType: ModernMissionType,
        zoneId: FrontZoneId?,
        regionId: RegionId?,
        contactId: String?,
        priority: Int,
        rationale: String
    ) {
        self.id = id
        self.role = role
        self.missionType = missionType
        self.zoneId = zoneId
        self.regionId = regionId
        self.contactId = contactId
        self.priority = priority
        self.rationale = rationale
    }

    init(directive: ModernSubDirective) {
        self.init(
            id: directive.id,
            role: directive.role,
            missionType: directive.missionType,
            zoneId: directive.zoneId,
            regionId: directive.regionId,
            contactId: directive.contactId,
            priority: directive.priority,
            rationale: directive.rationale
        )
    }
}

struct AgentDecisionRecord: Identifiable, Codable, Equatable {
    let id: String
    let turn: Int
    let agentId: String
    let provider: String
    let contextSummary: String
    let rawJSON: String?
    let parsedIntent: String?
    let commandChainReplayItems: [ModernCommandChainReplayItem]
    let commandResults: [CommandResultSummary]
    let errors: [String]

    init(
        id: String,
        turn: Int,
        agentId: String,
        provider: String,
        contextSummary: String,
        rawJSON: String?,
        parsedIntent: String?,
        commandChainReplayItems: [ModernCommandChainReplayItem] = [],
        commandResults: [CommandResultSummary],
        errors: [String]
    ) {
        self.id = id
        self.turn = turn
        self.agentId = agentId
        self.provider = provider
        self.contextSummary = contextSummary
        self.rawJSON = rawJSON
        self.parsedIntent = parsedIntent
        self.commandChainReplayItems = commandChainReplayItems
        self.commandResults = commandResults
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case turn
        case agentId
        case provider
        case contextSummary
        case rawJSON
        case parsedIntent
        case commandChainReplayItems
        case commandResults
        case errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        turn = try container.decode(Int.self, forKey: .turn)
        agentId = try container.decode(String.self, forKey: .agentId)
        provider = try container.decode(String.self, forKey: .provider)
        contextSummary = try container.decode(String.self, forKey: .contextSummary)
        rawJSON = try container.decodeIfPresent(String.self, forKey: .rawJSON)
        parsedIntent = try container.decodeIfPresent(String.self, forKey: .parsedIntent)
        commandChainReplayItems = try container.decodeIfPresent(
            [ModernCommandChainReplayItem].self,
            forKey: .commandChainReplayItems
        ) ?? []
        commandResults = try container.decode([CommandResultSummary].self, forKey: .commandResults)
        errors = try container.decode([String].self, forKey: .errors)
    }
}
