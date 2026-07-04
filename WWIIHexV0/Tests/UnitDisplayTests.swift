import XCTest
@testable import WWIIHexV0

final class UnitDisplayTests: XCTestCase {
    func testDivisionDisplayUsesTacticalHexCoord() {
        let division = RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
        let state = RegionRuleTestFixtures.state(divisions: [division])

        let displayHex = MapDisplayAdapter(state: state).unitDisplayHex(for: division)

        XCTAssertEqual(displayHex, HexCoord(q: 2, r: 0))
    }

    func testRegionRepresentativeUpdateDoesNotMoveTacticalUnitDisplay() {
        var state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )
        let newHex = HexCoord(q: 2, r: 1)
        state.map.tiles[newHex] = HexTile(coord: newHex, regionId: "bastogne")
        state.map.hexToRegion[newHex] = "bastogne"
        var bastogne = state.map.regions["bastogne"]
        bastogne?.displayHexes.append(newHex)
        bastogne?.representativeHex = newHex
        state.map.regions["bastogne"] = bastogne

        let displayHex = MapDisplayAdapter(state: state).unitDisplayHex(for: state.divisions[0])

        XCTAssertEqual(displayHex, HexCoord(q: 2, r: 0))
    }

    func testStackingUsesSameAnchorButDifferentOffsets() throws {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "a", faction: .allies, coord: HexCoord(q: 2, r: 0)),
                RegionRuleTestFixtures.division(id: "b", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )

        let placements = MapDisplayAdapter(state: state).unitPlacements(viewerFaction: .allies)
        let first = try XCTUnwrap(placements["a"])
        let second = try XCTUnwrap(placements["b"])

        XCTAssertEqual(first.hex, second.hex)
        XCTAssertNotEqual(first.offset, second.offset)
        XCTAssertEqual(first.stackCount, 2)
        XCTAssertEqual(second.stackCount, 2)
    }
}
