import XCTest
@testable import WWIIHexV0

final class WarDeploymentFrontLineTests: XCTestCase {
    func testFrontSegmentGeneratedAtEnemyBorder() {
        let fixture = WarDeploymentTestFixtures.invasionFrance()
        let german = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]

        XCTAssertEqual(german?.frontSegments.map(\.regionId), ["ardennes"])
        XCTAssertEqual(german?.frontSegments.first?.neighborEnemyZone, WarDeploymentTestFixtures.franceFront)
        XCTAssertEqual(german?.state, .highIntensity)
    }

    func testRegionAdvanceExtendsFront() {
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

        XCTAssertEqual(updated.regionToFrontZone["sedan"], WarDeploymentTestFixtures.germanyFront)
        XCTAssertEqual(updated.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments.map(\.regionId), ["sedan"])
    }

    func testEnemyBorderDetectedWithoutGlobalPathSearch() {
        let fixture = WarDeploymentTestFixtures.easternFront()
        let german = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]

        XCTAssertEqual(german?.frontSegments.count, 3)
        XCTAssertLessThanOrEqual(fixture.state.diagnostics.scannedRegionCount, fixture.map.regions.count)
    }

    func testEventUpdateOnlyScansTouchedAndNeighborZones() {
        let fixture = WarDeploymentTestFixtures.invasionFrance()
        let updated = WarDeploymentManager().update(
            state: fixture.state,
            map: fixture.map,
            divisions: [],
            turn: 2,
            events: [.regionControllerChanged("ardennes")]
        )

        XCTAssertEqual(
            Set(updated.diagnostics.updatedZoneIds),
            Set([WarDeploymentTestFixtures.germanyFront, WarDeploymentTestFixtures.germanyDepth, WarDeploymentTestFixtures.franceFront])
        )
        XCTAssertEqual(updated.diagnostics.scannedZoneCount, 3)
        XCTAssertLessThan(updated.diagnostics.scannedRegionCount, fixture.map.regions.count)
    }
}
