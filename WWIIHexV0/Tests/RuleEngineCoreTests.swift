import XCTest
@testable import WWIIHexV0

final class RuleEngineCoreTests: XCTestCase {
    func testHexDistanceNeighborsDirectionAndRange() {
        let origin = HexCoord(q: 0, r: 0)

        XCTAssertEqual(origin.distance(to: HexCoord(q: 2, r: -2)), 2)
        XCTAssertEqual(origin.neighbors.count, 6)
        XCTAssertTrue(origin.neighbors.contains(HexCoord(q: 1, r: 0)))
        XCTAssertEqual(origin.direction(to: HexCoord(q: 2, r: -2)), .northEast)
        XCTAssertEqual(origin.coordsWithin(distance: 1).count, 7)
    }

    func testTerrainMovementCostsAndFortressDefense() {
        let rules = MovementRules()
        let plainRoad = HexTile(coord: HexCoord(q: 0, r: 0), baseTerrain: .plain, hasRoad: true)
        let forestRoad = HexTile(coord: HexCoord(q: 1, r: 0), baseTerrain: .forest, hasRoad: true)
        let forest = HexTile(coord: HexCoord(q: 1, r: 0), baseTerrain: .forest)
        let riverPlain = HexTile(
            coord: HexCoord(q: 0, r: 0),
            baseTerrain: .plain,
            riverEdges: [.east]
        )
        let fortress = HexTile(coord: HexCoord(q: 1, r: 0), baseTerrain: .fortress)

        XCTAssertEqual(rules.movementCost(from: plainRoad, to: forestRoad, direction: .east), 1)
        XCTAssertEqual(rules.movementCost(from: plainRoad, to: forest, direction: .east), 2)
        XCTAssertEqual(rules.movementCost(from: riverPlain, to: forest, direction: .east), 4)
        XCTAssertEqual(fortress.baseTerrain.defenseBonus, 4)
    }

    func testLegalMoveChangesCoordFacingAndActedState() {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
            ]
        )

        let result = RuleEngine().execute(
            .move(divisionId: "a", destination: HexCoord(q: 2, r: 1)),
            in: state
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.division(id: "a")?.coord, HexCoord(q: 2, r: 1))
        XCTAssertEqual(result.state.division(id: "a")?.facing, .east)
        XCTAssertEqual(result.state.division(id: "a")?.hasActed, true)
    }

    func testMovementCannotContinueAfterEnteringEnemyZoneOfControl() {
        let map = Self.basicMap(width: 5, height: 1)
        let allied = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 0, r: 0))
        let german = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 0))
        let state = Self.testState(activeFaction: .allies, map: map, divisions: [allied, german])
        let movementRules = MovementRules()

        XCTAssertNotNil(movementRules.shortestPath(for: allied, to: HexCoord(q: 1, r: 0), in: state))
        XCTAssertNil(movementRules.shortestPath(for: allied, to: HexCoord(q: 3, r: 0), in: state))
    }

    func testIllegalMoveDoesNotChangeState() {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1)),
                Self.division(id: "b", faction: .allies, coord: HexCoord(q: 2, r: 1))
            ]
        )

        let result = RuleEngine().execute(
            .move(divisionId: "a", destination: HexCoord(q: 2, r: 1)),
            in: state
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.validation.errors, [.destinationOccupied])
        XCTAssertEqual(result.state, state)
    }

    func testFriendlyOccupiedHexCanBePassedThroughButNotStoppedOn() {
        let map = Self.basicMap(width: 4, height: 1)
        let mover = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 0, r: 0))
        let friendlyBlocker = Self.division(id: "b", faction: .allies, coord: HexCoord(q: 1, r: 0))
        let state = Self.testState(activeFaction: .allies, map: map, divisions: [mover, friendlyBlocker])

        let path = MovementRules().shortestPath(for: mover, to: HexCoord(q: 2, r: 0), in: state)
        XCTAssertEqual(path?.coords, [
            HexCoord(q: 0, r: 0),
            HexCoord(q: 1, r: 0),
            HexCoord(q: 2, r: 0)
        ])
        XCTAssertFalse(MovementRules().movementRange(for: mover, in: state).contains(HexCoord(q: 1, r: 0)))

        let passThroughResult = RuleEngine().execute(.move(divisionId: "a", destination: HexCoord(q: 2, r: 0)), in: state)
        let stopOnFriendlyResult = RuleEngine().execute(.move(divisionId: "a", destination: HexCoord(q: 1, r: 0)), in: state)

        XCTAssertTrue(passThroughResult.succeeded)
        XCTAssertEqual(passThroughResult.state.division(id: "a")?.coord, HexCoord(q: 2, r: 0))
        XCTAssertFalse(stopOnFriendlyResult.succeeded)
        XCTAssertEqual(stopOnFriendlyResult.validation.errors, [.destinationOccupied])
    }

    func testMoveValidationDistinguishesOutOfBoundsNoPathAndInsufficientMovement() {
        let start = HexCoord(q: 0, r: 0)
        let isolatedDestination = HexCoord(q: 2, r: 2)
        let blockedMap = MapState(
            width: 3,
            height: 3,
            tiles: [
                start: HexTile(coord: start),
                isolatedDestination: HexTile(coord: isolatedDestination)
            ],
            supplySources: [],
            objectives: []
        )
        let noPathState = Self.testState(
            activeFaction: .allies,
            map: blockedMap,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: start)
            ]
        )

        let noPath = RuleEngine().execute(
            .move(divisionId: "a", destination: isolatedDestination),
            in: noPathState
        )
        XCTAssertEqual(noPath.validation.errors, [.noPath])

        let insufficientState = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 0, r: 0))
            ]
        )
        let insufficient = RuleEngine().execute(
            .move(divisionId: "a", destination: HexCoord(q: 4, r: 0)),
            in: insufficientState
        )

        XCTAssertEqual(insufficient.validation.errors, [.insufficientMovement])

        let outOfBounds = RuleEngine().execute(
            .move(divisionId: "a", destination: HexCoord(q: 9, r: 9)),
            in: insufficientState
        )
        XCTAssertEqual(outOfBounds.validation.errors, [.destinationOutOfBounds])
    }

    func testAttackCausesDeterministicDamageAndCounterattack() {
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
        let defender = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 1))
        let state = Self.testState(activeFaction: .allies, divisions: [attacker, defender])

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.division(id: "g")?.hp, 8)
        XCTAssertEqual(result.state.division(id: "a")?.hp, 9)
        XCTAssertEqual(result.state.division(id: "a")?.hasActed, true)
    }

    func testAttackReducesDefenderStrengthOnly() throws {
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
        let defender = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 1))
        let state = Self.testState(activeFaction: .allies, divisions: [attacker, defender])

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        let updatedDefender = try XCTUnwrap(result.state.division(id: "g"))
        XCTAssertTrue(result.succeeded)
        XCTAssertLessThan(updatedDefender.strength, defender.strength)
    }

    func testArtilleryDefenderCannotCounterattackWhenAttackedAtRangeOne() {
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
        let defender = Division.artillery(
            id: "g_artillery",
            name: "g_artillery",
            faction: .germany,
            coord: HexCoord(q: 2, r: 1)
        )
        let state = Self.testState(activeFaction: .allies, divisions: [attacker, defender])

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g_artillery"), in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.division(id: "g_artillery")?.hp, 7)
        XCTAssertEqual(result.state.division(id: "a")?.hp, 10)
    }

    func testOutOfRangeAttackIsRejected() {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 0, r: 0)),
                Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 0))
            ]
        )

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.validation.errors, [.targetOutOfRange])
        XCTAssertEqual(result.state, state)
    }

    func testAlreadyActedUnitCannotActAgain() {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1), hasActed: true)
            ]
        )

        let result = RuleEngine().execute(
            .hold(divisionId: "a"),
            in: state
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.validation.errors, [.alreadyActed])
        XCTAssertEqual(result.state, state)
    }

    func testHoldCommandSetsHoldRetreatModeAndMarksActed() throws {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
            ]
        )

        let result = RuleEngine().execute(.hold(divisionId: "a"), in: state)
        let updated = try XCTUnwrap(result.state.division(id: "a"))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(updated.retreatMode, .hold)
        XCTAssertEqual(updated.hasActed, true)
    }

    func testAllowRetreatCommandSetsRetreatableModeAndMarksActed() throws {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1), retreatMode: .hold)
            ]
        )

        let result = RuleEngine().execute(.allowRetreat(divisionId: "a"), in: state)
        let updated = try XCTUnwrap(result.state.division(id: "a"))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(updated.retreatMode, .retreatable)
        XCTAssertEqual(updated.hasActed, true)
    }

    func testResupplyRestoresSuppliedUnitStrengthAndMarksActed() throws {
        let division = Self.division(
            id: "a",
            faction: .allies,
            coord: HexCoord(q: 0, r: 0),
            hp: 7,
            supplyState: .supplied
        )
        let state = Self.testState(activeFaction: .allies, divisions: [division])

        let result = RuleEngine().execute(.resupply(divisionId: "a"), in: state)
        let recovered = try XCTUnwrap(result.state.division(id: "a"))

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(recovered.supplyState, .supplied)
        XCTAssertGreaterThan(recovered.hp, division.hp)
        XCTAssertLessThanOrEqual(recovered.hp, division.maxHP)
        XCTAssertEqual(recovered.hasActed, true)
    }

    func testLowSupplyAndEncircledUnitsDoNotReinforceStrength() throws {
        let lowSupply = Self.division(
            id: "a",
            faction: .allies,
            coord: HexCoord(q: 0, r: 0),
            hp: 7,
            supplyState: .lowSupply
        )
        let encircled = Self.division(
            id: "a",
            faction: .allies,
            coord: HexCoord(q: 0, r: 0),
            hp: 7,
            supplyState: .encircled
        )
        let strainedSupplyMap = Self.basicMap(
            width: 5,
            height: 3,
            supplySources: [
                SupplySource(id: "allied_supply", faction: .allies, coord: HexCoord(q: 3, r: 1))
            ]
        )
        let isolatedMap = Self.basicMap(width: 3, height: 3, supplySources: [])
        let lowSupplyState = Self.testState(activeFaction: .allies, map: strainedSupplyMap, divisions: [lowSupply])
        let encircledState = Self.testState(activeFaction: .allies, map: isolatedMap, divisions: [encircled])

        let lowSupplyResult = RuleEngine().execute(.resupply(divisionId: "a"), in: lowSupplyState)
        let encircledResult = RuleEngine().execute(.resupply(divisionId: "a"), in: encircledState)

        XCTAssertEqual(try XCTUnwrap(lowSupplyResult.state.division(id: "a")).hp, lowSupply.hp)
        XCTAssertEqual(try XCTUnwrap(encircledResult.state.division(id: "a")).hp, encircled.hp)
    }

    func testEndTurnSwitchesFactionAndResetsNewActiveFactionActions() {
        let german = Self.division(
            id: "g",
            faction: .germany,
            coord: HexCoord(q: 4, r: 4),
            hasActed: true
        )
        let allied = Self.division(
            id: "a",
            faction: .allies,
            coord: HexCoord(q: 0, r: 0),
            hasActed: true
        )
        let state = Self.testState(activeFaction: .germany, divisions: [german, allied])

        let result = RuleEngine().execute(.endTurn, in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.activeFaction, .allies)
        XCTAssertEqual(result.state.phase, .alliedPlayer)
        XCTAssertEqual(result.state.turn, 1)
        XCTAssertEqual(result.state.division(id: "a")?.hasActed, false)
        XCTAssertEqual(result.state.division(id: "g")?.hasActed, true)
    }

    func testAttackCanEliminateUnitAndRecordVictoryCounter() {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1)),
                Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 1), hp: 1)
            ]
        )

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertNil(result.state.division(id: "g"))
        XCTAssertEqual(result.state.victoryState.eliminatedGermanDivisions, 1)
    }

    func testCaptureCityChangesController() {
        var map = Self.basicMap(width: 5, height: 5)
        let cityCoord = HexCoord(q: 2, r: 1)
        if var tile = map.tile(at: cityCoord) {
            tile.baseTerrain = .city
            tile.controller = .germany
            tile.cityName = "Test City"
            map.setTile(tile)
        }

        let state = Self.testState(
            activeFaction: .allies,
            map: map,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
            ]
        )

        let result = RuleEngine().execute(.move(divisionId: "a", destination: cityCoord), in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.map.tile(at: cityCoord)?.controller, .allies)
    }

    func testAlliedMoveCapturesEnemyControlledPlainHex() {
        var map = Self.basicMap(width: 4, height: 1)
        let target = HexCoord(q: 1, r: 0)
        if var tile = map.tile(at: target) {
            tile.controller = .germany
            map.setTile(tile)
        }
        let state = Self.testState(
            activeFaction: .allies,
            map: map,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 0, r: 0))
            ]
        )

        let result = RuleEngine().execute(.move(divisionId: "a", destination: target), in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.map.tile(at: target)?.controller, .allies)
    }

    func testCaptureSynchronizesRegionTheaterVisibilityAndFrontLineInSameTurn() throws {
        let fixture = FrontLineTestFixtures.mapAndTheaters(specs: [
            .init(id: "allied_home", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["front_city"]),
            .init(id: "front_city", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["allied_home", "german_depth"]),
            .init(id: "german_depth", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["front_city"])
        ])
        var map = fixture.map
        let target = HexCoord(q: 1, r: 0)
        if var targetTile = map.tile(at: target) {
            targetTile.baseTerrain = .city
            targetTile.cityName = "Front City"
            targetTile.controller = .germany
            map.setTile(targetTile)
        }

        let allied = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 0, r: 0))
        let german = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 0))
        var state = Self.testState(activeFaction: .allies, map: map, divisions: [allied, german])
        state.theaterState = fixture.theaterState
        state.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: state.theaterState)
        state.theaterState = TheaterSystem().updateTheaters(
            state: state.theaterState,
            map: state.map,
            divisions: state.divisions,
            turn: state.turn,
            force: true
        )
        state.frontLineState = FrontLineManager().makeInitialState(
            map: state.map,
            theaterState: state.theaterState,
            divisions: state.divisions,
            turn: state.turn
        )
        state.warDeploymentState = WarDeploymentManager().makeInitialState(
            map: state.map,
            theaterState: state.theaterState,
            divisions: state.divisions,
            turn: state.turn
        )

        let result = RuleEngine().execute(.move(divisionId: "a", destination: target), in: state)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.state.map.tile(at: target)?.controller, .allies)
        XCTAssertEqual(result.state.map.region(id: "front_city")?.controller, .allies)
        XCTAssertEqual(result.state.theaterState.regionToTheater["front_city"], FrontLineTestFixtures.theaterB)
        XCTAssertEqual(result.state.theaterState.dynamicTheaterId(for: target, map: result.state.map), FrontLineTestFixtures.theaterA)
        XCTAssertEqual(result.state.theaterState.initialSnapshot?.regionToTheater["front_city"], FrontLineTestFixtures.theaterB)
        XCTAssertGreaterThan(result.state.theaterState.theaters[FrontLineTestFixtures.theaterA]?.controlRatios[.allies] ?? 0, 0)
        XCTAssertEqual(result.state.frontLineState.diagnostics.updateMode, .eventDriven)
        XCTAssertTrue(result.state.frontLineState.diagnostics.updatedRegionIds.contains("front_city"))
        XCTAssertEqual(result.state.frontLineState.regionStates["front_city"]?.dirtyFlag, true)
        XCTAssertLessThan(
            RegionVisibilityRules().visibleRegions(for: .allies, in: result.state, radius: 0).count,
            result.state.map.regions.count
        )
    }

    func testAgentContextDoesNotTreatEmptyVisibilityAsAllVisible() {
        let fixture = FrontLineTestFixtures.mapAndTheaters(specs: [
            .init(id: "a", faction: .allies, theaterId: FrontLineTestFixtures.theaterA, neighbors: ["b"]),
            .init(id: "b", faction: .germany, theaterId: FrontLineTestFixtures.theaterB, neighbors: ["a"])
        ])
        let state = Self.testState(activeFaction: .allies, map: fixture.map, divisions: [])
        let agent = GameAgent.sample(id: "observer", name: "Observer", faction: .allies, role: .armyCommander)

        let context = AgentContextBuilder().agentContext(for: agent, state: state, playerDirective: nil)

        XCTAssertFalse(context.visibleRegions.contains { $0.visible })
    }

    func testUnsuppliedUnitBecomesLowSupplyOrEncircled() throws {
        var map = Self.basicMap(width: 7, height: 7)
        map.supplySources = [SupplySource(id: "allied_supply", faction: .allies, coord: HexCoord(q: 0, r: 0))]

        let state = Self.testState(
            activeFaction: .germany,
            map: map,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 6, r: 6)),
                Self.division(id: "g", faction: .germany, coord: HexCoord(q: 5, r: 6))
            ]
        )

        var next = state
        SupplyRules().updateSupplyStates(in: &next)

        let supplyState = try XCTUnwrap(next.division(id: "a")?.supplyState)
        XCTAssertTrue([SupplyState.lowSupply, .encircled].contains(supplyState))
    }

    func testSupplyModifiersReduceDerivedStatsAndEncirclementAttritionPreservesOneHP() {
        var lowSupply = Self.division(id: "low", faction: .allies, coord: HexCoord(q: 1, r: 1))
        lowSupply.supplyState = .lowSupply
        XCTAssertEqual(lowSupply.attack, 3)
        XCTAssertEqual(lowSupply.defense, 4)
        XCTAssertEqual(lowSupply.movement, 2)

        var encircled = Self.division(id: "encircled", faction: .allies, coord: HexCoord(q: 2, r: 2), hp: 1)
        encircled.supplyState = .encircled
        XCTAssertEqual(encircled.attack, 2)
        XCTAssertEqual(encircled.defense, 3)
        XCTAssertEqual(encircled.movement, 1)

        var state = Self.testState(activeFaction: .allies, divisions: [encircled])
        SupplyRules().applyEncirclementAttrition(in: &state)
        XCTAssertEqual(state.division(id: "encircled")?.hp, 1)
    }

    func testEncircledEndTurnAppliesStrengthAttrition() throws {
        let encircled = Self.division(
            id: "a",
            faction: .allies,
            coord: HexCoord(q: 1, r: 1),
            hp: 6,
            supplyState: .encircled
        )
        let isolatedMap = Self.basicMap(width: 3, height: 3, supplySources: [])
        let state = Self.testState(activeFaction: .allies, map: isolatedMap, divisions: [encircled])

        let result = RuleEngine().execute(.endTurn, in: state)

        let updated = try XCTUnwrap(result.state.division(id: "a"))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(updated.supplyState, .encircled)
        XCTAssertLessThan(updated.hp, encircled.hp)
        XCTAssertGreaterThanOrEqual(updated.hp, 1)
    }

    func testRetreatableDivisionAutoRetreatsAfterSevereLoss() throws {
        var map = Self.basicMap(
            width: 5,
            height: 5,
            supplySources: [
                SupplySource(id: "german_supply", faction: .germany, coord: HexCoord(q: 4, r: 2)),
                SupplySource(id: "allied_supply", faction: .allies, coord: HexCoord(q: 0, r: 2))
            ]
        )
        if var germanSupplyTile = map.tile(at: HexCoord(q: 4, r: 2)) {
            germanSupplyTile.hasRoad = true
            map.setTile(germanSupplyTile)
        }
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 2))
        let defender = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 2), hp: 4)
        let state = Self.testState(activeFaction: .allies, map: map, divisions: [attacker, defender])
        let expectedDestination = try XCTUnwrap(SupplyRules().retreatDestination(for: defender, in: state))

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        let retreated = try XCTUnwrap(result.state.division(id: "g"))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(retreated.coord, expectedDestination)
        XCTAssertTrue(result.state.eventLog.contains { $0.message.localizedCaseInsensitiveContains("retreat") })
    }

    func testRetreatableDivisionDoesNotRetreatAfterMinorLoss() throws {
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
        let defender = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 1), hp: 10)
        let state = Self.testState(activeFaction: .allies, divisions: [attacker, defender])

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        let updated = try XCTUnwrap(result.state.division(id: "g"))
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(updated.coord, defender.coord)
        XCTAssertFalse(updated.isRetreating)
    }

    func testHoldModeDoesNotRetreatAndTakesExtraLosses() throws {
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
        let retreatable = Self.division(id: "r", faction: .germany, coord: HexCoord(q: 2, r: 1), hp: 10)
        let hold = Self.division(id: "h", faction: .germany, coord: HexCoord(q: 2, r: 1), hp: 10, retreatMode: .hold)
        let retreatableState = Self.testState(activeFaction: .allies, divisions: [attacker, retreatable])
        let holdState = Self.testState(activeFaction: .allies, divisions: [attacker, hold])

        let retreatableResult = RuleEngine().execute(.attack(attackerId: "a", targetId: "r"), in: retreatableState)
        let holdResult = RuleEngine().execute(.attack(attackerId: "a", targetId: "h"), in: holdState)

        let retreatableAfter = try XCTUnwrap(retreatableResult.state.division(id: "r"))
        let holdAfter = try XCTUnwrap(holdResult.state.division(id: "h"))
        XCTAssertEqual(holdAfter.coord, hold.coord)
        XCTAssertFalse(holdAfter.isRetreating)
        XCTAssertLessThanOrEqual(holdAfter.hp, retreatableAfter.hp)
    }

    func testRetreatFailureLogsAndAppliesStrengthPenalty() throws {
        let attacker = Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1))
        let defender = Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 1), hp: 4)
        let isolatedMap = Self.basicMap(width: 4, height: 4, supplySources: [])
        let state = Self.testState(activeFaction: .allies, map: isolatedMap, divisions: [attacker, defender])

        let result = RuleEngine().execute(.attack(attackerId: "a", targetId: "g"), in: state)

        let updated = try XCTUnwrap(result.state.division(id: "g"))
        let logText = result.state.eventLog.map(\.message).joined(separator: "\n").lowercased()

        XCTAssertEqual(updated.coord, defender.coord)
        XCTAssertLessThan(updated.hp, defender.hp)
        XCTAssertTrue(logText.contains("failed to retreat"))
    }

    func testBastogneGermanControlRequiresFullTurnBeforeVictory() {
        var state = Self.testState(
            activeFaction: .germany,
            map: MapState.ardennesV0(),
            divisions: []
        )
        if var bastogne = state.map.tile(at: HexCoord(q: 5, r: 4)) {
            bastogne.controller = .germany
            state.map.setTile(bastogne)
        }

        VictoryRules().updateVictoryState(in: &state)
        XCTAssertNil(state.victoryState.winner)
        XCTAssertEqual(state.victoryState.germanBastogneHeldSinceTurn, 1)

        VictoryRules().updateVictoryState(in: &state)
        XCTAssertNil(state.victoryState.winner)

        state.turn = 2
        VictoryRules().updateVictoryState(in: &state)
        XCTAssertEqual(state.victoryState.winner, .germany)
        XCTAssertEqual(state.victoryState.reason, .bastogneHeldByGermany)
    }

    func testGermanArmorUnsuppliedRequiresFullTurnBeforeAlliedVictory() {
        var panzer = Division.panzer(
            id: "g_panzer",
            name: "g_panzer",
            faction: .germany,
            coord: HexCoord(q: 2, r: 2)
        )
        panzer.supplyState = .lowSupply
        var state = Self.testState(activeFaction: .allies, divisions: [panzer])

        VictoryRules().updateVictoryState(in: &state)
        XCTAssertNil(state.victoryState.winner)
        XCTAssertEqual(state.victoryState.germanArmorUnsuppliedSinceTurn, 1)

        VictoryRules().updateVictoryState(in: &state)
        XCTAssertNil(state.victoryState.winner)

        state.turn = 2
        VictoryRules().updateVictoryState(in: &state)
        XCTAssertEqual(state.victoryState.winner, .allies)
        XCTAssertEqual(state.victoryState.reason, .germanArmorUnsupplied)
    }

    func testInvalidCommandDoesNotModifyGameState() {
        let state = Self.testState(
            activeFaction: .allies,
            divisions: [
                Self.division(id: "a", faction: .allies, coord: HexCoord(q: 1, r: 1)),
                Self.division(id: "g", faction: .germany, coord: HexCoord(q: 2, r: 1))
            ]
        )

        let result = RuleEngine().execute(.attack(attackerId: "missing", targetId: "g"), in: state)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.validation.errors, [.divisionNotFound])
        XCTAssertEqual(result.state, state)
    }

    private static func division(
        id: String,
        faction: Faction,
        coord: HexCoord,
        hp: Int = 10,
        supplyState: SupplyState = .supplied,
        hasActed: Bool = false,
        retreatMode: RetreatMode = .retreatable
    ) -> Division {
        Division(
            id: id,
            name: id,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .west : .east,
            hp: hp,
            maxHP: 10,
            components: [
                DivisionComponent(type: .infantry, weight: 1.0)
            ],
            supplyState: supplyState,
            hasActed: hasActed,
            retreatMode: retreatMode
        )
    }

    private static func testState(
        activeFaction: Faction,
        divisions: [Division]
    ) -> GameState {
        testState(activeFaction: activeFaction, map: basicMap(width: 5, height: 5), divisions: divisions)
    }

    private static func testState(
        activeFaction: Faction,
        map: MapState,
        divisions: [Division]
    ) -> GameState {
        GameState(
            scenarioId: "test",
            turn: 1,
            maxTurns: 8,
            activeFaction: activeFaction,
            phase: activeFaction == .germany ? .germanAI : .alliedPlayer,
            map: map,
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }

    private static func basicMap(
        width: Int,
        height: Int,
        supplySources: [SupplySource]? = nil
    ) -> MapState {
        var tiles: [HexCoord: HexTile] = [:]
        for q in 0..<width {
            for r in 0..<height {
                let coord = HexCoord(q: q, r: r)
                tiles[coord] = HexTile(coord: coord)
            }
        }

        return MapState(
            width: width,
            height: height,
            tiles: tiles,
            supplySources: supplySources ?? [
                SupplySource(id: "allied_supply", faction: .allies, coord: HexCoord(q: 0, r: 0)),
                SupplySource(id: "german_supply", faction: .germany, coord: HexCoord(q: width - 1, r: height - 1))
            ],
            objectives: []
        )
    }
}
