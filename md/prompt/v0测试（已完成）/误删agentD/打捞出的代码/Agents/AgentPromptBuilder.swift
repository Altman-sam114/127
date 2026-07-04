import Foundation

struct AgentPromptBuilder {
    func makeRequest(
        context: AgentContext,
        model: String,
        temperature: Double = 0.2,
        maxTokens: Int = 1200
    ) -> LLMRequest {
        LLMRequest(
            model: model,
            systemPrompt: systemPrompt(context: context),
            userPrompt: userPrompt(context: context),
            temperature: temperature,
            maxTokens: maxTokens,
            responseFormat: "json_object"
        )
    }

    private func systemPrompt(context: AgentContext) -> String {
        """
        You are the local LLM decision layer for a turn-based WWII hex strategy prototype.
        Agent: \(context.agentId)
        Faction: \(context.faction.rawValue)
        Personality: \(context.personality)

        Return only valid JSON matching the schema. Do not include prose, markdown, comments, or extra keys.
        You must not assume invisible information, modify game rules, invent units, or bypass command validation.
        """
    }

    private func userPrompt(context: AgentContext) -> String {
        let objectives = context.objectives
            .map { "\($0.name) at \($0.id), controller: \($0.controller?.rawValue ?? "neutral")" }
            .joined(separator: "\n")
        let friendly = context.friendlyDivisions
            .map { "\($0.id) \($0.name) hp:\($0.hp)/\($0.maxHP) pos:(\($0.coord.q),\($0.coord.r)) supply:\($0.supplyState.rawValue) acted:\($0.hasActed)" }
            .joined(separator: "\n")
        let enemies = context.enemyDivisions
            .map { "\($0.id) \($0.name) hp:\($0.hp)/\($0.maxHP) pos:(\($0.coord.q),\($0.coord.r))" }
            .joined(separator: "\n")
        let recentEvents = context.recentEvents.map(\.message).joined(separator: "\n")

        return """
        Current task:
        Issue operational orders for this agent's assigned divisions on turn \(context.turn), phase \(context.phase.rawValue).

        Available commands:
        - move: requires divisionId and to { q, r }
        - attack: requires divisionId and targetDivisionId
        - hold: requires divisionId
        - resupply: requires divisionId

        Battlefield summary:
        Friendly divisions:
        \(friendly)

        Known enemy divisions:
        \(enemies)

        Objectives:
        \(objectives)

        Supply:
        friendly supplied \(context.supplySummary.friendlySupplied), low supply \(context.supplySummary.friendlyLowSupply), encircled \(context.supplySummary.friendlyEncircled)

        Recent events:
        \(recentEvents)

        Player directive:
        \(context.playerDirective ?? "None")

        JSON schema:
        {
          "schemaVersion": 1,
          "agentId": "\(context.agentId)",
          "turn": \(context.turn),
          "intent": "short operational intent",
          "orders": [
            {
              "type": "move|attack|hold|resupply",
              "divisionId": "existing division id",
              "to": { "q": 0, "r": 0 },
              "targetDivisionId": null,
              "stance": null,
              "reason": "short reason"
            }
          ]
        }
        """
    }
}
