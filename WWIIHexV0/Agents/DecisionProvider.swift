import Foundation

// DEPRECATED as of v0.352 - kept for regression reference, not invoked by default. See WarPipelineMode.
protocol DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope
}
