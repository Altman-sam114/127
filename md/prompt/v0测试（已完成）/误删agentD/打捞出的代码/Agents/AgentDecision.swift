import Foundation

struct AgentDecisionEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let agentId: String
    let turn: Int
    let intent: String
    let orders: [AgentOrder]
}

struct AgentOrder: Codable, Equatable {
    let type: AgentOrderType
    let divisionId: String
    let to: HexCoord?
    let targetDivisionId: String?
    let stance: String?
    let reason: String
}

enum AgentOrderType: String, Codable, Equatable, CaseIterable {
    case move
    case attack
    case hold
    case resupply
}
