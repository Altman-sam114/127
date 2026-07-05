import Combine
import Foundation

final class AppContainer: ObservableObject {
    @Published private(set) var gameState: GameState
    @Published private(set) var selectedUnitId: String?
    @Published private(set) var selectedHex: HexCoord?
    @Published private(set) var selectedRegionId: RegionId?
    @Published private(set) var movementHighlights: Set<HexCoord>
    @Published private(set) var attackHighlights: Set<HexCoord>
    @Published private(set) var interactionLog: [GameLogEntry]
    @Published private(set) var lastCommandMessage: String?
    @Published private(set) var lastAgentDecisionRecord: AgentDecisionRecord?
    @Published private(set) var lastWarDirectiveRecords: [WarDirectiveRecord]
    @Published private(set) var observerModeEnabled: Bool
    @Published private(set) var mapDisplayLayer: MapDisplayLayer
    @Published private(set) var localSnapshotSummary: String?
    @Published private(set) var playerFaction: Faction
    @Published private(set) var nextOperationPlayerFaction: Faction

    let commandHandler: GameCommandHandling
    let dataLoader: DataLoader
    let generalRegistry: GeneralRegistry
    let warPipelineMode: WarPipelineMode
    let turnManager: TurnManager?
    private var isRunningAI = false
    private static let localSnapshotKey = "modernCommandAgent.localSnapshot.v1"
    private static let localSnapshotSummaryKey = "modernCommandAgent.localSnapshot.summary.v1"
    private static let localSnapshotPlayerFactionKey = "modernCommandAgent.localSnapshot.playerFaction.v1"
    private static let localSnapshotSchemaVersion = 2

    private struct LocalPlaytestSnapshot: Codable, Equatable {
        let schemaVersion: Int
        let savedAt: Date
        let playerFaction: Faction
        let gameState: GameState

        init(
            schemaVersion: Int = AppContainer.localSnapshotSchemaVersion,
            savedAt: Date = Date(),
            playerFaction: Faction,
            gameState: GameState
        ) {
            self.schemaVersion = schemaVersion
            self.savedAt = savedAt
            self.playerFaction = playerFaction
            self.gameState = gameState
        }
    }

    init(
        gameState: GameState,
        commandHandler: GameCommandHandling,
        dataLoader: DataLoader,
        generalRegistry: GeneralRegistry = .empty,
        playerFaction: Faction = .allies,
        turnManager: TurnManager? = nil,
        warPipelineMode: WarPipelineMode = .marshalDirective,
        observerModeEnabled: Bool = false,
        mapDisplayLayer: MapDisplayLayer = .hex
    ) {
        let bootstrappedState = StrategicStateBootstrapper().bootstrapIfNeeded(gameState)
        self.gameState = Self.refreshGeneralAssignments(in: bootstrappedState, registry: generalRegistry)
        self.commandHandler = commandHandler
        self.dataLoader = dataLoader
        self.generalRegistry = generalRegistry
        self.playerFaction = playerFaction
        self.nextOperationPlayerFaction = playerFaction
        self.warPipelineMode = warPipelineMode
        self.turnManager = turnManager
        self.selectedUnitId = nil
        self.selectedHex = nil
        self.selectedRegionId = nil
        self.movementHighlights = []
        self.attackHighlights = []
        self.interactionLog = []
        self.lastCommandMessage = nil
        self.lastAgentDecisionRecord = nil
        self.lastWarDirectiveRecords = []
        self.observerModeEnabled = observerModeEnabled
        self.mapDisplayLayer = mapDisplayLayer
        self.localSnapshotSummary = Self.storedLocalSnapshotSummary()
    }

    static func bootstrap() -> AppContainer {
        let dataLoader = DataLoader()
        let gameState = dataLoader.loadInitialGameState()
        let commandHandler = RuleEngine()
        let generalRegistry = (try? dataLoader.loadGeneralRegistry()) ?? .empty
        let guderian = GameAgent.guderian(from: dataLoader, state: gameState)
        let bootstrappedState = Self.refreshGeneralAssignments(
            in: StrategicStateBootstrapper().bootstrapIfNeeded(gameState),
            registry: generalRegistry
        )
        let turnManager = TurnManager(
            agent: guderian,
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: commandHandler,
            commanderPool: Self.buildCommanderPool(state: bootstrappedState, registry: generalRegistry),
            marshalAgent: Self.buildMarshalAgent(faction: .germany, state: bootstrappedState)
        )
        return AppContainer(
            gameState: bootstrappedState,
            commandHandler: commandHandler,
            dataLoader: dataLoader,
            generalRegistry: generalRegistry,
            playerFaction: Self.defaultPlayerFaction(for: bootstrappedState),
            turnManager: turnManager,
            warPipelineMode: .marshalDirective
        )
    }

    func submit(_ command: Command) {
        let stateBeforeCommand = gameState
        let result = commandHandler.execute(command, in: gameState)
        var nextState = StrategicStateBootstrapper().bootstrapIfNeeded(result.state)
        if result.succeeded {
            nextState = applyPlayerCommandBookkeeping(
                command,
                to: nextState,
                previousState: stateBeforeCommand
            )
        }
        gameState = refreshGeneralAssignments(in: nextState)
        lastCommandMessage = result.message

        let status = result.succeeded ? "accepted" : "rejected"
        appendInteractionEvent("Command \(status): \(command.displayName). \(result.message)")
        refreshSelectionAfterStateChange()
        runAIIfNeeded()
    }

    func runAIIfNeeded() {
        guard !isRunningAI else {
            return
        }

        gameState = refreshedRuntimeState(gameState)
        guard shouldRunAI(for: gameState.activeFaction, phase: gameState.phase) else {
            return
        }

        isRunningAI = true
        let stateSnapshot = gameState
        let pipelineMode = warPipelineMode
        let observerEnabled = observerModeEnabled
        let playerFactionSnapshot = playerFaction

        Task {
            let outcome = await self.runAISequence(
                from: stateSnapshot,
                pipelineMode: pipelineMode,
                observerEnabled: observerEnabled,
                playerFaction: playerFactionSnapshot
            )
            await MainActor.run {
                self.gameState = self.refreshedRuntimeState(outcome.state)
                self.lastAgentDecisionRecord = outcome.record
                self.lastWarDirectiveRecords = outcome.directiveRecords
                self.lastCommandMessage = outcome.record.errors.isEmpty
                    ? "AI turn completed."
                    : "AI turn completed with \(outcome.record.errors.count) issue(s)."
                self.appendInteractionEvent("AI \(outcome.record.provider) resolved \(outcome.record.commandResults.count) command result(s).")
                self.isRunningAI = false
                self.refreshSelectionAfterStateChange()
            }
        }
    }

    func handleBoardTap(_ coord: HexCoord) {
        guard gameState.map.contains(coord) else {
            return
        }

        selectedHex = coord
        selectedRegionId = mapDisplayAdapter.regionId(for: coord)
        appendInteractionEvent(selectionMessage(for: coord))

        let displayedDivisions = mapDisplayAdapter.divisions(displayedAt: coord, viewerFaction: playerFaction)
        if let attacker = selectedActionDivision,
           let enemy = displayedDivisions.first(where: { $0.faction != attacker.faction }) {
            submit(.attack(attackerId: attacker.id, targetId: enemy.id))
            return
        }

        if let attacker = selectedActionDivision,
           let contactTarget = visibleContactTarget(at: coord, for: attacker) {
            submit(.attack(attackerId: attacker.id, targetId: contactTarget.id))
            return
        }

        if let tappedDivision = displayedDivisions.first {
            handleDivisionTap(tappedDivision)
            return
        }

        if let division = selectedActionDivision {
            submitMove(division: division, tappedHex: coord)
        } else {
            selectedUnitId = nil
            clearHighlights()
        }
    }

    func holdSelected() {
        guard let division = selectedActionDivision else {
            appendInteractionEvent("Hold rejected: no active player-controlled unit selected.")
            return
        }

        submit(.hold(divisionId: division.id))
    }

    func allowRetreatSelected() {
        guard let division = selectedActionDivision else {
            appendInteractionEvent("Allow retreat rejected: no active player-controlled unit selected.")
            return
        }

        submit(.allowRetreat(divisionId: division.id))
    }

    func resupplySelected() {
        guard let division = selectedActionDivision else {
            appendInteractionEvent("Resupply rejected: no active player-controlled unit selected.")
            return
        }

        submit(.resupply(divisionId: division.id))
    }

    func orderModernReconArea() {
        submitSelectedModernMission("Recon Area") { division, target in
            .recon(divisionId: division.id, target: target)
        }
    }

    func orderModernUAVOrbit() {
        submitSelectedModernMission("UAV Orbit") { division, target in
            .uavRecon(divisionId: division.id, target: target)
        }
    }

    func orderModernFireMission() {
        guard let division = selectedActionDivision else {
            appendInteractionEvent("Fire mission rejected: no active player-controlled unit selected.")
            return
        }
        guard let target = selectedFireMissionTarget() else {
            appendInteractionEvent("Fire mission rejected: select a target hex, sector, or visible contact.")
            return
        }

        submit(.fireMission(
            issuerId: division.id,
            target: target,
            munitionClass: preferredMunitionClass(for: division)
        ))
    }

    func orderModernSuppressAirDefense() {
        submitSelectedModernMission("Air Support / SEAD") { division, target in
            .suppressAirDefense(divisionId: division.id, target: target)
        }
    }

    func orderModernElectronicWarfare() {
        submitSelectedModernMission("Jam / Counter-Drone") { division, target in
            .electronicWarfare(divisionId: division.id, target: target)
        }
    }

    func orderModernResupplyRepair() {
        resupplySelected()
    }

    func orderModernAssaultObjective() {
        orderSelectedGeneralAttackRegion()
    }

    func orderModernHoldDelay() {
        orderSelectedGeneralHoldLine()
    }

    func orderSelectedGeneralHoldLine() {
        guard let zone = selectedGeneralCommandZone else {
            appendInteractionEvent("General order rejected: no player-controlled front zone selected.")
            return
        }

        let directive = ZoneDirective(
            zoneId: zone.id,
            defense: DefenseParameters(
                targetReserves: max(1, min(2, zone.unitsDepth.count)),
                stance: .holdLine
            ),
            category: .defense,
            tactic: .holdPosition
        )
        submitPlayerDirective(
            directive,
            sourceRegionId: sourceRegionId(for: zone, targetZoneId: nil),
            targetRegionId: nil
        )
    }

    func orderSelectedGeneralAttackRegion() {
        guard let target = selectedAttackTarget else {
            appendInteractionEvent("General order rejected: select an enemy front region to attack.")
            return
        }
        guard let zone = selectedGeneralCommandZone else {
            appendInteractionEvent("General order rejected: no player-controlled source front zone available.")
            return
        }

        let directive = ZoneDirective(
            zoneId: zone.id,
            attack: AttackParameters(
                targetTheaterId: TheaterId(target.zone.id.rawValue),
                weightedRegions: [target.region.id],
                intensity: .limitedCounter,
                focusRegionId: target.region.id,
                maxCommittedUnits: max(1, min(3, zone.unitsFront.count + zone.unitsDepth.count))
            ),
            category: .offense,
            tactic: .standardAttack,
            commandTarget: .region(target.region.id)
        )
        submitPlayerDirective(
            directive,
            sourceRegionId: sourceRegionId(for: zone, targetZoneId: target.zone.id),
            targetRegionId: target.region.id
        )
    }

    func queueProduction(_ kind: ProductionKind) {
        guard !observerModeEnabled else {
            appendInteractionEvent("Production rejected: observer mode is read-only.")
            return
        }

        submit(.queueProduction(kind: kind))
    }

    func endTurn() {
        submit(.endTurn)
    }

    func advanceOrRunAI() {
        if shouldRunAI(for: gameState.activeFaction, phase: gameState.phase) {
            runAIIfNeeded()
        } else {
            endTurn()
        }
    }

    func setObserverModeEnabled(_ enabled: Bool) {
        observerModeEnabled = enabled
    }

    func setMapDisplayLayer(_ layer: MapDisplayLayer) {
        mapDisplayLayer = layer
    }

    func setNextOperationPlayerFaction(_ faction: Faction) {
        guard playableOperationSides.contains(faction) else {
            return
        }
        nextOperationPlayerFaction = faction
    }

    func resetGame() {
        resetGame(playerFaction: nextOperationPlayerFaction)
    }

    func resetGame(playerFaction selectedPlayerFaction: Faction) {
        isRunningAI = false
        let initialState = dataLoader.loadInitialGameState()
        let resolvedPlayerFaction = initialState.divisions.contains(where: { $0.faction == selectedPlayerFaction })
            ? selectedPlayerFaction
            : Self.defaultPlayerFaction(for: initialState)
        playerFaction = resolvedPlayerFaction
        nextOperationPlayerFaction = resolvedPlayerFaction
        gameState = refreshGeneralAssignments(
            in: StrategicStateBootstrapper().bootstrapIfNeeded(
                configuredNewOperationState(initialState, playerFaction: resolvedPlayerFaction)
            )
        )
        resetTransientSessionState()
        lastCommandMessage = "New Grey Tide 2030 operation loaded for \(resolvedPlayerFaction.shortDisplayName)."
        appendInteractionEvent("New operation loaded: \(scenarioDisplayName), player side \(resolvedPlayerFaction.displayName).")
        runAIIfNeeded()
    }

    func saveLocalSnapshot() {
        do {
            let snapshot = LocalPlaytestSnapshot(
                playerFaction: playerFaction,
                gameState: gameState
            )
            let data = try JSONEncoder().encode(snapshot)
            let summary = snapshotSummary(for: gameState)
            UserDefaults.standard.set(data, forKey: Self.localSnapshotKey)
            UserDefaults.standard.set(summary, forKey: Self.localSnapshotSummaryKey)
            UserDefaults.standard.set(playerFaction.rawValue, forKey: Self.localSnapshotPlayerFactionKey)
            localSnapshotSummary = summary
            lastCommandMessage = "Local snapshot saved."
            appendInteractionEvent("Local snapshot saved: \(summary).")
        } catch {
            lastCommandMessage = "Save failed: \(error.localizedDescription)"
            appendInteractionEvent("Save failed: \(error.localizedDescription)")
        }
    }

    func loadLocalSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.localSnapshotKey) else {
            lastCommandMessage = "Continue rejected: no local snapshot found."
            appendInteractionEvent("Continue rejected: no local snapshot found.")
            return
        }

        do {
            let snapshot = try Self.decodeLocalSnapshot(data)
            isRunningAI = false
            playerFaction = snapshot.playerFaction
            nextOperationPlayerFaction = snapshot.playerFaction
            gameState = refreshGeneralAssignments(in: StrategicStateBootstrapper().bootstrapIfNeeded(snapshot.gameState))
            resetTransientSessionState()
            let summary = snapshotSummary(for: gameState)
            localSnapshotSummary = summary
            UserDefaults.standard.set(summary, forKey: Self.localSnapshotSummaryKey)
            UserDefaults.standard.set(playerFaction.rawValue, forKey: Self.localSnapshotPlayerFactionKey)
            lastCommandMessage = "Local snapshot loaded."
            appendInteractionEvent("Local snapshot loaded: \(summary).")
            runAIIfNeeded()
        } catch {
            lastCommandMessage = "Continue failed: \(error.localizedDescription)"
            appendInteractionEvent("Continue failed: \(error.localizedDescription)")
        }
    }

    func clearLocalSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.localSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.localSnapshotSummaryKey)
        UserDefaults.standard.removeObject(forKey: Self.localSnapshotPlayerFactionKey)
        localSnapshotSummary = nil
        lastCommandMessage = "Local snapshot cleared."
        appendInteractionEvent("Local snapshot cleared.")
    }

    var canLoadLocalSnapshot: Bool {
        UserDefaults.standard.data(forKey: Self.localSnapshotKey) != nil
    }

    var playableOperationSides: [Faction] {
        [.blueForce, .redForce]
    }

    var scenarioDisplayName: String {
        switch gameState.scenarioId {
        case "grey_tide_2030":
            return "Grey Tide 2030"
        case "ardennes_v0":
            return "Legacy Fallback Scenario"
        default:
            return gameState.scenarioId
        }
    }

    var playerRoleDisplayName: String {
        playerFaction.displayName
    }

    var primaryOpponentDisplayName: String {
        if let opponent = gameState.divisions.map(\.faction).first(where: { playerFaction.isHostile(to: $0) }) {
            return opponent.displayName
        }
        return "No active hostile force"
    }

    var playtestControlModeSummary: String {
        if observerModeEnabled {
            return "Observer AI"
        }

        if gameState.activeFaction == playerFaction,
           playerFaction.canCommand(in: gameState.phase) {
            return "Manual \(playerFaction.shortDisplayName) command"
        }

        return "\(gameState.activeFaction.shortDisplayName) controlled by AI"
    }

    var playtestActionGateTitle: String {
        if gameState.victoryState.winner != nil {
            return "Status"
        }

        if observerModeEnabled {
            return "Automation"
        }

        if canIssuePlayerDirective {
            return "Action Gate"
        }

        if shouldRunAI(for: gameState.activeFaction, phase: gameState.phase) {
            return "Action Gate"
        }

        return "Action Gate"
    }

    var playtestActionGateDetail: String {
        if let winner = gameState.victoryState.winner {
            return "\(winner.shortDisplayName) victory reached"
        }

        if observerModeEnabled {
            return shouldRunAI(for: gameState.activeFaction, phase: gameState.phase)
                ? "AI can resolve active side"
                : "Advance turn to continue"
        }

        if canIssuePlayerDirective {
            return "Player orders open"
        }

        if shouldRunAI(for: gameState.activeFaction, phase: gameState.phase) {
            return "\(gameState.activeFaction.shortDisplayName) AI ready"
        }

        return "End turn to advance phase"
    }

    var playtestObjectiveSummaryText: String? {
        guard gameState.scenarioId == "grey_tide_2030" else {
            return nil
        }

        let control = VictoryRules.greyTideObjectiveControlCounts(in: gameState)
        return "Blue \(control.blue)/\(control.total), Red \(control.red), Neutral \(control.neutral)"
    }

    var playtestObjectiveThresholdText: String? {
        guard gameState.scenarioId == "grey_tide_2030" else {
            return nil
        }

        let control = VictoryRules.greyTideObjectiveControlCounts(in: gameState)
        if let winner = gameState.victoryState.winner {
            return "\(winner.shortDisplayName) victory condition reached."
        }

        let remaining = max(0, 7 - control.blue)
        if remaining == 0 {
            return "Blue immediate victory threshold is met."
        }

        return "Blue needs \(remaining) more for instant win; final turn needs 6."
    }

    var playtestGuidanceItems: [String] {
        var items: [String] = []
        if selectedDivision == nil {
            items.append("Select a friendly formation on the map.")
        } else if canIssueSelectedModernUnitMission {
            items.append("Use Tasks for recon, fires, EW, sustainment, or maneuver.")
        } else {
            items.append("Selected formation is waiting, spent, or outside player command.")
        }

        if gameState.operationalAwareness.visibleContacts(for: playerFaction).isEmpty {
            items.append("Run Recon Area or UAV Orbit before calling precision fires.")
        } else {
            items.append("Visible contacts can drive fire missions and contact-gated attacks.")
        }

        if gameState.fireSupportState.lastMissionResults.isEmpty {
            items.append("Fire results and rejected commands appear in Log and AI tabs.")
        } else {
            items.append("Review recent fire effects before committing ground maneuver.")
        }

        if gameState.activeFaction != playerFaction || !playerFaction.canCommand(in: gameState.phase) {
            items.append("End Turn or enable Observer to let non-player command phases resolve.")
        }

        return Array(items.prefix(4))
    }

    private func resetTransientSessionState() {
        selectedUnitId = nil
        selectedHex = nil
        selectedRegionId = nil
        movementHighlights = []
        attackHighlights = []
        interactionLog = []
        lastCommandMessage = nil
        lastAgentDecisionRecord = nil
        lastWarDirectiveRecords = []
    }

    var selectedDivision: Division? {
        guard let selectedUnitId else {
            return nil
        }
        return gameState.division(id: selectedUnitId)
    }

    var selectedRegionInspectorState: RegionInspectorState? {
        guard let selectedRegionId else {
            return nil
        }
        return mapDisplayAdapter.inspectorState(for: selectedRegionId, selectedHex: selectedHex, viewerFaction: playerFaction)
    }

    var selectedUnitInspectorStrategicState: UnitInspectorStrategicState? {
        guard let selectedDivision else {
            return nil
        }
        return mapDisplayAdapter.unitInspectorState(for: selectedDivision)
    }

    var selectedGeneralCommandZone: FrontZone? {
        inferredPlayerCommandZone()
    }

    var selectedGeneral: GeneralData? {
        generalRegistry.general(id: selectedGeneralAssignment?.generalId)
    }

    var selectedGeneralAssignment: GeneralAssignment? {
        selectedGeneralCommandZone?.generalAssignment
    }

    var selectedGeneralAssignedDivisions: [Division] {
        guard let assignment = selectedGeneralAssignment else {
            return []
        }
        let assignedIds = Set(assignment.assignedDivisionIds)
        return gameState.divisions
            .filter { assignedIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    var selectedGeneralHQUnderAttack: Bool {
        guard let zone = selectedGeneralCommandZone else {
            return false
        }
        return GeneralDispatcher(registry: generalRegistry).isHQUnderAttack(
            zone: zone,
            map: gameState.map
        )
    }

    var selectedGeneralTargetRegion: RegionNode? {
        selectedRegionId.flatMap { gameState.map.region(id: $0) }
    }

    var selectedGeneralTargetZone: FrontZone? {
        guard let selectedRegionId else {
            return nil
        }
        return gameState.warDeploymentState.zone(for: selectedRegionId)
    }

    var selectedGeneralPlannedOperations: [PlayerPlannedOperation] {
        let zoneId = selectedGeneralCommandZone?.id
        return Array(gameState.playerCommandState.plannedOperations
            .filter { operation in
                operation.turn == gameState.turn &&
                    (zoneId == nil || operation.zoneId == zoneId)
            }
            .suffix(5))
    }

    var canOrderSelectedGeneralHoldLine: Bool {
        canIssuePlayerDirective && selectedGeneralCommandZone != nil
    }

    var canOrderSelectedGeneralAttackRegion: Bool {
        canIssuePlayerDirective && selectedAttackTarget != nil && selectedGeneralCommandZone != nil
    }

    var displayEventLog: [GameLogEntry] {
        Array((gameState.eventLog + interactionLog).suffix(80))
    }

    var selectedUnitCanAct: Bool {
        selectedActionDivision != nil
    }

    var selectedModernMissionRegion: RegionNode? {
        selectedRegionId.flatMap { gameState.map.region(id: $0) }
    }

    var selectedModernMissionContactCount: Int {
        selectedRegionInspectorState?.visibleContacts.count ?? 0
    }

    var playerFireBudgetSummary: String {
        let budget = gameState.fireSupportState.budget(for: playerFaction.alignment)
        return "T\(budget.tubeArtillery) R\(budget.rocket) P\(budget.precision) L\(budget.loitering)"
    }

    var canIssueSelectedModernUnitMission: Bool {
        selectedActionDivision != nil
    }

    var canOrderModernAssaultObjective: Bool {
        canOrderSelectedGeneralAttackRegion
    }

    var canOrderModernHoldDelay: Bool {
        canOrderSelectedGeneralHoldLine
    }

    private var selectedActionDivision: Division? {
        guard !observerModeEnabled else {
            return nil
        }
        guard let division = selectedDivision,
              division.faction == playerFaction,
              gameState.activeFaction == playerFaction,
              playerFaction.canCommand(in: gameState.phase),
              !division.hasActed else {
            return nil
        }

        return division
    }

    private var canIssuePlayerDirective: Bool {
        !observerModeEnabled &&
            gameState.activeFaction == playerFaction &&
            playerFaction.canCommand(in: gameState.phase)
    }

    private var selectedAttackTarget: (region: RegionNode, zone: FrontZone)? {
        guard let selectedRegionId,
              let region = gameState.map.region(id: selectedRegionId),
              let targetZone = gameState.warDeploymentState.zone(for: selectedRegionId),
              targetZone.faction != playerFaction else {
            return nil
        }
        return (region, targetZone)
    }

    private var mapDisplayAdapter: MapDisplayAdapter {
        MapDisplayAdapter(state: gameState, revealAll: observerModeEnabled)
    }

    private func refreshedRuntimeState(_ state: GameState) -> GameState {
        refreshGeneralAssignments(
            in: StrategicStateBootstrapper().refreshRuntimeState(state)
        )
    }

    private func refreshGeneralAssignments(in state: GameState) -> GameState {
        Self.refreshGeneralAssignments(in: state, registry: generalRegistry)
    }

    private static func refreshGeneralAssignments(
        in state: GameState,
        registry: GeneralRegistry
    ) -> GameState {
        guard !registry.allGenerals.isEmpty else {
            return state
        }
        var next = state
        next.warDeploymentState = GeneralDispatcher(registry: registry).assignGenerals(
            to: state.warDeploymentState,
            map: state.map
        )
        return next
    }

    private func applyPlayerCommandBookkeeping(
        _ command: Command,
        to state: GameState,
        previousState: GameState
    ) -> GameState {
        var next = state
        if command == .endTurn || next.activeFaction != previousState.activeFaction || next.turn != previousState.turn {
            next.playerCommandState.clearTurnLocks()
            return next
        }

        guard let divisionId = command.actingDivisionId,
              previousState.activeFaction == playerFaction,
              playerFaction.canCommand(in: previousState.phase),
              previousState.division(id: divisionId)?.faction == playerFaction else {
            return next
        }

        next.playerCommandState.lockDivision(divisionId)
        return registerPlayerIntervention(for: divisionId, in: next)
    }

    private func registerPlayerIntervention(for divisionId: String, in state: GameState) -> GameState {
        guard let zoneId = logicalZoneId(for: divisionId, in: state.warDeploymentState),
              var zone = state.warDeploymentState.frontZones[zoneId],
              let assignment = zone.generalAssignment else {
            return state
        }

        var next = state
        zone.generalAssignment = assignment.registeringPlayerIntervention(cost: 2)
        next.warDeploymentState.frontZones[zoneId] = zone
        return next
    }

    private func inferredPlayerCommandZone() -> FrontZone? {
        if let division = selectedDivision,
           division.faction == playerFaction,
           let zoneId = gameState.warDeploymentState.zoneId(for: division.coord, map: gameState.map),
           let zone = gameState.warDeploymentState.frontZones[zoneId],
           zone.faction == playerFaction {
            return zone
        }

        if let selectedRegionId,
           let zone = gameState.warDeploymentState.zone(for: selectedRegionId),
           zone.faction == playerFaction {
            return zone
        }

        guard let targetZone = selectedGeneralTargetZone,
              targetZone.faction != playerFaction else {
            return nil
        }

        return playerZonesAdjacent(to: targetZone.id).first
    }

    private func playerZonesAdjacent(to targetZoneId: FrontZoneId) -> [FrontZone] {
        gameState.warDeploymentState.frontZones.values
            .filter { zone in
                zone.faction == playerFaction &&
                    zone.frontSegments.contains { $0.neighborEnemyZone == targetZoneId }
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func sourceRegionId(for zone: FrontZone, targetZoneId: FrontZoneId?) -> RegionId? {
        if let selectedDivision,
           selectedDivision.faction == zone.faction,
           let regionId = selectedDivision.location(in: gameState.map),
           zone.regionIds.contains(regionId) {
            return regionId
        }

        if let selectedRegionId,
           zone.regionIds.contains(selectedRegionId) {
            return selectedRegionId
        }

        if let targetZoneId,
           let segment = zone.frontSegments
            .filter({ $0.neighborEnemyZone == targetZoneId })
            .sorted(by: { $0.regionId.rawValue < $1.regionId.rawValue })
            .first {
            return segment.regionId
        }

        return zone.generalAssignment?.hqRegionId ?? zone.regionIds.first
    }

    private func submitSelectedModernMission(
        _ missionName: String,
        command: (Division, HexCoord) -> Command
    ) {
        guard let division = selectedActionDivision else {
            appendInteractionEvent("\(missionName) rejected: no active player-controlled unit selected.")
            return
        }
        guard let target = selectedMissionTargetHex() else {
            appendInteractionEvent("\(missionName) rejected: select a target hex or sector.")
            return
        }

        submit(command(division, target))
    }

    private func selectedMissionTargetHex() -> HexCoord? {
        if let selectedHex {
            return selectedHex
        }

        if let selectedRegionId,
           let hex = gameState.map.representativeHex(for: selectedRegionId) {
            return hex
        }

        return selectedDivision?.coord
    }

    private func selectedFireMissionTarget() -> FireMissionTarget? {
        if let contact = selectedMissionContact() {
            return .contact(id: contact.id)
        }
        if let selectedRegionId {
            return .region(selectedRegionId)
        }
        if let selectedHex {
            return .hex(selectedHex)
        }
        return nil
    }

    private func selectedMissionContact() -> ContactTrack? {
        let contacts = gameState.operationalAwareness.visibleContacts(for: playerFaction)
        if let selectedHex,
           let contact = contacts.first(where: { $0.lastKnownCoord == selectedHex }) {
            return contact
        }
        if let selectedRegionId,
           let contact = contacts.first(where: { gameState.map.region(for: $0.lastKnownCoord) == selectedRegionId }) {
            return contact
        }
        return contacts.first
    }

    private func preferredMunitionClass(for division: Division) -> MunitionClass {
        if division.componentWeight(where: { $0 == .loiteringMunition || $0 == .uav }) >= 0.10 {
            return .loitering
        }
        if division.componentWeight(where: { $0 == .rocketArtillery }) >= 0.20 {
            return .rocket
        }
        if division.componentWeight(where: { $0 == .artillery }) >= 0.20 || division.isArtillery {
            return .tubeArtillery
        }
        return .precision
    }

    private func logicalZoneId(for divisionId: String, in deploymentState: WarDeploymentState) -> FrontZoneId? {
        deploymentState.frontZones.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .first {
                $0.unitsFront.contains(divisionId)
                    || $0.unitsDepth.contains(divisionId)
                    || $0.unitsGarrison.contains(divisionId)
            }?
            .id
    }

    private func submitPlayerDirective(
        _ directive: ZoneDirective,
        sourceRegionId: RegionId?,
        targetRegionId: RegionId?
    ) {
        guard canIssuePlayerDirective else {
            appendInteractionEvent("General order rejected: not in the player command phase.")
            return
        }
        guard gameState.warDeploymentState.frontZones[directive.zoneId]?.faction == playerFaction else {
            appendInteractionEvent("General order rejected: source zone is not controlled by the player.")
            return
        }

        let startState = refreshedRuntimeState(gameState)
        guard let refreshedZone = startState.warDeploymentState.frontZones[directive.zoneId],
              refreshedZone.faction == playerFaction else {
            appendInteractionEvent("General order rejected: source zone changed during refresh.")
            return
        }
        let lockedIds = startState.playerCommandState.micromanagedDivisionIds
        let execution = WarCommandExecutor(commandHandler: commandHandler).execute(
            directive,
            in: startState,
            excluding: lockedIds
        )

        var nextState = refreshGeneralAssignments(in: execution.finalState)
        let commandSummaries = execution.commandResults.enumerated().map { index, result in
            CommandResultSummary.directiveCommand(
                directiveIndex: 0,
                commandIndex: index,
                directive: directive,
                command: execution.generatedCommands[index],
                result: result
            )
        }
        var diagnostics: [String] = []
        if execution.generatedCommands.isEmpty {
            diagnostics.append("Player directive generated no executable commands.")
        }
        let rejected = commandSummaries.filter { !$0.executed }
        if !rejected.isEmpty {
            diagnostics.append("\(rejected.count) command(s) were rejected by rules.")
        }
        if !lockedIds.isEmpty {
            diagnostics.append("\(lockedIds.count) micromanaged division(s) excluded.")
        }

        let record = WarDirectiveRecord(
            id: "player_directive_turn_\(startState.turn)_\(directive.zoneId.rawValue)_\(directive.type.rawValue)_\(targetRegionId?.rawValue ?? "hold")",
            issuerId: "player",
            turn: startState.turn,
            faction: playerFaction,
            zoneId: directive.zoneId,
            directiveType: directive.type,
            targetRegionIds: targetRegionId.map { [$0] } ?? directive.targetRegionIds,
            commandResults: commandSummaries,
            diagnostics: diagnostics,
            category: directive.category,
            tactic: directive.tactic,
            commanderAgentId: refreshedZone.generalAssignment?.generalId,
            commandTarget: directive.commandTarget
        )

        nextState.warDirectiveRecords.append(record)
        nextState.playerCommandState.recordOperation(
            PlayerPlannedOperation(
                id: "player_operation_turn_\(startState.turn)_\(directive.zoneId.rawValue)_\(directive.type.rawValue)_\(targetRegionId?.rawValue ?? "hold")",
                turn: startState.turn,
                zoneId: directive.zoneId,
                faction: playerFaction,
                directiveType: directive.type,
                sourceRegionId: sourceRegionId,
                targetRegionId: targetRegionId,
                createdByGeneralId: refreshedZone.generalAssignment?.generalId
            )
        )

        gameState = nextState
        lastWarDirectiveRecords = Array((lastWarDirectiveRecords + [record]).suffix(12))
        lastCommandMessage = playerDirectiveMessage(for: execution, diagnostics: diagnostics)
        appendInteractionEvent("General order submitted: \(directive.type.rawValue) \(directive.zoneId.rawValue).")
        refreshSelectionAfterStateChange()
    }

    private func playerDirectiveMessage(
        for execution: WarCommandExecutionResult,
        diagnostics: [String]
    ) -> String {
        let acceptedCount = execution.commandResults.filter(\.succeeded).count
        let totalCount = execution.generatedCommands.count
        if totalCount == 0 {
            return diagnostics.first ?? "General order produced no commands."
        }
        if acceptedCount == totalCount {
            return "General order executed \(acceptedCount) command(s)."
        }
        return "General order executed \(acceptedCount)/\(totalCount) command(s)."
    }

    private func shouldRunAI(for faction: Faction, phase: GamePhase) -> Bool {
        guard faction.canCommand(in: phase) else {
            return false
        }

        if faction == playerFaction {
            return observerModeEnabled
        }

        return faction.isHostile(to: playerFaction)
    }

    private func runAISequence(
        from state: GameState,
        pipelineMode: WarPipelineMode,
        observerEnabled: Bool,
        playerFaction: Faction
    ) async -> AgentTurnOutcome {
        var currentState = refreshedRuntimeState(state)
        var lastOutcome: AgentTurnOutcome?
        let maxSteps = observerEnabled ? 2 : 1

        for _ in 0..<maxSteps {
            currentState = refreshedRuntimeState(currentState)
            guard shouldRunAIInSnapshot(
                state: currentState,
                observerEnabled: observerEnabled,
                playerFaction: playerFaction
            ) else {
                break
            }

            let manager = turnManager(for: currentState.activeFaction, state: currentState)
            let outcome = await manager.runAITurn(
                state: currentState,
                faction: currentState.activeFaction,
                pipelineMode: pipelineMode
            )
            currentState = refreshedRuntimeState(outcome.state)
            lastOutcome = AgentTurnOutcome(
                state: currentState,
                record: outcome.record,
                directiveRecords: (lastOutcome?.directiveRecords ?? []) + outcome.directiveRecords
            )
        }

        return lastOutcome ?? AgentTurnOutcome(
            state: currentState,
            record: AgentDecisionRecord(
                id: "agent_noop_turn_\(currentState.turn)",
                turn: currentState.turn,
                agentId: "system",
                provider: "System",
                contextSummary: "No AI faction was active.",
                rawJSON: nil,
                parsedIntent: nil,
                commandResults: [],
                errors: []
            )
        )
    }

    private func shouldRunAIInSnapshot(
        state: GameState,
        observerEnabled: Bool,
        playerFaction: Faction
    ) -> Bool {
        guard state.activeFaction.canCommand(in: state.phase) else {
            return false
        }

        if state.activeFaction == playerFaction {
            return observerEnabled
        }

        return state.activeFaction.isHostile(to: playerFaction)
    }

    private func turnManager(for faction: Faction, state: GameState) -> TurnManager {
        if faction == .germany, let turnManager, generalRegistry.allGenerals.isEmpty {
            return turnManager
        }

        let agent: GameAgent
        switch faction {
        case .germany:
            agent = GameAgent.guderian(from: dataLoader, state: state)
        case .allies, .blueForce, .redForce, .greenForce, .neutral:
            let assignedIds = state.divisions
                .filter { $0.faction == faction && !$0.isDestroyed }
                .map(\.id)
            agent = GameAgent.sample(
                id: "\(faction.rawValue)_mock_commander",
                name: "\(faction.shortDisplayName) Mock Commander",
                faction: faction,
                role: .armyCommander,
                assignedDivisionIds: assignedIds
            )
        }

        return TurnManager(
            agent: agent,
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: commandHandler,
            commanderPool: Self.buildCommanderPool(state: state, registry: generalRegistry),
            marshalAgent: Self.buildMarshalAgent(faction: faction, state: state)
        )
    }

    private static func buildCommanderPool(
        state: GameState,
        registry: GeneralRegistry = .empty
    ) -> TheaterCommanderPool {
        if !registry.allGenerals.isEmpty {
            return GeneralDispatcher(registry: registry).commanderPool(for: state)
        }

        let agents: [any ZoneCommanderProviding] = state.warDeploymentState.frontZones.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { zone in
                let style: ZoneCommanderAgentConfig.CommandStyle = zone.faction.alignment == .red ? .aggressive : .balanced
                let factionName = zone.faction.shortDisplayName
                let config = ZoneCommanderAgentConfig(
                    id: "auto_\(zone.id.rawValue)",
                    name: "\(factionName) Commander (\(zone.id.rawValue))",
                    faction: zone.faction,
                    assignedZoneId: zone.id,
                    skills: [],
                    commandStyle: style
                )
                return ZoneCommanderAgent(config: config)
            }
        return TheaterCommanderPool(commanders: agents)
    }

    private static func buildMarshalAgent(faction: Faction, state: GameState) -> MarshalAgent {
        MarshalAgent(config: MarshalAgentConfig.automatic(for: faction, state: state))
    }

    private func handleDivisionTap(_ division: Division) {
        if observerModeEnabled {
            selectDivision(division)
            appendInteractionEvent("Inspecting unit: \(division.name).")
            return
        }

        if division.faction == playerFaction {
            selectDivision(division)
            appendInteractionEvent("Selected unit: \(division.name).")
            return
        }

        if let attacker = selectedActionDivision {
            submit(.attack(attackerId: attacker.id, targetId: division.id))
        } else {
            selectDivision(division)
            appendInteractionEvent("Selected enemy unit: \(division.name).")
        }
    }

    private func selectDivision(_ division: Division) {
        selectedUnitId = division.id
        selectedHex = mapDisplayAdapter.unitDisplayHex(for: division) ?? division.coord
        selectedRegionId = division.location(in: gameState.map)
        refreshHighlights()
    }

    private func refreshSelectionAfterStateChange() {
        if let selectedUnitId,
           gameState.division(id: selectedUnitId) == nil {
            self.selectedUnitId = nil
        }

        if let selectedDivision {
            selectedHex = mapDisplayAdapter.unitDisplayHex(for: selectedDivision) ?? selectedDivision.coord
            selectedRegionId = selectedDivision.location(in: gameState.map)
        }

        refreshHighlights()
    }

    private func refreshHighlights() {
        guard let division = selectedActionDivision else {
            clearHighlights()
            return
        }

        movementHighlights = MovementRules().movementRange(for: division, in: gameState)
        attackHighlights = Set(
            gameState.operationalAwareness.visibleContacts(for: division.faction)
                .filter { contact in
                    guard contact.confidence >= .medium,
                          let linkedDivisionId = contact.linkedDivisionId,
                          let target = gameState.division(id: linkedDivisionId),
                          target.faction.isHostile(to: division.faction),
                          !target.isDestroyed else {
                        return false
                    }
                    return division.coord.distance(to: target.coord) <= division.range
                }
                .map(\.lastKnownCoord)
        )
    }

    private func clearHighlights() {
        movementHighlights = []
        attackHighlights = []
    }

    private func submitMove(division: Division, tappedHex: HexCoord) {
        submit(.move(divisionId: division.id, destination: tappedHex))
    }

    private func visibleContactTarget(at coord: HexCoord, for attacker: Division) -> Division? {
        gameState.operationalAwareness.visibleContacts(for: attacker.faction)
            .filter { $0.lastKnownCoord == coord && $0.confidence >= .medium }
            .compactMap { contact -> Division? in
                guard let linkedDivisionId = contact.linkedDivisionId,
                      let target = gameState.division(id: linkedDivisionId),
                      target.faction.isHostile(to: attacker.faction),
                      !target.isDestroyed,
                      attacker.coord.distance(to: target.coord) <= attacker.range else {
                    return nil
                }
                return target
            }
            .sorted {
                if $0.strength == $1.strength {
                    return $0.id < $1.id
                }
                return $0.strength < $1.strength
            }
            .first
    }

    private func selectionMessage(for coord: HexCoord) -> String {
        guard let selectedRegionId,
              let region = gameState.map.region(id: selectedRegionId) else {
            return "Selected hex \(coord.q),\(coord.r)."
        }
        return "Selected region: \(region.name) (\(selectedRegionId.rawValue))."
    }

    private func configuredNewOperationState(
        _ initialState: GameState,
        playerFaction selectedPlayerFaction: Faction
    ) -> GameState {
        var state = initialState
        if state.divisions.contains(where: { $0.faction == selectedPlayerFaction }),
           let commandPhase = selectedPlayerFaction.commandPhase {
            state.activeFaction = selectedPlayerFaction
            state.phase = commandPhase
        }
        return state
    }

    private static func defaultPlayerFaction(for state: GameState) -> Faction {
        if state.divisions.contains(where: { $0.faction == .blueForce }) {
            return .blueForce
        }

        if state.divisions.contains(where: { $0.faction == .allies }) {
            return .allies
        }

        if state.activeFaction.canCommand(in: state.phase) {
            return state.activeFaction
        }

        return state.divisions
            .map(\.faction)
            .first(where: { $0.commandPhase == .alliedPlayer }) ?? .allies
    }

    private func appendInteractionEvent(_ message: String) {
        interactionLog.append(
            GameLogEntry(
                turn: gameState.turn,
                faction: gameState.activeFaction,
                phase: gameState.phase,
                message: message,
                createdAt: Date()
            )
        )

        if interactionLog.count > 80 {
            interactionLog.removeFirst(interactionLog.count - 80)
        }
    }

    private func snapshotSummary(for state: GameState) -> String {
        "\(scenarioDisplayName) turn \(state.turn)/\(state.maxTurns), player \(playerFaction.shortDisplayName), active \(state.activeFaction.shortDisplayName), \(state.phase.displayName)"
    }

    private static func storedLocalSnapshotSummary() -> String? {
        UserDefaults.standard.string(forKey: localSnapshotSummaryKey)
    }

    private static func storedLocalSnapshotPlayerFaction() -> Faction? {
        Faction.dataValue(UserDefaults.standard.string(forKey: localSnapshotPlayerFactionKey))
    }

    private static func decodeLocalSnapshot(_ data: Data) throws -> LocalPlaytestSnapshot {
        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(LocalPlaytestSnapshot.self, from: data),
           snapshot.schemaVersion <= localSnapshotSchemaVersion {
            return snapshot
        }

        let legacyState = try decoder.decode(GameState.self, from: data)
        return LocalPlaytestSnapshot(
            schemaVersion: 1,
            savedAt: .distantPast,
            playerFaction: storedLocalSnapshotPlayerFaction() ?? defaultPlayerFaction(for: legacyState),
            gameState: legacyState
        )
    }

}
