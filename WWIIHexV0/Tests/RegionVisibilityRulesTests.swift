import XCTest
@testable import WWIIHexV0

final class RegionVisibilityRulesTests: XCTestCase {
    func testVisibleRegionsUseGraphRadius() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )

        let visible = RegionVisibilityRules().visibleRegions(for: .allies, in: state, radius: 1)

        XCTAssertTrue(visible.contains("bastogne"))
        XCTAssertTrue(visible.contains("forest_road"))
        XCTAssertTrue(visible.contains("st_vith"))
        XCTAssertFalse(visible.contains("allied_depot"))
    }

    func testVisibilityMapMarksUnseenRegions() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )

        let visibility = RegionVisibilityRules().visibilityMap(for: .allies, in: state, radius: 0)

        XCTAssertEqual(visibility["bastogne"], .visible)
        XCTAssertEqual(visibility["forest_road"], .unseen)
    }
}

