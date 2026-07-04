import XCTest
@testable import WWIIHexV0

final class WarSystemsIntegrationTests: XCTestCase {
    func testDataLoaderBuildsHexRegionTheaterFrontAndDeploymentChain() {
        let state = DataLoader().loadInitialGameState()

        let sampleHex = state.map.hexToRegion.keys.sorted {
            if $0.q != $1.q { return $0.q < $1.q }
            return $0.r < $1.r
        }.first
        let regionId = sampleHex.flatMap { state.map.region(for: $0) }
        let theaterId = regionId.flatMap { state.theaterState.regionToTheater[$0] }
        let frontZoneId = regionId.flatMap { state.warDeploymentState.regionToFrontZone[$0] }

        XCTAssertNotNil(sampleHex)
        XCTAssertNotNil(regionId)
        XCTAssertNotNil(theaterId)
        XCTAssertNotNil(frontZoneId)
        XCTAssertFalse(state.theaterState.theaters.isEmpty)
        XCTAssertFalse(state.frontLineState.frontLines.isEmpty)
        XCTAssertFalse(state.warDeploymentState.frontZones.isEmpty)
        XCTAssertLessThanOrEqual(
            state.warDeploymentState.diagnostics.scannedRegionCount,
            state.map.regions.count
        )
    }

    func testTheaterFrontLineDeploymentAdvanceStayConsistent() {
        var scenario = Self.westFrontScenario()
        let initialGermanLine = scenario.frontLineState.frontLines.values.first {
            $0.theaterId == TheaterId(Self.germanFront.rawValue)
        }

        XCTAssertTrue(initialGermanLine?.segments.contains { $0.regionA == "ardennes" && $0.regionB == "sedan" } ?? false)
        XCTAssertEqual(
            scenario.gameState.warDeploymentState.frontZones[Self.germanFront]?.frontSegments.map(\.regionId),
            ["ardennes"]
        )
        XCTAssertEqual(
            scenario.gameState.warDeploymentState.frontZones[Self.germanFront]?.unitsFront,
            ["front_panzer"]
        )
        XCTAssertEqual(
            scenario.gameState.warDeploymentState.frontZones[Self.germanDepth]?.unitsDepth,
            ["depth_motorized"]
        )
        XCTAssertEqual(
            scenario.gameState.warDeploymentState.frontZones[Self.germanCore]?.unitsGarrison,
            ["berlin_guard"]
        )

        scenario.map.regions["sedan"]?.controller = .germany
        scenario.map.tiles[HexCoord(q: 2, r: 0)]?.controller = .germany
        let advancedTheater = TheaterSystem().expandDynamicTheater(
            state: scenario.theaterState,
            map: scenario.map,
            divisions: scenario.divisions,
            breakthroughHex: HexCoord(q: 2, r: 0),
            advancingTheaterId: TheaterId(Self.germanFront.rawValue),
            faction: .germany
        ).state
        scenario.theaterState = advancedTheater
        scenario.frontLineState = FrontLineManager().update(
            state: scenario.frontLineState,
            map: scenario.map,
            theaterState: scenario.theaterState,
            divisions: scenario.divisions,
            turn: 2,
            events: [.regionControllerChanged("sedan"), .theaterAssignmentChanged("sedan")]
        )
        let advancedDeployment = WarDeploymentManager().advanceRegion(
            "sedan",
            from: Self.frenchFront,
            to: Self.germanFront,
            state: scenario.gameState.warDeploymentState,
            map: scenario.map,
            divisions: scenario.divisions,
            turn: 2
        )

        XCTAssertEqual(
            advancedDeployment.regionToFrontZone["sedan"],
            Self.germanFront
        )
        XCTAssertEqual(advancedDeployment.hexToFrontZone[HexCoord(q: 2, r: 0)], Self.germanFront)
        XCTAssertTrue(
            advancedDeployment.frontZones[Self.germanFront]?.frontSegments.contains { $0.regionId == "sedan" } ?? false
        )
        XCTAssertLessThan(
            advancedDeployment.diagnostics.scannedRegionCount,
            scenario.map.regions.count
        )
        XCTAssertTrue(
            scenario.frontLineState.frontLines.values.contains {
                $0.segments.contains { $0.regionA == "sedan" && $0.regionB == "paris" }
            }
        )
    }

    func testMockAIUsesFrontDeploymentAndCommandsExecute() async throws {
        let scenario = Self.westFrontScenario()
        let state = scenario.gameState
        let agent = GameAgent.guderianFallback(
            assignedDivisionIds: ["front_panzer", "depth_motorized", "berlin_guard"]
        )
        let context = AgentContextBuilder().agentContext(
            for: agent,
            state: state,
            playerDirective: "Use front deployment."
        )

        XCTAssertEqual(context.frontZones.count, 3)
        XCTAssertTrue(context.frontZones.contains { $0.frontUnitIds == ["front_panzer"] })
        XCTAssertTrue(context.frontZones.contains { $0.depthUnitIds == ["depth_motorized"] })
        XCTAssertTrue(context.frontZones.contains { $0.garrisonUnitIds == ["berlin_guard"] })

        let envelope = try await MockAIClient().decide(context: context)
        XCTAssertEqual(envelope.schemaVersion, 2)
        XCTAssertEqual(Set(envelope.orders.map(\.divisionId)), Set(["front_panzer", "depth_motorized", "berlin_guard"]))
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "front_panzer" }?.type, .attack)
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "depth_motorized" }?.type, .move)
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "depth_motorized" }?.toRegionId, "ardennes")
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "berlin_guard" }?.type, .hold)

        var nextState = state
        var succeededCommands = 0
        for order in envelope.orders {
            let issued = try AgentCommandMapper().map(order, agentId: envelope.agentId, state: nextState)
            let result = RuleEngine().execute(issued.command, in: nextState)
            if result.succeeded {
                succeededCommands += 1
            }
            nextState = result.state
        }

        XCTAssertGreaterThanOrEqual(succeededCommands, 2)
        XCTAssertEqual(nextState.division(id: "berlin_guard")?.location(in: nextState.map), "berlin")
        XCTAssertLessThan(nextState.division(id: "allied_defender")?.strength ?? 10, 10)
    }

    func testRetiredTheaterFrontAndDeploymentClearWhenEnemyContactGone() {
        let scenario = Self.westFrontScenario()
        var map = scenario.map
        for regionId in map.regions.keys {
            map.regions[regionId]?.controller = .germany
            map.regions[regionId]?.owner = .germany
        }
        for hex in map.tiles.keys {
            map.tiles[hex]?.controller = .germany
        }

        var theaterState = scenario.theaterState
        for theaterId in theaterState.theaters.keys {
            theaterState.theaters[theaterId]?.controllingFaction = .germany
        }
        let retired = TheaterSystem().retireTheaters(
            state: theaterState,
            map: map,
            divisions: scenario.divisions,
            faction: .germany
        )
        let frontLines = FrontLineManager().makeInitialState(
            map: map,
            theaterState: retired,
            divisions: scenario.divisions,
            turn: 2
        )
        let deployment = WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: retired,
            divisions: scenario.divisions,
            turn: 2
        )

        XCTAssertTrue(retired.theaters.values.contains { $0.status == .inactive })
        XCTAssertTrue(frontLines.frontLines.values.allSatisfy {
            retired.theaters[$0.theaterId]?.status != .inactive
        })
        XCTAssertTrue(deployment.frontZones.values.filter { $0.faction == .germany }.allSatisfy {
            $0.frontSegments.allSatisfy { segment in
                retired.theaters[TheaterId(segment.neighborEnemyZone.rawValue)]?.controllingFaction == .germany
            }
        })
    }

    private static let germanCore = FrontZoneId("german_core")
    private static let germanDepth = FrontZoneId("german_depth")
    private static let germanFront = FrontZoneId("german_front")
    private static let frenchFront = FrontZoneId("french_front")

    private struct WarScenario {
        var map: MapState
        var theaterState: TheaterState
        var frontLineState: FrontLineState
        var divisions: [Division]
        var gameState: GameState
    }

    private static func westFrontScenario() -> WarScenario {
        let divisions = [
            division(id: "front_panzer", faction: .germany, coord: HexCoord(q: 1, r: 0), type: .tank),
            division(id: "depth_motorized", faction: .germany, coord: HexCoord(q: 0, r: 0), type: .motorizedInfantry),
            division(id: "berlin_guard", faction: .germany, coord: HexCoord(q: 0, r: -1), type: .infantry),
            division(id: "allied_defender", faction: .allies, coord: HexCoord(q: 2, r: 0), type: .infantry)
        ]
        var fixture = WarDeploymentTestFixtures.state(
            specs: [
                .init(id: "berlin", faction: .germany, zone: germanCore, neighbors: ["rhein"], city: true, factories: 3),
                .init(id: "rhein", faction: .germany, zone: germanDepth, neighbors: ["berlin", "ardennes"]),
                .init(id: "ardennes", faction: .germany, zone: germanFront, neighbors: ["rhein", "sedan"]),
                .init(id: "sedan", faction: .allies, zone: frenchFront, neighbors: ["ardennes", "paris"]),
                .init(id: "paris", faction: .allies, zone: frenchFront, neighbors: ["sedan"], city: true, factories: 4)
            ],
            divisions: divisions
        )
        addDisplayHex(HexCoord(q: 2, r: 1), to: "ardennes", faction: .germany, fixture: &fixture)
        fixture.state = WarDeploymentManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: divisions,
            turn: 1
        )
        let frontLineState = FrontLineManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: divisions,
            turn: 1
        )
        let gameState = GameState(
            scenarioId: "war_systems_integration",
            turn: 1,
            maxTurns: 8,
            activeFaction: .germany,
            phase: .germanAI,
            map: fixture.map,
            theaterState: fixture.theaterState,
            frontLineState: frontLineState,
            warDeploymentState: fixture.state,
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )

        return WarScenario(
            map: fixture.map,
            theaterState: fixture.theaterState,
            frontLineState: frontLineState,
            divisions: divisions,
            gameState: gameState
        )
    }

    private static func division(
        id: String,
        faction: Faction,
        coord: HexCoord,
        type: ComponentType
    ) -> Division {
        Division(
            id: id,
            name: id,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .east : .west,
            components: [DivisionComponent(type: type, weight: 1)]
        )
    }

    private static func addDisplayHex(
        _ hex: HexCoord,
        to regionId: RegionId,
        faction: Faction,
        fixture: inout (map: MapState, theaterState: TheaterState, state: WarDeploymentState)
    ) {
        fixture.map.regions[regionId]?.displayHexes.append(hex)
        fixture.map.tiles[hex] = HexTile(
            coord: hex,
            baseTerrain: .plain,
            controller: faction,
            regionId: regionId
        )
        fixture.map.hexToRegion[hex] = regionId
        fixture.map.width = max(fixture.map.width, hex.q + 1)
        fixture.map.height = max(fixture.map.height, hex.r + 1)
        if let theaterId = fixture.theaterState.regionToTheater[regionId] {
            fixture.theaterState.hexToTheater[hex] = theaterId
        }
    }
}
