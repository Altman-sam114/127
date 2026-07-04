import Foundation

// DEPRECATED as of v0.352 - kept for regression reference, not invoked by default. See WarPipelineMode.
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
    let toRegionId: RegionId?
    let targetDivisionId: String?
    let stance: String?
    let reason: String

    init(
        type: AgentOrderType,
        divisionId: String,
        to: HexCoord? = nil,
        toRegionId: RegionId? = nil,
        targetDivisionId: String? = nil,
        stance: String? = nil,
        reason: String
    ) {
        self.type = type
        self.divisionId = divisionId
        self.to = to
        self.toRegionId = toRegionId
        self.targetDivisionId = targetDivisionId
        self.stance = stance
        self.reason = reason
    }
}

enum AgentOrderType: String, Codable, Equatable, CaseIterable {
    case move
    case attack
    case hold
    case resupply
}
