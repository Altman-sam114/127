import XCTest
@testable import WWIIHexV0

final class RegionCombatRulesTests: XCTestCase {
    func testStrategicAttackUsesGraphDistance() {
        let map = RegionMovementRulesTests.testMap()
        let rules = RegionCombatRules()

        XCTAssertTrue(rules.canStrategicallyAttack(from: "bastogne", to: "st_vith", range: 1, in: map))
        XCTAssertFalse(rules.canStrategicallyAttack(from: "allied_depot", to: "st_vith", range: 1, in: map))
    }

    func testPressureCountsEnemyDivisionsInRegionRadius() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0)),
                RegionRuleTestFixtures.division(id: "german", faction: .germany, coord: HexCoord(q: 3, r: 0))
            ]
        )

        let pressure = RegionCombatRules().pressure(on: "bastogne", for: .allies, in: state)

        XCTAssertGreaterThan(pressure, 0)
    }
}

