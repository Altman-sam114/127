import Foundation

enum CommandValidationError: String, Codable, Equatable {
    case wrongPhase
    case wrongFaction
    case divisionNotFound
    case targetNotFound
    case alreadyActed
    case destinationOutOfBounds
    case destinationOccupied
    case noPath
    case insufficientMovement
    case targetOutOfRange
    case invalidTargetFaction
    case regionNotFound
    case invalidRegionForHex
    case insufficientResources
    case insufficientTargetQuality
    case insufficientAmmo
    case assetOnCooldown
    case invalidSourceAsset
    case airDefenseThreatTooHigh
    case friendlyProximityRisk
    case restrictedFireZone

    var displayMessage: String {
        switch self {
        case .wrongPhase:
            return "wrong command phase"
        case .wrongFaction:
            return "formation belongs to another side"
        case .divisionNotFound:
            return "formation not found"
        case .targetNotFound:
            return "target not found"
        case .alreadyActed:
            return "formation has already acted"
        case .destinationOutOfBounds:
            return "target hex is outside the operation area"
        case .destinationOccupied:
            return "destination is occupied"
        case .noPath:
            return "no valid route"
        case .insufficientMovement:
            return "insufficient movement"
        case .targetOutOfRange:
            return "target is out of range"
        case .invalidTargetFaction:
            return "target is not hostile under current ROE"
        case .regionNotFound:
            return "sector not found"
        case .invalidRegionForHex:
            return "hex does not belong to the selected sector"
        case .insufficientResources:
            return "insufficient resources"
        case .insufficientTargetQuality:
            return "target quality is too low"
        case .insufficientAmmo:
            return "insufficient fires ammunition"
        case .assetOnCooldown:
            return "fire support asset is on cooldown"
        case .invalidSourceAsset:
            return "selected formation lacks the required mission asset"
        case .airDefenseThreatTooHigh:
            return "air defense threat is too high"
        case .friendlyProximityRisk:
            return "friendly proximity risk is too high"
        case .restrictedFireZone:
            return "restricted fire zone requires a linked hostile target and precision-capable munition"
        }
    }
}

struct CommandValidation: Codable, Equatable {
    var errors: [CommandValidationError]

    var isValid: Bool {
        errors.isEmpty
    }

    static let valid = CommandValidation(errors: [])

    static func invalid(_ error: CommandValidationError) -> CommandValidation {
        CommandValidation(errors: [error])
    }

    var displayMessage: String {
        errors.map(\.displayMessage).joined(separator: "; ")
    }

    var displayMessages: [String] {
        errors.map(\.displayMessage)
    }
}
