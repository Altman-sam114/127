import Foundation

enum AgentDecisionParserError: Error, Equatable, LocalizedError {
    case malformedJSON(String)
    case unsupportedSchemaVersion(Int)
    case agentMismatch(expected: String, actual: String)
    case turnMismatch(expected: Int, actual: Int)

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
        }
    }
}

struct AgentDecisionParser {
    let supportedSchemaVersion: Int
    private let decoder: JSONDecoder

    init(supportedSchemaVersion: Int = 1, decoder: JSONDecoder = JSONDecoder()) {
        self.supportedSchemaVersion = supportedSchemaVersion
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

        guard envelope.schemaVersion == supportedSchemaVersion else {
            throw AgentDecisionParserError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        if let expectedAgentId, envelope.agentId != expectedAgentId {
            throw AgentDecisionParserError.agentMismatch(expected: expectedAgentId, actual: envelope.agentId)
        }

        if let expectedTurn, envelope.turn != expectedTurn {
            throw AgentDecisionParserError.turnMismatch(expected: expectedTurn, actual: envelope.turn)
        }

        return envelope
    }
}
