import Foundation

// DEPRECATED as of v0.352 - kept for regression reference, not invoked by default. See WarPipelineMode.
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
    case missingRegionDestination(divisionId: String)
    case missingTarget(divisionId: String)
    case regionMappingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDestination(let divisionId):
            return "Move order for \(divisionId) is missing destination."
        case .missingRegionDestination(let divisionId):
            return "Move order for \(divisionId) is missing toRegionId."
        case .missingTarget(let divisionId):
            return "Attack order for \(divisionId) is missing targetDivisionId."
        case .regionMappingFailed(let detail):
            return detail
        }
    }
}

struct AgentCommandMapper {
    let adapter: CommandIntentAdapter

    init(adapter: CommandIntentAdapter = CommandIntentAdapter()) {
        self.adapter = adapter
    }

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

    func map(_ order: AgentOrder, agentId: String, state: GameState) throws -> IssuedCommand {
        if state.map.regions.isEmpty && order.toRegionId == nil {
            return try map(order, agentId: agentId)
        }

        let regionCommand = try mapToRegionCommand(order, state: state)
        do {
            let command = try adapter.makeHexCommand(from: regionCommand, in: state)
            return IssuedCommand(command: command, issuedBy: .agent(agentId: agentId))
        } catch {
            throw AgentCommandMappingError.regionMappingFailed(error.localizedDescription)
        }
    }

    func mapToRegionCommand(_ order: AgentOrder, state: GameState) throws -> RegionCommand {
        guard let division = state.division(id: order.divisionId) else {
            throw AgentCommandMappingError.regionMappingFailed(
                CommandIntentAdapterError.divisionNotFound(divisionId: order.divisionId).localizedDescription
            )
        }

        let from: RegionId
        do {
            from = try adapter.regionId(for: division, in: state)
        } catch {
            throw AgentCommandMappingError.regionMappingFailed(error.localizedDescription)
        }

        switch order.type {
        case .move:
            guard let toRegionId = order.toRegionId else {
                if let legacyHex = order.to {
                    do {
                        let legacyRegion = try adapter.regionId(for: legacyHex, in: state.map)
                        return .move(divisionId: order.divisionId, from: from, to: legacyRegion)
                    } catch {
                        throw AgentCommandMappingError.regionMappingFailed(error.localizedDescription)
                    }
                }
                throw AgentCommandMappingError.missingRegionDestination(divisionId: order.divisionId)
            }
            return .move(divisionId: order.divisionId, from: from, to: toRegionId)

        case .attack:
            guard let targetDivisionId = order.targetDivisionId else {
                throw AgentCommandMappingError.missingTarget(divisionId: order.divisionId)
            }
            let targetRegion = state.division(id: targetDivisionId).flatMap { state.map.region(for: $0.coord) }
            return .attack(
                attackerId: order.divisionId,
                from: from,
                targetDivisionId: targetDivisionId,
                targetRegionId: targetRegion
            )

        case .hold:
            return .hold(divisionId: order.divisionId, regionId: from)

        case .resupply:
            return .resupply(divisionId: order.divisionId, regionId: from)
        }
    }
}
