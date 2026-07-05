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
}
