import Foundation

// DEPRECATED as of v0.352 - kept for regression reference, not invoked by default. See WarPipelineMode.
// Local LLM provider. Disabled by default in v0 (MockAI runs). Pluggable for v0.5+.
// Never hardcode endpoint/port; injected LLMClient decides transport.

struct LocalLLMDecisionProvider: DecisionProvider {
    let llmClient: LLMClient
    let promptBuilder: AgentPromptBuilder
    let parser: AgentDecisionParser
    let model: String
    let temperature: Double
    let maxTokens: Int

    init(
        llmClient: LLMClient,
        promptBuilder: AgentPromptBuilder = AgentPromptBuilder(),
        parser: AgentDecisionParser = AgentDecisionParser(),
        model: String = "local-model",
        temperature: Double = 0.2,
        maxTokens: Int = 1200
    ) {
        self.llmClient = llmClient
        self.promptBuilder = promptBuilder
        self.parser = parser
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope {
        let request = promptBuilder.makeRequest(
            context: context,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
        let rawJSON = try await llmClient.completeJSON(request: request)
        return try parser.parse(rawJSON, expectedAgentId: context.agentId, expectedTurn: context.turn)
    }
}
