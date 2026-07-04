    init(resourceDirectory: URL) {
        self.init(bundle: .main, resourceDirectory: resourceDirectory)
    }

    func loadInitialGameState() -> GameState {
        GameState.initial()
    }

    func loadArdennesDataSet() throws -> ScenarioDataSet {
        let dataSet = ScenarioDataSet(
            scenario: try loadScenarioDefinition(),
            terrainRules: try loadTerrainRules(),
            unitTemplates: try loadUnitTemplates(),
            generalAgents: try loadGeneralAgents()
        )
        try validate(dataSet)
        return dataSet
    func loadGeneralAgents() throws -> [GeneralAgentDefinition] {
        try loadJSON(GeneralAgentCatalogDefinition.self, named: "general_agents").agents
    }
        if !errors.isEmpty {
            throw DataLoaderError.validationFailed(errors)
        }
