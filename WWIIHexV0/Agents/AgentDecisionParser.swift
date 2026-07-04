import Foundation

// DEPRECATED as of v0.352 - kept for regression reference, not invoked by default. See WarPipelineMode.
enum AgentDecisionParserError: Error, Equatable, LocalizedError {
    case malformedJSON(String)
    case unsupportedSchemaVersion(Int)
    case agentMismatch(expected: String, actual: String)
    case turnMismatch(expected: Int, actual: Int)
    case missingRegionDestination(divisionId: String)

    var errorDescription: String? {
        switch self {
        case .malformedJSON(let detail):
            return "Malformed agent decision JSON: \(detail)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported agent decision schemaVersion \(version)."
        case .agentMismatch(let expected, let actual):
            return "Agent decision agentId mismatch. Expected \(expected), got \(actual)."
        case .turnMismatch(let expected, let actual):
            return "Agent decision turn mismatch. Expected \(expected), got \(actual)."
        case .missingRegionDestination(let divisionId):
            return "Move order for \(divisionId) is missing toRegionId."
        }
    }
}

struct AgentDecisionParser {
    let supportedSchemaVersions: Set<Int>
    private let decoder: JSONDecoder

    init(supportedSchemaVersion: Int, decoder: JSONDecoder = JSONDecoder()) {
        self.supportedSchemaVersions = [supportedSchemaVersion]
        self.decoder = decoder
    }

    init(supportedSchemaVersions: Set<Int> = [1, 2], decoder: JSONDecoder = JSONDecoder()) {
        self.supportedSchemaVersions = supportedSchemaVersions
        self.decoder = decoder
    }

    func parse(
        _ rawJSON: String,
        expectedAgentId: String? = nil,
        expectedTurn: Int? = nil
    ) throws -> AgentDecisionEnvelope {
        guard let data = rawJSON.data(using: .utf8) else {
            throw AgentDecisionParserError.malformedJSON("Input is not valid UTF-8.")
        }

        let envelope: AgentDecisionEnvelope
        do {
            envelope = try decoder.decode(AgentDecisionEnvelope.self, from: data)
        } catch {
            throw AgentDecisionParserError.malformedJSON(error.localizedDescription)
        }

        guard supportedSchemaVersions.contains(envelope.schemaVersion) else {
            throw AgentDecisionParserError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        if let expectedAgentId, envelope.agentId != expectedAgentId {
            throw AgentDecisionParserError.agentMismatch(expected: expectedAgentId, actual: envelope.agentId)
        }

        if let expectedTurn, envelope.turn != expectedTurn {
            throw AgentDecisionParserError.turnMismatch(expected: expectedTurn, actual: envelope.turn)
        }

        if envelope.schemaVersion >= 2 {
            for order in envelope.orders where order.type == .move && order.toRegionId == nil {
                throw AgentDecisionParserError.missingRegionDestination(divisionId: order.divisionId)
            }
        }

        return envelope
    }
}
