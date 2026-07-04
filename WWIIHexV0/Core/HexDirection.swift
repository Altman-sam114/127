import Foundation

enum HexDirection: String, Codable, Hashable, CaseIterable {
    case east
    case northEast
    case northWest
    case west
    case southWest
    case southEast

    var dq: Int {
        switch self {
        case .east:
            return 1
        case .northEast:
            return 1
        case .northWest:
            return 0
        case .west:
            return -1
        case .southWest:
            return -1
        case .southEast:
            return 0
        }
    }

    var dr: Int {
        switch self {
        case .east:
            return 0
        case .northEast:
            return -1
        case .northWest:
            return -1
        case .west:
            return 0
        case .southWest:
            return 1
        case .southEast:
            return 1
        }
    }

    var opposite: HexDirection {
        switch self {
        case .east:
            return .west
        case .northEast:
            return .southWest
        case .northWest:
            return .southEast
        case .west:
            return .east
        case .southWest:
            return .northEast
        case .southEast:
            return .northWest
        }
    }

    private var orderedIndex: Int {
        Self.ordered.firstIndex(of: self) ?? 0
    }

    static let ordered: [HexDirection] = [
        .east,
        .northEast,
        .northWest,
        .west,
        .southWest,
        .southEast
    ]

    func relation(toFacing facing: HexDirection) -> AttackFacingRelation {
        let diff = (orderedIndex - facing.orderedIndex + Self.ordered.count) % Self.ordered.count

        switch diff {
        case 0, 1, 5:
            return .front
        case 3:
            return .rear
        default:
            return .flank
        }
    }
}

enum AttackFacingRelation: String, Codable, Equatable {
    case front
    case flank
    case rear
}
