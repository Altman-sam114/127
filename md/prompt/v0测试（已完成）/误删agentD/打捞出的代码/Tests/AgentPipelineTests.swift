import XCTest
@testable import WWIIHexV0

final class AgentPipelineTests: XCTestCase {
    func testAgentContextBuilderCreatesCodableContext() throws {
        let state = Self.testState(activeFaction: .germany)
        let agent = GameAgent.guderianFallback(assignedDivisionIds: ["ger_panzer_1"])
        let context = AgentContextBuilder().agentContext(
            for: agent,
            state: state,
            playerDirective: "Break through toward Bastogne."
        )

        XCTAssertEqual(context.agentId, "guderian")
        XCTAssertEqual(context.friendlyDivisions.map(\.id), ["ger_panzer_1"])
        XCTAssertEqual(context.enemyDivisions.map(\.id), ["all_infantry_1"])
        XCTAssertFalse(context.visibleTiles.isEmpty)
        XCTAssertTrue(context.visibleTiles.allSatisfy { $0.visibility == .visible })

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(AgentContext.self, from: data)
        XCTAssertEqual(decoded, context)
    }

    func testMockAIClientOutputsCodableDecisionEnvelope() async throws {
        let state = Self.testState(activeFaction: .germany)
        let agent = GameAgent.guderianFallback(assignedDivisionIds: ["ger_panzer_1"])
        let context = AgentContextBuilder().agentContext(for: agent, state: state, playerDirective: nil)

        let envelope = try await MockAIClient().decide(context: context)

        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.agentId, "guderian")
        XCTAssertFalse(envelope.orders.isEmpty)

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(AgentDecisionEnvelope.self, from: data)
        XCTAssertEqual(decoded, envelope)
    }

    func testParserAcceptsValidMoveJSONAndRejectsBadJSON() throws {
        let json = """
        {
          "schemaVersion": 1,
          "agentId": "guderian",
          "turn": 1,
          "intent": "Advance",
          "orders": [
            {
              "type": "move",
              "divisionId": "ger_panzer_1",
              "to": { "q": 8, "r": 3 },
              "targetDivisionId": null,
              "stance": null,
              "reason": "Move west."
            }
          ]
        }
        """

        let parser = AgentDecisionParser()
        let envelope = try parser.parse(json, expectedAgentId: "guderian", expectedTurn: 1)

        XCTAssertEqual(envelope.orders.first?.type, .move)
        XCTAssertThrowsError(try parser.parse("{bad json", expectedAgentId: "guderian", expectedTurn: 1)) { error in
            XCTAssertTrue(error is AgentDecisionParserError)
        }
    }

    func testParserRejectsMismatchedSchemaAgentAndTurn() {
        let parser = AgentDecisionParser()
        let schemaJSON = """
        {"schemaVersion":2,"agentId":"guderian","turn":1,"intent":"x","orders":[]}
        """
        let agentJSON = """
        {"schemaVersion":1,"agentId":"other","turn":1,"intent":"x","orders":[]}
        """
        let turnJSON = """
        {"schemaVersion":1,"agentId":"guderian","turn":2,"intent":"x","orders":[]}
        """

        XCTAssertThrowsError(try parser.parse(schemaJSON, expectedAgentId: "guderian", expectedTurn: 1))
        XCTAssertThrowsError(try parser.parse(agentJSON, expectedAgentId: "guderian", expectedTurn: 1))
        XCTAssertThrowsError(try parser.parse(turnJSON, expectedAgentId: "guderian", expectedTurn: 1))
    }

    func testAgentOrderMapperMapsMoveAndAttack() throws {
        let mapper = AgentCommandMapper()
        let move = AgentOrder(
            type: .move,
            divisionId: "ger_panzer_1",
            to: HexCoord(q: 8, r: 3),
            targetDivisionId: nil,
            stance: nil,
            reason: "Advance."
        )
        let attack = AgentOrder(
            type: .attack,
            divisionId: "ger_panzer_1",
            to: nil,
            targetDivisionId: "all_infantry_1",
            stance: nil,
            reason: "Attack."
        )

        XCTAssertEqual(
            try mapper.map(move, agentId: "guderian").command,
            .move(divisionId: "ger_panzer_1", destination: HexCoord(q: 8, r: 3))
        )
        XCTAssertEqual(
            try mapper.map(attack, agentId: "guderian").command,
            .attack(attackerId: "ger_panzer_1", targetId: "all_infantry_1")
        )
    }

    func testAgentOrderMapperRejectsMissingRequiredFields() {
        let mapper = AgentCommandMapper()
        let badMove = AgentOrder(
            type: .move,
            divisionId: "ger_panzer_1",
            to: nil,
            targetDivisionId: nil,
            stance: nil,
            reason: "Missing destination."
        )
        let badAttack = AgentOrder(
            type: .attack,
            divisionId: "ger_panzer_1",
            to: nil,
            targetDivisionId: nil,
            stance: nil,
            reason: "Missing target."
        )

        XCTAssertThrowsError(try mapper.map(badMove, agentId: "guderian"))
        XCTAssertThrowsError(try mapper.map(badAttack, agentId: "guderian"))
    }

    func testProviderFailureDoesNotModifyGameState() async {
        let state = Self.testState(activeFaction: .germany)
        let manager = TurnManager(
            agent: GameAgent.guderianFallback(assignedDivisionIds: ["ger_panzer_1"]),
            provider: FailingDecisionProvider(),
            providerName: "FailingProvider",
            commandHandler: RuleEngine()
        )

        let outcome = await manager.runGermanAITurn(state: state)

        XCTAssertEqual(outcome.state, state)
        XCTAssertFalse(outcome.record.errors.isEmpty)
        XCTAssertTrue(outcome.record.commandResults.isEmpty)
    }

    func testInvalidMappedCommandIsRecordedAndDoesNotExecute() async {
        let state = Self.testState(activeFaction: .germany)
        let provider = StaticDecisionProvider(
            envelope: AgentDecisionEnvelope(
                schemaVersion: 1,
                agentId: "guderian",
                turn: 1,
                intent: "Attempt invalid move.",
                orders: [
                    AgentOrder(
                        type: .move,
                        divisionId: "ger_panzer_1",
                        to: HexCoord(q: 99, r: 99),
                        targetDivisionId: nil,
                        stance: nil,
                        reason: "Out of bounds."
                    )
                ]
            )
        )
        let manager = TurnManager(
            agent: GameAgent.guderianFallback(assignedDivisionIds: ["ger_panzer_1"]),
            provider: provider,
            providerName: "Static",
            commandHandler: RuleEngine()
        )

        let outcome = await manager.runGermanAITurn(state: state)

        XCTAssertEqual(outcome.record.commandResults.first?.validationSucceeded, false)
        XCTAssertEqual(outcome.record.commandResults.first?.errors, ["destinationOutOfBounds"])
        XCTAssertEqual(outcome.state.division(id: "ger_panzer_1")?.coord, state.division(id: "ger_panzer_1")?.coord)
        XCTAssertEqual(outcome.state.activeFaction, .allies)
    }

    private static func testState(activeFaction: Faction) -> GameState {
        GameState(
            scenarioId: "agent_test",
            turn: 1,
            maxTurns: 8,
            activeFaction: activeFaction,
            phase: activeFaction == .germany ? .germanAI : .alliedPlayer,
            map: MapState.ardennesV0(),
            divisions: [
                Division.panzer(
                    id: "ger_panzer_1",
                    name: "1st Panzer Division",
                    faction: .germany,
                    coord: HexCoord(q: 9, r: 3)
                ),
                Division.infantry(
                    id: "all_infantry_1",
                    name: "101st Infantry Division",
                    faction: .allies,
                    coord: HexCoord(q: 4, r: 5)
                )
            ],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: [
                GameLogEntry(turn: 1, faction: .germany, phase: .germanAI, message: "Test event.")
            ]
        )
    }
}

private struct StaticDecisionProvider: DecisionProvider {
    let envelope: AgentDecisionEnvelope

    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope {
        envelope
    }
}

private struct FailingDecisionProvider: DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope {
        throw TestProviderError.failed
    }
}

private enum TestProviderError: Error {
    case failed
}
