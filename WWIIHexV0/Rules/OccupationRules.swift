import Foundation

struct OccupationRules {
    func canOccupy(
        division: Division,
        destination: HexCoord,
        in state: GameState
    ) -> Bool {
        guard let tile = state.map.tile(at: destination),
              tile.isCapturable,
              tile.controller != division.faction else {
            return false
        }

        if let occupying = state.division(at: destination),
           occupying.id != division.id {
            return false
        }

        return true
    }
}
