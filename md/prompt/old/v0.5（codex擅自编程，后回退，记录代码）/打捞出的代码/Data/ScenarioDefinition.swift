struct ScenarioDataSet: Equatable {
    let scenario: ScenarioDefinition
    let terrainRules: TerrainRuleDefinition
    let unitTemplates: [UnitTemplateDefinition]
    let generalAgents: [GeneralAgentDefinition]
}
