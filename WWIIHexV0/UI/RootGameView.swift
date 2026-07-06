import SwiftUI

struct RootGameView: View {
    @ObservedObject var container: AppContainer
    @State private var selectedCompactPanel: CompactInfoPanel = .unit
    @State private var isInfoExpanded = false
    @State private var isGeneralProfilePresented = false

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack(alignment: .bottomTrailing) {
                boardView
                    .ignoresSafeArea()

                VStack {
                    HUDView(
                        gameState: container.gameState,
                        onEndTurn: container.advanceOrRunAI,
                        onNewGame: container.resetGame
                    )
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
                    .padding(.horizontal, 8)

                    Picker("Map Layer", selection: Binding(
                        get: { container.mapDisplayLayer },
                        set: { container.setMapDisplayLayer($0) }
                    )) {
                        ForEach(MapDisplayLayer.allCases) { layer in
                            Text(layer.displayName).tag(layer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)

                    Toggle("Observer", isOn: Binding(
                        get: { container.observerModeEnabled },
                        set: { container.setObserverModeEnabled($0) }
                    ))
                    .toggleStyle(.button)
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)

                    Spacer()
                }

                if isInfoExpanded {
                    infoOverlay(isLandscape: isLandscape, size: proxy.size)
                        .transition(.opacity)
                }

                VStack {
                    Spacer()
                    HStack {
                        infoToggleButton
                        Spacer()
                    }
                }
                .padding(10)

                UnitTooltipView(division: container.selectedDivision)
                    .allowsHitTesting(false)
            }
        }
        .background(PlatformStyles.systemBackground)
        .sheet(isPresented: $isGeneralProfilePresented) {
            if let general = container.selectedGeneral {
                GeneralProfileView(
                    general: general,
                    assignment: container.selectedGeneralAssignment,
                    zone: container.selectedGeneralCommandZone,
                    assignedDivisions: container.selectedGeneralAssignedDivisions,
                    hqUnderAttack: container.selectedGeneralHQUnderAttack,
                    onClose: { isGeneralProfilePresented = false }
                )
            } else {
                Text("No commander selected.")
                    .font(.headline)
                    .padding()
            }
        }
    }

    private var boardView: some View {
        BoardSceneView(
            renderState: BoardSceneAdapter.renderState(from: container),
            onHexTapped: container.handleBoardTap
        )
        .accessibilityLabel("Modern command hex operations board")
    }

    private var infoToggleButton: some View {
        Button {
            isInfoExpanded.toggle()
        } label: {
            Label(isInfoExpanded ? "Hide Info" : "Info", systemImage: "info.circle")
                .font(.caption.bold())
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(isInfoExpanded ? "Hide command panel" : "Show command panel")
        .accessibilityValue(isInfoExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Opens the unit, mission, playtest, log, economy, diplomacy, and AI panels.")
    }

    private func infoOverlay(isLandscape: Bool, size: CGSize) -> some View {
        let width = isLandscape ? min(max(size.width * 0.32, 260), 360) : size.width
        let height = isLandscape ? size.height : min(max(size.height * 0.44, 320), 460)

        return VStack(spacing: 0) {
            compactPanelWithTabs
        }
        .frame(width: width, height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.35), lineWidth: 1)
        }
        .padding(isLandscape ? 10 : 0)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: isLandscape ? .trailing : .bottom
        )
    }

    private var compactPanelWithTabs: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $selectedCompactPanel) {
                ForEach(CompactInfoPanel.allCases) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            compactPanel
        }
    }

    @ViewBuilder
    private var compactPanel: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch selectedCompactPanel {
                case .unit:
                    UnitInspectorView(
                        division: container.selectedDivision,
                        playerFaction: container.playerFaction,
                        strategicState: container.selectedUnitInspectorStrategicState
                    )
                    RegionInspectorView(inspectorState: container.selectedRegionInspectorState)
                    modernMissionPanel
                    CommandPanelView(
                        selectedDivision: container.selectedDivision,
                        activeFaction: container.gameState.activeFaction,
                        phase: container.gameState.phase,
                        playerFaction: container.playerFaction,
                        observerModeEnabled: container.observerModeEnabled,
                        lastCommandMessage: container.lastCommandMessage,
                        onHold: container.holdSelected,
                        onAllowRetreat: container.allowRetreatSelected,
                        onResupply: container.resupplySelected,
                        onEndTurn: container.advanceOrRunAI
                    )
                    GeneralCommandPanelView(
                        zone: container.selectedGeneralCommandZone,
                        general: container.selectedGeneral,
                        assignment: container.selectedGeneralAssignment,
                        assignedDivisions: container.selectedGeneralAssignedDivisions,
                        targetRegion: container.selectedGeneralTargetRegion,
                        targetZone: container.selectedGeneralTargetZone,
                        hqUnderAttack: container.selectedGeneralHQUnderAttack,
                        plannedOperations: container.selectedGeneralPlannedOperations,
                        canHoldLine: container.canOrderSelectedGeneralHoldLine,
                        canAttackRegion: container.canOrderSelectedGeneralAttackRegion,
                        onShowProfile: { isGeneralProfilePresented = true },
                        onHoldLine: container.orderSelectedGeneralHoldLine,
                        onAttackRegion: container.orderSelectedGeneralAttackRegion
                    )
                case .mission:
                    modernMissionPanel
                case .playtest:
                    playtestPanel
                case .region:
                    RegionInspectorView(inspectorState: container.selectedRegionInspectorState)
                case .general:
                    GeneralCommandPanelView(
                        zone: container.selectedGeneralCommandZone,
                        general: container.selectedGeneral,
                        assignment: container.selectedGeneralAssignment,
                        assignedDivisions: container.selectedGeneralAssignedDivisions,
                        targetRegion: container.selectedGeneralTargetRegion,
                        targetZone: container.selectedGeneralTargetZone,
                        hqUnderAttack: container.selectedGeneralHQUnderAttack,
                        plannedOperations: container.selectedGeneralPlannedOperations,
                        canHoldLine: container.canOrderSelectedGeneralHoldLine,
                        canAttackRegion: container.canOrderSelectedGeneralAttackRegion,
                        onShowProfile: { isGeneralProfilePresented = true },
                        onHoldLine: container.orderSelectedGeneralHoldLine,
                        onAttackRegion: container.orderSelectedGeneralAttackRegion
                    )
                case .log:
                    EventLogView(entries: container.displayEventLog)
                case .economy:
                    EconomyPanelView(
                        gameState: container.gameState,
                        playerFaction: container.playerFaction,
                        observerModeEnabled: container.observerModeEnabled,
                        onQueueProduction: container.queueProduction
                    )
                case .diplomacy:
                    DiplomacyPanelView(
                        diplomacyState: container.gameState.diplomacyState,
                        activeFaction: container.gameState.activeFaction
                    )
                case .agent:
                    AgentPanelView(
                        record: container.lastAgentDecisionRecord,
                        rulerRecord: container.gameState.diplomacyState.latestRulerRecord,
                        directiveRecords: container.lastWarDirectiveRecords
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    private var modernMissionPanel: some View {
        ModernMissionPanelView(
            selectedDivision: container.selectedDivision,
            selectedHex: container.selectedHex,
            selectedRegion: container.selectedModernMissionRegion,
            visibleContactCount: container.selectedModernMissionContactCount,
            fireBudgetSummary: container.playerFireBudgetSummary,
            missionAvailabilityText: container.modernMissionAvailabilityText,
            canIssueReconMission: container.canIssueSelectedReconMission,
            canIssueUAVMission: container.canIssueSelectedUAVMission,
            canIssueFireMission: container.canIssueSelectedFireMission,
            canIssueSuppressAirDefenseMission: container.canIssueSelectedSuppressAirDefenseMission,
            canIssueElectronicWarfareMission: container.canIssueSelectedElectronicWarfareMission,
            canIssueResupplyRepairMission: container.canIssueSelectedResupplyRepairMission,
            canAssaultObjective: container.canOrderModernAssaultObjective,
            canHoldDelay: container.canOrderModernHoldDelay,
            observerModeEnabled: container.observerModeEnabled,
            onReconArea: container.orderModernReconArea,
            onUAVOrbit: container.orderModernUAVOrbit,
            onFireMission: container.orderModernFireMission,
            onSuppressAirDefense: container.orderModernSuppressAirDefense,
            onElectronicWarfare: container.orderModernElectronicWarfare,
            onResupplyRepair: container.orderModernResupplyRepair,
            onAssaultObjective: container.orderModernAssaultObjective,
            onHoldDelay: container.orderModernHoldDelay
        )
    }

    private var playtestPanel: some View {
        ModernPlaytestPanelView(
            scenarioName: container.scenarioDisplayName,
            playerSideName: container.playerRoleDisplayName,
            opponentSideName: container.primaryOpponentDisplayName,
            controlModeText: container.playtestControlModeSummary,
            actionGateTitle: container.playtestActionGateTitle,
            actionGateDetail: container.playtestActionGateDetail,
            turnText: "\(container.gameState.turn) / \(container.gameState.maxTurns)",
            objectiveSummaryText: container.playtestObjectiveSummaryText,
            objectiveThresholdText: container.playtestObjectiveThresholdText,
            localSnapshotSummary: container.localSnapshotSummary,
            canLoadSnapshot: container.canLoadLocalSnapshot,
            lastCommandMessage: container.lastCommandMessage,
            lastCommandFeedbackTone: container.lastCommandFeedbackTone,
            guidanceItems: container.playtestGuidanceItems,
            playableSides: container.playableOperationSides,
            nextOperationPlayerFaction: Binding(
                get: { container.nextOperationPlayerFaction },
                set: { container.setNextOperationPlayerFaction($0) }
            ),
            observerModeEnabled: Binding(
                get: { container.observerModeEnabled },
                set: { container.setObserverModeEnabled($0) }
            ),
            mapDisplayLayer: Binding(
                get: { container.mapDisplayLayer },
                set: { container.setMapDisplayLayer($0) }
            ),
            modernC2OverlayEnabled: Binding(
                get: { container.modernC2OverlayEnabled },
                set: { container.setModernC2OverlayEnabled($0) }
            ),
            onNewOperation: container.resetGame(playerFaction:),
            onSaveSnapshot: container.saveLocalSnapshot,
            onLoadSnapshot: container.loadLocalSnapshot,
            onClearSnapshot: container.clearLocalSnapshot
        )
    }
}

private enum CompactInfoPanel: String, CaseIterable, Identifiable {
    case unit = "Formation"
    case mission = "Tasks"
    case playtest = "Playtest"
    case region = "Sector"
    case general = "Command"
    case log = "Log"
    case economy = "Sustainment"
    case diplomacy = "ROE"
    case agent = "AI"

    var id: String {
        rawValue
    }
}
