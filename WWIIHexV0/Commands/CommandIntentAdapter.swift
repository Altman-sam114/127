import Foundation

enum CommandIntentAdapterError: Error, Equatable, LocalizedError {
    case invalidRegionForHex(hex: HexCoord)
    case regionNotFound(regionId: RegionId)
    case divisionNotFound(divisionId: String)
    case divisionHasNoRegion(divisionId: String)
    case destinationRegionHasNoUsableHex(regionId: RegionId)
    case targetRegionMismatch(targetDivisionId: String, expected: RegionId, actual: RegionId)

    var errorDescription: String? {
        switch self {
        case .invalidRegionForHex(let hex):
            return "Hex \(hex.q),\(hex.r) does not map to a region."
        case .regionNotFound(let regionId):
            return "Region \(regionId.rawValue) was not found."
        case .divisionNotFound(let divisionId):
            return "Formation \(divisionId) was not found."
        case .divisionHasNoRegion(let divisionId):
            return "Formation \(divisionId) is not inside a mapped region."
        case .destinationRegionHasNoUsableHex(let regionId):
            return "Region \(regionId.rawValue) has no usable tactical hex."
        case .targetRegionMismatch(let targetDivisionId, let expected, let actual):
            return "Target \(targetDivisionId) is in \(actual.rawValue), not \(expected.rawValue)."
        }
    }
}

struct CommandIntentAdapter {
    func regionId(for hex: HexCoord, in map: MapState) throws -> RegionId {
        guard let regionId = map.region(for: hex) else {
            throw CommandIntentAdapterError.invalidRegionForHex(hex: hex)
        }
        guard map.region(id: regionId) != nil else {
            throw CommandIntentAdapterError.regionNotFound(regionId: regionId)
        }
        return regionId
    }

    func regionId(for division: Division, in state: GameState) throws -> RegionId {
        guard let regionId = state.map.region(for: division.coord) else {
            throw CommandIntentAdapterError.divisionHasNoRegion(divisionId: division.id)
        }
        guard state.map.region(id: regionId) != nil else {
            throw CommandIntentAdapterError.regionNotFound(regionId: regionId)
        }
        return regionId
    }

    func makeRegionMoveCommand(
        divisionId: String,
        tappedHex: HexCoord,
        state: GameState
    ) throws -> RegionCommand {
        guard let division = state.division(id: divisionId) else {
            throw CommandIntentAdapterError.divisionNotFound(divisionId: divisionId)
        }

        let from = try regionId(for: division, in: state)
        let to = try regionId(for: tappedHex, in: state.map)
        return .move(divisionId: divisionId, from: from, to: to)
    }

    func makeMoveCommand(
        divisionId: String,
        tappedHex: HexCoord,
        state: GameState
    ) throws -> Command {
        _ = try makeRegionMoveCommand(divisionId: divisionId, tappedHex: tappedHex, state: state)
        return .move(divisionId: divisionId, destination: tappedHex)
    }

    func makeHexCommand(from regionCommand: RegionCommand, in state: GameState) throws -> Command {
        switch regionCommand {
        case .move(let divisionId, _, let to):
            guard let division = state.division(id: divisionId) else {
                throw CommandIntentAdapterError.divisionNotFound(divisionId: divisionId)
            }
            let destination = try tacticalDestination(in: to, for: division, state: state)
            return .move(divisionId: divisionId, destination: destination)

        case .attack(let attackerId, _, let targetDivisionId, let targetRegionId):
            if let targetRegionId,
               let target = state.division(id: targetDivisionId) {
                let actualRegion = try regionId(for: target, in: state)
                if actualRegion != targetRegionId {
                    throw CommandIntentAdapterError.targetRegionMismatch(
                        targetDivisionId: targetDivisionId,
                        expected: targetRegionId,
                        actual: actualRegion
                    )
                }
            }
            return .attack(attackerId: attackerId, targetId: targetDivisionId)

        case .hold(let divisionId, _):
            return .hold(divisionId: divisionId)

        case .resupply(let divisionId, _):
            return .resupply(divisionId: divisionId)
        }
    }

    private func tacticalDestination(in regionId: RegionId, for division: Division, state: GameState) throws -> HexCoord {
        guard let region = state.map.region(id: regionId) else {
            throw CommandIntentAdapterError.regionNotFound(regionId: regionId)
        }

        let candidates = ([region.representativeHex] + region.displayHexes)
            .reduce(into: [HexCoord]()) { result, hex in
                if !result.contains(hex) {
                    result.append(hex)
                }
            }

        if let currentRegion = state.map.region(for: division.coord),
           currentRegion == regionId {
            return division.coord
        }

        for hex in candidates {
            guard state.map.tile(at: hex)?.isPassable == true else {
                continue
            }
            if let occupying = state.division(at: hex), occupying.id != division.id {
                continue
            }
            return hex
        }

        throw CommandIntentAdapterError.destinationRegionHasNoUsableHex(regionId: regionId)
    }
}
