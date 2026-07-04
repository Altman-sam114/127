import XCTest
@testable import WWIIHexV0

final class ObserverModeIntegrationTests: XCTestCase {
    func testObserverModeRunsBothDirectiveAIsAndChangesTheFront() async throws {
        let initialState = Self.observerScenario()
        var state = initialState
        let initialControllers = state.map.regions.mapValues(\.controller)
        var allRecords: [WarDirectiveRecord] = []

        for _ in 0..<24 {
            let outcome = await Self.runActiveFactionAITurn(state)
            state = Self.refreshStrategicState(outcome.state)
            allRecords.append(contentsOf: outcome.directiveRecords)
        }

        let successfulAttacks = allRecords.flatMap(\.commandResults).filter {
            $0.executed && $0.commandDisplayName?.lowercased().contains("attack") == true
        }
        XCTAssertFalse(successfulAttacks.isEmpty)

        let changedRegion = state.map.regions.contains { regionId, region in
            initialControllers[regionId] != region.controller
        }
        XCTAssertTrue(changedRegion)

        XCTAssertFalse(Self.hasAttackWithdrawOscillation(records: allRecords, limit: 6))

        XCTAssertTrue(state.map.validateRegionGraph().isEmpty)
        XCTAssertTrue(state.theaterState.regionToTheater.allSatisfy { regionId, theaterId in
            state.map.regions[regionId] != nil && state.theaterState.theaters[theaterId] != nil
        })
        XCTAssertTrue(state.warDeploymentState.regionToFrontZone.allSatisfy { regionId, zoneId in
            state.map.regions[regionId] != nil && state.warDeploymentState.frontZones[zoneId] != nil
        })
        XCTAssertTrue(Set(allRecords.map(\.faction)).isSuperset(of: [.germany, .allies]))
    }

    private static func hasAttackWithdrawOscillation(records: [WarDirectiveRecord], limit: Int) -> Bool {
        let tacticalRecords = records.filter { $0.zoneId != nil && $0.directiveType != nil }
        var streak = 0
        var previousKey: String?

        for record in tacticalRecords {
            let key = "\(record.zoneId?.rawValue ?? "none"):\(record.targetRegionIds.first?.rawValue ?? "none"):\(record.directiveType?.rawValue ?? "none")"
            if key == previousKey {
                streak += 1
            } else {
                streak = 1
                previousKey = key
            }
            if streak > limit {
                return true
            }
        }

        return false
    }

    private static func refreshStrategicState(_ state: GameState) -> GameState {
        var next = state
        next.theaterState = TheaterSystem().updateTheaters(
            state: next.theaterState,
            map: next.map,
            divisions: next.divisions,
            turn: next.turn
        )
        next.frontLineState = FrontLineManager().makeInitialState(
            map: next.map,
            theaterState: next.theaterState,
            divisions: next.divisions,
            turn: next.turn
        )
        next.warDeploymentState = WarDeploymentManager().makeInitialState(
            map: next.map,
            theaterState: next.theaterState,
            divisions: next.divisions,
            turn: next.turn
        )
        return next
    }

    private static func runActiveFactionAITurn(_ state: GameState) async -> AgentTurnOutcome {
        let faction = state.activeFaction
        let agent: GameAgent
        switch faction {
        case .germany:
            agent = GameAgent.guderianFallback(
                assignedDivisionIds: state.divisions
                    .filter { $0.faction == .germany && !$0.isDestroyed }
                    .map(\.id)
            )
        case .allies:
            agent = GameAgent.sample(
                id: "allied_mock_commander",
                name: "Allied Mock Commander",
                faction: .allies,
                role: .armyCommander,
                assignedDivisionIds: state.divisions
                    .filter { $0.faction == .allies && !$0.isDestroyed }
                    .map(\.id)
            )
        }

        let manager = TurnManager(
            agent: agent,
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: RuleEngine(),
            commanderPool: TheaterCommanderPool.automatic(for: state)
        )
        return await manager.runAITurn(
            state: state,
            faction: faction,
            pipelineMode: .zoneDirective
        )
    }

    private static func observerScenario() -> GameState {
        var divisions: [Division] = []
        for index in 0..<3 {
            divisions.append(
                Division.infantry(
                    id: "german_\(index)",
                    name: "German \(index)",
                    faction: .germany,
                    coord: HexCoord(q: index, r: 0)
                )
            )
        }
        divisions.append(
            Division.infantry(
                id: "allied_0",
                name: "Allied 0",
                faction: .allies,
                coord: HexCoord(q: 4, r: 0)
            )
        )

        let map = observerMap()
        let theaterState = observerTheaters()

        let frontLineState = FrontLineManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: 1
        )
        let deployment = WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: 1
        )

        return GameState(
            scenarioId: "observer_mode_integration",
            turn: 1,
            maxTurns: 20,
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
    }

    private static func observerMap() -> MapState {
        let specs: [(RegionId, Faction, [RegionId], [HexCoord])] = [
            ("ardennes", .germany, ["sedan"], [HexCoord(q: 0, r: 0), HexCoord(q: 1, r: 0), HexCoord(q: 2, r: 0), HexCoord(q: 1, r: 1)]),
            ("sedan", .allies, ["ardennes", "paris"], [HexCoord(q: 3, r: 0)]),
            ("paris", .allies, ["sedan"], [HexCoord(q: 4, r: 0), HexCoord(q: 4, r: 1)])
        ]
        var regions: [RegionId: RegionNode] = [:]
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        var edges: Set<RegionEdge> = []

        for (regionId, faction, neighbors, hexes) in specs {
            regions[regionId] = RegionNode(
                id: regionId,
                name: regionId.rawValue,
                owner: faction,
                controller: faction,
                terrain: .plain,
                neighbors: neighbors,
                displayHexes: hexes,
                representativeHex: hexes[0]
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

    private static func observerTheaters() -> TheaterState {
        TheaterState(
            theaters: [
                "germany_front": TheaterNode(
                    id: "germany_front",
                    name: "germany_front",
                    status: .active,
                    regionIds: ["ardennes"],
                    controllingFaction: .germany,
                    frontWeight: 1
                ),
                "france_front": TheaterNode(
                    id: "france_front",
                    name: "france_front",
                    status: .active,
                    regionIds: ["sedan", "paris"],
                    controllingFaction: .allies,
                    frontWeight: 2
                )
            ],
            regionToTheater: [
                "ardennes": "germany_front",
                "sedan": "france_front",
                "paris": "france_front"
            ]
        )
    }
}
