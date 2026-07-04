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
            commandDisplayName: command.displayName,
            mappingSucceeded: true,
            validationSucceeded: result.validation.isValid,
            executed: result.succeeded,
            message: result.message,
            errors: result.validation.errors.map(\.rawValue)
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
            commandDisplayName: Command.endTurn.displayName,
            mappingSucceeded: true,
            validationSucceeded: result.validation.isValid,
            executed: result.succeeded,
            message: result.message,
            errors: result.validation.errors.map(\.rawValue)
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
            commandDisplayName: command.displayName,
            mappingSucceeded: true,
            validationSucceeded: result.validation.isValid,
            executed: result.succeeded,
            message: result.message,
            errors: result.validation.errors.map(\.rawValue)
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
    let commandResults: [CommandResultSummary]
    let errors: [String]
}
