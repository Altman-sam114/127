import Foundation

protocol LLMClient {
    func completeJSON(request: LLMRequest) async throws -> String
}

struct LLMRequest: Codable, Equatable {
    let model: String
    let systemPrompt: String
    let userPrompt: String
    let temperature: Double
    let maxTokens: Int
    let responseFormat: String
}
