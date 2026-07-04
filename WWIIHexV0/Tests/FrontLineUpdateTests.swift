import XCTest
@testable import WWIIHexV0

final class FrontLineUpdateTests: XCTestCase {
    private let manager = FrontLineManager()

    func testRegionControllerChangeUpdatesFrontLine() {
        var fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a", "c"]),
                .init(id: "c", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["b"]),
                .init(id: "d", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: [])
            ]
        )
        let initial = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)

        fixture.map.regions["b"]?.controller = .allies
        let updated = manager.update(
            state: initial,
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [],
            turn: 2,
            events: [.regionControllerChanged("b")]
        )

        XCTAssertTrue(updated.regionStates["b"]?.dirtyFlag == true)
        XCTAssertLessThan(updated.diagnostics.scannedRegionCount, fixture.map.regions.count)
    }

    func testTheaterExpansionExtendsFrontLine() {
        var fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a", "c"]),
                .init(id: "c", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["b"])
            ]
        )
        let initial = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)

        fixture.map.regions["b"]?.controller = .allies
        fixture.theaterState.regionToTheater["b"] = FrontLineTestFixtures.theaterA
        fixture.theaterState.theaters[FrontLineTestFixtures.theaterA]?.regionIds = ["a", "b"]
        fixture.theaterState.theaters[FrontLineTestFixtures.theaterB]?.regionIds = ["c"]
        let updated = manager.update(
            state: initial,
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [],
            turn: 2,
            events: [.theaterAssignmentChanged("b")]
        )

        let segments = updated.frontLines(for: FrontLineTestFixtures.theaterA).flatMap(\.segments)
        XCTAssertEqual(segments.map(\.id), [FrontSegment.makeId("b", "c")])
    }

    func testTheaterDisappearanceDeletesFrontLine() {
        var fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a"])
            ]
        )
        let initial = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)
        fixture.theaterState.theaters[FrontLineTestFixtures.theaterB]?.status = .inactive

        let updated = manager.update(
            state: initial,
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [],
            turn: 2,
            events: [.theaterChanged(FrontLineTestFixtures.theaterB)]
        )

        XCTAssertTrue(updated.frontLines.isEmpty)
        XCTAssertTrue(updated.regionStates["a"]?.frontLines.isEmpty ?? false)
        XCTAssertTrue(updated.regionStates["b"]?.frontLines.isEmpty ?? false)
    }
}
