import Foundation

struct VictoryRules {
    static let greyTideMainObjectiveIds: Set<String> = [
        "obj_east_airport",
        "obj_harbor_terminal",
        "obj_river_bridge",
        "obj_comms_center",
        "obj_radar_ridge",
        "obj_fuel_depot",
        "obj_rail_junction",
        "obj_highland_pass",
        "obj_coastal_battery",
        "obj_refinery_district"
    ]

    func updateVictoryState(in state: inout GameState) {
        guard state.victoryState.winner == nil else {
            return
        }

        if state.scenarioId == "grey_tide_2030" {
            updateGreyTideVictoryState(in: &state)
            return
        }

        let bastogneController = state.map.controllerOfObjective(named: "Bastogne")
        let stVithController = state.map.controllerOfObjective(named: "St. Vith")

        if bastogneController == .germany {
            if let heldSince = state.victoryState.germanBastogneHeldSinceTurn,
               state.turn > heldSince {
                state.victoryState.winner = .germany
                state.victoryState.reason = .bastogneHeldByGermany
                return
            } else if state.victoryState.germanBastogneHeldSinceTurn == nil {
                state.victoryState.germanBastogneHeldSinceTurn = state.turn
            }
        } else {
            state.victoryState.germanBastogneHeldSinceTurn = nil
        }

        if bastogneController == .germany && stVithController == .germany {
            state.victoryState.winner = .germany
            state.victoryState.reason = .bastogneAndStVithControlledByGermany
            return
        }

        if state.victoryState.eliminatedAlliedDivisions >= 3 {
            state.victoryState.winner = .germany
            state.victoryState.reason = .alliedUnitsDestroyed
            return
        }

        if state.victoryState.eliminatedGermanDivisions >= 3 {
            state.victoryState.winner = .allies
            state.victoryState.reason = .germanUnitsDestroyed
            return
        }

        let germanArmor = state.divisions.filter { $0.faction == .germany && $0.isArmor }
        if !germanArmor.isEmpty && germanArmor.allSatisfy({ $0.supplyState != .supplied }) {
            if let since = state.victoryState.germanArmorUnsuppliedSinceTurn,
               state.turn > since {
                state.victoryState.winner = .allies
                state.victoryState.reason = .germanArmorUnsupplied
                return
            } else if state.victoryState.germanArmorUnsuppliedSinceTurn == nil {
                state.victoryState.germanArmorUnsuppliedSinceTurn = state.turn
            }
        } else {
            state.victoryState.germanArmorUnsuppliedSinceTurn = nil
        }

        if state.turn >= state.maxTurns && bastogneController == .allies {
            state.victoryState.winner = .allies
            state.victoryState.reason = .bastogneHeldByAlliesAtFinalTurn
        }
    }

    private func updateGreyTideVictoryState(in state: inout GameState) {
        let control = greyTideObjectiveControlCounts(in: state)

        if control.blue >= 7 {
            state.victoryState.winner = .blueForce
            state.victoryState.reason = .greyTideBlueKeyNodesSecured
            return
        }

        if state.turn >= state.maxTurns {
            if control.blue >= 6 {
                state.victoryState.winner = .blueForce
                state.victoryState.reason = .greyTideBlueFinalObjectiveLead
            } else {
                state.victoryState.winner = .redForce
                state.victoryState.reason = .greyTideRedDefenseNetworkHeld
            }
        }
    }

    static func greyTideObjectiveControlCounts(in state: GameState) -> (blue: Int, red: Int, neutral: Int, total: Int) {
        var blue = 0
        var red = 0
        var neutral = 0
        var total = 0
        for objective in state.map.objectives where greyTideMainObjectiveIds.contains(objective.id) {
            total += 1
            switch state.map.tile(at: objective.coord)?.controller?.alignment {
            case .some(.blue):
                blue += 1
            case .some(.red):
                red += 1
            case .some(.green),
                 .some(.neutral),
                 .none:
                neutral += 1
            }
        }

        return (blue, red, neutral, total)
    }

    private func greyTideObjectiveControlCounts(in state: GameState) -> (blue: Int, red: Int, neutral: Int, total: Int) {
        Self.greyTideObjectiveControlCounts(in: state)
    }
}
