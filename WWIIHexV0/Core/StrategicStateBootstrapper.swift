import Foundation

struct StrategicStateBootstrapper {
    func bootstrapIfNeeded(_ state: GameState) -> GameState {
        var next = EconomyRules().bootstrapIfNeeded(state)
        if next.diplomacyState.countries.isEmpty {
            next.diplomacyState = DiplomacyState.initial(for: Faction.allCases, turn: next.turn)
            next.appendEvent("Diplomacy state bootstrapped with countries, blocs, and initial war relations.")
        }

        guard !state.map.regions.isEmpty else {
            return next
        }

        if next.theaterState.theaters.isEmpty || next.theaterState.regionToTheater.isEmpty {
            next.theaterState = TheaterSystem().makeInitialFixedTheaters(
                map: next.map,
                divisions: next.divisions,
                turn: next.turn
            )
            next.appendEvent(
                "Theater state bootstrapped from region data.",
                category: .theaterChange,
                relatedRecordId: nil
            )
        }

        if next.theaterState.initialSnapshot == nil {
            next.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: next.theaterState)
        }

        if next.frontLineState.frontLines.isEmpty && !next.theaterState.theaters.isEmpty {
            next.frontLineState = FrontLineManager().makeInitialState(
                map: next.map,
                theaterState: next.theaterState,
                divisions: next.divisions,
                turn: next.turn
            )
            next.appendEvent(
                "Front line state bootstrapped from theater data.",
                category: .frontChange,
                relatedRecordId: nil
            )
        }

        if next.warDeploymentState.frontZones.isEmpty && !next.theaterState.theaters.isEmpty {
            next.warDeploymentState = WarDeploymentState.bootstrapFrontZones(
                from: next.theaterState,
                map: next.map,
                divisions: next.divisions,
                turn: next.turn
            )
            next.appendEvent(
                "FrontZone deployment state bootstrapped from theater data.",
                category: .frontChange,
                relatedRecordId: nil
            )
        }

        return next
    }

    func refreshRuntimeState(_ state: GameState) -> GameState {
        guard !state.map.regions.isEmpty else {
            return state
        }

        var next = bootstrapIfNeeded(state)
        _ = RegionOccupationRules().aggregateControl(in: &next)
        next.theaterState = TheaterSystem().updateTheaters(
            state: next.theaterState,
            map: next.map,
            divisions: next.divisions,
            turn: next.turn,
            force: true
        )
        if next.theaterState.initialSnapshot == nil {
            next.theaterState.initialSnapshot = TheaterInitialSnapshot.capture(from: next.theaterState)
        }
        next.frontLineState = FrontLineManager().makeInitialState(
            map: next.map,
            theaterState: next.theaterState,
            divisions: next.divisions,
            turn: next.turn
        )
        let rebuiltDeployment = WarDeploymentState.bootstrapFrontZones(
            from: next.theaterState,
            map: next.map,
            divisions: next.divisions,
            turn: next.turn
        )
        next.warDeploymentState = rebuiltDeployment.preservingGeneralAssignments(from: state.warDeploymentState)
        return next
    }
}
