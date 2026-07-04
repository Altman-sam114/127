import Foundation

struct MapEditorExportResult: Equatable {
    let scenarioFileName: String
    let regionFileName: String
    let scenarioDefinition: ScenarioDefinition
    let regionDataSet: RegionDataSet
    let scenarioData: Data
    let regionData: Data
}

enum MapEditorExportError: Error, CustomStringConvertible, Equatable {
    case unassignedHex(HexCoord)
    case emptyRegion(RegionId)
    case missingRegion(RegionId)
    case invalidTerrain(BaseTerrain)
    case encodingFailed(String)

    var description: String {
        switch self {
        case .unassignedHex(let coord):
            return "Hex \(coord.mapEditorKey) is not assigned to a region."
        case .emptyRegion(let id):
            return "Region \(id.rawValue) has no hexes."
        case .missingRegion(let id):
            return "Region \(id.rawValue) is referenced but not defined."
        case .invalidTerrain(let terrain):
            return "Terrain \(terrain.rawValue) cannot be exported."
        case .encodingFailed(let message):
            return "Encoding failed: \(message)"
        }
    }
}

enum MapEditorExporter {
    static func export(
        document: MapEditorDocument,
        scenarioFileName: String? = nil,
        regionFileName: String? = nil
    ) throws -> MapEditorExportResult {
        try validateAssignable(document)
        let regionDataSet = try makeRegionDataSet(from: document)
        let scenarioDefinition = makeScenarioDefinition(from: document)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return MapEditorExportResult(
                scenarioFileName: scenarioFileName ?? "\(document.id)_scenario",
                regionFileName: regionFileName ?? "\(document.id)_regions",
                scenarioDefinition: scenarioDefinition,
                regionDataSet: regionDataSet,
                scenarioData: try encoder.encode(scenarioDefinition),
                regionData: try encoder.encode(regionDataSet)
            )
        } catch {
            throw MapEditorExportError.encodingFailed(error.localizedDescription)
        }
    }

    static func write(_ result: MapEditorExportResult, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try result.scenarioData.write(
            to: directory.appendingPathComponent(result.scenarioFileName).appendingPathExtension("json"),
            options: .atomic
        )
        try result.regionData.write(
            to: directory.appendingPathComponent(result.regionFileName).appendingPathExtension("json"),
            options: .atomic
        )
    }

    private static func validateAssignable(_ document: MapEditorDocument) throws {
        for hex in document.sortedHexes where hex.regionId == nil {
            throw MapEditorExportError.unassignedHex(hex.coord)
        }

        for regionId in Set(document.hexes.values.compactMap(\.regionId)) where document.regions[regionId] == nil {
            throw MapEditorExportError.missingRegion(regionId)
        }
    }

    private static func makeScenarioDefinition(from document: MapEditorDocument) -> ScenarioDefinition {
        let objectives = document.sortedHexes.compactMap { hex -> ObjectiveDefinition? in
            guard let objectiveId = hex.objectiveId else { return nil }
            return ObjectiveDefinition(
                id: objectiveId,
                name: hex.cityName ?? hex.fortressName ?? objectiveId,
                kind: hex.terrain == .fortress ? ObjectiveType.fortress.rawValue : ObjectiveType.city.rawValue,
                coord: HexCoordDefinition(q: hex.coord.q, r: hex.coord.r),
                points: 1
            )
        }

        let keyLocations = document.sortedHexes.compactMap { hex -> KeyLocationDefinition? in
            guard hex.cityName != nil || hex.fortressName != nil || hex.isSupplySource else { return nil }
            let name = hex.cityName ?? hex.fortressName ?? "Supply \(hex.coord.mapEditorKey)"
            return KeyLocationDefinition(
                id: name.normalizedMapEditorIdentifier,
                name: name,
                kind: hex.isSupplySource ? ObjectiveType.supply.rawValue : hex.terrain.rawValue,
                coord: HexCoordDefinition(q: hex.coord.q, r: hex.coord.r),
                faction: hex.supplyFaction?.rawValue ?? hex.controller?.rawValue,
                objectiveId: hex.objectiveId
            )
        }
        let controlledFactions: [Faction] = document.sortedHexes.compactMap(\.controller)
        let supplyFactions: [Faction] = document.sortedHexes.compactMap(\.supplyFaction)
        let unitFactions: [Faction] = document.initialUnits.map(\.faction)
        var documentFactions = Set<Faction>()
        documentFactions.formUnion(controlledFactions)
        documentFactions.formUnion(supplyFactions)
        documentFactions.formUnion(unitFactions)
        documentFactions.formUnion([.blueForce, .redForce, .neutral])
        let exportedFactions = documentFactions
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)

        return ScenarioDefinition(
            schemaVersion: 2,
            id: document.id,
            displayName: document.displayName,
            map: ScenarioMapDefinition(
                width: document.width,
                height: document.height,
                coordinateSystem: "axial-q-r",
                isSparse: document.isSparse,
                tiles: document.sortedHexes.map { hex in
                    ScenarioTileDefinition(
                        q: hex.coord.q,
                        r: hex.coord.r,
                        terrain: hex.terrain.rawValue,
                        hasRoad: hex.hasRoad,
                        riverEdges: [],
                        controller: hex.controller?.rawValue ?? "neutral",
                        cityName: hex.cityName,
                        fortressName: hex.fortressName,
                        isSupplySource: hex.isSupplySource,
                        supplyFaction: hex.supplyFaction?.rawValue,
                        objectiveId: hex.objectiveId,
                        regionId: hex.regionId?.rawValue
                    )
                }
            ),
            factions: exportedFactions,
            maxTurns: 12,
            initialTurn: 1,
            initialPhase: GamePhase.alliedPlayer.rawValue,
            playerFaction: Faction.blueForce.rawValue,
            aiFaction: Faction.redForce.rawValue,
            keyLocations: keyLocations,
            objectives: objectives,
            initialUnits: document.initialUnits.map { unit in
                InitialUnitDefinition(
                    id: unit.id,
                    name: unit.name,
                    faction: unit.faction.rawValue,
                    templateId: unit.templateId,
                    coord: HexCoordDefinition(q: unit.coord.q, r: unit.coord.r),
                    facing: unit.facing.rawValue,
                    hp: unit.hp,
                    retreatMode: unit.retreatMode.rawValue,
                    supplyState: unit.supplyState.rawValue,
                    assignedAgentId: unit.assignedAgentId
                )
            },
            victoryConditions: [],
            dataNotes: [
                "Generated by MapEditor v0.34.",
                "Region neighbors, road edges, and representative hexes are derived at export time."
            ]
        )
    }

    private static func makeRegionDataSet(from document: MapEditorDocument) throws -> RegionDataSet {
        let hexesByRegion = Dictionary(grouping: document.sortedHexes) { $0.regionId }
        var neighborMap: [RegionId: Set<RegionId>] = [:]
        var edgeRoadFlags: [String: Bool] = [:]

        for hex in document.sortedHexes {
            guard let regionA = hex.regionId else { continue }
            for neighborCoord in hex.coord.neighbors {
                guard let neighborHex = document.hexes[neighborCoord],
                      let regionB = neighborHex.regionId,
                      regionA != regionB else {
                    continue
                }

                neighborMap[regionA, default: []].insert(regionB)
                neighborMap[regionB, default: []].insert(regionA)
                let key = edgeKey(regionA, regionB)
                edgeRoadFlags[key] = (edgeRoadFlags[key] ?? false) || (hex.hasRoad && neighborHex.hasRoad)
            }
        }

        let regionDefinitions = try document.regions.values.sorted { $0.id.rawValue < $1.id.rawValue }.map { draft in
            guard let regionHexes = hexesByRegion[draft.id], !regionHexes.isEmpty else {
                throw MapEditorExportError.emptyRegion(draft.id)
            }

            let representativeHex = representativeHex(for: regionHexes)
            let terrain = dominantTerrain(in: regionHexes)
            let cityHex = regionHexes.first { $0.cityName != nil || $0.terrain == .city || $0.fortressName != nil }
            return RegionNodeDefinition(
                id: draft.id,
                name: draft.name,
                owner: draft.owner,
                controller: draft.controller,
                theaterId: document.regionTheaterAssignments[draft.id],
                assignedGeneralId: draft.assignedGeneralId,
                terrain: terrain,
                neighbors: (neighborMap[draft.id] ?? []).sorted { $0.rawValue < $1.rawValue },
                displayHexes: regionHexes.map(\.coord).sortedByMapOrder(),
                representativeHex: representativeHex,
                city: cityHex.map {
                    CityInfoDefinition(
                        name: $0.cityName ?? $0.fortressName ?? draft.name,
                        victoryPoints: $0.objectiveId == nil ? 0 : 1,
                        isCapital: false
                    )
                },
                infrastructure: draft.infrastructure,
                supplyValue: draft.supplyValue,
                factories: draft.factories,
                resources: [],
                coreOf: draft.coreOf,
                occupationState: nil,
                isPassable: true
            )
        }

        let edges = edgeRoadFlags.keys.sorted().compactMap { key -> RegionEdgeDefinition? in
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count == 2 else { return nil }
            return RegionEdgeDefinition(
                from: RegionId(parts[0]),
                to: RegionId(parts[1]),
                hasRoad: edgeRoadFlags[key] ?? false,
                hasRiverCrossing: false,
                movementCostModifier: 0
            )
        }

        let supplySources = document.sortedHexes.compactMap { hex -> RegionSupplySourceDefinition? in
            guard hex.isSupplySource,
                  let faction = hex.supplyFaction,
                  let regionId = hex.regionId else {
                return nil
            }
            return RegionSupplySourceDefinition(
                id: "supply_\(hex.coord.mapEditorKey.replacingOccurrences(of: ",", with: "_"))",
                faction: faction,
                regionId: regionId
            )
        }

        let objectives = document.sortedHexes.compactMap { hex -> RegionObjectiveDefinition? in
            guard let objectiveId = hex.objectiveId, let regionId = hex.regionId else { return nil }
            return RegionObjectiveDefinition(
                id: objectiveId,
                name: hex.cityName ?? hex.fortressName ?? objectiveId,
                regionId: regionId,
                type: hex.terrain == .fortress ? .fortress : .city,
                victoryPoints: 1,
                mainObjective: false
            )
        }

        return RegionDataSet(
            schemaVersion: 2,
            scenarioId: document.id,
            displayName: "\(document.displayName) Regions",
            hexToRegion: Dictionary(uniqueKeysWithValues: document.sortedHexes.compactMap { hex in
                hex.regionId.map { (hex.coord.mapEditorKey, $0) }
            }),
            regions: regionDefinitions,
            edges: edges,
            supplySources: supplySources,
            objectives: objectives
        )
    }

    private static func representativeHex(for hexes: [MapEditorHex]) -> HexCoord {
        let q = Double(hexes.reduce(0) { $0 + $1.coord.q }) / Double(hexes.count)
        let r = Double(hexes.reduce(0) { $0 + $1.coord.r }) / Double(hexes.count)
        return hexes.min { lhs, rhs in
            let lhsDistance = pow(Double(lhs.coord.q) - q, 2) + pow(Double(lhs.coord.r) - r, 2)
            let rhsDistance = pow(Double(rhs.coord.q) - q, 2) + pow(Double(rhs.coord.r) - r, 2)
            if lhsDistance == rhsDistance {
                return lhs.coord.mapEditorKey < rhs.coord.mapEditorKey
            }
            return lhsDistance < rhsDistance
        }?.coord ?? hexes[0].coord
    }

    private static func dominantTerrain(in hexes: [MapEditorHex]) -> BaseTerrain {
        let counts = Dictionary(grouping: hexes, by: \.terrain).mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
        }.first?.key ?? .plain
    }

    private static func edgeKey(_ a: RegionId, _ b: RegionId) -> String {
        [a.rawValue, b.rawValue].sorted().joined(separator: "|")
    }
}

private extension Array where Element == HexCoord {
    func sortedByMapOrder() -> [HexCoord] {
        sorted { lhs, rhs in
            lhs.r == rhs.r ? lhs.q < rhs.q : lhs.r < rhs.r
        }
    }
}

private extension String {
    var normalizedMapEditorIdentifier: String {
        lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }
            .joined()
    }
}
