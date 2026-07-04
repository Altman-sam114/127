import XCTest
@testable import WWIIHexV0

final class WarDeploymentDeploymentTests: XCTestCase {
    func testFrontUnitsEvenlyAssignedToSegments() {
        let divisions = [
            Division.infantry(id: "u1", name: "u1", faction: .germany, coord: HexCoord(q: 0, r: 0)),
            Division.infantry(id: "u2", name: "u2", faction: .germany, coord: HexCoord(q: 0, r: 2)),
            Division.infantry(id: "u3", name: "u3", faction: .germany, coord: HexCoord(q: 0, r: 4))
        ]
        let fixture = WarDeploymentTestFixtures.easternFront(divisions: divisions)
        let counts = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]?.frontSegments
            .map { $0.assignedFrontUnitIds.count } ?? []

        XCTAssertEqual(counts, [1, 1, 1])
    }

    func testDepthUnitAssignedToFriendlyNeighborDepthZone() {
        let divisions = [
            Division.infantry(id: "reserve", name: "reserve", faction: .germany, coord: HexCoord(q: 0, r: 0))
        ]
        let fixture = WarDeploymentTestFixtures.invasionFrance(divisions: divisions)

        XCTAssertEqual(fixture.state.frontZones[WarDeploymentTestFixtures.germanyDepth]?.unitsDepth, ["reserve"])
    }

    func testGarrisonUnitDoesNotMoveFromCoreZone() {
        let divisions = [
            Division.infantry(id: "guard", name: "guard", faction: .germany, coord: HexCoord(q: 0, r: -1))
        ]
        let fixture = WarDeploymentTestFixtures.invasionFrance(divisions: divisions)

        XCTAssertEqual(fixture.state.frontZones[WarDeploymentTestFixtures.germanyCore]?.unitsGarrison, ["guard"])
    }

    func testCityOnFrontSegmentStillReceivesFrontUnits() {
        let divisions = [
            Division.infantry(id: "forward_guard", name: "forward_guard", faction: .germany, coord: HexCoord(q: 1, r: 0))
        ]
        let fixture = WarDeploymentTestFixtures.frontCity(divisions: divisions)

        let zone = fixture.state.frontZones[WarDeploymentTestFixtures.germanyFront]
        XCTAssertEqual(zone?.unitsFront, ["forward_guard"])
        XCTAssertEqual(zone?.unitsGarrison, [])
        XCTAssertEqual(zone?.frontSegments.first?.assignedFrontUnitIds, ["forward_guard"])
    }
}
