import XCTest
@testable import WWIIHexV0

final class VisibilityDisplayTests: XCTestCase {
    func testVisibleRegionDisplaysVisible() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )

        let visibility = MapDisplayAdapter(state: state).visibility(for: HexCoord(q: 2, r: 0), faction: .allies)

        XCTAssertEqual(visibility, .visible)
    }

    func testUnseenRegionDisplaysFog() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 0, r: 0))
            ]
        )

        let visibility = MapDisplayAdapter(state: state).visibility(for: HexCoord(q: 4, r: 0), faction: .allies)

        XCTAssertEqual(visibility, .unseen)
    }

    func testEnemyInUnseenRegionIsHidden() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 0, r: 0)),
                RegionRuleTestFixtures.division(id: "german", faction: .germany, coord: HexCoord(q: 4, r: 0))
            ]
        )

        let placements = MapDisplayAdapter(state: state).unitPlacements(viewerFaction: .allies)

        XCTAssertNil(placements["german"])
        XCTAssertNotNil(placements["allied"])
    }
}
