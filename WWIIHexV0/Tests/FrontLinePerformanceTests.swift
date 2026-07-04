import XCTest
@testable import WWIIHexV0

final class FrontLinePerformanceTests: XCTestCase {
    private let manager = FrontLineManager()

    func testTurnRebuildScansOnlyActiveRegionsOnce() {
        let fixture = FrontLineTestFixtures.largeGrid(width: 30, height: 20)
        let state = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)

        XCTAssertLessThanOrEqual(state.diagnostics.scannedRegionCount, fixture.map.regions.count)
        XCTAssertEqual(state.diagnostics.updateMode, .turnRebuild)
        XCTAssertFalse(state.frontLines(for: FrontLineTestFixtures.theaterA).isEmpty)
    }

    func testEventDrivenUpdateDoesNotScanFullMap() {
        var fixture = FrontLineTestFixtures.largeGrid(width: 30, height: 20)
        let initial = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)
        fixture.map.regions["r_15_10"]?.controller = .allies

        let updated = manager.update(
            state: initial,
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [],
            turn: 2,
            events: [.regionControllerChanged("r_15_10")]
        )

        XCTAssertEqual(updated.diagnostics.updateMode, .eventDriven)
        XCTAssertLessThan(updated.diagnostics.scannedRegionCount, fixture.map.regions.count)
        XCTAssertLessThanOrEqual(updated.diagnostics.scannedRegionCount, 5)
    }
}
