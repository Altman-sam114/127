import Foundation

struct AgentTurnOutcome: Equatable {
    let state: GameState
    let record: AgentDecisionRecord
}

struct TurnManager {
    let agent: GameAgent
    let provider: DecisionProvider
    let providerName: String
    let commandHandler: GameCommandHandling
    let contextBuilder: AgentContextBuilder
    let parser: AgentDecisionParser
    let mapper: AgentCommandMapper

    init(
        agent: GameAgent,
        provider: DecisionProvider,
        providerName: String,
        commandHandler: GameCommandHandling,
        contextBuilder: AgentContextBuilder = AgentContextBuilder(),
        parser: AgentDecisionParser = AgentDecisionParser(),
        mapper: AgentCommandMapper = AgentCommandMapper()
    ) {
        self.agent = agent
        self.provider = provider
        self.providerName = providerName
        self.commandHandler = commandHandler
        self.contextBuilder = contextBuilder
        self.parser = parser
        self.mapper = mapper
    }

    func runGermanAITurn(state: GameState) async -> AgentTurnOutcome {
        let context = contextBuilder.agentContext(for: agent, state: state, playerDirective: nil)
        let contextSummary = Self.contextSummary(context)

        guard state.activeFaction == .germany, state.phase == .germanAI else {
            return AgentTurnOutcome(
                state: state,
                record: failureRecord(
                    state: state,
                    contextSummary: contextSummary,
                    rawJSON: nil,
                    parsedIntent: nil,
                    errors: ["German AI turn requested outside germanAI phase."]
                )
            )
        }

        do {
            let envelope = try await provider.decide(context: context)
            let rawJSON = try Self.canonicalJSON(envelope)
            let parsedDecision = try parser.parse(rawJSON, expectedAgentId: agent.id, expectedTurn: state.turn)
            var nextState = state
            var commandResults: [CommandResultSummary] = []
            var errors: [String] = parsedDecision.orders.isEmpty ? ["Agent returned no orders."] : []

            for (index, order) in parsedDecision.orders.enumerated() {
                do {
                    let issuedCommand = try mapper.map(order, agentId: parsedDecision.agentId)
                    let result = commandHandler.execute(issuedCommand.command, in: nextState)
                    nextState = result.state
                    commandResults.append(
                        .mapped(orderIndex: index, order: order, command: issuedCommand.command, result: result)
                    )

                    if !result.succeeded {
                        errors.append("Order \(index) rejected: \(result.validation.errors.map(\.rawValue).joined(separator: ", ")).")
                    }
                } catch {
                    errors.append("Order \(index) mapping failed: \(error.localizedDescription)")
                    commandResults.append(.mappingFailed(orderIndex: index, order: order, error: error))
                }
            }

            let endTurnResult = commandHandler.execute(.endTurn, in: nextState)
            nextState = endTurnResult.state
            commandResults.append(.endTurn(result: endTurnResult))
            if !endTurnResult.succeeded {
                errors.append("AI end turn failed: \(endTurnResult.validation.errors.map(\.rawValue).joined(separator: ", ")).")
            }

            let record = AgentDecisionRecord(
                id: "agent_\(agent.id)_turn_\(state.turn)",
                turn: state.turn,
                agentId: agent.id,
                provider: providerName,
                contextSummary: contextSummary,
                rawJSON: rawJSON,
                parsedIntent: parsedDecision.intent,
                commandResults: commandResults,
                errors: errors
            )
            return AgentTurnOutcome(state: nextState, record: record)
        } catch {
            return AgentTurnOutcome(
                state: state,
                record: failureRecord(
                    state: state,
                    contextSummary: contextSummary,
                    rawJSON: nil,
                    parsedIntent: nil,
                    errors: [error.localizedDescription]
                )
            )
        }
    }

    private func failureRecord(
        state: GameState,
        contextSummary: String,
        rawJSON: String?,
        parsedIntent: String?,
        errors: [String]
    ) -> AgentDecisionRecord {
        AgentDecisionRecord(
            id: "agent_\(agent.id)_turn_\(state.turn)_failed",
            turn: state.turn,
            agentId: agent.id,
            provider: providerName,
            contextSummary: contextSummary,
            rawJSON: rawJSON,
            parsedIntent: parsedIntent,
            commandResults: [],
            errors: errors
        )
    }

    static func contextSummary(_ context: AgentContext) -> String {
        "\(context.agentId) turn \(context.turn): \(context.friendlyDivisions.count) friendly divisions, \(context.enemyDivisions.count) known enemy divisions, \(context.objectives.count) objectives visible."
    }

    static func canonicalJSON(_ envelope: AgentDecisionEnvelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        return String(decoding: data, as: UTF8.self)
    }
}
