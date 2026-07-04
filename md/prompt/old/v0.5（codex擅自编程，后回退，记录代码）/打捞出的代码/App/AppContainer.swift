    @Published private(set) var attackHighlights: Set<HexCoord>
    @Published private(set) var interactionLog: [GameLogEntry]
    @Published private(set) var lastCommandMessage: String?

    let commandHandler: GameCommandHandling
    let dataLoader: DataLoader
    let playerFaction: Faction

    init(
        gameState: GameState,
        commandHandler: GameCommandHandling,
        dataLoader: DataLoader,
        playerFaction: Faction = .allies
    ) {
        self.gameState = gameState
        self.commandHandler = commandHandler
        self.dataLoader = dataLoader
        self.playerFaction = playerFaction
        self.selectedUnitId = nil
        self.selectedHex = nil
        self.movementHighlights = []
        self.attackHighlights = []
        self.interactionLog = []
        self.lastCommandMessage = nil
    }

    static func bootstrap() -> AppContainer {
        let dataLoader = DataLoader()
        return AppContainer(
            gameState: dataLoader.loadInitialGameState(),
            commandHandler: RuleEngine(),
            dataLoader: dataLoader
        )
    }
        let status = result.succeeded ? "accepted" : "rejected"
        appendInteractionEvent("Command \(status): \(command.displayName). \(result.message)")
        refreshSelectionAfterStateChange()
    }
}
