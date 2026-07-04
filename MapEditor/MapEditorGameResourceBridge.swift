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
        return try makeDocument(scenario: scenario, regionData: regionData)
    }

    static func overwriteDefaultGameResources(document: MapEditorDocument) throws -> MapEditorExportResult {
        let result = try MapEditorExporter.export(
            document: document,
            scenarioFileName: scenarioResourceName,
            regionFileName: regionResourceName
        )
        try MapEditorExporter.write(result, to: gameDataDirectory)
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
                faction: Faction.dataValue(unit.faction) ?? .allies,
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
