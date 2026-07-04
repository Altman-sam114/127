import XCTest
@testable import WWIIHexV0

final class EncirclementDetectionTests: XCTestCase {
    private let manager = FrontLineManager()

    func testEncirclementStructureMarksFrontLineAndSegments() {
        let fixture = FrontLineTestFixtures.mapAndTheaters(
            specs: [
                .init(id: "a1", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "a2", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "a3", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
                .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a1", "a2", "a3", "e"]),
                .init(id: "e", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["b"])
            ]
        )
        let state = manager.makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1)
        let frontLine = state.frontLines(for: FrontLineTestFixtures.theaterA).first

        XCTAssertEqual(frontLine?.type, .encirclement)
        XCTAssertEqual(frontLine?.state, .collapsing)
        XCTAssertEqual(frontLine?.segments.count, 3)
        XCTAssertTrue(frontLine?.segments.allSatisfy(\.isEncirclementCandidate) ?? false)
        XCTAssertTrue(frontLine?.segments.allSatisfy { $0.pressureLevel > 0.7 } ?? false)
        XCTAssertTrue(frontLine?.segments.allSatisfy { $0.supplyImpact == .high } ?? false)
    }
}
