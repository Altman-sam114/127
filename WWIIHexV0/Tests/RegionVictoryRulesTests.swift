import XCTest
@testable import WWIIHexV0

final class RegionVictoryRulesTests: XCTestCase {
    func testStrategicVictoryAssessmentUsesRegionObjectives() {
        var state = RegionRuleTestFixtures.state(divisions: [])
        state.map.regions["bastogne"]?.controller = .germany
        state.map.regions["st_vith"]?.controller = .germany

        let assessment = RegionVictoryRules().assessVictory(in: state)

        XCTAssertEqual(assessment.winner, .germany)
        XCTAssertEqual(assessment.reason, .bastogneAndStVithControlledByGermany)
    }

    func testRegionVictoryDoesNotMutateGameVictoryState() {
        var state = RegionRuleTestFixtures.state(divisions: [])
        state.map.regions["bastogne"]?.controller = .germany
        state.map.regions["st_vith"]?.controller = .germany

        _ = RegionVictoryRules().assessVictory(in: state)

        XCTAssertNil(state.victoryState.winner)
    }
}

