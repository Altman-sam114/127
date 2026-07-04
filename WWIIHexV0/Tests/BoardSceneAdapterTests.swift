import XCTest
@testable import WWIIHexV0

final class BoardSceneAdapterTests: XCTestCase {
    func testClickHexMapsToRegionId() {
        let state = RegionRuleTestFixtures.state(divisions: [])

        XCTAssertEqual(BoardSceneAdapter.regionId(for: HexCoord(q: 2, r: 0), in: state), "bastogne")
    }

    func testSameRegionDifferentHexesMapToSameRegion() {
        var map = RegionRuleTestFixtures.map()
        map.hexToRegion[HexCoord(q: 2, r: 1)] = "bastogne"
        var bastogne = map.regions["bastogne"]
        bastogne?.displayHexes.append(HexCoord(q: 2, r: 1))
        map.regions["bastogne"] = bastogne
        map.tiles[HexCoord(q: 2, r: 1)] = HexTile(coord: HexCoord(q: 2, r: 1), regionId: "bastogne")
        let state = GameState(
            scenarioId: "board_scene_adapter_test",
            turn: 1,
            maxTurns: 8,
            activeFaction: .allies,
            phase: .alliedPlayer,
            map: map,
            divisions: [],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )

        XCTAssertEqual(BoardSceneAdapter.regionId(for: HexCoord(q: 2, r: 0), in: state), "bastogne")
        XCTAssertEqual(BoardSceneAdapter.regionId(for: HexCoord(q: 2, r: 1), in: state), "bastogne")
    }

    func testRegionHighlightUsesSelectedRegion() {
        let state = RegionRuleTestFixtures.state(divisions: [])

        XCTAssertTrue(
            BoardSceneAdapter.isHighlighted(
                hex: HexCoord(q: 2, r: 0),
                selectedRegionId: "bastogne",
                in: state
            )
        )
        XCTAssertFalse(
            BoardSceneAdapter.isHighlighted(
                hex: HexCoord(q: 1, r: 0),
                selectedRegionId: "bastogne",
                in: state
            )
        )
    }
}
