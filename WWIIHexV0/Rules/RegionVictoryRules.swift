import Foundation

struct RegionVictoryAssessment: Equatable {
    let winner: Faction?
    let reason: VictoryReason?
}

struct RegionVictoryRules {
    func assessVictory(in state: GameState) -> RegionVictoryAssessment {
        if state.scenarioId == "grey_tide_2030" {
            return assessGreyTideVictory(in: state)
        }

        let bastogneController = controller(ofCityNamed: "Bastogne", in: state)
        let stVithController = controller(ofCityNamed: "St. Vith", in: state)

        if bastogneController == .germany && stVithController == .germany {
            return RegionVictoryAssessment(winner: .germany, reason: .bastogneAndStVithControlledByGermany)
        }

        if state.turn >= state.maxTurns && bastogneController == .allies {
            return RegionVictoryAssessment(winner: .allies, reason: .bastogneHeldByAlliesAtFinalTurn)
        }

        return RegionVictoryAssessment(winner: nil, reason: nil)
    }

    func controller(ofCityNamed name: String, in state: GameState) -> Faction? {
        state.map.regions.values.first { $0.city?.name == name }?.controller
    }

    private func assessGreyTideVictory(in state: GameState) -> RegionVictoryAssessment {
        let control = greyTideObjectiveControlCounts(in: state)

        if control.blue >= 7 {
            return RegionVictoryAssessment(winner: .blueForce, reason: .greyTideBlueKeyNodesSecured)
        }

        if state.turn >= state.maxTurns {
            if control.blue >= 6 {
                return RegionVictoryAssessment(winner: .blueForce, reason: .greyTideBlueFinalObjectiveLead)
            }
            return RegionVictoryAssessment(winner: .redForce, reason: .greyTideRedDefenseNetworkHeld)
        }

        return RegionVictoryAssessment(winner: nil, reason: nil)
    }

    private func greyTideObjectiveControlCounts(in state: GameState) -> (blue: Int, red: Int) {
        let control = VictoryRules.greyTideObjectiveControlCounts(in: state)
        return (control.blue, control.red)
    }
}
