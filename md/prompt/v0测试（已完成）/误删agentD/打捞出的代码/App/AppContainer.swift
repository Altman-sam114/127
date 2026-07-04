final class AppContainer: ObservableObject {
    @Published private(set) var gameState: GameState
    @Published private(set) var selectedUnitId: String?
    @Published private(set) var selectedHex: HexCoord?
    @Published private(set) var movementHighlights: Set<HexCoord>
    @Published private(set) var attackHighlights: Set<HexCoord>
    @Published private(set) var interactionLog: [GameLogEntry]
    @Published private(set) var lastCommandMessage: String?
    @Published private(set) var lastAgentDecisionRecord: AgentDecisionRecord?

    let commandHandler: GameCommandHandling
    let dataLoader: DataLoader
    let playerFaction: Faction
    private let turnManager: TurnManager?
    private var isRunningAI = false

    init(
        gameState: GameState,
        commandHandler: GameCommandHandling,
        dataLoader: DataLoader,
        playerFaction: Faction = .allies,
        turnManager: TurnManager? = nil
    ) {
        self.gameState = gameState
        self.commandHandler = commandHandler
        self.dataLoader = dataLoader
        self.playerFaction = playerFaction
        self.turnManager = turnManager
        self.selectedUnitId = nil
        self.selectedHex = nil
        self.movementHighlights = []
        self.attackHighlights = []
        self.interactionLog = []
        self.lastCommandMessage = nil
        self.lastAgentDecisionRecord = nil
    }

    static func bootstrap() -> AppContainer {
        let dataLoader = DataLoader()
        let gameState = dataLoader.loadInitialGameState()
        let commandHandler = RuleEngine()
        let guderian = GameAgent.guderian(from: dataLoader, state: gameState)
        let turnManager = TurnManager(
            agent: guderian,
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: commandHandler
        )
        return AppContainer(
            gameState: gameState,
            commandHandler: commandHandler,
            dataLoader: dataLoader,
            turnManager: turnManager
        )
    }

    func submit(_ command: Command) {
        let result = commandHandler.execute(command, in: gameState)
        let status = result.succeeded ? "accepted" : "rejected"
        appendInteractionEvent("Command \(status): \(command.displayName). \(result.message)")
        refreshSelectionAfterStateChange()
        runAIIfNeeded()
    }
    private func appendInteractionEvent(_ message: String) {
        interactionLog.append(
            GameLogEntry(
                turn: gameState.turn,
            interactionLog.removeFirst(interactionLog.count - 80)
        }
    }

    func runAIIfNeeded() {
        guard !isRunningAI,
              let turnManager,
              gameState.activeFaction == .germany,
              gameState.phase == .germanAI else {
            return
        }

        isRunningAI = true
        let stateSnapshot = gameState

        Task {
            let outcome = await turnManager.runGermanAITurn(state: stateSnapshot)
            await MainActor.run {
                self.gameState = outcome.state
                self.lastAgentDecisionRecord = outcome.record
                self.lastCommandMessage = outcome.record.errors.isEmpty
                    ? "AI turn completed."
                    : "AI turn completed with \(outcome.record.errors.count) issue(s)."
                self.appendInteractionEvent("AI \(outcome.record.provider) resolved \(outcome.record.commandResults.count) command result(s).")
                self.isRunningAI = false
                self.refreshSelectionAfterStateChange()
            }
        }
    }
}
