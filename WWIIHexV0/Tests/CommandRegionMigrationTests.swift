import XCTest
@testable import WWIIHexV0

final class CommandRegionMigrationTests: XCTestCase {
    func testRegionMoveCommandMapsToHexCommandAndExecutes() throws {
        let division = RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 1, r: 0))
        let state = RegionRuleTestFixtures.state(activeFaction: .allies, divisions: [division])
        let regionCommand = RegionCommand.move(divisionId: "allied", from: "forest_road", to: "bastogne")
        let hexCommand = try CommandIntentAdapter().makeHexCommand(from: regionCommand, in: state)

        let result = RuleEngine().execute(hexCommand, in: state)

        XCTAssertEqual(hexCommand, .move(divisionId: "allied", destination: HexCoord(q: 2, r: 0)))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.division(id: "allied")?.coord, HexCoord(q: 2, r: 0))
        XCTAssertEqual(result.state.division(id: "allied")?.location(in: result.state.map), "bastogne")
    }

    func testHexCommandStillWorksWithoutRegionData() {
        let state = GameState.initial()
        let command = Command.move(divisionId: "ger_panzer_1", destination: HexCoord(q: 8, r: 3))

        let result = RuleEngine().execute(command, in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.division(id: "ger_panzer_1")?.coord, HexCoord(q: 8, r: 3))
    }
}

