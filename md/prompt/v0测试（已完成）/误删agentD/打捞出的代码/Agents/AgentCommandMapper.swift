import Foundation

enum CommandIssuer: Codable, Equatable {
    case agent(agentId: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case agentId
    }

    private enum IssuerType: String, Codable {
        case agent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IssuerType.self, forKey: .type)
        switch type {
        case .agent:
            self = .agent(agentId: try container.decode(String.self, forKey: .agentId))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .agent(let agentId):
            try container.encode(IssuerType.agent, forKey: .type)
            try container.encode(agentId, forKey: .agentId)
        }
    }
}

struct IssuedCommand: Codable, Equatable {
    let command: Command
    let issuedBy: CommandIssuer
}

enum AgentCommandMappingError: Error, Equatable, LocalizedError {
    case missingDestination(divisionId: String)
    case missingTarget(divisionId: String)

    var errorDescription: String? {
        switch self {
        case .missingDestination(let divisionId):
            return "Move order for \(divisionId) is missing destination."
        case .missingTarget(let divisionId):
            return "Attack order for \(divisionId) is missing targetDivisionId."
        }
    }
}

struct AgentCommandMapper {
    func map(_ order: AgentOrder, agentId: String) throws -> IssuedCommand {
        let command: Command

        switch order.type {
        case .move:
            guard let destination = order.to else {
                throw AgentCommandMappingError.missingDestination(divisionId: order.divisionId)
            }
            command = .move(divisionId: order.divisionId, destination: destination)
        case .attack:
            guard let targetDivisionId = order.targetDivisionId else {
                throw AgentCommandMappingError.missingTarget(divisionId: order.divisionId)
            }
            command = .attack(attackerId: order.divisionId, targetId: targetDivisionId)
        case .hold:
            command = .hold(divisionId: order.divisionId)
        case .resupply:
            command = .resupply(divisionId: order.divisionId)
        }

        return IssuedCommand(command: command, issuedBy: .agent(agentId: agentId))
    }
}
