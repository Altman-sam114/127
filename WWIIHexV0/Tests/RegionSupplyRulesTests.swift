import XCTest
@testable import WWIIHexV0

final class RegionSupplyRulesTests: XCTestCase {
    func testStrategicSupplyUsesRegionConnectivity() {
        let division = RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
        let state = RegionRuleTestFixtures.state(divisions: [division])

        XCTAssertEqual(RegionSupplyRules().supplyState(for: division, in: state), .supplied)
    }

    func testEnemyControlledRegionBlocksStrategicSupply() {
        var state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
            ]
        )
        state.map.regions["forest_road"]?.controller = .germany

        XCTAssertEqual(RegionSupplyRules().supplyState(for: state.divisions[0], in: state), .encircled)
    }

    func testRegionSupplyDoesNotMutateHexSupplyState() {
        var division = RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 2, r: 0))
        division.supplyState = .lowSupply
        let state = RegionRuleTestFixtures.state(divisions: [division])

        _ = RegionSupplyRules().supplyState(for: division, in: state)

        XCTAssertEqual(state.division(id: "allied")?.supplyState, .lowSupply)
    }

    func testCapturedSupplySourceFollowsOccupiedHexController() {
        var state = Self.capturedSupplyScenario()

        XCTAssertEqual(state.map.supplySources(for: .germany).map(\.id), ["depot"])
        XCTAssertTrue(state.map.supplySources(for: .allies).isEmpty)

        if var supplyHex = state.map.tile(at: HexCoord(q: 0, r: 0)) {
            supplyHex.controller = .allies
            state.map.setTile(supplyHex)
        }
        _ = RegionOccupationRules().aggregateControl(in: &state)

        XCTAssertEqual(state.map.regions["depot"]?.controller, .germany)
        XCTAssertEqual(state.map.supplySources(for: .allies).map(\.id), ["depot"])
        XCTAssertTrue(state.map.supplySources(for: .germany).isEmpty)

        for hex in state.map.regions["depot"]?.displayHexes ?? [] {
            guard var tile = state.map.tile(at: hex) else { continue }
            tile.controller = .allies
            state.map.setTile(tile)
        }
        _ = RegionOccupationRules().aggregateControl(in: &state)

        XCTAssertEqual(state.map.regions["depot"]?.controller, .allies)
        XCTAssertEqual(RegionSupplyRules().supplyState(for: state.division(id: "allied")!, in: state), .supplied)
        XCTAssertEqual(RegionSupplyRules().supplyState(for: state.division(id: "german")!, in: state), .encircled)
    }

    private static func capturedSupplyScenario() -> GameState {
        let depotHexes = [HexCoord(q: 0, r: 0), HexCoord(q: 1, r: 0)]
        let rearHex = HexCoord(q: 2, r: 0)
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]

        for hex in depotHexes {
            tiles[hex] = HexTile(coord: hex, baseTerrain: .plain, controller: .germany, regionId: "depot")
            hexToRegion[hex] = "depot"
        }
        tiles[rearHex] = HexTile(coord: rearHex, baseTerrain: .plain, controller: .allies, regionId: "rear")
        hexToRegion[rearHex] = "rear"

        let regions: [RegionId: RegionNode] = [
            "depot": RegionNode(
                id: "depot",
                name: "Depot",
                owner: .germany,
                controller: .germany,
                terrain: .plain,
                neighbors: ["rear"],
                displayHexes: depotHexes,
                representativeHex: depotHexes[0],
                supplyValue: 2
            ),
            "rear": RegionNode(
                id: "rear",
                name: "Rear",
                owner: .allies,
                controller: .allies,
                terrain: .plain,
                neighbors: ["depot"],
                displayHexes: [rearHex],
                representativeHex: rearHex
            )
        ]
        let map = MapState(
            width: 3,
            height: 1,
            tiles: tiles,
            supplySources: [
                SupplySource(id: "depot", faction: .germany, coord: depotHexes[0])
            ],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: [RegionEdge(from: "depot", to: "rear")]
        )

        return GameState(
            scenarioId: "captured_supply_source",
            turn: 1,
            maxTurns: 3,
            activeFaction: .allies,
            phase: .alliedPlayer,
            map: map,
            divisions: [
                Division.infantry(id: "allied", name: "Allied", faction: .allies, coord: rearHex),
                Division.infantry(id: "german", name: "German", faction: .germany, coord: rearHex)
            ],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }
}
