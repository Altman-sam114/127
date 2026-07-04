import Foundation

enum HarnessFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw HarnessFailure.failed(message)
    }
}

@main
struct AgentPipelineHarness {
    static func main() async {
        do {
            let dataDirectory = URL(fileURLWithPath: "/Users/a114514/Desktop/codexapp/test/WWIIHexV0/Data")
            let loader = DataLoader(resourceDirectory: dataDirectory)
            let dataSet = try loader.loadArdennesDataSet()
            let state = loader.loadInitialGameState()

            guard let guderianDefinition = dataSet.generalAgents.first(where: { $0.id == "guderian" }) else {
                throw HarnessFailure.failed("Missing guderian definition in general_agents.json.")
            }
            guard let guderian = GameAgent(definition: guderianDefinition) else {
                throw HarnessFailure.failed("Could not construct GameAgent from guderian definition.")
            }

            let germanUnitIds = Set(state.divisions.filter { $0.faction == .germany }.map(\.id))
            try require(Set(guderian.assignedDivisionIds) == germanUnitIds, "guderian assignments do not match German units.")
            try require(state.activeFaction == .germany, "Initial active faction is not Germany.")
            try require(state.phase == .germanAI, "Initial phase is not germanAI.")

            let context = AgentContextBuilder().agentContext(for: guderian, state: state, playerDirective: nil)
            try require(context.agentId == "guderian", "Context agent id mismatch.")
            try require(Set(context.friendlyDivisions.map(\.id)) == germanUnitIds, "Context friendly divisions mismatch.")
            try require(!context.enemyDivisions.isEmpty, "Context has no known enemy divisions.")
            try require(!context.visibleTiles.isEmpty, "Context has no visible tiles.")

            let envelope = try await MockAIClient().decide(context: context)
            try require(envelope.schemaVersion == 1, "MockAI schema version mismatch.")
            try require(envelope.agentId == "guderian", "MockAI agent id mismatch.")
            try require(envelope.turn == state.turn, "MockAI turn mismatch.")
            try require(!envelope.orders.isEmpty, "MockAI returned no orders.")

            let rawJSON = try TurnManager.canonicalJSON(envelope)
            let parsed = try AgentDecisionParser().parse(rawJSON, expectedAgentId: guderian.id, expectedTurn: state.turn)
            try require(parsed == envelope, "Parser did not round-trip MockAI envelope.")

            let mapper = AgentCommandMapper()
            let mappedCommands = try parsed.orders.map { try mapper.map($0, agentId: parsed.agentId) }
            try require(mappedCommands.count == parsed.orders.count, "Mapped command count mismatch.")
            for mappedCommand in mappedCommands {
                switch mappedCommand.issuedBy {
                case .agent(let agentId):
                    try require(agentId == "guderian", "Mapped command issuer mismatch.")
                }
            }

            let manager = TurnManager(
                agent: guderian,
                provider: MockAIClient(),
                providerName: "MockAI",
                commandHandler: RuleEngine()
            )
            let outcome = await manager.runGermanAITurn(state: state)

            try require(outcome.record.agentId == "guderian", "Decision record agent id mismatch.")
            try require(outcome.record.provider == "MockAI", "Decision record provider mismatch.")
            try require(outcome.record.rawJSON != nil, "Decision record missing raw JSON.")
            try require(outcome.record.parsedIntent == envelope.intent, "Decision record intent mismatch.")
            try require(outcome.record.commandResults.contains { $0.id == "end_turn" && $0.executed }, "Decision record missing executed end turn.")
            try require(outcome.state.activeFaction == .allies, "AI turn did not hand control to Allies.")
            try require(outcome.state.phase == .alliedPlayer, "AI turn did not enter alliedPlayer phase.")

            print("Agent pipeline harness passed")
            print("dataSetAgents=\(dataSet.generalAgents.count)")
            print("friendlyDivisions=\(context.friendlyDivisions.count)")
            print("enemyDivisions=\(context.enemyDivisions.count)")
            print("mockOrders=\(envelope.orders.count)")
            print("commandResults=\(outcome.record.commandResults.count)")
            print("recordErrors=\(outcome.record.errors.count)")
            if !outcome.record.errors.isEmpty {
                print("recordErrorDetails=\(outcome.record.errors.joined(separator: " | "))")
            }
            print("nextPhase=\(outcome.state.phase.rawValue)")
        } catch {
            fputs("Agent pipeline harness failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
