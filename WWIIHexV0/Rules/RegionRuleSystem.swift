import Foundation

struct RegionRuleAnalysis: Equatable {
    var supplyByDivisionId: [String: SupplyState]
    var visibleRegionsByFaction: [Faction: Set<RegionId>]
    var victoryAssessment: RegionVictoryAssessment
}

struct RegionRuleSystem {
    let movement = RegionMovementRules()
    let combat = RegionCombatRules()
    let occupation = RegionOccupationRules()
    let supply = RegionSupplyRules()
    let visibility = RegionVisibilityRules()
    let victory = RegionVictoryRules()

    func analyze(_ state: GameState) -> RegionRuleAnalysis {
        var supplyByDivisionId: [String: SupplyState] = [:]
        for division in state.divisions {
            supplyByDivisionId[division.id] = supply.supplyState(for: division, in: state)
        }

        var visibleRegionsByFaction: [Faction: Set<RegionId>] = [:]
        for faction in Faction.allCases {
            visibleRegionsByFaction[faction] = visibility.visibleRegions(for: faction, in: state)
        }

        return RegionRuleAnalysis(
            supplyByDivisionId: supplyByDivisionId,
            visibleRegionsByFaction: visibleRegionsByFaction,
            victoryAssessment: victory.assessVictory(in: state)
        )
    }
}

