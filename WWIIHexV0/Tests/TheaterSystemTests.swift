import XCTest
@testable import WWIIHexV0

final class TheaterSystemTests: XCTestCase {
    private let system = TheaterSystem()

    func testInitialFixedGenerationCreatesFourTheaters() {
        let state = system.makeInitialFixedTheaters(map: TheaterTestFixtures.map(), divisions: [])

        XCTAssertEqual(state.theaters.count, 4)
        for kind in FixedTheaterKind.allCases {
            XCTAssertNotNil(state.theaters[kind.id])
            XCTAssertFalse(state.theaters[kind.id]?.regionIds.isEmpty ?? true)
        }
    }

    func testEveryRegionMapsToExactlyOneTheater() {
        let map = TheaterTestFixtures.map()
        let state = system.makeInitialFixedTheaters(map: map, divisions: [])

        XCTAssertEqual(Set(state.regionToTheater.keys), Set(map.regions.keys))
        for theaterId in state.regionToTheater.values {
            XCTAssertNotNil(state.theaters[theaterId])
        }
    }

    func testHexRegionTheaterMappingExists() {
        let map = TheaterTestFixtures.map()
        let state = system.makeInitialFixedTheaters(map: map, divisions: [])
        let hex = HexCoord(q: 0, r: 0)

        let regionId = map.region(for: hex)
        XCTAssertEqual(regionId, "nw_a")
        XCTAssertEqual(state.regionToTheater[regionId!], FixedTheaterKind.northWest.id)
    }

    func testUnitPoolUsesDivisionCurrentRegion() {
        let map = TheaterTestFixtures.map()
        let divisions = [
            TheaterTestFixtures.division(id: "allied_nw", faction: .allies, coord: HexCoord(q: 0, r: 0)),
            TheaterTestFixtures.division(id: "german_se", faction: .germany, coord: HexCoord(q: 3, r: 3))
        ]
        let state = system.makeInitialFixedTheaters(map: map, divisions: divisions)

        XCTAssertEqual(state.theaters[FixedTheaterKind.northWest.id]?.unitIds, ["allied_nw"])
        XCTAssertEqual(state.theaters[FixedTheaterKind.southEast.id]?.unitIds, ["german_se"])
    }

    func testExpansionBelowThresholdRemainsProvisional() {
        var map = TheaterTestFixtures.map()
        TheaterTestFixtures.setController(.germany, for: "se_a", in: &map)
        TheaterTestFixtures.setController(.allies, for: "se_b", in: &map)
        let state = system.makeInitialFixedTheaters(map: map, divisions: [])
        XCTAssertLessThan(state.theaters[FixedTheaterKind.southEast.id]?.controlRatios[.germany] ?? 1, 0.70)

        let result = system.expandTheater(
            state: state,
            map: map,
            divisions: [],
            breakthroughRegionId: "se_a",
            faction: .germany
        )

        XCTAssertEqual(result.affectedTheaterId, FixedTheaterKind.southEast.id)
        XCTAssertEqual(result.state.theaters[FixedTheaterKind.southEast.id]?.status, .provisional)
        if case .provisional(_, let ratio) = result.transition {
            XCTAssertLessThan(ratio, 0.70)
        } else {
            XCTFail("Expected provisional expansion")
        }
    }

    func testExpansionAtSeventyPercentFormalizesTheater() {
        var map = TheaterTestFixtures.map()
        TheaterTestFixtures.setController(.germany, for: "se_a", in: &map)
        TheaterTestFixtures.setController(.germany, for: "se_b", in: &map)
        let state = system.makeInitialFixedTheaters(map: map, divisions: [])

        let result = system.expandTheater(
            state: state,
            map: map,
            divisions: [],
            breakthroughRegionId: "se_a",
            faction: .germany
        )

        XCTAssertEqual(result.state.theaters[FixedTheaterKind.southEast.id]?.status, .active)
        XCTAssertEqual(result.state.theaters[FixedTheaterKind.southEast.id]?.controllingFaction, .germany)
        if case .formalized(_, let faction, let ratio) = result.transition {
            XCTAssertEqual(faction, .germany)
            XCTAssertGreaterThanOrEqual(ratio, 0.70)
        } else {
            XCTFail("Expected formalized expansion")
        }
    }

    func testRetirementMarksSurroundedFriendlyTheaterInactive() {
        var state = system.makeInitialFixedTheaters(map: TheaterTestFixtures.map(), divisions: [])
        for theaterId in state.theaters.keys {
            state.theaters[theaterId]?.controllingFaction = .allies
        }

        let retired = system.retireTheaters(
            state: state,
            map: TheaterTestFixtures.map(),
            divisions: [],
            faction: .allies
        )

        XCTAssertTrue(retired.theaters.values.contains { $0.status == .inactive })
    }

    func testRetiredTheaterUnitsRedistributeToActiveNeighbors() {
        let map = TheaterTestFixtures.map()
        let divisions = [
            TheaterTestFixtures.division(id: "retired_1", faction: .allies, coord: HexCoord(q: 0, r: 0)),
            TheaterTestFixtures.division(id: "retired_2", faction: .allies, coord: HexCoord(q: 1, r: 0))
        ]
        var state = system.makeInitialFixedTheaters(map: map, divisions: divisions)
        state.theaters[FixedTheaterKind.northWest.id]?.controllingFaction = .allies
        state.theaters[FixedTheaterKind.northEast.id]?.controllingFaction = .allies
        state.theaters[FixedTheaterKind.southWest.id]?.controllingFaction = .allies
        state.theaters[FixedTheaterKind.southEast.id]?.controllingFaction = .germany

        let retired = system.retireTheaters(
            state: state,
            map: map,
            divisions: divisions,
            faction: .allies
        )

        XCTAssertEqual(retired.theaters[FixedTheaterKind.northWest.id]?.status, .inactive)
        XCTAssertEqual(retired.theaters[FixedTheaterKind.northWest.id]?.unitIds, [])

        let activeNeighborUnitCount = retired.theaters[FixedTheaterKind.northWest.id]!.neighborTheaterIds
            .compactMap { retired.theaters[$0]?.unitIds.count }
            .reduce(0, +)
        XCTAssertEqual(activeNeighborUnitCount, 2)
    }

    func testSupportInterfacesReturnAvailableForcesAndThreats() {
        let divisions = [
            TheaterTestFixtures.division(id: "ready_unit", faction: .allies, coord: HexCoord(q: 0, r: 0))
        ]
        let state = system.makeInitialFixedTheaters(map: TheaterTestFixtures.map(), divisions: divisions)

        let available = system.getAvailableForces(FixedTheaterKind.northWest.id, in: state)
        XCTAssertEqual(available, ["ready_unit"])

        let request = system.requestSupport(
            from: FixedTheaterKind.northWest.id,
            to: FixedTheaterKind.northEast.id,
            in: state
        )
        XCTAssertEqual(request?.availableUnitIds, ["ready_unit"])

        let threatened = system.notifyThreat(
            theaterId: FixedTheaterKind.northWest.id,
            sourceRegionId: "nw_a",
            threatScore: 7,
            message: "Breakthrough risk.",
            in: state
        )
        XCTAssertEqual(threatened.theaters[FixedTheaterKind.northWest.id]?.recentThreats.first?.threatScore, 7)
    }

    func testAISummaryDoesNotExposeHexDetails() {
        let state = system.makeInitialFixedTheaters(map: TheaterTestFixtures.map(), divisions: [])
        let summaries = system.aiSummaries(for: state)

        XCTAssertEqual(summaries.count, 4)
        XCTAssertTrue(summaries.allSatisfy { !$0.regionIds.isEmpty })
    }

    func testLargeMapGenerationCompletesWithAllRegionsMapped() {
        let map = TheaterTestFixtures.largeMap(width: 30, height: 20)
        measure {
            let state = system.makeInitialFixedTheaters(map: map, divisions: [])
            XCTAssertEqual(state.regionToTheater.count, map.regions.count)
        }
    }
}

private enum TheaterTestFixtures {
    static func map() -> MapState {
        let specs: [(RegionId, String, Faction, [HexCoord], [RegionId])] = [
            ("nw_a", "NW A", .allies, [HexCoord(q: 0, r: 0), HexCoord(q: 0, r: 1)], ["nw_b", "ne_a", "sw_a"]),
            ("nw_b", "NW B", .allies, [HexCoord(q: 1, r: 0), HexCoord(q: 1, r: 1)], ["nw_a", "ne_a", "sw_a"]),
            ("ne_a", "NE A", .germany, [HexCoord(q: 2, r: 0), HexCoord(q: 2, r: 1)], ["nw_a", "nw_b", "ne_b", "se_a"]),
            ("ne_b", "NE B", .germany, [HexCoord(q: 3, r: 0), HexCoord(q: 3, r: 1)], ["ne_a", "se_a"]),
            ("sw_a", "SW A", .allies, [HexCoord(q: 0, r: 2), HexCoord(q: 0, r: 3)], ["nw_a", "nw_b", "sw_b", "se_a"]),
            ("sw_b", "SW B", .allies, [HexCoord(q: 1, r: 2), HexCoord(q: 1, r: 3)], ["sw_a", "se_a"]),
            ("se_a", "SE A", .allies, [HexCoord(q: 2, r: 2)], ["ne_a", "ne_b", "sw_a", "sw_b", "se_b"]),
            ("se_b", "SE B", .germany, [HexCoord(q: 3, r: 2), HexCoord(q: 3, r: 3)], ["se_a"])
        ]

        return makeMap(width: 4, height: 4, specs: specs)
    }

    static func largeMap(width: Int, height: Int) -> MapState {
        var specs: [(RegionId, String, Faction, [HexCoord], [RegionId])] = []

        for q in 0..<width {
            for r in 0..<height {
                let id = RegionId("r_\(q)_\(r)")
                var neighbors: [RegionId] = []
                if q > 0 { neighbors.append(RegionId("r_\(q - 1)_\(r)")) }
                if q < width - 1 { neighbors.append(RegionId("r_\(q + 1)_\(r)")) }
                if r > 0 { neighbors.append(RegionId("r_\(q)_\(r - 1)")) }
                if r < height - 1 { neighbors.append(RegionId("r_\(q)_\(r + 1)")) }

                specs.append((
                    id,
                    id.rawValue,
                    q < width / 2 ? .allies : .germany,
                    [HexCoord(q: q, r: r)],
                    neighbors
                ))
            }
        }

        return makeMap(width: width, height: height, specs: specs)
    }

    static func division(id: String, faction: Faction, coord: HexCoord) -> Division {
        Division(
            id: id,
            name: id,
            faction: faction,
            coord: coord,
            components: [DivisionComponent(type: .infantry, weight: 1)]
        )
    }

    static func setController(_ faction: Faction, for regionId: RegionId, in map: inout MapState) {
        map.regions[regionId]?.controller = faction
        for coord in map.regions[regionId]?.displayHexes ?? [] {
            guard var tile = map.tile(at: coord) else { continue }
            tile.controller = faction
            map.setTile(tile)
        }
    }

    private static func makeMap(
        width: Int,
        height: Int,
        specs: [(RegionId, String, Faction, [HexCoord], [RegionId])]
    ) -> MapState {
        var regions: [RegionId: RegionNode] = [:]
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        var edges: Set<RegionEdge> = []

        for (id, name, controller, hexes, neighbors) in specs {
            regions[id] = RegionNode(
                id: id,
                name: name,
                owner: controller,
                controller: controller,
                terrain: .plain,
                neighbors: neighbors,
                displayHexes: hexes,
                representativeHex: hexes[0],
                city: CityInfo(name: name, victoryPoints: 1)
            )

            for hex in hexes {
                tiles[hex] = HexTile(coord: hex, baseTerrain: .plain, controller: controller, regionId: id)
                hexToRegion[hex] = id
            }

            for neighbor in neighbors {
                edges.insert(RegionEdge(from: id, to: neighbor))
            }
        }

        return MapState(
            width: width,
            height: height,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: edges
        )
    }
}
