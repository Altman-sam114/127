import Foundation

struct RegionVictoryAssessment: Equatable {
    let winner: Faction?
    let reason: VictoryReason?
}

struct RegionVictoryRules {
    func assessVictory(in state: GameState) -> RegionVictoryAssessment {
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
}

