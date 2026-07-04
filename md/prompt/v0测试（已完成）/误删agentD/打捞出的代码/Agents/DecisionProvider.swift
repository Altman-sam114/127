import Foundation

protocol DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope
}
