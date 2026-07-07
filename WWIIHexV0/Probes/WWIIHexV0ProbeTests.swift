import XCTest
@testable import WWIIHexV0

final class WWIIHexV0ProbeTests: XCTestCase {
    func testProbeDataBootRegionGraphAndStrategicLayers() {
        let state = DataLoader().loadInitialGameState()

        XCTAssertEqual(state.scenarioId, "grey_tide_2030")
        XCTAssertTrue(state.map.validateRegionGraph().isEmpty)
        XCTAssertFalse(state.map.regions.isEmpty)
        XCTAssertTrue(state.theaterState.theaters.keys.map(\.rawValue).contains("blue_littoral_sector"))
        XCTAssertTrue(state.theaterState.theaters.keys.map(\.rawValue).contains("red_littoral_sector"))
        XCTAssertTrue(state.theaterState.theaters.keys.map(\.rawValue).contains("central_crossing"))
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
        XCTAssertNotNil(envelope.orders.first { $0.divisionId == "front_panzer" })
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
        XCTAssertGreaterThanOrEqual(envelope.orders.count, 3)
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
        XCTAssertFalse(result.generatedCommands.isEmpty)
        XCTAssertTrue(result.commandResults.contains { $0.succeeded })
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

        XCTAssertEqual(outcome.record.parsedIntent, "zone directives")
        XCTAssertFalse(outcome.directiveRecords.isEmpty)
        XCTAssertTrue(outcome.record.rawJSON?.contains("\"orders\"") == false)
        XCTAssertTrue(outcome.record.commandResults.contains { $0.executed })
    }

    func testProbeGreyTideObserverTenAIHalfTurns() async throws {
        let bootstrapper = StrategicStateBootstrapper()
        var state = bootstrapper.bootstrapIfNeeded(DataLoader().loadInitialGameState())
        let initialTurn = state.turn

        XCTAssertEqual(state.scenarioId, "grey_tide_2030")

        for step in 0..<10 {
            state = bootstrapper.refreshRuntimeState(state)
            let activeFaction = state.activeFaction

            XCTAssertEqual(state.phase, activeFaction.commandPhase, "step \(step) active phase mismatch")
            XCTAssertTrue(activeFaction.alignment == .blue || activeFaction.alignment == .red, "step \(step) unexpected active faction")

            let outcome = await Self.greyTideProbeTurnManager(for: activeFaction, state: state)
                .runAITurn(state: state, faction: activeFaction, pipelineMode: .marshalDirective)

            XCTAssertTrue(
                outcome.record.commandResults.contains { $0.id == "end_turn" && $0.executed },
                "step \(step) did not execute end turn: \(outcome.record.errors.joined(separator: "; "))"
            )
            XCTAssertFalse(
                outcome.record.errors.contains { $0.localizedCaseInsensitiveContains("outside its controllable phase") },
                "step \(step) ran outside controllable phase"
            )
            state = bootstrapper.refreshRuntimeState(outcome.state)
        }

        XCTAssertEqual(state.turn, initialTurn + 5)
        XCTAssertTrue(state.map.validateRegionGraph().isEmpty)
        XCTAssertFalse(state.warDeploymentState.frontZones.isEmpty)
        XCTAssertFalse(state.theaterState.theaters.isEmpty)
        XCTAssertFalse(state.operationalAwareness.sensorCoverage.isEmpty)
    }

    func testProbePlaytestSideSelectionActionGateAndSnapshot() {
        let dataLoader = DataLoader()
        let container = AppContainer(
            gameState: dataLoader.loadInitialGameState(),
            commandHandler: RuleEngine(),
            dataLoader: dataLoader,
            generalRegistry: (try? dataLoader.loadGeneralRegistry()) ?? .empty,
            playerFaction: .blueForce
        )
        container.clearLocalSnapshot()

        container.resetGame(playerFaction: .blueForce)

        XCTAssertEqual(container.gameState.scenarioId, "grey_tide_2030")
        XCTAssertEqual(container.playerFaction, .blueForce)
        XCTAssertEqual(container.nextOperationPlayerFaction, .blueForce)
        XCTAssertEqual(container.gameState.activeFaction, .blueForce)
        XCTAssertEqual(container.gameState.phase, .alliedPlayer)
        XCTAssertEqual(container.playtestControlModeSummary, "Manual Blue Force command")
        XCTAssertEqual(container.playtestActionGateDetail, "Blue Force orders open")
        let blueControl = VictoryRules.greyTideObjectiveControlCounts(in: container.gameState)
        let blueRemaining = max(0, 7 - blueControl.blue)
        XCTAssertEqual(
            container.playtestObjectiveSummaryText,
            "Blue \(blueControl.blue)/\(blueControl.total), Red \(blueControl.red), Neutral \(blueControl.neutral)"
        )
        XCTAssertTrue(container.playtestObjectiveThresholdText?.contains("Secure \(blueRemaining) more objective") == true)
        XCTAssertEqual(container.lastCommandFeedbackTone, .success)

        container.saveLocalSnapshot()
        XCTAssertTrue(container.localSnapshotSummary?.contains("player Blue Force") == true)

        container.resetGame(playerFaction: .redForce)

        XCTAssertEqual(container.playerFaction, .redForce)
        XCTAssertEqual(container.nextOperationPlayerFaction, .redForce)
        XCTAssertEqual(container.gameState.activeFaction, .redForce)
        XCTAssertEqual(container.gameState.phase, .germanAI)
        XCTAssertEqual(container.playtestControlModeSummary, "Manual Red Force command")
        XCTAssertEqual(container.playtestActionGateDetail, "Red Force orders open")
        let redControl = VictoryRules.greyTideObjectiveControlCounts(in: container.gameState)
        let redRemaining = max(0, 7 - redControl.blue)
        XCTAssertEqual(
            container.playtestObjectiveSummaryText,
            "Blue \(redControl.blue)/\(redControl.total), Red \(redControl.red), Neutral \(redControl.neutral)"
        )
        XCTAssertTrue(container.playtestObjectiveThresholdText?.contains("Deny Blue \(redRemaining) more objectives") == true)

        container.saveLocalSnapshot()
        XCTAssertTrue(container.localSnapshotSummary?.contains("player Red Force") == true)

        container.resetGame(playerFaction: .blueForce)
        XCTAssertEqual(container.playerFaction, .blueForce)

        container.loadLocalSnapshot()

        XCTAssertEqual(container.playerFaction, .redForce)
        XCTAssertEqual(container.nextOperationPlayerFaction, .redForce)
        XCTAssertEqual(container.gameState.activeFaction, .redForce)
        XCTAssertEqual(container.gameState.phase, .germanAI)
        XCTAssertEqual(container.lastCommandFeedbackTone, .success)
        XCTAssertTrue(container.lastCommandMessage?.contains("Local snapshot loaded") == true)

        container.clearLocalSnapshot()
    }

    func testProbeNeutralMainObjectiveOccupationUpdatesVictorySummaryAndImmediateVictory() throws {
        let dataLoader = DataLoader()
        var state = StrategicStateBootstrapper().bootstrapIfNeeded(dataLoader.loadInitialGameState())
        state.activeFaction = .blueForce
        state.phase = .alliedPlayer
        state.victoryState = .ongoing

        let targetObjective = try XCTUnwrap(
            state.map.objectives.first { objective in
                guard VictoryRules.greyTideMainObjectiveIds.contains(objective.id),
                      state.map.tile(at: objective.coord)?.controller?.alignment == .neutral,
                      state.division(at: objective.coord) == nil else {
                    return false
                }

                return objective.coord.neighbors.contains { neighbor in
                    guard let tile = state.map.tile(at: neighbor) else {
                        return false
                    }
                    return tile.isPassable && state.division(at: neighbor) == nil
                }
            }
        )
        let destination = targetObjective.coord
        let stagingHex = try XCTUnwrap(
            destination.neighbors.first { neighbor in
                guard let tile = state.map.tile(at: neighbor) else {
                    return false
                }
                return tile.isPassable && state.division(at: neighbor) == nil
            }
        )

        let initialControl = VictoryRules.greyTideObjectiveControlCounts(in: state)
        XCTAssertGreaterThan(initialControl.neutral, 0)
        XCTAssertLessThan(initialControl.blue, 7)

        var presetBlueObjectives = initialControl.blue
        for objective in state.map.objectives
            where VictoryRules.greyTideMainObjectiveIds.contains(objective.id)
                && objective.id != targetObjective.id
                && presetBlueObjectives < 6 {
            guard var tile = state.map.tile(at: objective.coord),
                  tile.controller?.alignment != .blue else {
                continue
            }
            tile.controller = .blueForce
            state.map.setTile(tile)
            presetBlueObjectives += 1
        }

        XCTAssertEqual(VictoryRules.greyTideObjectiveControlCounts(in: state).blue, 6)
        XCTAssertEqual(state.map.tile(at: destination)?.controller?.alignment, .neutral)

        let divisionIndex = try XCTUnwrap(
            state.divisions.firstIndex {
                $0.faction == .blueForce && !$0.isDestroyed && !$0.isRetreating
            }
        )
        let movingDivisionId = state.divisions[divisionIndex].id
        state.divisions[divisionIndex].coord = stagingHex
        state.divisions[divisionIndex].hasActed = false
        state.divisions[divisionIndex].isRetreating = false

        let move = Command.move(divisionId: movingDivisionId, destination: destination)
        XCTAssertEqual(CommandValidator().validate(move, in: state), .valid)

        let moveResult = RuleEngine().execute(move, in: state)

        XCTAssertTrue(moveResult.succeeded, moveResult.message)
        XCTAssertEqual(moveResult.state.map.tile(at: destination)?.controller, .blueForce)
        XCTAssertEqual(moveResult.state.division(id: movingDivisionId)?.coord, destination)
        XCTAssertEqual(moveResult.state.division(id: movingDivisionId)?.hasActed, true)
        XCTAssertEqual(moveResult.state.victoryState.winner, .blueForce)
        XCTAssertEqual(moveResult.state.victoryState.reason, .greyTideBlueKeyNodesSecured)

        let movedControl = VictoryRules.greyTideObjectiveControlCounts(in: moveResult.state)
        XCTAssertEqual(movedControl.blue, 7)
        XCTAssertEqual(movedControl.total, 10)
        XCTAssertLessThan(movedControl.neutral, initialControl.neutral)

        let movedContainer = AppContainer(
            gameState: moveResult.state,
            commandHandler: RuleEngine(),
            dataLoader: dataLoader,
            generalRegistry: (try? dataLoader.loadGeneralRegistry()) ?? .empty,
            playerFaction: .blueForce
        )
        XCTAssertEqual(
            movedContainer.playtestObjectiveSummaryText,
            "Blue \(movedControl.blue)/\(movedControl.total), Red \(movedControl.red), Neutral \(movedControl.neutral)"
        )
        XCTAssertEqual(movedContainer.playtestActionGateDetail, "Blue Force victory reached")
        XCTAssertEqual(movedContainer.playtestObjectiveThresholdText, "Blue Force victory condition reached.")
    }

    func testProbeModernMissionReconUsesAppContainerAndRulesPipeline() throws {
        let dataLoader = DataLoader()
        let container = AppContainer(
            gameState: dataLoader.loadInitialGameState(),
            commandHandler: RuleEngine(),
            dataLoader: dataLoader,
            generalRegistry: (try? dataLoader.loadGeneralRegistry()) ?? .empty,
            playerFaction: .blueForce
        )
        container.resetGame(playerFaction: .blueForce)

        let candidate = try XCTUnwrap(
            container.gameState.divisions
                .filter { $0.faction == .blueForce && !$0.hasActed && !$0.isDestroyed && !$0.isRetreating }
                .filter { division in
                    container.gameState.divisions.filter { $0.coord == division.coord }.count == 1
                }
                .first {
                    CommandValidator()
                        .validate(.recon(divisionId: $0.id, target: $0.coord), in: container.gameState)
                        .isValid
                }
        )

        container.handleBoardTap(candidate.coord)

        XCTAssertEqual(container.selectedDivision?.id, candidate.id)
        XCTAssertTrue(container.selectedUnitCanAct)
        XCTAssertTrue(container.canIssueSelectedReconMission)
        XCTAssertTrue(container.modernMissionAvailabilityText.contains("Recon Area"))

        container.orderModernReconArea()

        let acted = try XCTUnwrap(container.gameState.division(id: candidate.id))
        XCTAssertTrue(acted.hasActed)
        XCTAssertEqual(container.lastCommandFeedbackTone, .success)
        XCTAssertTrue(container.lastCommandMessage?.localizedCaseInsensitiveContains("recon") == true)
        XCTAssertTrue(container.gameState.eventLog.contains { $0.category == .intelligence })
        XCTAssertFalse(container.canIssueSelectedReconMission)
        XCTAssertTrue(container.modernMissionAvailabilityText.contains("already acted"))
    }

    func testProbeRestrictedFireZoneRequiresPrecisionLinkedHostileTarget() throws {
        let state = Self.restrictedFireZoneProbeState()
        let ruleEngine = RuleEngine()

        let rocketResult = ruleEngine.execute(
            .fireMission(
                issuerId: "blue_fires",
                target: .contact(id: "contact_restricted_red_armor"),
                munitionClass: .rocket
            ),
            in: state
        )

        XCTAssertFalse(rocketResult.succeeded)
        XCTAssertEqual(rocketResult.validation, .invalid(.restrictedFireZone))
        XCTAssertTrue(
            rocketResult.message.contains("restricted fire zone requires a current high-confidence linked hostile target and precision-capable munition")
        )
        XCTAssertTrue(rocketResult.state.fireSupportState.lastMissionResults.isEmpty)
        XCTAssertEqual(rocketResult.state.division(id: "blue_fires")?.hasActed, false)

        let precisionResult = ruleEngine.execute(
            .fireMission(
                issuerId: "blue_fires",
                target: .contact(id: "contact_restricted_red_armor"),
                munitionClass: .precision
            ),
            in: state
        )

        XCTAssertTrue(precisionResult.succeeded, precisionResult.message)
        let missionResult = try XCTUnwrap(precisionResult.state.fireSupportState.lastMissionResults.last)
        XCTAssertEqual(missionResult.targetDivisionId, "red_armor_restricted")
        XCTAssertEqual(missionResult.munitionClass, .precision)
        XCTAssertTrue(missionResult.riskFlags.contains(.restrictedFireZone))
        XCTAssertEqual(missionResult.status, .degraded)
        XCTAssertGreaterThan(missionResult.damage, 0)
        XCTAssertLessThan(
            precisionResult.state.division(id: "red_armor_restricted")?.strength ?? 10,
            state.division(id: "red_armor_restricted")?.strength ?? 10
        )
        XCTAssertEqual(precisionResult.state.division(id: "blue_fires")?.hasActed, true)
        XCTAssertEqual(
            precisionResult.state.fireSupportState.budget(for: .blue).available(for: .precision),
            state.fireSupportState.budget(for: .blue).available(for: .precision) - 1
        )
        XCTAssertTrue(
            precisionResult.state.eventLog.contains {
                $0.category == .fireSupport && $0.message.contains("restricted fire zone")
            }
        )

        var staleState = state
        staleState.operationalAwareness.contacts["contact_restricted_red_armor"]?.ageInTurns = 1
        let staleResult = ruleEngine.execute(
            .fireMission(
                issuerId: "blue_fires",
                target: .contact(id: "contact_restricted_red_armor"),
                munitionClass: .precision
            ),
            in: staleState
        )

        XCTAssertFalse(staleResult.succeeded)
        XCTAssertEqual(staleResult.validation, .invalid(.restrictedFireZone))
        XCTAssertTrue(staleResult.state.fireSupportState.lastMissionResults.isEmpty)
        XCTAssertEqual(staleResult.state.division(id: "blue_fires")?.hasActed, false)

        var mediumState = state
        mediumState.operationalAwareness.contacts["contact_restricted_red_armor"]?.confidence = .medium
        let mediumResult = ruleEngine.execute(
            .fireMission(
                issuerId: "blue_fires",
                target: .contact(id: "contact_restricted_red_armor"),
                munitionClass: .precision
            ),
            in: mediumState
        )

        XCTAssertFalse(mediumResult.succeeded)
        XCTAssertEqual(mediumResult.validation, .invalid(.restrictedFireZone))
        XCTAssertTrue(mediumResult.state.fireSupportState.lastMissionResults.isEmpty)
        XCTAssertEqual(mediumResult.state.division(id: "blue_fires")?.hasActed, false)
    }

    func testProbeGreyTideDirectAttackRequiresVisibleLinkedContact() throws {
        let state = Self.modernDirectAttackProbeState(includeContact: false)
        let ruleEngine = RuleEngine()

        let blindResult = ruleEngine.execute(
            .attack(attackerId: "blue_attack_contact_gate", targetId: "red_target_contact_gate"),
            in: state
        )

        XCTAssertFalse(blindResult.succeeded)
        XCTAssertEqual(blindResult.validation, .invalid(.insufficientTargetQuality))
        XCTAssertEqual(blindResult.state.division(id: "blue_attack_contact_gate")?.hasActed, false)
        XCTAssertEqual(
            blindResult.state.division(id: "red_target_contact_gate")?.strength,
            state.division(id: "red_target_contact_gate")?.strength
        )

        let spottedState = Self.modernDirectAttackProbeState(includeContact: true)
        let attackResult = ruleEngine.execute(
            .attack(attackerId: "blue_attack_contact_gate", targetId: "red_target_contact_gate"),
            in: spottedState
        )

        XCTAssertTrue(attackResult.succeeded, attackResult.message)
        XCTAssertEqual(attackResult.validation, .valid)
        XCTAssertEqual(attackResult.state.division(id: "blue_attack_contact_gate")?.hasActed, true)
        XCTAssertLessThan(
            attackResult.state.division(id: "red_target_contact_gate")?.strength ?? 10,
            spottedState.division(id: "red_target_contact_gate")?.strength ?? 10
        )
        XCTAssertTrue(
            attackResult.state.eventLog.contains {
                $0.message.localizedCaseInsensitiveContains("attacked")
            }
        )
    }

    @MainActor
    func testProbeAppContainerObserverRunsTwoAIHalfTurns() async throws {
        let dataLoader = DataLoader()
        let container = AppContainer(
            gameState: dataLoader.loadInitialGameState(),
            commandHandler: RuleEngine(),
            dataLoader: dataLoader,
            generalRegistry: (try? dataLoader.loadGeneralRegistry()) ?? .empty,
            playerFaction: .blueForce
        )
        container.resetGame(playerFaction: .blueForce)
        let initialTurn = container.gameState.turn

        container.setObserverModeEnabled(true)

        XCTAssertEqual(container.playtestControlModeSummary, "Observer AI")
        XCTAssertEqual(container.playtestActionGateTitle, "Automation")
        XCTAssertEqual(container.playtestActionGateDetail, "Blue Force AI can resolve")

        container.advanceOrRunAI()
        try await Self.waitForContainerAI(
            container,
            expectedTurn: initialTurn + 1,
            expectedActiveFaction: .blueForce,
            expectedPhase: .alliedPlayer
        )

        XCTAssertEqual(container.gameState.turn, initialTurn + 1)
        XCTAssertEqual(container.gameState.activeFaction, .blueForce)
        XCTAssertEqual(container.gameState.phase, .alliedPlayer)
        XCTAssertTrue(
            container.lastAgentDecisionRecord?.commandResults.contains { $0.id == "end_turn" && $0.executed } == true
        )
        XCTAssertTrue(container.lastWarDirectiveRecords.contains { $0.faction == .blueForce })
        XCTAssertTrue(container.lastWarDirectiveRecords.contains { $0.faction == .redForce })
        XCTAssertFalse(
            container.lastAgentDecisionRecord?.errors.contains {
                $0.localizedCaseInsensitiveContains("outside its controllable phase")
            } == true
        )
        XCTAssertTrue(container.gameState.map.validateRegionGraph().isEmpty)
        XCTAssertFalse(container.gameState.warDeploymentState.frontZones.isEmpty)
        XCTAssertFalse(container.gameState.theaterState.theaters.isEmpty)
        XCTAssertFalse(container.gameState.operationalAwareness.sensorCoverage.isEmpty)
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
        XCTAssertEqual(classification.tactic, .elasticDefense)
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
        XCTAssertEqual(directive.tactic, .blitzkrieg)
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

    private static func restrictedFireZoneProbeState() -> GameState {
        let blueCoord = HexCoord(q: 0, r: 0)
        let targetCoord = HexCoord(q: 2, r: 0)
        let map = restrictedFireZoneProbeMap(blueCoord: blueCoord, targetCoord: targetCoord)
        let divisions = [
            Division(
                id: "blue_fires",
                name: "Blue Precision Fires",
                faction: .blueForce,
                coord: blueCoord,
                facing: .east,
                components: [
                    DivisionComponent(type: .rocketArtillery, weight: 0.45),
                    DivisionComponent(type: .loiteringMunition, weight: 0.25),
                    DivisionComponent(type: .uav, weight: 0.15),
                    DivisionComponent(type: .lightInfantry, weight: 0.15)
                ]
            ),
            Division(
                id: "red_armor_restricted",
                name: "Red Armor in Civilian Zone",
                faction: .redForce,
                coord: targetCoord,
                facing: .west,
                components: [DivisionComponent(type: .armor, weight: 1.0)]
            )
        ]
        let contact = ContactTrack(
            id: "contact_restricted_red_armor",
            ownerFaction: .blueForce,
            observerSide: .blue,
            lastKnownCoord: targetCoord,
            confidence: .confirmed,
            estimatedType: .armor,
            source: .uav,
            ageInTurns: 0,
            linkedDivisionId: "red_armor_restricted"
        )

        return GameState(
            scenarioId: "probe_restricted_fire_zone",
            turn: 1,
            maxTurns: 4,
            activeFaction: .blueForce,
            phase: .alliedPlayer,
            map: map,
            theaterState: .empty,
            frontLineState: .empty,
            warDeploymentState: .empty,
            operationalAwareness: OperationalAwarenessState(
                contacts: [contact.id: contact],
                sensorCoverage: [],
                ewEffects: []
            ),
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }

    private static func restrictedFireZoneProbeMap(
        blueCoord: HexCoord,
        targetCoord: HexCoord
    ) -> MapState {
        let blueRegion = RegionId("blue_fires_sector")
        let civilianRegion = RegionId("civilian_buffer")
        let regions: [RegionId: RegionNode] = [
            blueRegion: RegionNode(
                id: blueRegion,
                name: "Blue Fires Sector",
                owner: .blueForce,
                controller: .blueForce,
                terrain: .plain,
                neighbors: [civilianRegion],
                displayHexes: [blueCoord],
                representativeHex: blueCoord
            ),
            civilianRegion: RegionNode(
                id: civilianRegion,
                name: "Civilian Buffer",
                owner: .neutral,
                controller: .greenForce,
                terrain: .plain,
                neighbors: [blueRegion],
                displayHexes: [HexCoord(q: 1, r: 0), targetCoord],
                representativeHex: targetCoord
            )
        ]
        let tiles: [HexCoord: HexTile] = [
            blueCoord: HexTile(coord: blueCoord, baseTerrain: .plain, controller: .blueForce, regionId: blueRegion),
            HexCoord(q: 1, r: 0): HexTile(
                coord: HexCoord(q: 1, r: 0),
                baseTerrain: .plain,
                controller: .greenForce,
                regionId: civilianRegion
            ),
            targetCoord: HexTile(coord: targetCoord, baseTerrain: .plain, controller: .greenForce, regionId: civilianRegion)
        ]

        return MapState(
            width: 3,
            height: 1,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: [
                blueCoord: blueRegion,
                HexCoord(q: 1, r: 0): civilianRegion,
                targetCoord: civilianRegion
            ],
            regionEdges: [RegionEdge(from: blueRegion, to: civilianRegion)]
        )
    }

    private static func modernDirectAttackProbeState(includeContact: Bool) -> GameState {
        let blueCoord = HexCoord(q: 0, r: 0)
        let targetCoord = HexCoord(q: 1, r: 0)
        let map = modernDirectAttackProbeMap(blueCoord: blueCoord, targetCoord: targetCoord)
        let divisions = [
            Division(
                id: "blue_attack_contact_gate",
                name: "Blue Contact Gate Assault",
                faction: .blueForce,
                coord: blueCoord,
                facing: .east,
                components: [
                    DivisionComponent(type: .armor, weight: 0.6),
                    DivisionComponent(type: .mechanizedInfantry, weight: 0.4)
                ]
            ),
            Division(
                id: "red_target_contact_gate",
                name: "Red Contact Gate Target",
                faction: .redForce,
                coord: targetCoord,
                facing: .west,
                components: [DivisionComponent(type: .lightInfantry, weight: 1.0)]
            )
        ]
        let contact = ContactTrack(
            id: "contact_red_target_contact_gate",
            ownerFaction: .blueForce,
            observerSide: .blue,
            lastKnownCoord: targetCoord,
            confidence: .medium,
            estimatedType: .infantry,
            source: .groundRecon,
            ageInTurns: 0,
            linkedDivisionId: "red_target_contact_gate"
        )

        return GameState(
            scenarioId: "grey_tide_2030",
            turn: 1,
            maxTurns: 4,
            activeFaction: .blueForce,
            phase: .alliedPlayer,
            map: map,
            theaterState: .empty,
            frontLineState: .empty,
            warDeploymentState: .empty,
            operationalAwareness: OperationalAwarenessState(
                contacts: includeContact ? [contact.id: contact] : [:],
                sensorCoverage: [],
                ewEffects: []
            ),
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }

    private static func modernDirectAttackProbeMap(
        blueCoord: HexCoord,
        targetCoord: HexCoord
    ) -> MapState {
        let blueRegion = RegionId("blue_attack_sector")
        let targetRegion = RegionId("red_attack_sector")
        let regions: [RegionId: RegionNode] = [
            blueRegion: RegionNode(
                id: blueRegion,
                name: "Blue Attack Sector",
                owner: .blueForce,
                controller: .blueForce,
                terrain: .plain,
                neighbors: [targetRegion],
                displayHexes: [blueCoord],
                representativeHex: blueCoord
            ),
            targetRegion: RegionNode(
                id: targetRegion,
                name: "Red Attack Sector",
                owner: .redForce,
                controller: .redForce,
                terrain: .plain,
                neighbors: [blueRegion],
                displayHexes: [targetCoord],
                representativeHex: targetCoord
            )
        ]

        return MapState(
            width: 2,
            height: 1,
            tiles: [
                blueCoord: HexTile(coord: blueCoord, baseTerrain: .plain, controller: .blueForce, regionId: blueRegion),
                targetCoord: HexTile(coord: targetCoord, baseTerrain: .plain, controller: .redForce, regionId: targetRegion)
            ],
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: [
                blueCoord: blueRegion,
                targetCoord: targetRegion
            ],
            regionEdges: [RegionEdge(from: blueRegion, to: targetRegion)]
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

    private static func greyTideProbeTurnManager(for faction: Faction, state: GameState) -> TurnManager {
        let assignedDivisionIds = state.divisions
            .filter { $0.faction == faction && !$0.isDestroyed }
            .map(\.id)
        let agent = GameAgent.sample(
            id: "probe_\(faction.rawValue)_observer_commander",
            name: "\(faction.shortDisplayName) Observer Commander",
            faction: faction,
            role: .armyCommander,
            assignedDivisionIds: assignedDivisionIds
        )

        return TurnManager(
            agent: agent,
            provider: MockAIClient(),
            providerName: "ProbeAI",
            commandHandler: RuleEngine(),
            commanderPool: TheaterCommanderPool.automatic(for: state),
            marshalAgent: MarshalAgent(config: MarshalAgentConfig.automatic(for: faction, state: state))
        )
    }

    @MainActor
    private static func waitForContainerAI(
        _ container: AppContainer,
        expectedTurn: Int,
        expectedActiveFaction: Faction,
        expectedPhase: GamePhase,
        timeoutNanoseconds: UInt64 = 10_000_000_000
    ) async throws {
        let stepNanoseconds: UInt64 = 100_000_000
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if container.gameState.turn == expectedTurn,
               container.gameState.activeFaction == expectedActiveFaction,
               container.gameState.phase == expectedPhase,
               container.lastAgentDecisionRecord != nil {
                return
            }

            try await Task.sleep(nanoseconds: stepNanoseconds)
            waited += stepNanoseconds
        }

        XCTFail(
            "Timed out waiting for AppContainer AI: turn \(container.gameState.turn), active \(container.gameState.activeFaction), phase \(container.gameState.phase)"
        )
    }
}
