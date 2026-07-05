import Foundation

enum MapEditorGameResourceBridgeError: Error, CustomStringConvertible {
    case missingTerrain(String)
    case missingResource(URL)

    var description: String {
        switch self {
        case .missingTerrain(let terrain):
            return "Unknown terrain in game data: \(terrain)."
        case .missingResource(let url):
            return "Missing resource: \(url.path)."
        }
    }
}

enum MapEditorGameResourceBridge {
    static let scenarioResourceName = "grey_tide_2030_scenario"
    static let regionResourceName = "grey_tide_2030_regions"

    static var gameDataDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "WWIIHexV0")
            .appending(path: "Data")
    }

    static func loadDefaultDocument() throws -> MapEditorDocument {
        let resources = try loadDefaultDefinitions()
        return try makeDocument(scenario: resources.scenario, regionData: resources.regionData)
    }

    static func overwriteDefaultGameResources(document: MapEditorDocument) throws -> MapEditorExportResult {
        let existing = try loadDefaultDefinitions()
        let result = try MapEditorExporter.export(
            document: document,
            scenarioFileName: scenarioResourceName,
            regionFileName: regionResourceName
        )
        let preserved = try preserveDefaultMetadata(
            in: result,
            existingScenario: existing.scenario,
            existingRegionData: existing.regionData
        )
        try MapEditorExporter.write(preserved, to: gameDataDirectory)
        return preserved
    }

    private static func loadDefaultDefinitions() throws -> (scenario: ScenarioDefinition, regionData: RegionDataSet) {
        let scenarioURL = gameDataDirectory.appending(path: scenarioResourceName).appendingPathExtension("json")
        let regionURL = gameDataDirectory.appending(path: regionResourceName).appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: scenarioURL.path) else {
            throw MapEditorGameResourceBridgeError.missingResource(scenarioURL)
        }
        guard FileManager.default.fileExists(atPath: regionURL.path) else {
            throw MapEditorGameResourceBridgeError.missingResource(regionURL)
        }

        let decoder = JSONDecoder()
        let scenario = try decoder.decode(ScenarioDefinition.self, from: Data(contentsOf: scenarioURL))
        let regionData = try decoder.decode(RegionDataSet.self, from: Data(contentsOf: regionURL))
        return (scenario, regionData)
    }

    private static func preserveDefaultMetadata(
        in result: MapEditorExportResult,
        existingScenario: ScenarioDefinition,
        existingRegionData: RegionDataSet
    ) throws -> MapEditorExportResult {
        let scenario = preserveScenarioMetadata(
            exported: result.scenarioDefinition,
            existing: existingScenario
        )
        let regionData = preserveRegionMetadata(
            exported: result.regionDataSet,
            existing: existingRegionData
        )
        return try makeResult(
            scenarioFileName: result.scenarioFileName,
            regionFileName: result.regionFileName,
            scenario: scenario,
            regionData: regionData
        )
    }

    private static func makeResult(
        scenarioFileName: String,
        regionFileName: String,
        scenario: ScenarioDefinition,
        regionData: RegionDataSet
    ) throws -> MapEditorExportResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return MapEditorExportResult(
            scenarioFileName: scenarioFileName,
            regionFileName: regionFileName,
            scenarioDefinition: scenario,
            regionDataSet: regionData,
            scenarioData: try encoder.encode(scenario),
            regionData: try encoder.encode(regionData)
        )
    }

    private static func preserveScenarioMetadata(
        exported: ScenarioDefinition,
        existing: ScenarioDefinition
    ) -> ScenarioDefinition {
        let existingTilesByCoord = Dictionary(uniqueKeysWithValues: existing.map.tiles.map {
            ($0.coord, $0)
        })
        let tiles = exported.map.tiles.map { tile -> ScenarioTileDefinition in
            let existingTile = existingTilesByCoord[tile.coord]
            return ScenarioTileDefinition(
                q: tile.q,
                r: tile.r,
                terrain: tile.terrain,
                hasRoad: tile.hasRoad,
                riverEdges: existingTile?.riverEdges ?? tile.riverEdges,
                controller: tile.controller,
                cityName: tile.cityName,
                fortressName: tile.fortressName,
                isSupplySource: tile.isSupplySource,
                supplyFaction: tile.supplyFaction,
                objectiveId: tile.objectiveId,
                regionId: tile.regionId
            )
        }
        let existingObjectivesById = Dictionary(uniqueKeysWithValues: existing.objectives.map {
            ($0.id, $0)
        })
        let objectives = exported.objectives.map { objective -> ObjectiveDefinition in
            guard let existingObjective = existingObjectivesById[objective.id] else {
                return objective
            }
            return ObjectiveDefinition(
                id: objective.id,
                name: objective.name,
                kind: objective.kind,
                coord: objective.coord,
                points: existingObjective.points
            )
        }
        return ScenarioDefinition(
            schemaVersion: max(existing.schemaVersion, exported.schemaVersion),
            id: exported.id,
            displayName: exported.displayName,
            map: ScenarioMapDefinition(
                width: exported.map.width,
                height: exported.map.height,
                coordinateSystem: exported.map.coordinateSystem,
                isSparse: exported.map.isSparse,
                tiles: tiles
            ),
            factions: stableUnique(exported.factions + existing.factions),
            maxTurns: existing.maxTurns,
            initialTurn: existing.initialTurn,
            initialPhase: existing.initialPhase,
            playerFaction: existing.playerFaction,
            aiFaction: existing.aiFaction,
            keyLocations: exported.keyLocations,
            objectives: objectives,
            initialUnits: exported.initialUnits,
            victoryConditions: existing.victoryConditions,
            dataNotes: stableUnique(existing.dataNotes + exported.dataNotes)
        )
    }

    private static func preserveRegionMetadata(
        exported: RegionDataSet,
        existing: RegionDataSet
    ) -> RegionDataSet {
        let existingRegionsById = Dictionary(uniqueKeysWithValues: existing.regions.map {
            ($0.id, $0)
        })
        let regions = exported.regions.map { region -> RegionNodeDefinition in
            guard let existingRegion = existingRegionsById[region.id] else {
                return region
            }
            let city = mergedCity(exported: region.city, existing: existingRegion.city)
            return RegionNodeDefinition(
                id: region.id,
                name: region.name,
                owner: region.owner,
                controller: region.controller,
                theaterId: region.theaterId,
                assignedGeneralId: region.assignedGeneralId,
                terrain: region.terrain,
                neighbors: region.neighbors,
                displayHexes: region.displayHexes,
                representativeHex: region.representativeHex,
                city: city,
                infrastructure: region.infrastructure,
                supplyValue: region.supplyValue,
                factories: region.factories,
                resources: existingRegion.resources,
                coreOf: region.coreOf,
                occupationState: existingRegion.occupationState,
                isPassable: existingRegion.isPassable
            )
        }
        let existingEdgesByKey = Dictionary(uniqueKeysWithValues: existing.edges.map {
            (edgeKey($0.from, $0.to), $0)
        })
        let edges = exported.edges.map { edge -> RegionEdgeDefinition in
            let existingEdge = existingEdgesByKey[edgeKey(edge.from, edge.to)]
            return RegionEdgeDefinition(
                from: edge.from,
                to: edge.to,
                hasRoad: edge.hasRoad,
                hasRiverCrossing: existingEdge?.hasRiverCrossing ?? edge.hasRiverCrossing,
                movementCostModifier: existingEdge?.movementCostModifier ?? edge.movementCostModifier
            )
        }
        let existingObjectivesById = Dictionary(uniqueKeysWithValues: existing.objectives.map {
            ($0.id, $0)
        })
        let objectives = exported.objectives.map { objective -> RegionObjectiveDefinition in
            guard let existingObjective = existingObjectivesById[objective.id] else {
                return objective
            }
            return RegionObjectiveDefinition(
                id: objective.id,
                name: objective.name,
                regionId: objective.regionId,
                type: objective.type,
                victoryPoints: existingObjective.victoryPoints,
                mainObjective: existingObjective.mainObjective
            )
        }
        return RegionDataSet(
            schemaVersion: max(existing.schemaVersion, exported.schemaVersion),
            scenarioId: exported.scenarioId,
            displayName: exported.displayName,
            hexToRegion: exported.hexToRegion,
            regions: regions,
            edges: edges,
            supplySources: exported.supplySources,
            objectives: objectives
        )
    }

    private static func mergedCity(
        exported: CityInfoDefinition?,
        existing: CityInfoDefinition?
    ) -> CityInfoDefinition? {
        guard let exported else {
            return nil
        }
        return CityInfoDefinition(
            name: exported.name,
            victoryPoints: existing?.victoryPoints ?? exported.victoryPoints,
            isCapital: existing?.isCapital ?? exported.isCapital
        )
    }

    private static func edgeKey(_ lhs: RegionId, _ rhs: RegionId) -> String {
        [lhs.rawValue, rhs.rawValue].sorted().joined(separator: "|")
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func makeDocument(
        scenario: ScenarioDefinition,
        regionData: RegionDataSet
    ) throws -> MapEditorDocument {
        let regionMapping = regionData.toHexToRegion()
        var hexes: [HexCoord: MapEditorHex] = [:]
        for tile in scenario.map.tiles {
            let coord = HexCoord(q: tile.q, r: tile.r)
            guard let terrain = BaseTerrain(rawValue: tile.terrain) else {
                throw MapEditorGameResourceBridgeError.missingTerrain(tile.terrain)
            }
            hexes[coord] = MapEditorHex(
                coord: coord,
                terrain: terrain,
                hasRoad: tile.hasRoad,
                controller: Faction.dataValue(tile.controller),
                cityName: tile.cityName,
                fortressName: tile.fortressName,
                isSupplySource: tile.isSupplySource,
                supplyFaction: Faction.dataValue(tile.supplyFaction),
                objectiveId: tile.objectiveId,
                regionId: regionMapping[coord] ?? tile.regionId.map { RegionId($0) }
            )
        }

        let regions = Dictionary(uniqueKeysWithValues: regionData.regions.map { definition in
            (
                definition.id,
                MapEditorRegionDraft(
                    id: definition.id,
                    name: definition.name,
                    owner: definition.owner,
                    controller: definition.controller,
                    infrastructure: definition.infrastructure,
                    supplyValue: definition.supplyValue,
                    factories: definition.factories,
                    coreOf: definition.coreOf,
                    assignedGeneralId: definition.assignedGeneralId
                )
            )
        })
        let regionTheaterAssignments = Dictionary(uniqueKeysWithValues: regionData.regions.compactMap { definition in
            definition.theaterId.map { (definition.id, $0) }
        })
        let theaters = Dictionary(uniqueKeysWithValues: Set(regionTheaterAssignments.values).map { theaterId in
            (theaterId, MapEditorTheaterDraft(id: theaterId))
        })
        let units = scenario.initialUnits.map { unit in
            MapEditorUnitDraft(
                id: unit.id,
                name: unit.name,
                faction: Faction.dataValue(unit.faction) ?? .blueForce,
                templateId: unit.templateId,
                coord: HexCoord(q: unit.coord.q, r: unit.coord.r),
                facing: HexDirection(rawValue: unit.facing) ?? .west,
                hp: unit.hp,
                retreatMode: unit.retreatMode.flatMap(RetreatMode.init(rawValue:)) ?? .retreatable,
                supplyState: SupplyState(rawValue: unit.supplyState) ?? .supplied,
                assignedAgentId: unit.assignedAgentId
            )
        }

        return MapEditorDocument(
            id: scenario.id,
            displayName: scenario.displayName,
            width: scenario.map.width,
            height: scenario.map.height,
            hexes: hexes,
            regions: regions,
            theaters: theaters,
            regionTheaterAssignments: regionTheaterAssignments,
            initialUnits: units
        )
    }
}
