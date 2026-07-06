import Foundation

enum SupplyState: String, Codable, Equatable, CaseIterable {
    case supplied
    case lowSupply
    case encircled

    var displayName: String {
        switch self {
        case .supplied:
            return "Ready"
        case .lowSupply:
            return "Low Logistics"
        case .encircled:
            return "Logistics Cut"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .supplied:
            return "Ready"
        case .lowSupply:
            return "Low"
        case .encircled:
            return "Cut"
        }
    }
}
