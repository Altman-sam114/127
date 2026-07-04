import XCTest
@testable import WWIIHexV0

final class GameStateTests: XCTestCase {
    func testInitialStateMatchesV0ScenarioDefaults() {
        let state = GameState.initial()

        XCTAssertEqual(state.scenarioId, "ardennes_v0")
        XCTAssertEqual(state.turn, 1)
        XCTAssertEqual(state.maxTurns, 8)
        XCTAssertEqual(state.activeFaction, .germany)
        XCTAssertEqual(state.phase, .germanAI)
        XCTAssertEqual(state.eventLog.count, 1)
    }
}
