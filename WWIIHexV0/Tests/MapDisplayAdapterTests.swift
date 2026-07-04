import XCTest
@testable import WWIIHexV0

final class MapDisplayAdapterTests: XCTestCase {
    func testHexToRegionMappingUsesMapState() {
        let adapter = MapDisplayAdapter(state: RegionRuleTestFixtures.state(divisions: []))

        XCTAssertEqual(adapter.regionId(for: HexCoord(q: 2, r: 0)), "bastogne")
    }

    func testInvalidHexMapsToNil() {
        let adapter = MapDisplayAdapter(state: RegionRuleTestFixtures.state(divisions: []))

        XCTAssertNil(adapter.regionId(for: HexCoord(q: 9, r: 9)))
    }

    func testRegionDisplayHexesRoundTripToRegion() {
        let adapter = MapDisplayAdapter(state: RegionRuleTestFixtures.state(divisions: []))

        let displayHexes = adapter.displayHexes(for: "bastogne")

        XCTAssertFalse(displayHexes.isEmpty)
        XCTAssertTrue(displayHexes.allSatisfy { adapter.regionId(for: $0) == "bastogne" })
    }

    func testRepresentativeHexBelongsToDisplayHexes() throws {
        let adapter = MapDisplayAdapter(state: RegionRuleTestFixtures.state(divisions: []))

        let representative = try XCTUnwrap(adapter.representativeHex(for: "bastogne"))

        XCTAssertTrue(adapter.displayHexes(for: "bastogne").contains(representative))
    }

    func testVisualTerrainAndControllerPreferTacticalHex() throws {
        var state = RegionRuleTestFixtures.state(divisions: [])
        var bastogne = try XCTUnwrap(state.map.regions["bastogne"])
        bastogne.terrain = .forest
        bastogne.controller = .germany
        state.map.regions["bastogne"] = bastogne
        state.map.tiles[HexCoord(q: 2, r: 0)] = HexTile(
            coord: HexCoord(q: 2, r: 0),
            baseTerrain: .city,
            controller: .allies,
            regionId: "bastogne"
        )

        let display = try XCTUnwrap(
            MapDisplayAdapter(state: state)
                .hexDisplayState(for: HexCoord(q: 2, r: 0), viewerFaction: .allies)
        )

        XCTAssertEqual(display.terrain, .city)
        XCTAssertEqual(display.controller, .allies)
    }
}
