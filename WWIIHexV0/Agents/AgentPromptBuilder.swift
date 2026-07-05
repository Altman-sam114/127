import Foundation

// DEPRECATED as of v0.352 - kept for regression reference, not invoked by default. See WarPipelineMode.
// Builds LLM prompt from AgentContext. v0 keeps it simple; mostly for LocalLLMDecisionProvider.

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
            .map { "\($0.name) region:\($0.regionId?.rawValue ?? "unknown"), controller: \($0.controller?.rawValue ?? "neutral")" }
            .joined(separator: "\n")
        let friendly = context.friendlyDivisions
            .map { "\($0.id) \($0.name) str:\($0.strength)/\($0.maxStrength) region:\($0.regionId?.rawValue ?? "unknown") supply:\($0.supplyState.rawValue) acted:\($0.hasActed)" }
            .joined(separator: "\n")
        let contacts = context.contactSummaries
            .map {
                "\($0.id) type:\($0.estimatedType.rawValue) confidence:\($0.confidence.rawValue) region:\($0.regionId?.rawValue ?? "unknown") source:\($0.source.rawValue) age:\($0.ageInTurns)"
            }
            .joined(separator: "\n")
        let regions = context.visibleRegions
            .filter(\.visible)
            .map { "\($0.id.rawValue) \($0.name) terrain:\($0.terrain.rawValue) controller:\($0.controller.rawValue) neighbors:\($0.neighbors.map(\.rawValue).joined(separator: ","))" }
            .joined(separator: "\n")
        let recentEvents = context.recentEvents.map(\.message).joined(separator: "\n")

        return """
        Current task:
        Issue operational orders for this agent's assigned divisions on turn \(context.turn), phase \(context.phase.rawValue).

        Available commands:
        - move: requires divisionId and toRegionId
        - attack: legacy only; requires a real targetDivisionId and should not be used from unconfirmed contacts
        - hold: requires divisionId
        - resupply: requires divisionId
        Recon and EW are modeled by the rules layer, but this legacy JSON schema cannot issue them yet.

        Battlefield summary:
        Friendly divisions:
        \(friendly)

        Visible contacts:
        \(contacts.isEmpty ? "No visible contacts." : contacts)

        Objectives:
        \(objectives)

        Visible regions:
        \(regions)

        Supply:
        friendly supplied \(context.supplySummary.friendlySupplied), low supply \(context.supplySummary.friendlyLowSupply), encircled \(context.supplySummary.friendlyEncircled)

        Recent events:
        \(recentEvents)

        Player directive:
        \(context.playerDirective ?? "None")

        JSON schema:
        {
          "schemaVersion": 2,
          "agentId": "\(context.agentId)",
          "turn": \(context.turn),
          "intent": "short operational intent",
          "orders": [
            {
              "type": "move|attack|hold|resupply",
              "divisionId": "existing division id",
              "toRegionId": "existing visible region id",
              "targetDivisionId": null,
              "stance": null,
              "reason": "short reason"
            }
          ]
        }
        """
    }
}
