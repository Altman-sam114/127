import XCTest
@testable import WWIIHexV0

final class RegionRuleSystemTests: XCTestCase {
    func testRegionAnalysisRunsBesideHexCommandExecution() {
        let allied = RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 0, r: 0))
        let state = RegionRuleTestFixtures.state(activeFaction: .allies, divisions: [allied])
        let beforeAnalysis = RegionRuleSystem().analyze(state)

        let result = RuleEngine().execute(.move(divisionId: "allied", destination: HexCoord(q: 1, r: 0)), in: state)
        let afterAnalysis = RegionRuleSystem().analyze(result.state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.division(id: "allied")?.coord, HexCoord(q: 1, r: 0))
        XCTAssertEqual(beforeAnalysis.supplyByDivisionId["allied"], .supplied)
        XCTAssertEqual(afterAnalysis.supplyByDivisionId["allied"], .supplied)
    }

    func testRegionAnalysisDoesNotChangeGameState() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )

        _ = RegionRuleSystem().analyze(state)

        XCTAssertEqual(state, RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        ))
    }
}

