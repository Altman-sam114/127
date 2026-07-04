import XCTest
import SpriteKit
@testable import WWIIHexV0

final class LayeredMapUIStateTests: XCTestCase {
    func testOverlayBucketsMatchRegionTheaterAndFrontLineState() {
        let state = Self.layeredState()
        let calculator = MapLayerOverlayCalculator(state: state)

        for (hex, regionId) in state.map.hexToRegion {
            XCTAssertEqual(calculator.bucket(for: hex, layer: .province).bucketId, regionId.rawValue)
            XCTAssertEqual(
                calculator.bucket(for: hex, layer: .dynamicTheater).bucketId,
                state.theaterState.regionToTheater[regionId]?.rawValue
            )
            XCTAssertEqual(
                calculator.bucket(for: hex, layer: .initialTheater).bucketId,
                state.theaterState.initialSnapshot?.regionToTheater[regionId]?.rawValue
            )

            let expectedFrontBucket = state.frontLineState.regionStates[regionId]?.frontLines
                .map(\.id.rawValue)
                .sorted()
                .joined(separator: "+")
            XCTAssertEqual(calculator.bucket(for: hex, layer: .frontLine).bucketId, expectedFrontBucket?.isEmpty == true ? nil : expectedFrontBucket)
        }
    }

    func testRegionOwnerChangeUpdatesOverlayAndLogsEvent() {
        let state = Self.layeredState()
        let directive = ZoneDirective(
            zoneId: "germany_front",
            attack: AttackParameters(
                targetTheaterId: "france_front",
                weightedRegions: ["sedan"],
                intensity: .allOut
            )
        )

        let result = WarCommandExecutor().execute(directive, in: state)
        let calculator = MapLayerOverlayCalculator(state: result.finalState)

        XCTAssertEqual(result.finalState.map.regions["sedan"]?.controller, .germany)
        XCTAssertEqual(
            calculator.bucket(for: HexCoord(q: 2, r: 0), layer: .province).bucketId,
            "sedan"
        )
        XCTAssertTrue(result.finalState.eventLog.contains {
            [.regionOwnerChange, .theaterChange, .frontChange].contains($0.category) &&
                $0.relatedRecordId == "war_directive_germany_front_attack" &&
                $0.message.contains("sedan")
        })
    }

    func testDeploymentLayerBucketsUseFactionAndDeploymentRole() {
        let frontHex = HexCoord(q: 1, r: 0)
        let depthHex = HexCoord(q: 0, r: 0)
        var state = Self.layeredState(
            divisions: [
                Division.infantry(id: "front", name: "front", faction: .germany, coord: frontHex),
                Division.infantry(id: "depth", name: "depth", faction: .germany, coord: depthHex)
            ]
        )
        state.warDeploymentState.frontZones["germany_front"]?.unitsFront = ["front"]
        state.warDeploymentState.frontZones["germany_front"]?.unitsDepth = ["depth"]

        let calculator = MapLayerOverlayCalculator(state: state)

        XCTAssertEqual(calculator.bucket(for: frontHex, layer: .deployment).bucketId, "germany_frontUnit")
        XCTAssertEqual(calculator.bucket(for: depthHex, layer: .deployment).bucketId, "germany_depthUnit")
    }

    func testInspectorStatesExposeHexDynamicTheaterAndDeploymentData() {
        let selectedHex = HexCoord(q: 1, r: 0)
        let state = Self.layeredState()
        let adapter = MapDisplayAdapter(state: state, revealAll: true)
        let regionState = adapter.inspectorState(for: "ardennes", selectedHex: selectedHex, viewerFaction: .germany)
        let division = try! XCTUnwrap(state.division(id: "german_0"))
        let unitState = adapter.unitInspectorState(for: division)

        XCTAssertEqual(regionState?.selectedHex, selectedHex)
        XCTAssertEqual(regionState?.selectedHexController, .germany)
        XCTAssertEqual(regionState?.selectedHexDynamicTheaterId, "germany_front")
        XCTAssertEqual(regionState?.selectedHexFrontZoneId, "germany_front")
        XCTAssertEqual(unitState.coord, selectedHex)
        XCTAssertEqual(unitState.regionId, "ardennes")
        XCTAssertEqual(unitState.dynamicTheaterId, "germany_front")
        XCTAssertEqual(unitState.frontZoneId, "germany_front")
        XCTAssertEqual(unitState.deploymentRole, .frontUnit)
        XCTAssertFalse(unitState.frontLineIds.isEmpty)
    }

    func testRevealAllObserverModeShowsFoggedEnemyUnits() {
        let state = RegionRuleTestFixtures.state(
            divisions: [
                RegionRuleTestFixtures.division(id: "allied", faction: .allies, coord: HexCoord(q: 0, r: 0)),
                RegionRuleTestFixtures.division(id: "german", faction: .germany, coord: HexCoord(q: 4, r: 0))
            ]
        )

        let normalPlacements = MapDisplayAdapter(state: state, revealAll: false).unitPlacements(viewerFaction: .allies)
        let observerPlacements = MapDisplayAdapter(state: state, revealAll: true).unitPlacements(viewerFaction: .allies)

        XCTAssertNil(normalPlacements["german"])
        XCTAssertNotNil(observerPlacements["german"])
        XCTAssertEqual(MapDisplayAdapter(state: state, revealAll: true).visibility(for: HexCoord(q: 4, r: 0), faction: .allies), .visible)
    }

    func testStrategicOverlayColorsAreUniqueWithinLayer() {
        let state = Self.multiBucketColorState()
        let layout = HexLayout(hexSize: 32, origin: .zero)

        for layer in [MapDisplayLayer.province, .initialTheater, .dynamicTheater] {
            let node = MapLayerOverlayNode(state: state, layer: layer, layout: layout)
            let colorKeys = node.children
                .compactMap { $0 as? SKShapeNode }
                .filter { $0.zPosition == 11 }
                .compactMap { Self.colorKey($0.fillColor) }
            let bucketIds = Set(MapLayerOverlayCalculator(state: state).buckets(layer: layer).values.compactMap(\.bucketId))

            XCTAssertEqual(Set(colorKeys).count, bucketIds.count, "\(layer.rawValue) overlay colors must not collapse buckets together.")
        }
    }

    func testDefaultMapStrategicOverlayColorsAreUniqueWithinLayer() throws {
        let state = try DataLoader().loadGameState(
            scenarioName: MapEditorGameResourceBridge.scenarioResourceName,
            regionName: MapEditorGameResourceBridge.regionResourceName
        )
        let layout = HexLayout.fixed(mapWidth: state.map.width, mapHeight: state.map.height)

        for layer in [MapDisplayLayer.province, .initialTheater, .dynamicTheater] {
            let node = MapLayerOverlayNode(state: state, layer: layer, layout: layout)
            let overlayShapes = node.children
                .compactMap { $0 as? SKShapeNode }
                .filter { $0.zPosition == 11 }
            let colorKeys = overlayShapes
                .compactMap { Self.colorKey($0.fillColor) }
            let bucketIds = Set(MapLayerOverlayCalculator(state: state).buckets(layer: layer).values.compactMap(\.bucketId))

            XCTAssertEqual(Set(colorKeys).count, bucketIds.count, "\(layer.rawValue) default map overlay colors must not collapse buckets together.")
            XCTAssertTrue(overlayShapes.allSatisfy { $0.lineWidth > 0 }, "\(layer.rawValue) overlay should keep visible hex dividers.")
        }
    }

    private static func layeredState(
        divisions: [Division] = [
            Division.infantry(
                id: "german_0",
                name: "german_0",
                faction: .germany,
                coord: HexCoord(q: 1, r: 0)
            )
        ]
    ) -> GameState {
        let map = layeredMap()
        var theaterState = layeredTheaters()
        theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: theaterState)

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
            scenarioId: "layered_ui_state",
            turn: 1,
            maxTurns: 4,
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

    private static func layeredMap() -> MapState {
        let specs: [(RegionId, Faction, [RegionId], [HexCoord])] = [
            ("ardennes", .germany, ["sedan"], [HexCoord(q: 0, r: 0), HexCoord(q: 1, r: 0)]),
            ("sedan", .allies, ["ardennes"], [HexCoord(q: 2, r: 0)])
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
            width: 3,
            height: 1,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: edges
        )
    }

    private static func layeredTheaters() -> TheaterState {
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
                    regionIds: ["sedan"],
                    controllingFaction: .allies,
                    frontWeight: 1
                )
            ],
            regionToTheater: [
                "ardennes": "germany_front",
                "sedan": "france_front"
            ]
        )
    }

    private static func multiBucketColorState() -> GameState {
        let hexes = [
            HexCoord(q: 0, r: 0),
            HexCoord(q: 1, r: 0),
            HexCoord(q: 0, r: 1),
            HexCoord(q: 1, r: 1)
        ]
        let regions: [RegionId] = ["r0", "r1", "r2", "r3"]
        let theaters: [TheaterId] = ["t0", "t1", "t2", "t3"]
        var tiles: [HexCoord: HexTile] = [:]
        var regionNodes: [RegionId: RegionNode] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        var theaterNodes: [TheaterId: TheaterNode] = [:]
        var regionToTheater: [RegionId: TheaterId] = [:]
        var hexToTheater: [HexCoord: TheaterId] = [:]

        for index in hexes.indices {
            let faction: Faction = index < 2 ? .germany : .allies
            let hex = hexes[index]
            let regionId = regions[index]
            let theaterId = theaters[index]
            tiles[hex] = HexTile(coord: hex, baseTerrain: .plain, controller: faction, regionId: regionId)
            hexToRegion[hex] = regionId
            regionNodes[regionId] = RegionNode(
                id: regionId,
                name: regionId.rawValue,
                owner: faction,
                controller: faction,
                terrain: .plain,
                neighbors: [],
                displayHexes: [hex],
                representativeHex: hex
            )
            theaterNodes[theaterId] = TheaterNode(
                id: theaterId,
                name: theaterId.rawValue,
                status: .active,
                regionIds: [regionId],
                controllingFaction: faction
            )
            regionToTheater[regionId] = theaterId
            hexToTheater[hex] = theaterId
        }

        let map = MapState(
            width: 2,
            height: 2,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regionNodes,
            hexToRegion: hexToRegion,
            regionEdges: []
        )
        var theaterState = TheaterState(
            theaters: theaterNodes,
            hexToTheater: hexToTheater,
            regionToTheater: regionToTheater
        )
        theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: theaterState)
        return GameState(
            scenarioId: "v03510_color_unique",
            turn: 1,
            maxTurns: 2,
            activeFaction: .germany,
            phase: .germanAI,
            map: map,
            theaterState: theaterState,
            frontLineState: .empty,
            warDeploymentState: .empty,
            divisions: [],
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
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
