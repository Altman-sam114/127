import Foundation

enum VictoryReason: String, Codable, Equatable {
    case bastogneHeldByGermany
    case bastogneAndStVithControlledByGermany
    case alliedUnitsDestroyed
    case bastogneHeldByAlliesAtFinalTurn
    case germanUnitsDestroyed
    case germanArmorUnsupplied
}

struct VictoryState: Codable, Equatable {
    var winner: Faction?
    var reason: VictoryReason?
    var eliminatedGermanDivisions: Int
    var eliminatedAlliedDivisions: Int
    var germanBastogneHeldSinceTurn: Int?
    var germanArmorUnsuppliedSinceTurn: Int?

    static var ongoing: VictoryState {
        VictoryState(
            winner: nil,
            reason: nil,
            eliminatedGermanDivisions: 0,
            eliminatedAlliedDivisions: 0,
            germanBastogneHeldSinceTurn: nil,
            germanArmorUnsuppliedSinceTurn: nil
        )
    }

    mutating func recordEliminatedDivision(faction: Faction) {
        switch faction {
        case .germany:
            eliminatedGermanDivisions += 1
        case .allies:
            eliminatedAlliedDivisions += 1
        }
    }
}
