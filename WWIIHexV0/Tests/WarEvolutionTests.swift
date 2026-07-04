import XCTest
@testable import WWIIHexV0

final class WarEvolutionTests: XCTestCase {
    func testFranceInvasionAdvanceUpdatesFrontAndDepth() {
        let fixture = WarDeploymentTestFixtures.invasionFrance()
        let updated = WarDeploymentManager().advanceRegion(
            "sedan",
            from: WarDeploymentTestFixtures.franceFront,
            to: WarDeploymentTestFixtures.germanyFront,
            state: fixture.state,
            map: fixture.map,
            divisions: [],
            turn: 2
        )

        XCTAssertEqual(updated.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments.map(\.regionId), ["sedan"])
        XCTAssertTrue(updated.frontZones[WarDeploymentTestFixtures.germanyFront]?.neighbors.contains(WarDeploymentTestFixtures.germanyDepth) ?? false)
    }

    func testZoneDeathDeletesFront() {
        let fixture = WarDeploymentTestFixtures.localBreakthrough()
        let updated = WarDeploymentManager().advanceRegion(
            "pocket",
            from: WarDeploymentTestFixtures.franceFront,
            to: WarDeploymentTestFixtures.germanyFront,
            state: fixture.state,
            map: fixture.map,
            divisions: [],
            turn: 2
        )

        XCTAssertNil(updated.frontZones[WarDeploymentTestFixtures.franceFront])
        XCTAssertTrue(updated.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments.isEmpty ?? false)
    }

    func testLocalBreakthroughMarksPocketEncircled() {
        let fixture = WarDeploymentTestFixtures.localBreakthrough()
        let segments = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments ?? []

        XCTAssertTrue(segments.contains(where: { $0.isEncircled }))
    }
}
