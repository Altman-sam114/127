import XCTest
@testable import WWIIHexV0

final class RegionMovementRulesTests: XCTestCase {
    func testShortestPathUsesRegionGraphAndCosts() {
        let map = Self.testMap()
        let path = RegionMovementRules().shortestPath(from: "allied_depot", to: "bastogne", in: map)

        XCTAssertEqual(path?.regionIds, ["allied_depot", "forest_road", "bastogne"])
        XCTAssertEqual(path?.cost, 2)
    }

    func testReachableRegionsHonorsMovementBudget() {
        let reachable = RegionMovementRules().reachableRegions(
            from: "allied_depot",
            movementBudget: 2,
            in: Self.testMap()
        )

        XCTAssertNotNil(reachable["forest_road"])
        XCTAssertNotNil(reachable["bastogne"])
        XCTAssertNil(reachable["st_vith"])
    }

    func testImpassableRegionBlocksStrategicMovement() {
        var map = Self.testMap()
        map.regions["forest_road"]?.isPassable = false

        XCTAssertNil(RegionMovementRules().shortestPath(from: "allied_depot", to: "bastogne", in: map))
    }

    static func testMap() -> MapState {
        let nodes = RegionRuleTestFixtures.nodes()
        let edges: Set<RegionEdge> = [
            RegionEdge(from: "allied_depot", to: "forest_road", hasRoad: true),
            RegionEdge(from: "forest_road", to: "bastogne", hasRoad: true),
            RegionEdge(from: "bastogne", to: "st_vith", hasRiverCrossing: true)
        ]
        return RegionRuleTestFixtures.map(regions: nodes, edges: edges)
    }
}

