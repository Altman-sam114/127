import Foundation

enum WarPipelineMode: String, Codable, Equatable, CaseIterable {
    case legacyAgentOrder
    case zoneDirective
    case marshalDirective
}
