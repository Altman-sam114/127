import XCTest
@testable import WWIIHexV0

final class RegionOccupationRulesTests: XCTestCase {
    func testSetControllerUpdatesRegionOnly() {
        var map = RegionRuleTestFixtures.map()
        let hex = HexCoord(q: 2, r: 0)
        let oldHexController = map.tile(at: hex)?.controller

        RegionOccupationRules().setController(.germany, for: "bastogne", in: &map)

        XCTAssertEqual(map.region(id: "bastogne")?.controller, .germany)
        XCTAssertEqual(map.tile(at: hex)?.controller, oldHexController)
    }

    func testContestedRegionsUsesDivisionHexToRegionMapping() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "a", faction: .allies, coord: HexCoord(q: 2, r: 0)),
                RegionRuleTestFixtures.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 0))
            ]
        )

        XCTAssertEqual(RegionOccupationRules().contestedRegions(in: state), ["bastogne"])
    }

    // v0.21: 聚合占领测试

    func testAggregateControlCityRequiresAllHexes() {
        // bastogne=(2,0) city，单 hex，需全占才翻
        var map = RegionRuleTestFixtures.map()
        // hex 仍 allies 控制 → region 不变
        var state = GameState(
            scenarioId: "t", turn: 1, maxTurns: 8, activeFaction: .allies,
            phase: .alliedPlayer, map: map,
            divisions: [RegionRuleTestFixtures.division(id: "a", faction: .allies, coord: HexCoord(q: 2, r: 0))],
            victoryState: .ongoing, selectedUnitSummary: nil, eventLog: []
        )
        let changed0 = RegionOccupationRules().aggregateControl(in: &state)
        XCTAssertTrue(changed0.isEmpty)
        XCTAssertEqual(state.map.region(id: "bastogne")?.controller, .allies)

        // hex 翻 germany → region 翻（city 全占）
        map = state.map
        if var tile = map.tile(at: HexCoord(q: 2, r: 0)) { tile.controller = .germany; map.setTile(tile) }
        state.map = map
        let changed1 = RegionOccupationRules().aggregateControl(in: &state)
        XCTAssertEqual(changed1, ["bastogne"])
        XCTAssertEqual(state.map.region(id: "bastogne")?.controller, .germany)
    }

    func testAggregateControlNonCityMajorityThreshold() {
        // forest_road=(1,0) forest，单 hex，≥50% 即占 1/1
        var map = RegionRuleTestFixtures.map()
        if var tile = map.tile(at: HexCoord(q: 1, r: 0)) { tile.controller = .germany; map.setTile(tile) }
        var state = GameState(
            scenarioId: "t", turn: 1, maxTurns: 8, activeFaction: .allies,
            phase: .alliedPlayer, map: map,
            divisions: [],
            victoryState: .ongoing, selectedUnitSummary: nil, eventLog: []
        )
        let changed = RegionOccupationRules().aggregateControl(in: &state)
        XCTAssertEqual(changed, ["forest_road"])
        XCTAssertEqual(state.map.region(id: "forest_road")?.controller, .germany)
    }

    func testAggregateControlNoChangeWhenHexesNeutral() {
        var state = RegionRuleTestFixtures.state(divisions: [])
        let changed = RegionOccupationRules().aggregateControl(in: &state)
        XCTAssertTrue(changed.isEmpty)
    }
}

