import XCTest
@testable import WWIIHexV0

final class AgentRegionCommandPipelineTests: XCTestCase {
    func testMockAIV2RegionJSONCanExecuteThroughRuleEngine() async throws {
        // 用 germany agent 指挥 germany 单位（guderianFallback 默认 germany），
        // 避免 agent.faction != division.faction 导致 friendlyDivisions 过滤空。
        let state = RegionRuleTestFixtures.state(
            activeFaction: .germany,
            divisions: [
                RegionRuleTestFixtures.division(id: "ger_1", faction: .germany, coord: HexCoord(q: 4, r: 0))
            ]
        )
        let context = AgentContextBuilder().agentContext(
            for: GameAgent.guderianFallback(assignedDivisionIds: ["ger_1"]),
            state: state,
            playerDirective: nil
        )

        let envelope = try await MockAIClient().decide(context: context)
        let order = try XCTUnwrap(envelope.orders.first)
        let issued = try AgentCommandMapper().map(order, agentId: envelope.agentId, state: state)
        let result = RuleEngine().execute(issued.command, in: state)

        XCTAssertEqual(envelope.schemaVersion, 2)
        XCTAssertTrue(result.succeeded)
    }

    func testReplayCanReapplyMappedRegionCommandAsHexCommand() throws {
        let state = RegionRuleTestFixtures.state(
            activeFaction: .allies,
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 1, r: 0))
            ]
        )
        let regionCommand = RegionCommand.move(divisionId: "allied", from: "forest_road", to: "bastogne")
        let hexCommand = try CommandIntentAdapter().makeHexCommand(from: regionCommand, in: state)

        let first = RuleEngine().execute(hexCommand, in: state)
        let replay = RuleEngine().execute(hexCommand, in: state)

        XCTAssertEqual(first.state.division(id: "allied")?.coord, replay.state.division(id: "allied")?.coord)
    }
}

