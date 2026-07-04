import Foundation

enum SupplyState: String, Codable, Equatable, CaseIterable {
    case supplied
    case lowSupply
    case encircled
}
