import XCTest
@testable import WWIIHexV0

final class MapEditorOutputTests: XCTestCase {
    func testEditorExportLoadsIntoGameStateAndBuildsWarLayers() throws {
        let document = makeProbeDocument()
        let result = try MapEditorExporter.export(
            document: document,
            scenarioFileName: "mapeditor_probe_scenario",
            regionFileName: "mapeditor_probe_regions"
        )

        XCTAssertEqual(result.regionDataSet.regions.count, 2)
        XCTAssertEqual(result.regionDataSet.edges.count, 1)
        XCTAssertTrue(result.regionDataSet.edges[0].hasRoad)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try MapEditorExporter.write(result, to: tempDirectory)

        let state = try DataLoader(resourceDirectory: tempDirectory).loadGameState(
            scenarioName: "mapeditor_probe_scenario",
            regionName: "mapeditor_probe_regions"
        )

        XCTAssertTrue(state.map.validateRegionGraph().isEmpty)
        XCTAssertEqual(state.map.hexToRegion[HexCoord(q: 0, r: 0)], RegionId("german_region"))
        XCTAssertEqual(state.map.hexToRegion[HexCoord(q: 3, r: 0)], RegionId("allied_region"))
        XCTAssertEqual(state.theaterState.regionToTheater[RegionId("german_region")], TheaterId("west_theater"))
        XCTAssertEqual(state.theaterState.regionToTheater[RegionId("allied_region")], TheaterId("east_theater"))
        XCTAssertFalse(state.frontLineState.frontLines.isEmpty)
        XCTAssertFalse(state.warDeploymentState.frontZones.isEmpty)
        XCTAssertEqual(Set(state.divisions.map(\.id)), ["ger_probe_1", "all_probe_1"])
    }

    func testGameResourceBridgeLoadsDefaultDataWithoutOverwriting() throws {
        let document = try MapEditorGameResourceBridge.loadDefaultDocument()

        XCTAssertEqual(document.id, "mapeditor_scenario")
        XCTAssertFalse(document.hexes.isEmpty)
        XCTAssertFalse(document.regions.isEmpty)
        XCTAssertFalse(document.initialUnits.isEmpty)

        let result = try MapEditorExporter.export(
            document: document,
            scenarioFileName: "mapeditor_bridge_scenario",
            regionFileName: "mapeditor_bridge_regions"
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try MapEditorExporter.write(result, to: tempDirectory)

        let state = try DataLoader(resourceDirectory: tempDirectory).loadGameState(
            scenarioName: "mapeditor_bridge_scenario",
            regionName: "mapeditor_bridge_regions"
        )

        XCTAssertTrue(state.map.validateRegionGraph().isEmpty)
        XCTAssertFalse(state.theaterState.theaters.isEmpty)
        XCTAssertFalse(state.frontLineState.frontLines.isEmpty)
    }

    func testDefaultEditorResourcesMatchGameStateRegionAndTheaterLayers() throws {
        let document = try MapEditorGameResourceBridge.loadDefaultDocument()
        let scenario = try DataLoader().loadScenarioDefinition(named: MapEditorGameResourceBridge.scenarioResourceName)
        let state = try DataLoader().loadGameState(
            scenarioName: MapEditorGameResourceBridge.scenarioResourceName,
            regionName: MapEditorGameResourceBridge.regionResourceName
        )

        XCTAssertEqual(state.activeFaction, .allies)
        XCTAssertEqual(state.phase, .alliedPlayer)

        let scenarioUnits = Dictionary(uniqueKeysWithValues: scenario.initialUnits.map {
            ($0.id, HexCoord(q: $0.coord.q, r: $0.coord.r))
        })
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: state.divisions.map { ($0.id, $0.coord) }), scenarioUnits)

        let documentHexToRegion = Dictionary(uniqueKeysWithValues: document.hexes.compactMap { coord, hex in
            hex.regionId.map { (coord, $0) }
        })
        XCTAssertEqual(state.map.hexToRegion, documentHexToRegion)

        let documentTheaterAssignments = document.regionTheaterAssignments
        XCTAssertEqual(state.theaterState.initialSnapshot?.regionToTheater, documentTheaterAssignments)
        XCTAssertEqual(state.theaterState.regionToTheater, documentTheaterAssignments)

        for (coord, hex) in document.hexes {
            XCTAssertEqual(state.map.tile(at: coord)?.regionId, hex.regionId, "Region mismatch at \(coord.mapEditorKey)")
        }

        for (regionId, draft) in document.regions {
            XCTAssertEqual(state.map.region(id: regionId)?.name, draft.name)
        }
    }

    func testDefaultOpeningUnitsDoNotStartInsideOpposingInitialTheater() throws {
        let state = try DataLoader().loadGameState(
            scenarioName: MapEditorGameResourceBridge.scenarioResourceName,
            regionName: MapEditorGameResourceBridge.regionResourceName
        )

        var factionsByTheater: [TheaterId: Set<Faction>] = [:]
        for division in state.divisions {
            guard let regionId = state.map.region(for: division.coord),
                  let theaterId = state.theaterState.initialSnapshot?.regionToTheater[regionId] else {
                XCTFail("Unit \(division.id) has no initial theater at \(division.coord)")
                continue
            }
            factionsByTheater[theaterId, default: []].insert(division.faction)
        }

        for (theaterId, factions) in factionsByTheater {
            XCTAssertEqual(factions.count, 1, "Initial theater \(theaterId.rawValue) has mixed factions: \(factions)")
        }
    }

    @MainActor
    func testAppBootstrapDoesNotRunAIOrMoveOpeningUnits() throws {
        let scenario = try DataLoader().loadScenarioDefinition(named: MapEditorGameResourceBridge.scenarioResourceName)
        let expectedCoords = Dictionary(uniqueKeysWithValues: scenario.initialUnits.map {
            ($0.id, HexCoord(q: $0.coord.q, r: $0.coord.r))
        })

        let container = AppContainer.bootstrap()

        XCTAssertEqual(container.gameState.activeFaction, .allies)
        XCTAssertEqual(container.gameState.phase, .alliedPlayer)
        XCTAssertTrue(container.lastWarDirectiveRecords.isEmpty)
        XCTAssertNil(container.lastAgentDecisionRecord)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: container.gameState.divisions.map { ($0.id, $0.coord) }), expectedCoords)
        XCTAssertEqual(container.gameState.division(id: "ger_editor_1")?.coord, HexCoord(q: 6, r: -1))
    }

    func testGameAndEditorHexLayoutsUseSameVerticalOrientation() {
        let editor = MapEditorHexLayout(hexSize: 36, origin: .zero)
        let game = HexLayout(hexSize: 36, origin: .zero)

        XCTAssertEqual(game.hexToPixel(HexCoord(q: 0, r: 1)).y, editor.center(for: HexCoord(q: 0, r: 1)).y, accuracy: 0.001)
        XCTAssertEqual(game.pixelToHex(editor.center(for: HexCoord(q: 4, r: -1))), HexCoord(q: 4, r: -1))
    }

    func testEditorSessionActionsReflectInGameState() throws {
        let viewModel = MapEditorViewModel(document: .new(id: "session_probe", displayName: "Session Probe", width: 4, height: 2))

        viewModel.mode = .hexPainter
        viewModel.selectedTerrain = .forest
        viewModel.paintRoad = true
        viewModel.paintController = .germany
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 0, r: 0))
        viewModel.applyPrimaryAction(at: HexCoord(q: 1, r: 0))
        viewModel.finishEditing()

        viewModel.selectedTerrain = .city
        viewModel.paintController = .allies
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 2, r: 0))
        viewModel.applyPrimaryAction(at: HexCoord(q: 3, r: 0))
        viewModel.finishEditing()

        viewModel.mode = .regionBuilder
        viewModel.newRegionText = "german_probe"
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 0, r: 0))
        viewModel.applyPrimaryAction(at: HexCoord(q: 1, r: 0))
        viewModel.applyPrimaryAction(at: HexCoord(q: 0, r: 1))
        viewModel.applyPrimaryAction(at: HexCoord(q: 1, r: 1))
        viewModel.finishEditing()

        viewModel.newRegionText = "allied_probe"
        viewModel.selectedRegionId = nil
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 2, r: 0))
        viewModel.applyPrimaryAction(at: HexCoord(q: 3, r: 0))
        viewModel.applyPrimaryAction(at: HexCoord(q: 2, r: 1))
        viewModel.applyPrimaryAction(at: HexCoord(q: 3, r: 1))
        viewModel.finishEditing()

        viewModel.mode = .theaterAssignment
        viewModel.newTheaterText = "west_probe"
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 0, r: 0))
        viewModel.finishEditing()

        viewModel.newTheaterText = "east_probe"
        viewModel.selectedTheaterId = nil
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 2, r: 0))
        viewModel.finishEditing()

        viewModel.mode = .unitPlanner
        viewModel.selectedUnitTemplateId = "panzer_division"
        viewModel.selectedUnitFaction = .germany
        viewModel.newUnitNameText = "测试装甲师"
        viewModel.beginAdding()
        viewModel.applyPrimaryAction(at: HexCoord(q: 1, r: 0))
        viewModel.finishEditing()

        let result = try XCTUnwrap(viewModel.export())
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try MapEditorExporter.write(result, to: tempDirectory)

        let state = try DataLoader(resourceDirectory: tempDirectory).loadGameState(
            scenarioName: result.scenarioFileName,
            regionName: result.regionFileName
        )

        XCTAssertEqual(state.map.tile(at: HexCoord(q: 0, r: 0))?.baseTerrain, .forest)
        XCTAssertEqual(state.map.tile(at: HexCoord(q: 2, r: 0))?.baseTerrain, .city)
        XCTAssertEqual(result.regionDataSet.regions.first(where: { $0.id == RegionId("region_1") })?.name, "german_probe")
        XCTAssertEqual(result.regionDataSet.regions.first(where: { $0.id == RegionId("region_2") })?.name, "allied_probe")
        XCTAssertEqual(state.map.hexToRegion[HexCoord(q: 0, r: 0)], RegionId("region_1"))
        XCTAssertEqual(state.map.hexToRegion[HexCoord(q: 2, r: 0)], RegionId("region_2"))
        XCTAssertEqual(viewModel.document.theaters[TheaterId("theater_1")]?.name, "west_probe")
        XCTAssertEqual(viewModel.document.theaters[TheaterId("theater_2")]?.name, "east_probe")
        XCTAssertEqual(state.theaterState.regionToTheater[RegionId("region_1")], TheaterId("theater_1"))
        XCTAssertEqual(state.theaterState.regionToTheater[RegionId("region_2")], TheaterId("theater_2"))
        XCTAssertEqual(state.divisions.first?.coord, HexCoord(q: 1, r: 0))
        XCTAssertEqual(state.divisions.first?.components.first?.type, .tank)

        let sparseViewModel = MapEditorViewModel(document: .new(id: "sparse_probe", displayName: "Sparse Probe", width: 1, height: 1))
        sparseViewModel.beginExtendingHexes()
        sparseViewModel.applyPrimaryAction(at: HexCoord(q: 4, r: 4))
        XCTAssertNil(sparseViewModel.document.hexes[HexCoord(q: 4, r: 4)])
        sparseViewModel.applyPrimaryAction(at: HexCoord(q: 1, r: 0))
        XCTAssertEqual(sparseViewModel.document.hexes[HexCoord(q: 1, r: 0)]?.terrain, .plain)
        sparseViewModel.beginDeleting()
        sparseViewModel.applyPrimaryAction(at: HexCoord(q: 1, r: 0))
        XCTAssertNil(sparseViewModel.document.hexes[HexCoord(q: 1, r: 0)])
        XCTAssertNotNil(sparseViewModel.document.hexes[HexCoord(q: 0, r: 0)])

        let panned = MapEditorViewportMath.cameraPositionAfterPan(
            currentPosition: CGPoint(x: 10, y: 20),
            previousViewPoint: CGPoint(x: 100, y: 100),
            currentViewPoint: CGPoint(x: 130, y: 90),
            scale: 2
        )
        XCTAssertEqual(panned.x, -50, accuracy: 0.001)
        XCTAssertEqual(panned.y, 40, accuracy: 0.001)

        let zoomed = MapEditorViewportMath.cameraPositionAfterZoom(
            currentPosition: CGPoint(x: 0, y: 0),
            anchor: CGPoint(x: 100, y: 0),
            oldScale: 1,
            newScale: 2
        )
        XCTAssertEqual(zoomed.x, -100, accuracy: 0.001)
        XCTAssertEqual(zoomed.y, 0, accuracy: 0.001)

        let shortcutViewModel = MapEditorViewModel(document: .new(id: "shortcut_probe", displayName: "Shortcut Probe", width: 1, height: 1))
        XCTAssertTrue(shortcutViewModel.handleShortcut("n"))
        XCTAssertEqual(shortcutViewModel.editAction, .adding)
        XCTAssertTrue(shortcutViewModel.handleShortcut("m"))
        XCTAssertEqual(shortcutViewModel.editAction, .idle)

        var inspectDocument = MapEditorDocument.new(id: "inspect_probe", displayName: "Inspect Probe", width: 1, height: 1)
        let inspectRegion = RegionId("region_1")
        let inspectTheater = TheaterId("theater_1")
        inspectDocument.createRegion(id: inspectRegion, name: "Old Region")
        inspectDocument.createTheater(id: inspectTheater, name: "Old Theater")
        inspectDocument.assign(HexCoord(q: 0, r: 0), to: inspectRegion)
        inspectDocument.assign(regionId: inspectRegion, to: inspectTheater)

        let inspectViewModel = MapEditorViewModel(document: inspectDocument)
        inspectViewModel.inspect(at: HexCoord(q: 0, r: 0))
        XCTAssertEqual(inspectViewModel.inspectedRegionName, "Old Region")
        XCTAssertEqual(inspectViewModel.inspectedTheaterName, "Old Theater")
        inspectViewModel.inspectedRegionName = "New Region"
        inspectViewModel.inspectedTheaterName = "New Theater"
        inspectViewModel.saveInspectedInfo()
        XCTAssertEqual(inspectViewModel.document.regions[inspectRegion]?.name, "New Region")
        XCTAssertEqual(inspectViewModel.document.theaters[inspectTheater]?.name, "New Theater")

        inspectViewModel.backgroundOpacity = 0.3
        inspectViewModel.backgroundScale = 1.7
        inspectViewModel.backgroundOffsetX = 12
        inspectViewModel.backgroundOffsetY = -9
        inspectViewModel.setBackgroundImage(path: "/tmp/mapeditor_probe.png")
        XCTAssertEqual(inspectViewModel.document.backgroundImage?.filePath, "/tmp/mapeditor_probe.png")
        inspectViewModel.moveBackgroundBy(deltaX: 3, deltaY: 4)
        XCTAssertEqual(inspectViewModel.document.backgroundImage?.positionX, 15)
        XCTAssertEqual(inspectViewModel.document.backgroundImage?.positionY, -5)
    }

    private func makeProbeDocument() -> MapEditorDocument {
        var document = MapEditorDocument.new(
            id: "mapeditor_probe",
            displayName: "MapEditor Probe",
            width: 4,
            height: 2
        )
        let germanRegion = RegionId("german_region")
        let alliedRegion = RegionId("allied_region")
        let westTheater = TheaterId("west_theater")
        let eastTheater = TheaterId("east_theater")
        document.createRegion(id: germanRegion, name: "German Region", controller: .germany)
        document.createRegion(id: alliedRegion, name: "Allied Region", controller: .allies)
        document.createTheater(id: westTheater, name: "West Theater")
        document.createTheater(id: eastTheater, name: "East Theater")

        for q in 0..<4 {
            for r in 0..<2 {
                let coord = HexCoord(q: q, r: r)
                guard var hex = document.hexes[coord] else { continue }
                hex.hasRoad = true
                hex.controller = q < 2 ? .germany : .allies
                if coord == HexCoord(q: 0, r: 0) {
                    hex.isSupplySource = true
                    hex.supplyFaction = .germany
                }
                if coord == HexCoord(q: 3, r: 1) {
                    hex.isSupplySource = true
                    hex.supplyFaction = .allies
                }
                document.setHex(hex)
                document.assign(coord, to: q < 2 ? germanRegion : alliedRegion)
            }
        }

        document.assign(regionId: germanRegion, to: westTheater)
        document.assign(regionId: alliedRegion, to: eastTheater)
        document.initialUnits = [
            MapEditorUnitDraft(
                id: "ger_probe_1",
                name: "Probe Panzer",
                faction: .germany,
                templateId: "panzer_division",
                coord: HexCoord(q: 1, r: 0),
                facing: .east
            ),
            MapEditorUnitDraft(
                id: "all_probe_1",
                name: "Probe Infantry",
                faction: .allies,
                templateId: "infantry_division",
                coord: HexCoord(q: 2, r: 0),
                facing: .west
            )
        ]
        return document
    }
}
