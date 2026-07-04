import Foundation

struct RegionCommandValidator {
    func validate(_ command: RegionCommand, in state: GameState) -> CommandValidation {
        switch command {
        case .move(let divisionId, let from, let to):
            let unit = validateUnit(divisionId: divisionId, expectedRegion: from, in: state)
            guard unit.isValid else { return unit }
            guard state.map.region(id: to) != nil else {
                return .invalid(.regionNotFound)
            }
            return .valid

        case .attack(let attackerId, let from, let targetDivisionId, let targetRegionId):
            let unit = validateUnit(divisionId: attackerId, expectedRegion: from, in: state)
            guard unit.isValid else { return unit }
            guard let attacker = state.division(id: attackerId) else {
                return .invalid(.divisionNotFound)
            }
            guard let target = state.division(id: targetDivisionId) else {
                return .invalid(.targetNotFound)
            }
            guard target.faction != attacker.faction else {
                return .invalid(.invalidTargetFaction)
            }
            if let targetRegionId {
                guard state.map.region(id: targetRegionId) != nil else {
                    return .invalid(.regionNotFound)
                }
                guard state.map.region(for: target.coord) == targetRegionId else {
                    return .invalid(.targetOutOfRange)
                }
            }
            return .valid

        case .hold(let divisionId, let regionId),
             .resupply(let divisionId, let regionId):
            if let regionId, state.map.region(id: regionId) == nil {
                return .invalid(.regionNotFound)
            }
            guard let division = state.division(id: divisionId) else {
                return .invalid(.divisionNotFound)
            }
            if let regionId, state.map.region(for: division.coord) != regionId {
                return .invalid(.invalidRegionForHex)
            }
            return .valid
        }
    }

    private func validateUnit(divisionId: String, expectedRegion: RegionId, in state: GameState) -> CommandValidation {
        guard state.map.region(id: expectedRegion) != nil else {
            return .invalid(.regionNotFound)
        }
        guard let division = state.division(id: divisionId) else {
            return .invalid(.divisionNotFound)
        }
        guard state.map.region(for: division.coord) == expectedRegion else {
            return .invalid(.invalidRegionForHex)
        }
        return .valid
    }
}

