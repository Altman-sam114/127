import XCTest
@testable import WWIIHexV0

final class WWIIHexV0ProbeTests: XCTestCase {
    func testProbeDataBootRegionGraphAndStrategicLayers() {
        let state = DataLoader().loadInitialGameState()

        XCTAssertEqual(state.scenarioId, "mapeditor_scenario")
        XCTAssertTrue(state.map.validateRegionGraph().isEmpty)
        XCTAssertFalse(state.map.regions.isEmpty)
        XCTAssertEqual(Set(state.theaterState.theaters.keys.map(\.rawValue)), Set(["theater_1", "theater_2", "theater_3", "theater_4"]))
        XCTAssertFalse(state.frontLineState.frontLines.isEmpty)
        XCTAssertFalse(state.warDeploymentState.frontZones.isEmpty)
        XCTAssertLessThanOrEqual(
            state.warDeploymentState.diagnostics.scannedRegionCount,
            state.map.regions.count
        )
    }

    func testProbeHexRegionDisplayMapping() throws {
        let scenario = Self.westFrontScenario()
        let adapter = MapDisplayAdapter(state: scenario.gameState)
        let regionId = try XCTUnwrap(adapter.regionId(for: HexCoord(q: 2, r: 1)))
        let representative = try XCTUnwrap(adapter.representativeHex(for: regionId))

        XCTAssertEqual(regionId, "ardennes")
        XCTAssertTrue(adapter.displayHexes(for: regionId).contains(representative))
        XCTAssertEqual(adapter.hexDisplayState(for: HexCoord(q: 2, r: 1), viewerFaction: .germany)?.controller, .germany)
    }

    func testProbeRegionCommandBridgeAndRuleEngineExecution() throws {
        let state = Self.commandBridgeState(activeFaction: .germany)

        let move = RegionCommand.move(divisionId: "probe_move", from: "rhein", to: "ardennes")
        let moveCommand = try CommandIntentAdapter().makeHexCommand(from: move, in: state)
        let moveResult = RuleEngine().execute(moveCommand, in: state)

        XCTAssertTrue(moveResult.succeeded, moveResult.message)
        XCTAssertEqual(moveResult.state.division(id: "probe_move")?.location(in: moveResult.state.map), "ardennes")

        let attack = RegionCommand.attack(
            attackerId: "probe_attack",
            from: "ardennes",
            targetDivisionId: "probe_defender",
            targetRegionId: "sedan"
        )
        let attackCommand = try CommandIntentAdapter().makeHexCommand(from: attack, in: state)
        let attackResult = RuleEngine().execute(attackCommand, in: state)

        XCTAssertTrue(attackResult.succeeded, attackResult.message)
        XCTAssertLessThan(attackResult.state.division(id: "probe_defender")?.strength ?? 10, 10)
    }

    func testProbeTheaterFrontLineDeploymentChain() {
        let scenario = Self.westFrontScenario()
        let frontZone = scenario.gameState.warDeploymentState.frontZones[Self.germanFront]

        XCTAssertEqual(scenario.theaterState.regionToTheater["ardennes"], TheaterId(Self.germanFront.rawValue))
        XCTAssertTrue(
            scenario.frontLineState.frontLines.values.contains {
                $0.segments.contains { $0.regionA == "ardennes" && $0.regionB == "sedan" }
            }
        )
        XCTAssertEqual(frontZone?.frontSegments.map(\.regionId), ["ardennes"])
        XCTAssertEqual(frontZone?.unitsFront, ["front_panzer"])
        XCTAssertEqual(scenario.gameState.warDeploymentState.frontZones[Self.germanDepth]?.unitsDepth, ["depth_motorized"])
        XCTAssertEqual(scenario.gameState.warDeploymentState.frontZones[Self.germanCore]?.unitsGarrison, ["berlin_guard"])
    }

    func testProbeAdvanceUpdatesFrontAndDeploymentIncrementally() {
        var scenario = Self.westFrontScenario()
        let breakthroughHex = HexCoord(q: 3, r: 0)
        scenario.map.regions["sedan"]?.controller = .germany
        scenario.map.tiles[breakthroughHex]?.controller = .germany
        scenario.theaterState = TheaterSystem().expandDynamicTheater(
            state: scenario.theaterState,
            map: scenario.map,
            divisions: scenario.divisions,
            breakthroughHex: breakthroughHex,
            advancingTheaterId: TheaterId(Self.germanFront.rawValue),
            faction: .germany
        ).state

        let frontLineState = FrontLineManager().update(
            state: scenario.frontLineState,
            map: scenario.map,
            theaterState: scenario.theaterState,
            divisions: scenario.divisions,
            turn: 2,
            events: [.regionControllerChanged("sedan"), .theaterAssignmentChanged("sedan")]
        )
        let deployment = WarDeploymentManager().advanceHex(
            breakthroughHex,
            from: Self.frenchFront,
            to: Self.germanFront,
            state: scenario.gameState.warDeploymentState,
            map: scenario.map,
            divisions: scenario.divisions,
            turn: 2
        )

        XCTAssertEqual(scenario.theaterState.regionToTheater["sedan"], TheaterId(Self.frenchFront.rawValue))
        XCTAssertEqual(scenario.theaterState.hexToTheater[breakthroughHex], TheaterId(Self.germanFront.rawValue))
        XCTAssertEqual(deployment.hexToFrontZone[breakthroughHex], Self.germanFront)
        XCTAssertEqual(deployment.regionToFrontZone["sedan"], Self.germanFront)
        XCTAssertTrue(deployment.frontZones[Self.germanFront]?.frontSegments.map(\.regionId).contains("sedan") ?? false)
        XCTAssertLessThan(deployment.diagnostics.scannedRegionCount, scenario.map.regions.count)
        XCTAssertTrue(
            frontLineState.frontLines.values.contains {
                $0.segments.contains { $0.regionA == "sedan" && $0.regionB == "paris" }
            }
        )
    }

    func testProbeMockAIReadsDeploymentAndExecutesOrders() async throws {
        let scenario = Self.westFrontScenario()
        let agent = GameAgent.guderianFallback(
            assignedDivisionIds: ["front_panzer", "depth_motorized", "berlin_guard"]
        )
        let context = AgentContextBuilder().agentContext(
            for: agent,
            state: scenario.gameState,
            playerDirective: "Probe front deployment."
        )

        let envelope = try await MockAIClient().decide(context: context)
        XCTAssertEqual(envelope.schemaVersion, 2)
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "front_panzer" }?.type, .attack)
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "depth_motorized" }?.toRegionId, "ardennes")
        XCTAssertEqual(envelope.orders.first { $0.divisionId == "berlin_guard" }?.type, .hold)

        var nextState = scenario.gameState
        for order in envelope.orders {
            let issued = try AgentCommandMapper().map(order, agentId: envelope.agentId, state: nextState)
            let result = RuleEngine().execute(issued.command, in: nextState)
            XCTAssertTrue(result.succeeded, result.message)
            nextState = result.state
        }

        XCTAssertEqual(nextState.division(id: "depth_motorized")?.location(in: nextState.map), "ardennes")
        XCTAssertEqual(nextState.division(id: "berlin_guard")?.location(in: nextState.map), "berlin")
        XCTAssertLessThan(nextState.division(id: "allied_defender")?.strength ?? 10, 10)
    }

    func testProbeV0351DirectiveMockAIAndExecutorChain() throws {
        var scenario = Self.westFrontScenario()
        let extraDivisions = [
            Self.division(id: "front_infantry_2", faction: .germany, coord: HexCoord(q: 2, r: 0), type: .infantry),
            Self.division(id: "front_infantry_3", faction: .germany, coord: HexCoord(q: 1, r: 1), type: .infantry)
        ]
        scenario.divisions.append(contentsOf: extraDivisions)
        scenario.gameState.divisions = scenario.divisions
        scenario.gameState.warDeploymentState = WarDeploymentManager().makeInitialState(
            map: scenario.map,
            theaterState: scenario.theaterState,
            divisions: scenario.divisions,
            turn: 1
        )

        let json = """
        {"zoneId":"german_front","type":"attack","parameters":{"targetTheaterId":"french_front","weightedRegions":["sedan"],"intensity":"allOut"}}
        """
        let decoded = try JSONDecoder().decode(ZoneDirective.self, from: Data(json.utf8))
        let directive = try XCTUnwrap(
            MockAICommander().directive(for: Self.germanFront, in: scenario.gameState)
        )
        let result = WarCommandExecutor().execute(decoded, in: scenario.gameState)

        XCTAssertEqual(directive.type, .attack)
        XCTAssertTrue(result.generatedCommands.contains { command in
            if case .attack = command {
                return true
            }
            return false
        })
        XCTAssertLessThan(result.finalState.division(id: "allied_defender")?.strength ?? 10, 10)
    }

    func testProbeV0352BootstrapAndZoneDirectivePipelineNoFallback() async throws {
        let scenario = Self.westFrontScenario()
        var incompleteState = scenario.gameState
        incompleteState.frontLineState = .empty
        incompleteState.warDeploymentState = .empty
        incompleteState.eventLog = []

        let bootstrapped = StrategicStateBootstrapper().bootstrapIfNeeded(incompleteState)
        XCTAssertFalse(bootstrapped.theaterState.theaters.isEmpty)
        XCTAssertFalse(bootstrapped.frontLineState.frontLines.isEmpty)
        XCTAssertFalse(bootstrapped.warDeploymentState.frontZones.isEmpty)
        XCTAssertTrue(bootstrapped.eventLog.contains { $0.category == .frontChange })

        let manager = TurnManager(
            agent: GameAgent.guderianFallback(
                assignedDivisionIds: bootstrapped.divisions
                    .filter { $0.faction == .germany && !$0.isDestroyed }
                    .map(\.id)
            ),
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: RuleEngine(),
            commanderPool: TheaterCommanderPool.automatic(for: bootstrapped)
        )
        let outcome = await manager.runAITurn(
            state: bootstrapped,
            faction: .germany,
            pipelineMode: .zoneDirective
        )

        XCTAssertEqual(outcome.record.parsedIntent, "v0.352 zone directives")
        XCTAssertFalse(outcome.directiveRecords.isEmpty)
        XCTAssertTrue(outcome.record.rawJSON?.contains("\"orders\"") == false)
        XCTAssertTrue(outcome.record.commandResults.contains { summary in
            summary.executed && summary.commandDisplayName?.contains("Attack") == true
        })
    }

    func testProbeV0352StrategicOverlayBuckets() throws {
        let state = Self.westFrontScenario().gameState
        let calculator = MapLayerOverlayCalculator(state: state)
        let frontBucket = calculator.bucket(for: HexCoord(q: 2, r: 0), layer: .frontLine)

        XCTAssertEqual(
            calculator.bucket(for: HexCoord(q: 2, r: 0), layer: .province).bucketId,
            "ardennes"
        )
        XCTAssertEqual(
            calculator.bucket(for: HexCoord(q: 2, r: 0), layer: .dynamicTheater).bucketId,
            Self.germanFront.rawValue
        )
        XCTAssertNotNil(frontBucket.bucketId)
        XCTAssertGreaterThan(frontBucket.pressure, 0)
        XCTAssertNil(calculator.bucket(for: HexCoord(q: 0, r: 0), layer: .frontLine).bucketId)
    }

    func testProbeV036DirectiveRoundTrip() throws {
        let directive = ZoneDirective(
            zoneId: Self.germanFront,
            attack: AttackParameters(
                targetTheaterId: TheaterId(Self.frenchFront.rawValue),
                weightedRegions: ["sedan"],
                intensity: .limitedCounter
            ),
            category: .offense,
            tactic: .standardAttack,
            commandTarget: .theater(TheaterId(Self.frenchFront.rawValue))
        )

        let data = try JSONEncoder().encode(directive)
        let decoded = try JSONDecoder().decode(ZoneDirective.self, from: data)

        XCTAssertEqual(decoded.category, .offense)
        XCTAssertEqual(decoded.tactic, .standardAttack)
        XCTAssertEqual(decoded.commandTarget, .theater(TheaterId(Self.frenchFront.rawValue)))
    }

    func testProbeV036ClassifierAttack() {
        let classification = BinaryTacticClassifier().classify(
            friendlyStrength: 100,
            visibleEnemyStrength: 50,
            hasContestedForwardPresence: false,
            hasStaticDefense: false,
            config: Self.commanderConfig(zoneId: Self.germanFront, faction: .germany)
        )

        XCTAssertEqual(classification.category, .offense)
        XCTAssertEqual(classification.tactic, .standardAttack)
    }

    func testProbeV036ClassifierDefend() {
        let classification = BinaryTacticClassifier().classify(
            friendlyStrength: 30,
            visibleEnemyStrength: 100,
            hasContestedForwardPresence: false,
            hasStaticDefense: false,
            config: Self.commanderConfig(zoneId: Self.germanFront, faction: .germany)
        )

        XCTAssertEqual(classification.category, .defense)
        XCTAssertEqual(classification.tactic, .holdPosition)
    }

    func testProbeV036SingleZoneCommanderOutputsDirective() throws {
        let scenario = Self.westFrontScenario()
        let zone = try XCTUnwrap(scenario.gameState.warDeploymentState.frontZones[Self.germanFront])
        let directive = try XCTUnwrap(
            ZoneCommanderAgent(
                config: Self.commanderConfig(zoneId: Self.germanFront, faction: .germany)
            ).makeDirective(for: zone, in: scenario.gameState)
        )

        XCTAssertEqual(directive.category, .offense)
        XCTAssertEqual(directive.tactic, .standardAttack)
        XCTAssertNotNil(directive.commandTarget)
    }

    func testProbeV036TheaterPoolGeneratesForAllZones() {
        let state = Self.westFrontScenario().gameState
        let expectedCount = state.warDeploymentState.frontZones.values
            .filter { $0.faction == .germany && !$0.frontSegments.isEmpty }
            .count
        let envelope = TheaterCommanderPool.automatic(for: state).envelope(for: .germany, in: state)

        XCTAssertEqual(envelope.directives.count, expectedCount)
        XCTAssertTrue(envelope.directives.allSatisfy { $0.tactic != nil })
    }

    func testProbeV036ExecutorHandlesTacticDirective() {
        let state = Self.westFrontScenario().gameState
        let directive = ZoneDirective(
            zoneId: Self.germanFront,
            attack: AttackParameters(
                targetTheaterId: TheaterId(Self.frenchFront.rawValue),
                weightedRegions: ["sedan"],
                intensity: .limitedCounter
            ),
            category: .offense,
            tactic: .standardAttack,
            commandTarget: .theater(TheaterId(Self.frenchFront.rawValue))
        )

        let result = WarCommandExecutor().execute(directive, in: state)

        XCTAssertFalse(result.generatedCommands.isEmpty)
    }

    func testProbeV037ManualDirectiveExecutesWithoutCommanderIssuer() {
        let state = Self.westFrontScenario().gameState
        let manualDirective = ZoneDirective(
            zoneId: Self.germanFront,
            attack: AttackParameters(
                targetTheaterId: TheaterId(Self.frenchFront.rawValue),
                weightedRegions: ["sedan"],
                intensity: .limitedCounter
            ),
            category: .offense,
            tactic: .standardAttack,
            commandTarget: .theater(TheaterId(Self.frenchFront.rawValue))
        )

        let result = WarCommandExecutor(commandHandler: RuleEngine()).execute(manualDirective, in: state)

        XCTAssertFalse(result.generatedCommands.isEmpty)
        XCTAssertTrue(result.commandResults.contains { $0.succeeded })
    }

    func testProbeV036DirectiveRecordContainsTactic() async {
        let scenario = Self.westFrontScenario()
        let manager = TurnManager(
            agent: GameAgent.guderianFallback(assignedDivisionIds: ["front_panzer", "depth_motorized", "berlin_guard"]),
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: RuleEngine(),
            commanderPool: TheaterCommanderPool.automatic(for: scenario.gameState)
        )

        let outcome = await manager.runAITurn(
            state: scenario.gameState,
            faction: .germany,
            pipelineMode: .zoneDirective
        )

        XCTAssertTrue(outcome.state.warDirectiveRecords.contains { $0.tactic != nil })
    }

    func testProbeV036NewDynamicZoneGetsFallbackCommander() {
        var scenario = Self.westFrontScenario()
        let pool = TheaterCommanderPool.automatic(for: scenario.gameState)
        let newZoneId = FrontZoneId("dynamic_probe_zone")
        scenario.gameState.warDeploymentState.frontZones[newZoneId] = FrontZone(
            id: newZoneId,
            name: "Dynamic Probe Zone",
            faction: .germany,
            regionIds: ["ardennes"],
            neighbors: [Self.frenchFront],
            frontSegments: [
                FrontZoneSegment(regionId: "ardennes", neighborEnemyZone: Self.frenchFront, assignedFrontUnitIds: ["front_panzer"])
            ],
            unitsFront: ["front_panzer"]
        )

        let envelope = pool.envelope(for: .germany, in: scenario.gameState)

        XCTAssertTrue(envelope.directives.contains { $0.zoneId == newZoneId && $0.tactic != nil })
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
            division(id: "front_panzer", faction: .germany, coord: HexCoord(q: 2, r: 1), type: .tank),
            division(id: "depth_motorized", faction: .germany, coord: HexCoord(q: 1, r: 0), type: .motorizedInfantry),
            division(id: "berlin_guard", faction: .germany, coord: HexCoord(q: 0, r: 0), type: .infantry),
            division(id: "allied_defender", faction: .allies, coord: HexCoord(q: 3, r: 0), type: .infantry)
        ]
        let map = westFrontMap()
        let theaterState = westFrontTheaters()
        let deployment = WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: 1
        )
        let frontLineState = FrontLineManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: 1
        )
        let gameState = GameState(
            scenarioId: "probe_west_front",
            turn: 1,
            maxTurns: 8,
            activeFaction: .germany,
            phase: .germanAI,
            map: map,
            theaterState: theaterState,
            frontLineState: frontLineState,
            warDeploymentState: deployment,
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )

        return WarScenario(
            map: map,
            theaterState: theaterState,
            frontLineState: frontLineState,
            divisions: divisions,
            gameState: gameState
        )
    }

    private static func commandBridgeState(activeFaction: Faction) -> GameState {
        GameState(
            scenarioId: "probe_command_bridge",
            turn: 1,
            maxTurns: 8,
            activeFaction: activeFaction,
            phase: .germanAI,
            map: westFrontMap(),
            divisions: [
                division(id: "probe_move", faction: .germany, coord: HexCoord(q: 1, r: 0), type: .infantry),
                division(id: "probe_attack", faction: .germany, coord: HexCoord(q: 2, r: 1), type: .tank),
                division(id: "probe_defender", faction: .allies, coord: HexCoord(q: 3, r: 0), type: .infantry)
            ],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }

    private static func westFrontMap() -> MapState {
        let specs: [(RegionId, Faction, FrontZoneId, [RegionId], [HexCoord], Bool, Int)] = [
            ("berlin", .germany, germanCore, ["rhein"], [HexCoord(q: 0, r: 0)], true, 3),
            ("rhein", .germany, germanDepth, ["berlin", "ardennes"], [HexCoord(q: 1, r: 0)], false, 0),
            ("ardennes", .germany, germanFront, ["rhein", "sedan"], [HexCoord(q: 2, r: 0), HexCoord(q: 2, r: 1)], false, 0),
            ("sedan", .allies, frenchFront, ["ardennes", "paris"], [HexCoord(q: 3, r: 0)], false, 0),
            ("paris", .allies, frenchFront, ["sedan"], [HexCoord(q: 4, r: 0)], true, 4)
        ]
        var regions: [RegionId: RegionNode] = [:]
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        var edges: Set<RegionEdge> = []

        for (regionId, faction, _, neighbors, hexes, city, factories) in specs {
            regions[regionId] = RegionNode(
                id: regionId,
                name: regionId.rawValue,
                owner: faction,
                controller: faction,
                terrain: .plain,
                neighbors: neighbors,
                displayHexes: hexes,
                representativeHex: hexes[0],
                city: city ? CityInfo(name: regionId.rawValue, victoryPoints: 1) : nil,
                supplyValue: city ? 1 : 0,
                factories: factories,
                coreOf: city || factories > 0 ? [faction] : []
            )
            for hex in hexes {
                tiles[hex] = HexTile(coord: hex, baseTerrain: .plain, controller: faction, regionId: regionId)
                hexToRegion[hex] = regionId
            }
            edges.formUnion(neighbors.map { RegionEdge(from: regionId, to: $0) })
        }

        return MapState(
            width: 5,
            height: 2,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: edges
        )
    }

    private static func westFrontTheaters() -> TheaterState {
        let theaters: [TheaterId: TheaterNode] = [
            TheaterId(germanCore.rawValue): TheaterNode(
                id: TheaterId(germanCore.rawValue),
                name: germanCore.rawValue,
                status: .active,
                regionIds: ["berlin"],
                controllingFaction: .germany,
                frontWeight: 1
            ),
            TheaterId(germanDepth.rawValue): TheaterNode(
                id: TheaterId(germanDepth.rawValue),
                name: germanDepth.rawValue,
                status: .active,
                regionIds: ["rhein"],
                controllingFaction: .germany,
                frontWeight: 1
            ),
            TheaterId(germanFront.rawValue): TheaterNode(
                id: TheaterId(germanFront.rawValue),
                name: germanFront.rawValue,
                status: .active,
                regionIds: ["ardennes"],
                controllingFaction: .germany,
                frontWeight: 1
            ),
            TheaterId(frenchFront.rawValue): TheaterNode(
                id: TheaterId(frenchFront.rawValue),
                name: frenchFront.rawValue,
                status: .active,
                regionIds: ["sedan", "paris"],
                controllingFaction: .allies,
                frontWeight: 2
            )
        ]
        return TheaterState(
            theaters: theaters,
            regionToTheater: [
                "berlin": TheaterId(germanCore.rawValue),
                "rhein": TheaterId(germanDepth.rawValue),
                "ardennes": TheaterId(germanFront.rawValue),
                "sedan": TheaterId(frenchFront.rawValue),
                "paris": TheaterId(frenchFront.rawValue)
            ]
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

    private static func commanderConfig(zoneId: FrontZoneId, faction: Faction) -> ZoneCommanderAgentConfig {
        ZoneCommanderAgentConfig(
            id: "probe_\(zoneId.rawValue)",
            name: "Probe Commander",
            faction: faction,
            assignedZoneId: zoneId,
            skills: [],
            commandStyle: .balanced
        )
    }
}
