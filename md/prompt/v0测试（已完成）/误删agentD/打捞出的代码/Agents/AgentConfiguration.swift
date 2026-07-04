import Foundation

extension GameAgent {
    static func guderian(from loader: DataLoader, state: GameState) -> GameAgent {
        if let definition = try? loader.loadGeneralAgents().first(where: { $0.id == "guderian" }),
           let agent = GameAgent(definition: definition) {
            return agent
        }

        return guderianFallback(
            assignedDivisionIds: state.divisions
                .filter { $0.faction == .germany }
                .map(\.id)
                .sorted()
        )
    }

    init?(definition: GeneralAgentDefinition) {
        guard let faction = Faction(rawValue: definition.faction),
              let role = AgentRole(rawValue: definition.role) else {
            return nil
        }

        self.init(
            id: definition.id,
            name: definition.name,
            faction: faction,
            role: role,
            authority: .operational,
            personality: AgentPersonality(
                prompt: definition.personalityPrompt,
                traits: [definition.commandStyle],
                aggression: definition.commandStyle == "breakthrough" ? 80 : 50,
                riskTolerance: definition.commandStyle == "breakthrough" ? 75 : 50,
                autonomy: 70
            ),
            relationship: AgentRelationship(loyalty: 70, trust: 70, satisfaction: 70),
            memory: .empty,
            assignedDivisionIds: definition.assignedDivisionIds
        )
    }

    static func guderianFallback(assignedDivisionIds: [String]) -> GameAgent {
        GameAgent(
            id: "guderian",
            name: "Heinz Guderian",
            faction: .germany,
            role: .armyCommander,
            authority: .operational,
            personality: AgentPersonality(
                prompt: "Prioritize armored breakthrough, road movement, concentration of force, and rapid encirclement.",
                traits: ["breakthrough"],
                aggression: 80,
                riskTolerance: 75,
                autonomy: 70
            ),
            relationship: AgentRelationship(loyalty: 70, trust: 70, satisfaction: 70),
            memory: .empty,
            assignedDivisionIds: assignedDivisionIds.isEmpty
                ? ["ger_panzer_1", "ger_motorized_1", "ger_infantry_1", "ger_artillery_1"]
                : assignedDivisionIds
        )
    }
}
