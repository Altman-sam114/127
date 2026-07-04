import XCTest
@testable import WWIIHexV0

final class CommandIntentAdapterTests: XCTestCase {
    func testHexToRegionMappingSucceeds() throws {
        let map = RegionRuleTestFixtures.map()

        let region = try CommandIntentAdapter().regionId(for: HexCoord(q: 2, r: 0), in: map)

        XCTAssertEqual(region, "bastogne")
    }

    func testInvalidHexThrowsInvalidRegionForHex() {
        let map = RegionRuleTestFixtures.map()

        XCTAssertThrowsError(try CommandIntentAdapter().regionId(for: HexCoord(q: 9, r: 9), in: map)) { error in
            XCTAssertEqual(error as? CommandIntentAdapterError, .invalidRegionForHex(hex: HexCoord(q: 9, r: 9)))
        }
    }

    func testSameRegionMultipleHexesMapToSameRegion() throws {
        var map = RegionRuleTestFixtures.map()
        var bastogne = try XCTUnwrap(map.regions["bastogne"])
        bastogne.displayHexes = [HexCoord(q: 2, r: 0), HexCoord(q: 2, r: 1)]
        map.regions["bastogne"] = bastogne
        map.hexToRegion[HexCoord(q: 2, r: 1)] = "bastogne"

        let adapter = CommandIntentAdapter()

        XCTAssertEqual(try adapter.regionId(for: HexCoord(q: 2, r: 0), in: map), "bastogne")
        XCTAssertEqual(try adapter.regionId(for: HexCoord(q: 2, r: 1), in: map), "bastogne")
    }

    func testTappedHexCanCreateRegionAndHexMoveCommand() throws {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 1, r: 0))
            ]
        )
        let adapter = CommandIntentAdapter()

        let regionCommand = try adapter.makeRegionMoveCommand(
            divisionId: "allied",
            tappedHex: HexCoord(q: 2, r: 0),
            state: state
        )
        let hexCommand = try adapter.makeHexCommand(from: regionCommand, in: state)

        XCTAssertEqual(regionCommand, .move(divisionId: "allied", from: "forest_road", to: "bastogne"))
        XCTAssertEqual(hexCommand, .move(divisionId: "allied", destination: HexCoord(q: 2, r: 0)))
    }
}

