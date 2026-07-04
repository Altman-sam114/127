    var victoryState: VictoryState
    var selectedUnitSummary: String?
    var eventLog: [GameLogEntry]

    static func initial() -> GameState {
            eventLog: [
                GameLogEntry(
                    turn: 1,
                    faction: .germany,
                    phase: .germanAI,
                    message: "Ardennes V0 scenario initialized."
                )
            ]
        )
    }
