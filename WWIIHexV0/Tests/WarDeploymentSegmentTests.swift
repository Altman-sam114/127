import XCTest
@testable import WWIIHexV0

final class WarDeploymentSegmentTests: XCTestCase {
    func testSegmentUsesRegionGranularity() {
        let fixture = WarDeploymentTestFixtures.invasionFrance()
        let segment = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments.first

        XCTAssertEqual(segment?.regionId, "ardennes")
        XCTAssertFalse(segment.map { fixture.map.regions[$0.regionId]?.displayHexes.isEmpty ?? true } ?? true)
    }

    func testSegmentEnemyZoneMapping() {
        let fixture = WarDeploymentTestFixtures.easternFront()
        let segments = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments ?? []

        XCTAssertTrue(segments.allSatisfy { $0.neighborEnemyZone == WarDeploymentTestFixtures.sovietFront })
    }

    func testEncirclementFlagForClosedPocket() {
        let fixture = WarDeploymentTestFixtures.localBreakthrough()
        let segments = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments ?? []

        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments.allSatisfy(\.isEncircled))
    }
}
