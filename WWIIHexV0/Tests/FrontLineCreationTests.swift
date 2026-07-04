import XCTest
@testable import WWIIHexV0

final class FrontLineCreationTests: XCTestCase {
    private let manager = FrontLineManager()

    func testAdjacentEnemyTheatersCreateFrontLine() {
        let fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a"])
            ]
        )

        let state = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)
        let frontLines = state.frontLines(for: FrontLineTestFixtures.theaterA)

        XCTAssertEqual(frontLines.count, 1)
        XCTAssertEqual(frontLines.first?.segments.count, 1)
        XCTAssertEqual(frontLines.first?.type, .normal)
        XCTAssertEqual(state.enemyNeighborCache["a"], ["b"])
    }

    func testNoEnemyContactCreatesNoFrontLine() {
        var fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: []),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: [])
            ]
        )
        fixture.map.tiles[HexCoord(q: 1, r: 0)] = nil
        fixture.map.tiles[HexCoord(q: 3, r: 0)] = HexTile(coord: HexCoord(q: 3, r: 0), baseTerrain: .plain, controller: .germany, regionId: "b")
        fixture.map.hexToRegion.removeValue(forKey: HexCoord(q: 1, r: 0))
        fixture.map.hexToRegion[HexCoord(q: 3, r: 0)] = "b"
        fixture.map.regions["b"]?.displayHexes = [HexCoord(q: 3, r: 0)]
        fixture.map.regions["b"]?.representativeHex = HexCoord(q: 3, r: 0)
        fixture.theaterState.hexToTheater.removeValue(forKey: HexCoord(q: 1, r: 0))
        fixture.theaterState.hexToTheater[HexCoord(q: 3, r: 0)] = FrontLineTestFixtures.theaterB

        let state = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)

        XCTAssertTrue(state.frontLines(for: FrontLineTestFixtures.theaterA).isEmpty)
        XCTAssertTrue(state.regionStates.values.allSatisfy { $0.frontLines.isEmpty })
    }
}
