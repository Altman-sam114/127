import XCTest
@testable import WWIIHexV0

final class MultiEnemyFrontTests: XCTestCase {
    private let manager = FrontLineManager()

    func testOneTheaterAgainstMultipleEnemyTheatersExposesSingleMainFrontLine() {
        let fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b", "c", "d"]),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a"]),
                .init(id: "c", faction: .germany, theaterId: FrontLineTestFixtures.theaterC, neighbors: ["a"]),
                .init(id: "d", faction: .germany, theaterId: FrontLineTestFixtures.theaterD, neighbors: ["a"])
            ]
        )

        let state = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)
        let frontLines = state.frontLines(for: FrontLineTestFixtures.theaterA)

        XCTAssertEqual(frontLines.count, 1)
        XCTAssertEqual(frontLines.first?.segments.count, 3)
        XCTAssertEqual(Set(frontLines.first?.opposingTheaterIds ?? []), [
            FrontLineTestFixtures.theaterB,
            FrontLineTestFixtures.theaterC,
            FrontLineTestFixtures.theaterD
        ])
    }
}
