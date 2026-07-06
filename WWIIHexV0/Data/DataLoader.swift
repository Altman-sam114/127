import Foundation

struct DataLoader {
    private let bundle: Bundle
    private let resourceDirectory: URL?
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main, resourceDirectory: URL? = nil) {
        self.bundle = bundle
        self.resourceDirectory = resourceDirectory
        self.decoder = JSONDecoder()
    }

    init(resourceDirectory: URL) {
        self.init(bundle: .main, resourceDirectory: resourceDirectory)
    }

    func loadInitialGameState() -> GameState {
        if let state = try? loadGameState(
            scenarioName: "grey_tide_2030_scenario",
            regionName: "grey_tide_2030_regions"
        ) {
            return state
        }

        if let state = try? loadGameState(
            scenarioName: "ardennes_v0_scenario",
            regionName: "ardennes_v02_regions"
        ) {
            return state
        }

        var state = GameState.initial()

        // v0.2: 叠加省份数据。加载失败时 fallback 纯 hex（不破现有行为）。
        // 省份是战略层叠加，hex 仍是战术层权威；tiles/objectives/supplySources 不变。
        if let regionData = try? loadArdennesV02Regions() {
            state.map.regions = regionData.toRegions()
            state.map.hexToRegion = regionData.toHexToRegion()
            state.map.regionEdges = regionData.toRegionEdges()
            // 反向填 HexTile.regionId，让 tile.regionId == hexToRegion[tile.coord]
            for (coord, regionId) in state.map.hexToRegion {
                if var tile = state.map.tile(at: coord) {
                    tile.regionId = regionId
                    state.map.setTile(tile)
                }
            }
            state.map = RegionOccupationRules().mapByAggregatingControllers(in: state.map)
            state.theaterState = makeTheaterState(
                map: state.map,
                regionData: regionData,
                divisions: state.divisions,
                turn: state.turn
            )
            state.frontLineState = FrontLineManager().makeInitialState(
                map: state.map,
                theaterState: state.theaterState,
                divisions: state.divisions,
                turn: state.turn
            )
            let deploymentState = WarDeploymentManager().makeInitialState(
                map: state.map,
                theaterState: state.theaterState,
                divisions: state.divisions,
                turn: state.turn
            )
            state.warDeploymentState = assignGenerals(
                to: deploymentState,
                map: state.map,
                regionData: regionData
            )
        }

        return state
    }

    func loadArdennesDataSet() throws -> ScenarioDataSet {
        let dataSet = ScenarioDataSet(
            scenario: try loadScenarioDefinition(),
            terrainRules: try loadTerrainRules(),
            unitTemplates: try loadLegacyUnitTemplates(),
            generalAgents: try loadGeneralAgents()
        )
        try validate(dataSet)
        return dataSet
    }

    func loadScenarioDefinition() throws -> ScenarioDefinition {
        try loadJSON(ScenarioDefinition.self, named: "ardennes_v0_scenario")
    }

    func loadScenarioDefinition(named resourceName: String) throws -> ScenarioDefinition {
        try loadJSON(ScenarioDefinition.self, named: resourceName)
    }

    func loadRegionDataSet(named resourceName: String) throws -> RegionDataSet {
        try loadJSON(RegionDataSet.self, named: resourceName)
    }

    /// v0.34: 加载 MapEditor 直接导出的 ScenarioDefinition + RegionDataSet。
    /// 这是编辑器输出的主验收路径，不要求走旧 Ardennes 数据集的 agent/胜利条件强校验。
    func loadGameState(scenarioName: String, regionName: String) throws -> GameState {
        let scenario = try loadScenarioDefinition(named: scenarioName)
        let regionData = try loadRegionDataSet(named: regionName)
        var map = try makeMapState(from: scenario)
        try apply(regionData, to: &map)
        map = RegionOccupationRules().mapByAggregatingControllers(in: map)
        let divisions = try makeDivisions(
            from: scenario.initialUnits,
            allowTemplateFallback: scenario.id != "grey_tide_2030"
        )
        let turn = scenario.initialTurn

        let theaterState = makeTheaterState(
            map: map,
            regionData: regionData,
            divisions: divisions,
            turn: turn
        )
        let frontLineState = FrontLineManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: turn
        )
        let deploymentState = WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: turn
        )
        let warDeploymentState = assignGenerals(
            to: deploymentState,
            map: map,
            regionData: regionData
        )

        return GameState(
            scenarioId: scenario.id,
            turn: turn,
            maxTurns: scenario.maxTurns,
            activeFaction: initialActiveFaction(for: scenario),
            phase: GamePhase.dataValue(scenario.initialPhase) ?? .germanAI,
            map: map,
            theaterState: theaterState,
            frontLineState: frontLineState,
            warDeploymentState: warDeploymentState,
            diplomacyState: DiplomacyState.initial(from: scenario.factions, turn: turn),
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: [
                GameLogEntry(
                    turn: turn,
                    faction: initialActiveFaction(for: scenario),
                    phase: GamePhase.dataValue(scenario.initialPhase) ?? .germanAI,
                    message: "Loaded \(scenario.id) from MapEditor-compatible JSON."
                )
            ]
        )
    }

    private func initialActiveFaction(for scenario: ScenarioDefinition) -> Faction {
        let phase = GamePhase.dataValue(scenario.initialPhase) ?? .alliedPlayer
        switch phase {
        case .alliedPlayer:
            return Faction.dataValue(scenario.playerFaction) ?? .allies
        case .germanAI:
            return Faction.dataValue(scenario.aiFaction) ?? .germany
        case .resolution:
            return Faction.dataValue(scenario.playerFaction) ?? .allies
        }
    }

    func loadTerrainRules() throws -> TerrainRuleDefinition {
        try loadJSON(TerrainRuleDefinition.self, named: "terrain_rules")
    }

    func loadUnitTemplates() throws -> [UnitTemplateDefinition] {
        do {
            return try loadJSON(UnitTemplateCatalogDefinition.self, named: "modern_unit_templates").templates
        } catch {
            return try loadLegacyUnitTemplates()
        }
    }

    func loadLegacyUnitTemplates() throws -> [UnitTemplateDefinition] {
        try loadJSON(UnitTemplateCatalogDefinition.self, named: "unit_templates").templates
    }

    func loadGeneralAgents() throws -> [GeneralAgentDefinition] {
        try loadJSON(GeneralAgentCatalogDefinition.self, named: "general_agents").agents
    }

    func loadGeneralRegistry() throws -> GeneralRegistry {
        let catalog = try loadJSON(GeneralCatalogDefinition.self, named: "generals")
        return GeneralRegistry(generals: catalog.generals)
    }

    /// v0.2: 加载阿登省份图数据。失败时抛 DataLoaderError。
    /// 返回的 RegionDataSet 可通过 toRegions()/toRegionEdges()/toHexToRegion() 映射到 MapState 叠加层。
    func loadArdennesV02Regions() throws -> RegionDataSet {
        try loadJSON(RegionDataSet.self, named: "ardennes_v02_regions")
    }

    /// v0.2: 校验省份数据集一致性。复用 RegionGraph.validate + hexToRegion/overlap 检查。
    /// 错误聚合为 DataLoaderError.validationFailed，便于 Agent 5 测试断言。
    func validate(_ regionData: RegionDataSet) throws {
        let regions = regionData.toRegions()
        let hexToRegion = regionData.toHexToRegion()
        let regionEdges = regionData.toRegionEdges()

        // 构临时 MapState 跑 validateRegionGraph（含 hexToRegion + overlap 检查）
        let probe = MapState(
            width: 11,
            height: 9,
            tiles: [:],
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: regionEdges
        )
        let errors = probe.validateRegionGraph().map { DataValidationError(message: $0.description) }
        if !errors.isEmpty {
            throw DataLoaderError.validationFailed(errors)
        }
    }

    func validate(_ dataSet: ScenarioDataSet) throws {
        var errors: [DataValidationError] = []
        let scenario = dataSet.scenario

        if !scenario.map.isSparse {
            let expectedTileCount = scenario.map.width * scenario.map.height
            if scenario.map.tiles.count != expectedTileCount {
                errors.append(
                    DataValidationError(
                        message: "Map tile count \(scenario.map.tiles.count) does not match width * height \(expectedTileCount)."
                    )
                )
            }
        }

        let tileCoords = Set(scenario.map.tiles.map(\.coord))
        if tileCoords.count != scenario.map.tiles.count {
            errors.append(DataValidationError(message: "Map contains duplicate tile coordinates."))
        }

        let unitIds = scenario.initialUnits.map(\.id)
        appendDuplicateErrors(unitIds, label: "initial unit id", to: &errors)

        let occupiedCoords = scenario.initialUnits.map(\.coord)
        if Set(occupiedCoords).count != occupiedCoords.count {
            errors.append(DataValidationError(message: "Initial units contain overlapping coordinates."))
        }

        for unit in scenario.initialUnits where !tileCoords.contains(unit.coord) {
            errors.append(
                DataValidationError(
                    message: "Initial unit \(unit.id) references missing tile (\(unit.coord.q),\(unit.coord.r))."
                )
            )
        }

        let templateIds = Set(dataSet.unitTemplates.map(\.id))
        appendDuplicateErrors(dataSet.unitTemplates.map(\.id), label: "unit template id", to: &errors)
        for unit in scenario.initialUnits where !templateIds.contains(unit.templateId) {
            errors.append(
                DataValidationError(
                    message: "Initial unit \(unit.id) references unknown template \(unit.templateId)."
                )
            )
        }

        for template in dataSet.unitTemplates {
            let componentWeight = template.components.reduce(0.0) { $0 + $1.weight }
            if abs(componentWeight - 1.0) > 0.0001 {
                errors.append(
                    DataValidationError(
                        message: "Unit template \(template.id) component weights sum to \(componentWeight), expected 1.0."
                    )
                )
            }
        }

        let germanSupplySources = scenario.map.tiles.filter {
            $0.isSupplySource && $0.supplyFaction == "germany"
        }
        let alliedSupplySources = scenario.map.tiles.filter {
            $0.isSupplySource && $0.supplyFaction == "allies"
        }
        if germanSupplySources.isEmpty {
            errors.append(DataValidationError(message: "Scenario is missing a German supply source."))
        }
        if alliedSupplySources.isEmpty {
            errors.append(DataValidationError(message: "Scenario is missing an Allied supply source."))
        }

        let objectiveIds = scenario.objectives.map(\.id)
        appendDuplicateErrors(objectiveIds, label: "objective id", to: &errors)
        let objectiveIdSet = Set(objectiveIds)

        let tileObjectiveIds = scenario.map.tiles.compactMap(\.objectiveId)
        appendDuplicateErrors(tileObjectiveIds, label: "tile objective id", to: &errors)
        for objectiveId in tileObjectiveIds where !objectiveIdSet.contains(objectiveId) {
            errors.append(
                DataValidationError(
                    message: "Tile objective \(objectiveId) is not declared in scenario objectives."
                )
            )
        }

        for condition in scenario.victoryConditions {
            if let objectiveId = condition.objectiveId, !objectiveIdSet.contains(objectiveId) {
                errors.append(
                    DataValidationError(
                        message: "Victory condition \(condition.id) references unknown objective \(objectiveId)."
                    )
                )
            }

            for objectiveId in condition.objectiveIds ?? [] where !objectiveIdSet.contains(objectiveId) {
                errors.append(
                    DataValidationError(
                        message: "Victory condition \(condition.id) references unknown objective \(objectiveId)."
                    )
                )
            }
        }

        let agentIds = dataSet.generalAgents.map(\.id)
        appendDuplicateErrors(agentIds, label: "general agent id", to: &errors)

        if scenario.id == "ardennes_v0" {
            let unitIdSet = Set(unitIds)
            for agent in dataSet.generalAgents {
                for divisionId in agent.assignedDivisionIds where !unitIdSet.contains(divisionId) {
                    errors.append(
                        DataValidationError(
                            message: "Agent \(agent.id) references unknown division \(divisionId)."
                        )
                    )
                }
            }

            if let guderian = dataSet.generalAgents.first(where: { $0.id == "guderian" }) {
                let germanUnitIds = Set(scenario.initialUnits.filter { $0.faction == "germany" }.map(\.id))
                let assignedDivisionIds = Set(guderian.assignedDivisionIds)
                if assignedDivisionIds != germanUnitIds {
                    errors.append(
                        DataValidationError(
                            message: "guderian.assignedDivisionIds must exactly cover German initial units."
                        )
                    )
                }
            } else {
                errors.append(DataValidationError(message: "Scenario is missing guderian agent configuration."))
            }
        }

        if !errors.isEmpty {
            throw DataLoaderError.validationFailed(errors)
        }
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, named resourceName: String) throws -> T {
        let url = try resourceURL(named: resourceName)
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func makeMapState(from scenario: ScenarioDefinition) throws -> MapState {
        var errors: [DataValidationError] = []
        var tiles: [HexCoord: HexTile] = [:]
        var supplySources: [SupplySource] = []
        var objectives: [Objective] = []

        for tileDefinition in scenario.map.tiles {
            let coord = HexCoord(q: tileDefinition.q, r: tileDefinition.r)
            guard tiles[coord] == nil else {
                errors.append(DataValidationError(message: "Duplicate tile coordinate \(coord.q),\(coord.r)."))
                continue
            }

            guard let terrain = BaseTerrain(rawValue: tileDefinition.terrain) else {
                errors.append(DataValidationError(message: "Unknown terrain \(tileDefinition.terrain) at \(coord.q),\(coord.r)."))
                continue
            }

            let controller = Faction.dataValue(tileDefinition.controller)
            let riverEdges = Set(tileDefinition.riverEdges.compactMap(HexDirection.init(rawValue:)))
            let regionId = tileDefinition.regionId.map { RegionId($0) }
            let tile = HexTile(
                coord: coord,
                baseTerrain: terrain,
                hasRoad: tileDefinition.hasRoad,
                riverEdges: riverEdges,
                controller: controller,
                cityName: tileDefinition.cityName,
                fortressName: tileDefinition.fortressName,
                isPassable: true,
                regionId: regionId
            )
            tiles[coord] = tile

            if tileDefinition.isSupplySource,
               let supplyFactionString = tileDefinition.supplyFaction,
               let supplyFaction = Faction.dataValue(supplyFactionString) {
                supplySources.append(
                    SupplySource(
                        id: "supply_\(coord.q)_\(coord.r)",
                        faction: supplyFaction,
                        coord: coord
                    )
                )
            }
        }

        for objectiveDefinition in scenario.objectives {
            guard let type = ObjectiveType(rawValue: objectiveDefinition.kind) else {
                errors.append(DataValidationError(message: "Unknown objective type \(objectiveDefinition.kind)."))
                continue
            }
            objectives.append(
                Objective(
                    id: objectiveDefinition.id,
                    name: objectiveDefinition.name,
                    coord: HexCoord(q: objectiveDefinition.coord.q, r: objectiveDefinition.coord.r),
                    type: type
                )
            )
        }

        if !errors.isEmpty {
            throw DataLoaderError.validationFailed(errors)
        }

        return MapState(
            width: scenario.map.width,
            height: scenario.map.height,
            tiles: tiles,
            supplySources: supplySources,
            objectives: objectives
        )
    }

    private func apply(_ regionData: RegionDataSet, to map: inout MapState) throws {
        map.regions = regionData.toRegions()
        map.hexToRegion = regionData.toHexToRegion()
        map.regionEdges = regionData.toRegionEdges()

        for (coord, regionId) in map.hexToRegion {
            guard var tile = map.tile(at: coord) else { continue }
            tile.regionId = regionId
            map.setTile(tile)
        }

        let errors = map.validateRegionGraph().map { DataValidationError(message: $0.description) }
        if !errors.isEmpty {
            throw DataLoaderError.validationFailed(errors)
        }
    }

    private func assignGenerals(
        to deploymentState: WarDeploymentState,
        map: MapState,
        regionData: RegionDataSet
    ) -> WarDeploymentState {
        let registry = (try? loadGeneralRegistry()) ?? .empty
        let seedAssignments = Dictionary(uniqueKeysWithValues: regionData.regions.compactMap { definition in
            definition.assignedGeneralId.map { (definition.id, $0) }
        })
        return GeneralDispatcher(registry: registry).assignGenerals(
            to: deploymentState,
            map: map,
            seedAssignments: seedAssignments
        )
    }

    private func makeDivisions(
        from definitions: [InitialUnitDefinition],
        allowTemplateFallback: Bool = true
    ) throws -> [Division] {
        let templates = (try? loadUnitTemplates()) ?? []
        var errors: [DataValidationError] = []
        let divisions = definitions.compactMap { definition -> Division? in
            guard let faction = Faction.dataValue(definition.faction) else {
                errors.append(DataValidationError(message: "Unknown unit faction \(definition.faction)."))
                return nil
            }

            let components: [DivisionComponent]
            let maxHP: Int
            if let template = templates.first(where: { $0.id == definition.templateId }) {
                maxHP = max(definition.hp, template.maxHP)
                components = template.components.compactMap { component in
                    guard let type = ComponentType.dataValue(component.type) else {
                        errors.append(
                            DataValidationError(
                                message: "Unit template \(template.id) contains unknown component type \(component.type)."
                            )
                        )
                        return nil
                    }
                    return DivisionComponent(type: type, weight: component.weight)
                }
            } else if allowTemplateFallback {
                maxHP = max(definition.hp, fallbackMaxHP(for: definition.templateId))
                components = fallbackComponents(for: definition.templateId)
            } else {
                errors.append(
                    DataValidationError(
                        message: "Unit \(definition.id) references unknown template \(definition.templateId)."
                    )
                )
                return nil
            }

            guard !components.isEmpty else {
                errors.append(DataValidationError(message: "Unit \(definition.id) references unknown template \(definition.templateId)."))
                return nil
            }

            return Division(
                id: definition.id,
                name: definition.name,
                faction: faction,
                coord: HexCoord(q: definition.coord.q, r: definition.coord.r),
                facing: HexDirection(rawValue: definition.facing) ?? .west,
                hp: definition.hp,
                maxHP: maxHP,
                components: components,
                supplyState: SupplyState(rawValue: definition.supplyState) ?? .supplied,
                retreatMode: definition.retreatMode.flatMap(RetreatMode.init(rawValue:)) ?? .retreatable
            )
        }

        if !errors.isEmpty {
            throw DataLoaderError.validationFailed(errors)
        }
        return divisions
    }

    private func fallbackComponents(for templateId: String) -> [DivisionComponent] {
        switch templateId {
        case "tank_division", "panzer_division":
            return [DivisionComponent(type: .tank, weight: 0.7), DivisionComponent(type: .motorizedInfantry, weight: 0.3)]
        case "motorized_division":
            return [DivisionComponent(type: .motorizedInfantry, weight: 1.0)]
        case "artillery_division":
            return [DivisionComponent(type: .artillery, weight: 1.0)]
        default:
            return [DivisionComponent(type: .infantry, weight: 1.0)]
        }
    }

    private func fallbackMaxHP(for templateId: String) -> Int {
        switch templateId {
        case "artillery_division",
             "anti_tank_division",
             "fires_battery",
             "air_defense_detachment",
             "logistics_element",
             "sof_team":
            return 8
        default:
            return 10
        }
    }

    private func makeTheaterState(
        map: MapState,
        regionData: RegionDataSet,
        divisions: [Division],
        turn: Int
    ) -> TheaterState {
        let assignments = Dictionary(uniqueKeysWithValues: regionData.regions.compactMap { definition in
            definition.theaterId.map { (definition.id, $0) }
        })

        guard !assignments.isEmpty else {
            return TheaterSystem().makeInitialFixedTheaters(map: map, divisions: divisions, turn: turn)
        }

        var groupedRegions: [TheaterId: [RegionId]] = [:]
        for regionId in map.regions.keys {
            let theaterId = assignments[regionId] ?? TheaterId("unassigned")
            groupedRegions[theaterId, default: []].append(regionId)
        }

        let theaters = Dictionary(uniqueKeysWithValues: groupedRegions.map { theaterId, regionIds in
            let sortedRegionIds = regionIds.sorted { $0.rawValue < $1.rawValue }
            let controllingFaction = majorityController(regionIds: sortedRegionIds, map: map)
            return (
                theaterId,
                TheaterNode(
                    id: theaterId,
                    name: theaterId.rawValue,
                    status: .active,
                    regionIds: sortedRegionIds,
                    controllingFaction: controllingFaction
                )
            )
        })

        let regionToTheater = Dictionary(uniqueKeysWithValues: groupedRegions.flatMap { theaterId, regionIds in
            regionIds.map { ($0, theaterId) }
        })
        let state = TheaterState(theaters: theaters, regionToTheater: regionToTheater)
        var updated = TheaterSystem().updateTheaters(state: state, map: map, divisions: divisions, turn: turn)
        updated.initialSnapshot = TheaterInitialSnapshot.capture(from: updated)
        return updated
    }

    private func majorityController(regionIds: [RegionId], map: MapState) -> Faction? {
        let counts = Dictionary(grouping: regionIds.compactMap { map.regions[$0]?.controller }) { $0 }
            .mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
        }.first?.key
    }

    private func resourceURL(named resourceName: String) throws -> URL {
        if let resourceDirectory {
            return resourceDirectory
                .appendingPathComponent(resourceName)
                .appendingPathExtension("json")
        }

        #if DEBUG
        if let sourceURL = sourceDataURL(named: resourceName) {
            return sourceURL
        }
        #endif

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw DataLoaderError.missingResource(resourceName)
        }
        return url
    }

    #if DEBUG
    private func sourceDataURL(named resourceName: String) -> URL? {
        let fileURL = URL(fileURLWithPath: #filePath)
        let dataDirectory = fileURL.deletingLastPathComponent()
        let url = dataDirectory
            .appendingPathComponent(resourceName)
            .appendingPathExtension("json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    #endif

    private func appendDuplicateErrors(
        _ values: [String],
        label: String,
        to errors: inout [DataValidationError]
    ) {
        var seen: Set<String> = []
        var duplicates: Set<String> = []

        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }

        for duplicate in duplicates.sorted() {
            errors.append(DataValidationError(message: "Duplicate \(label): \(duplicate)."))
        }
    }
}
