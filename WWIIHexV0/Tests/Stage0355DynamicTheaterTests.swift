import XCTest
import SpriteKit
@testable import WWIIHexV0

final class Stage0355DynamicTheaterTests: XCTestCase {
    func testOccupationRulesAreSymmetricForEmptyNormalHexes() {
        var alliedState = Self.twoRegionState(
            activeFaction: .allies,
            mover: Division.infantry(id: "allied", name: "allied", faction: .allies, coord: HexCoord(q: 0, r: 0))
        )
        let alliedResult = RuleEngine().execute(.move(divisionId: "allied", destination: HexCoord(q: 1, r: 0)), in: alliedState)
        XCTAssertTrue(alliedResult.succeeded)
        XCTAssertEqual(alliedResult.state.map.tile(at: HexCoord(q: 1, r: 0))?.controller, .allies)

        alliedState = Self.twoRegionState(
            activeFaction: .germany,
            mover: Division.infantry(id: "german", name: "german", faction: .germany, coord: HexCoord(q: 1, r: 0))
        )
        let germanResult = RuleEngine().execute(.move(divisionId: "german", destination: HexCoord(q: 0, r: 0)), in: alliedState)
        XCTAssertTrue(germanResult.succeeded)
        XCTAssertEqual(germanResult.state.map.tile(at: HexCoord(q: 0, r: 0))?.controller, .germany)
    }

    func testMoveIntoEnemyOccupiedHexIsRejectedInsteadOfOccupied() {
        var state = Self.twoRegionState(
            activeFaction: .allies,
            mover: Division.infantry(id: "allied", name: "allied", faction: .allies, coord: HexCoord(q: 0, r: 0))
        )
        state.divisions.append(
            Division.infantry(id: "german", name: "german", faction: .germany, coord: HexCoord(q: 1, r: 0))
        )

        let result = RuleEngine().execute(.move(divisionId: "allied", destination: HexCoord(q: 1, r: 0)), in: state)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.validation.errors, [.destinationOccupied])
        XCTAssertEqual(result.state.map.tile(at: HexCoord(q: 1, r: 0))?.controller, .germany)
    }

    func testDynamicTheaterBreakthroughDoesNotMutateInitialSnapshot() {
        var fixture = WarDeploymentTestFixtures.invasionFrance(
            divisions: [Division.infantry(id: "panzer", name: "panzer", faction: .germany, coord: HexCoord(q: 1, r: 0))]
        )
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)

        let initialSnapshot = fixture.theaterState.initialSnapshot
        let result = TheaterSystem().expandDynamicTheater(
            state: fixture.theaterState,
            map: fixture.map,
            divisions: [],
            breakthroughRegionId: "sedan",
            advancingTheaterId: TheaterId(WarDeploymentTestFixtures.germanyFront.rawValue),
            faction: .germany
        )

        XCTAssertEqual(result.state.initialSnapshot, initialSnapshot)
        XCTAssertEqual(result.state.regionToTheater["sedan"], TheaterId(WarDeploymentTestFixtures.franceFront.rawValue))
        XCTAssertEqual(result.state.hexToTheater[HexCoord(q: 2, r: 0)], TheaterId(WarDeploymentTestFixtures.germanyFront.rawValue))
        XCTAssertEqual(initialSnapshot?.regionToTheater["sedan"], TheaterId(WarDeploymentTestFixtures.franceFront.rawValue))
    }

    func testSingleHexBreakthroughDoesNotPullWholeRegionIntoDynamicTheater() throws {
        var fixture = Self.multiHexBreakthroughFixture()
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        let breakthroughHex = HexCoord(q: 2, r: 0)
        let untouchedHex = HexCoord(q: 3, r: 0)

        let result = TheaterSystem().expandDynamicTheater(
            state: fixture.theaterState,
            map: fixture.map,
            divisions: [],
            breakthroughHex: breakthroughHex,
            advancingTheaterId: "germany_front",
            faction: .germany
        )

        XCTAssertEqual(result.state.regionToTheater["sedan"], "france_front")
        XCTAssertEqual(result.state.initialSnapshot?.regionToTheater["sedan"], "france_front")
        XCTAssertEqual(result.state.dynamicTheaterId(for: breakthroughHex, map: fixture.map), "germany_front")
        XCTAssertEqual(result.state.dynamicTheaterId(for: untouchedHex, map: fixture.map), "france_front")
    }

    func testDynamicFrontLineUsesHexBreakthroughBeforeRegionControllerFlips() {
        var fixture = Self.multiHexBreakthroughFixture()
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        fixture.theaterState = TheaterSystem().expandDynamicTheater(
            state: fixture.theaterState,
            map: fixture.map,
            divisions: [],
            breakthroughHex: HexCoord(q: 2, r: 0),
            advancingTheaterId: "germany_front",
            faction: .germany
        ).state

        let frontLine = FrontLineManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [],
            turn: 1
        )
        let germanLine = frontLine.frontLines.values.first { $0.theaterId == "germany_front" }

        XCTAssertEqual(fixture.map.regions["sedan"]?.controller, .allies)
        XCTAssertTrue(germanLine?.segments.contains { $0.regionA == "sedan" && $0.regionB == "sedan" } ?? false)
        XCTAssertEqual(germanLine?.type, .breakthrough)
    }

    func testDeploymentUsesHexBreakthroughWithoutReassigningWholeRegion() {
        let panzer = Division.infantry(
            id: "panzer",
            name: "panzer",
            faction: .germany,
            coord: HexCoord(q: 2, r: 0)
        )
        var fixture = Self.multiHexBreakthroughFixture(divisions: [panzer])
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        let initialDeployment = WarDeploymentManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [panzer],
            turn: 1
        )

        let deployment = WarDeploymentManager().advanceHex(
            HexCoord(q: 2, r: 0),
            from: "france_front",
            to: "germany_front",
            state: initialDeployment,
            map: fixture.map,
            divisions: [panzer],
            turn: 2
        )

        XCTAssertEqual(deployment.hexToFrontZone[HexCoord(q: 2, r: 0)], "germany_front")
        XCTAssertEqual(deployment.hexToFrontZone[HexCoord(q: 3, r: 0)], "france_front")
        XCTAssertEqual(deployment.regionToFrontZone["sedan"], "france_front")
        XCTAssertEqual(deployment.frontZones["germany_front"]?.unitsFront, ["panzer"])
        XCTAssertFalse(deployment.frontZones["france_front"]?.regionIds.isEmpty ?? false)
    }

    func testDirectiveAttackUsesDynamicHexFrontWhenRegionIsSplit() {
        let panzer = Division.infantry(
            id: "panzer",
            name: "panzer",
            faction: .germany,
            coord: HexCoord(q: 2, r: 0)
        )
        var fixture = Self.multiHexBreakthroughFixture(divisions: [panzer])
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        fixture.theaterState = TheaterSystem().expandDynamicTheater(
            state: fixture.theaterState,
            map: fixture.map,
            divisions: [panzer],
            breakthroughHex: HexCoord(q: 2, r: 0),
            advancingTheaterId: "germany_front",
            faction: .germany
        ).state
        let deployment = WarDeploymentManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [panzer],
            turn: 1
        )
        let frontLineState = FrontLineManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [panzer],
            turn: 1
        )
        let state = GameState(
            scenarioId: "v0358_split_region_attack",
            turn: 1,
            maxTurns: 2,
            activeFaction: .germany,
            phase: .germanAI,
            map: fixture.map,
            theaterState: fixture.theaterState,
            frontLineState: frontLineState,
            warDeploymentState: deployment,
            divisions: [panzer],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
        let directive = ZoneDirective(
            zoneId: "germany_front",
            type: .attack,
            parameters: .attack(
                AttackParameters(
                    targetTheaterId: "france_front",
                    weightedRegions: ["sedan"],
                    intensity: .allOut
                )
            )
        )

        let result = WarCommandExecutor().execute(directive, in: state)

        XCTAssertTrue(result.commandResults.contains { $0.succeeded })
        XCTAssertEqual(result.finalState.division(id: "panzer")?.coord, HexCoord(q: 3, r: 0))
        XCTAssertEqual(result.finalState.theaterState.dynamicTheaterId(for: HexCoord(q: 3, r: 0), map: result.finalState.map), "germany_front")
        XCTAssertEqual(result.finalState.theaterState.dynamicTheaterId(for: HexCoord(q: 4, r: 0), map: result.finalState.map), "france_front")
        XCTAssertEqual(result.finalState.theaterState.regionToTheater["sedan"], "france_front")
    }

    func testBreakthroughRegionBuildsFrontBeforeRegionControllerFlips() {
        let panzer = Division.infantry(id: "panzer", name: "panzer", faction: .germany, coord: HexCoord(q: 2, r: 0))
        var fixture = WarDeploymentTestFixtures.invasionFrance(divisions: [panzer])
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        fixture.theaterState = TheaterSystem().expandDynamicTheater(
            state: fixture.theaterState,
            map: fixture.map,
            divisions: [panzer],
            breakthroughRegionId: "sedan",
            advancingTheaterId: TheaterId(WarDeploymentTestFixtures.germanyFront.rawValue),
            faction: .germany
        ).state

        let frontLine = FrontLineManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [panzer],
            turn: 1
        )
        let deployment = WarDeploymentManager().makeInitialState(
            map: fixture.map,
            theaterState: fixture.theaterState,
            divisions: [panzer],
            turn: 1
        )

        XCTAssertEqual(fixture.map.regions["sedan"]?.controller, .allies)
        XCTAssertTrue(frontLine.frontLines.values.contains { $0.type == .breakthrough || $0.segments.contains { $0.regionA == "sedan" } })
        XCTAssertEqual(
            deployment.frontZones[WarDeploymentTestFixtures.germanyFront]?.unitsFront,
            ["panzer"]
        )
        XCTAssertEqual(
            WarDeploymentManager().deploymentRole(
                for: panzer,
                in: fixture.map,
                state: deployment
            ),
            .frontUnit
        )
    }

    func testOverlaySeparatesInitialAndDynamicTheaterBuckets() {
        var fixture = WarDeploymentTestFixtures.invasionFrance()
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        fixture.theaterState = TheaterSystem().expandDynamicTheater(
            state: fixture.theaterState,
            map: fixture.map,
            divisions: [],
            breakthroughRegionId: "sedan",
            advancingTheaterId: TheaterId(WarDeploymentTestFixtures.germanyFront.rawValue),
            faction: .germany
        ).state
        let state = GameState(
            scenarioId: "v0355_overlay",
            turn: 1,
            maxTurns: 2,
            activeFaction: .germany,
            phase: .germanAI,
            map: fixture.map,
            theaterState: fixture.theaterState,
            frontLineState: FrontLineManager().makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1),
            warDeploymentState: WarDeploymentManager().makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1),
            divisions: [],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
        let calculator = MapLayerOverlayCalculator(state: state)

        XCTAssertEqual(
            calculator.bucket(for: HexCoord(q: 2, r: 0), layer: .initialTheater).bucketId,
            WarDeploymentTestFixtures.franceFront.rawValue
        )
        XCTAssertEqual(
            calculator.bucket(for: HexCoord(q: 2, r: 0), layer: .dynamicTheater).bucketId,
            WarDeploymentTestFixtures.germanyFront.rawValue
        )
        XCTAssertFalse(calculator.frontLineSegments().isEmpty)
    }

    func testFrontLineOverlaySegmentsUseFriendlyBoundaryHexCenters() {
        var fixture = WarDeploymentTestFixtures.invasionFrance()
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        let state = GameState(
            scenarioId: "v0356_frontline_overlay",
            turn: 1,
            maxTurns: 2,
            activeFaction: .germany,
            phase: .germanAI,
            map: fixture.map,
            theaterState: fixture.theaterState,
            frontLineState: FrontLineManager().makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1),
            warDeploymentState: WarDeploymentManager().makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1),
            divisions: [],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )

        let segments = MapLayerOverlayCalculator(state: state).frontLineSegments()
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertFalse(segment.points.isEmpty)
            XCTAssertTrue(segment.points.allSatisfy { state.map.region(for: $0) == segment.regionA })
            if let enemyRepresentative = state.map.region(id: segment.regionB)?.representativeHex {
                XCTAssertFalse(segment.points.contains(enemyRepresentative))
            }
        }

        let chains = MapLayerOverlayCalculator(state: state).frontLineChains()
        XCTAssertFalse(chains.isEmpty)
        for chain in chains {
            for pair in zip(chain.points, chain.points.dropFirst()) {
                XCTAssertEqual(pair.0.distance(to: pair.1), 1, "FrontLine chain must not jump over non-adjacent hexes.")
            }
        }
    }

    func testFriendlyDynamicTheaterContactDoesNotCreateFrontLine() {
        let westHex = HexCoord(q: 0, r: 0)
        let eastHex = HexCoord(q: 1, r: 0)
        let map = MapState(
            width: 2,
            height: 1,
            tiles: [
                westHex: HexTile(coord: westHex, baseTerrain: .plain, controller: .germany, regionId: "west"),
                eastHex: HexTile(coord: eastHex, baseTerrain: .plain, controller: .germany, regionId: "east")
            ],
            supplySources: [],
            objectives: [],
            regions: [
                "west": RegionNode(
                    id: "west",
                    name: "west",
                    owner: .germany,
                    controller: .germany,
                    terrain: .plain,
                    neighbors: ["east"],
                    displayHexes: [westHex],
                    representativeHex: westHex
                ),
                "east": RegionNode(
                    id: "east",
                    name: "east",
                    owner: .germany,
                    controller: .germany,
                    terrain: .plain,
                    neighbors: ["west"],
                    displayHexes: [eastHex],
                    representativeHex: eastHex
                )
            ],
            hexToRegion: [
                westHex: "west",
                eastHex: "east"
            ],
            regionEdges: [RegionEdge(from: "west", to: "east")]
        )
        let theaterState = TheaterState(
            theaters: [
                "germany_west": TheaterNode(
                    id: "germany_west",
                    name: "germany_west",
                    status: .active,
                    regionIds: ["west"],
                    controllingFaction: .germany
                ),
                "germany_east": TheaterNode(
                    id: "germany_east",
                    name: "germany_east",
                    status: .active,
                    regionIds: ["east"],
                    controllingFaction: .germany
                )
            ],
            hexToTheater: [
                westHex: "germany_west",
                eastHex: "germany_east"
            ],
            regionToTheater: [
                "west": "germany_west",
                "east": "germany_east"
            ]
        )

        let frontLineState = FrontLineManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: [],
            turn: 1
        )

        XCTAssertTrue(frontLineState.frontLines.isEmpty)
    }

    func testFriendlyDynamicTheaterContactWithoutCachedFactionDoesNotCreateFrontLine() {
        let germanDepthHex = HexCoord(q: 0, r: 0)
        let germanFrontHex = HexCoord(q: 1, r: 0)
        let alliedFrontHex = HexCoord(q: 2, r: 0)
        let map = MapState(
            width: 3,
            height: 1,
            tiles: [
                germanDepthHex: HexTile(coord: germanDepthHex, baseTerrain: .plain, controller: .germany, regionId: "german_depth"),
                germanFrontHex: HexTile(coord: germanFrontHex, baseTerrain: .plain, controller: .germany, regionId: "german_front"),
                alliedFrontHex: HexTile(coord: alliedFrontHex, baseTerrain: .plain, controller: .allies, regionId: "allied_front")
            ],
            supplySources: [],
            objectives: [],
            regions: [
                "german_depth": RegionNode(
                    id: "german_depth",
                    name: "german_depth",
                    owner: .germany,
                    controller: .germany,
                    terrain: .plain,
                    neighbors: ["german_front"],
                    displayHexes: [germanDepthHex],
                    representativeHex: germanDepthHex
                ),
                "german_front": RegionNode(
                    id: "german_front",
                    name: "german_front",
                    owner: .germany,
                    controller: .germany,
                    terrain: .plain,
                    neighbors: ["german_depth", "allied_front"],
                    displayHexes: [germanFrontHex],
                    representativeHex: germanFrontHex
                ),
                "allied_front": RegionNode(
                    id: "allied_front",
                    name: "allied_front",
                    owner: .allies,
                    controller: .allies,
                    terrain: .plain,
                    neighbors: ["german_front"],
                    displayHexes: [alliedFrontHex],
                    representativeHex: alliedFrontHex
                )
            ],
            hexToRegion: [
                germanDepthHex: "german_depth",
                germanFrontHex: "german_front",
                alliedFrontHex: "allied_front"
            ],
            regionEdges: [
                RegionEdge(from: "german_depth", to: "german_front"),
                RegionEdge(from: "german_front", to: "allied_front")
            ]
        )
        var theaterState = TheaterState(
            theaters: [
                "germany_depth": TheaterNode(id: "germany_depth", name: "germany_depth", status: .active, regionIds: ["german_depth"], controllingFaction: .germany, frontWeight: 1),
                "germany_front": TheaterNode(id: "germany_front", name: "germany_front", status: .active, regionIds: ["german_front"], controllingFaction: .germany, frontWeight: 1),
                "allied_front": TheaterNode(id: "allied_front", name: "allied_front", status: .active, regionIds: ["allied_front"], controllingFaction: .allies, frontWeight: 1)
            ],
            hexToTheater: [
                germanDepthHex: "germany_depth",
                germanFrontHex: "germany_front",
                alliedFrontHex: "allied_front"
            ],
            regionToTheater: [
                "german_depth": "germany_depth",
                "german_front": "germany_front",
                "allied_front": "allied_front"
            ]
        )
        theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: theaterState)
        theaterState.theaters["germany_depth"]?.controllingFaction = nil
        theaterState.theaters["germany_front"]?.controllingFaction = nil
        theaterState.theaters["allied_front"]?.controllingFaction = nil

        let frontLineState = FrontLineManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: [Division.infantry(id: "ger_15", name: "ger_15", faction: .germany, coord: germanDepthHex)],
            turn: 1
        )
        let segments = frontLineState.frontLines.values.flatMap(\.segments)

        XCTAssertFalse(segments.contains { $0.regionA == "german_depth" || $0.regionB == "german_depth" })
        XCTAssertTrue(segments.contains { $0.regionA == "german_front" && $0.regionB == "allied_front" })
    }

    func testFriendlyDepthUnitDoesNotCreateDeploymentFrontSegment() {
        let germanDepthHex = HexCoord(q: 0, r: 0)
        let germanFrontHex = HexCoord(q: 1, r: 0)
        let alliedFrontHex = HexCoord(q: 2, r: 0)
        let map = MapState(
            width: 3,
            height: 1,
            tiles: [
                germanDepthHex: HexTile(coord: germanDepthHex, baseTerrain: .plain, controller: .germany, regionId: "german_depth"),
                germanFrontHex: HexTile(coord: germanFrontHex, baseTerrain: .plain, controller: .germany, regionId: "german_front"),
                alliedFrontHex: HexTile(coord: alliedFrontHex, baseTerrain: .plain, controller: .allies, regionId: "allied_front")
            ],
            supplySources: [],
            objectives: [],
            regions: [
                "german_depth": RegionNode(
                    id: "german_depth",
                    name: "german_depth",
                    owner: .germany,
                    controller: .germany,
                    terrain: .plain,
                    neighbors: ["german_front"],
                    displayHexes: [germanDepthHex],
                    representativeHex: germanDepthHex
                ),
                "german_front": RegionNode(
                    id: "german_front",
                    name: "german_front",
                    owner: .germany,
                    controller: .germany,
                    terrain: .plain,
                    neighbors: ["german_depth", "allied_front"],
                    displayHexes: [germanFrontHex],
                    representativeHex: germanFrontHex
                ),
                "allied_front": RegionNode(
                    id: "allied_front",
                    name: "allied_front",
                    owner: .allies,
                    controller: .allies,
                    terrain: .plain,
                    neighbors: ["german_front"],
                    displayHexes: [alliedFrontHex],
                    representativeHex: alliedFrontHex
                )
            ],
            hexToRegion: [
                germanDepthHex: "german_depth",
                germanFrontHex: "german_front",
                alliedFrontHex: "allied_front"
            ],
            regionEdges: [
                RegionEdge(from: "german_depth", to: "german_front"),
                RegionEdge(from: "german_front", to: "allied_front")
            ]
        )
        var theaterState = TheaterState(
            theaters: [
                "germany_depth": TheaterNode(id: "germany_depth", name: "germany_depth", status: .active, regionIds: ["german_depth"], controllingFaction: .germany),
                "germany_front": TheaterNode(id: "germany_front", name: "germany_front", status: .active, regionIds: ["german_front"], controllingFaction: .germany),
                "allied_front": TheaterNode(id: "allied_front", name: "allied_front", status: .active, regionIds: ["allied_front"], controllingFaction: .allies)
            ],
            hexToTheater: [
                germanDepthHex: "germany_depth",
                germanFrontHex: "germany_front",
                alliedFrontHex: "allied_front"
            ],
            regionToTheater: [
                "german_depth": "germany_depth",
                "german_front": "germany_front",
                "allied_front": "allied_front"
            ]
        )
        theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: theaterState)
        let rearUnit = Division.infantry(id: "ger_15", name: "ger_15", faction: .germany, coord: germanDepthHex)

        let deployment = WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: [rearUnit],
            turn: 1
        )

        XCTAssertTrue(deployment.frontZones["germany_depth"]?.frontSegments.isEmpty ?? false)
        XCTAssertFalse(deployment.frontZones["germany_depth"]?.unitsFront.contains("ger_15") ?? false)
        XCTAssertNotEqual(
            WarDeploymentManager().deploymentRole(for: rearUnit, in: map, state: deployment),
            .frontUnit
        )
    }

    func testDefaultMapGermanDivision15DoesNotStartAsFrontUnit() throws {
        let state = try DataLoader().loadGameState(
            scenarioName: MapEditorGameResourceBridge.scenarioResourceName,
            regionName: MapEditorGameResourceBridge.regionResourceName
        )
        let division = try XCTUnwrap(state.division(id: "ger_editor_15"))
        let role = WarDeploymentManager().deploymentRole(
            for: division,
            in: state.map,
            state: state.warDeploymentState
        )

        XCTAssertEqual(division.coord, HexCoord(q: 4, r: 5))
        XCTAssertNotEqual(role, .frontUnit)
    }

    func testDefaultMapFrontSegmentsOnlyTouchEnemyZonesAfterObserverSteps() async throws {
        var state = try DataLoader().loadGameState(
            scenarioName: MapEditorGameResourceBridge.scenarioResourceName,
            regionName: MapEditorGameResourceBridge.regionResourceName
        )
        state.maxTurns = max(state.maxTurns, state.turn + 6)
        state = StrategicStateBootstrapper().refreshRuntimeState(state)

        for _ in 0..<4 {
            let germanOutcome = await Self.runTestAITurn(state, faction: .germany)
            state = StrategicStateBootstrapper().refreshRuntimeState(germanOutcome)
            let alliedOutcome = await Self.runTestAITurn(state, faction: .allies)
            state = StrategicStateBootstrapper().refreshRuntimeState(alliedOutcome)
            assertFrontSegmentsOnlyTouchEnemyZones(in: state)
        }
    }

    func testFrontLineOverlayKeepsDistinctTheaterColorsForWarningLines() {
        var fixture = WarDeploymentTestFixtures.easternFront()
        fixture.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: fixture.theaterState)
        let state = GameState(
            scenarioId: "v0357_frontline_colors",
            turn: 1,
            maxTurns: 2,
            activeFaction: .germany,
            phase: .germanAI,
            map: fixture.map,
            theaterState: fixture.theaterState,
            frontLineState: FrontLineManager().makeInitialState(map: fixture.map, theaterState: fixture.theaterState, divisions: [], turn: 1),
            warDeploymentState: fixture.state,
            divisions: [],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )

        let node = MapLayerOverlayNode(
            state: state,
            layer: .frontLine,
            layout: HexLayout(hexSize: 32, origin: .zero)
        )
        let lineColorKeys = Set(
            node.children
                .compactMap { $0 as? SKShapeNode }
                .filter { $0.zPosition == 12 }
                .compactMap { Self.colorKey($0.strokeColor) }
        )

        XCTAssertGreaterThanOrEqual(lineColorKeys.count, 2, "FrontLine overlay should keep per-theater colors instead of collapsing every line to warning red.")
    }

    private static func twoRegionState(activeFaction: Faction, mover: Division) -> GameState {
        let fixture = WarDeploymentTestFixtures.state(
            specs: [
                .init(id: "allied", faction: .allies, zone: "allied_zone", neighbors: ["german"]),
                .init(id: "german", faction: .germany, zone: "german_zone", neighbors: ["allied"])
            ],
            divisions: [mover]
        )
        var theaterState = fixture.theaterState
        theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: theaterState)
        return GameState(
            scenarioId: "v0355_occupation",
            turn: 1,
            maxTurns: 2,
            activeFaction: activeFaction,
            phase: activeFaction == .allies ? .alliedPlayer : .germanAI,
            map: fixture.map,
            theaterState: theaterState,
            frontLineState: FrontLineManager().makeInitialState(map: fixture.map, theaterState: theaterState, divisions: [mover], turn: 1),
            warDeploymentState: WarDeploymentManager().makeInitialState(map: fixture.map, theaterState: theaterState, divisions: [mover], turn: 1),
            divisions: [mover],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }

    private static func runTestAITurn(_ state: GameState, faction: Faction) async -> GameState {
        let assignedIds = state.divisions
            .filter { $0.faction == faction && !$0.isDestroyed }
            .map(\.id)
        let agent = GameAgent.sample(
            id: "test_\(faction.rawValue)_commander",
            name: "Test \(faction.displayName) Commander",
            faction: faction,
            role: .armyCommander,
            assignedDivisionIds: assignedIds
        )
        let commanders: [any ZoneCommanderProviding] = state.warDeploymentState.frontZones.values
            .filter { $0.faction == faction }
            .map { zone in
                ZoneCommanderAgent(
                    config: ZoneCommanderAgentConfig(
                        id: "test_\(zone.id.rawValue)",
                        name: zone.name,
                        faction: faction,
                        assignedZoneId: zone.id,
                        skills: [],
                        commandStyle: faction == .germany ? .aggressive : .balanced
                    )
                )
            }
        let manager = TurnManager(
            agent: agent,
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: RuleEngine(),
            commanderPool: TheaterCommanderPool(commanders: commanders)
        )
        var prepared = state
        prepared.activeFaction = faction
        prepared.phase = faction == .germany ? .germanAI : .alliedPlayer
        return await manager.runAITurn(
            state: prepared,
            faction: faction,
            pipelineMode: .zoneDirective
        ).state
    }

    private func assertFrontSegmentsOnlyTouchEnemyZones(in state: GameState, file: StaticString = #filePath, line: UInt = #line) {
        for zone in state.warDeploymentState.frontZones.values {
            for segment in zone.frontSegments {
                guard let enemyZone = state.warDeploymentState.frontZones[segment.neighborEnemyZone] else {
                    XCTFail("Missing neighbor zone \(segment.neighborEnemyZone.rawValue)", file: file, line: line)
                    continue
                }
                XCTAssertNotEqual(
                    zone.faction,
                    enemyZone.faction,
                    "Front segment \(segment.regionId.rawValue) links same-faction zones \(zone.id.rawValue) and \(enemyZone.id.rawValue).",
                    file: file,
                    line: line
                )
            }
        }
    }

    private static func multiHexBreakthroughFixture(
        divisions: [Division] = []
    ) -> (map: MapState, theaterState: TheaterState) {
        let ardennesHexes = [HexCoord(q: 0, r: 0), HexCoord(q: 1, r: 0)]
        let sedanHexes = [HexCoord(q: 2, r: 0), HexCoord(q: 3, r: 0), HexCoord(q: 4, r: 0)]
        var regions: [RegionId: RegionNode] = [
            "ardennes": RegionNode(
                id: "ardennes",
                name: "ardennes",
                owner: .germany,
                controller: .germany,
                terrain: .plain,
                neighbors: ["sedan"],
                displayHexes: ardennesHexes,
                representativeHex: ardennesHexes[0]
            ),
            "sedan": RegionNode(
                id: "sedan",
                name: "sedan",
                owner: .allies,
                controller: .allies,
                terrain: .plain,
                neighbors: ["ardennes"],
                displayHexes: sedanHexes,
                representativeHex: sedanHexes[0]
            )
        ]
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        for hex in ardennesHexes {
            tiles[hex] = HexTile(coord: hex, baseTerrain: .plain, controller: .germany, regionId: "ardennes")
            hexToRegion[hex] = "ardennes"
        }
        for hex in sedanHexes {
            tiles[hex] = HexTile(coord: hex, baseTerrain: .plain, controller: .allies, regionId: "sedan")
            hexToRegion[hex] = "sedan"
        }

        let map = MapState(
            width: 5,
            height: 1,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: [RegionEdge(from: "ardennes", to: "sedan")]
        )
        var theaterState = TheaterState(
            theaters: [
                "germany_front": TheaterNode(
                    id: "germany_front",
                    name: "germany_front",
                    status: .active,
                    regionIds: ["ardennes"],
                    controllingFaction: .germany
                ),
                "france_front": TheaterNode(
                    id: "france_front",
                    name: "france_front",
                    status: .active,
                    regionIds: ["sedan"],
                    controllingFaction: .allies
                )
            ],
            hexToTheater: [
                HexCoord(q: 0, r: 0): "germany_front",
                HexCoord(q: 1, r: 0): "germany_front",
                HexCoord(q: 2, r: 0): "france_front",
                HexCoord(q: 3, r: 0): "france_front",
                HexCoord(q: 4, r: 0): "france_front"
            ],
            regionToTheater: [
                "ardennes": "germany_front",
                "sedan": "france_front"
            ]
        )
        theaterState = TheaterSystem().updateTheaters(
            state: theaterState,
            map: map,
            divisions: divisions,
            turn: 1,
            force: true
        )
        return (map, theaterState)
    }

    private static func colorKey(_ color: SKColor) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return "\(Int(red * 255))-\(Int(green * 255))-\(Int(blue * 255))-\(Int(alpha * 255))"
    }
}
