import Foundation

enum MapDisplayLayer: String, Codable, Equatable, CaseIterable, Identifiable {
    case hex
    case province
    case initialTheater
    case dynamicTheater
    case frontLine
    case deployment

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .hex:
            return "Hex"
        case .province:
            return "Province"
        case .initialTheater:
            return "Initial"
        case .dynamicTheater:
            return "Dynamic"
        case .frontLine:
            return "Front"
        case .deployment:
            return "Deploy"
        }
    }
}
