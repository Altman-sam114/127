import SwiftUI

struct ModernPlaytestPanelView: View {
    let scenarioName: String
    let playerSideName: String
    let opponentSideName: String
    let controlModeText: String
    let actionGateTitle: String
    let actionGateDetail: String
    let turnText: String
    let objectiveSummaryText: String?
    let objectiveThresholdText: String?
    let localSnapshotSummary: String?
    let canLoadSnapshot: Bool
    let lastCommandMessage: String?
    let lastCommandFeedbackTone: CommandFeedbackTone?
    let guidanceItems: [String]
    let playableSides: [Faction]
    @Binding var nextOperationPlayerFaction: Faction
    @Binding var observerModeEnabled: Bool
    @Binding var mapDisplayLayer: MapDisplayLayer
    let onNewOperation: (Faction) -> Void
    let onSaveSnapshot: () -> Void
    let onLoadSnapshot: () -> Void
    let onClearSnapshot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ModernCommandDesignTokens.sectionSpacing) {
            Label("Playtest Loop", systemImage: "play.rectangle")
                .font(.headline)

            VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                LabeledContent("Operation", value: scenarioName)
                LabeledContent("Player Side", value: playerSideName)
                LabeledContent("Opposition", value: opponentSideName)
                LabeledContent("Control", value: controlModeText)
                LabeledContent(actionGateTitle, value: actionGateDetail)
                LabeledContent("Turn", value: turnText)
                if let objectiveSummaryText {
                    LabeledContent("Objectives", value: objectiveSummaryText)
                }
                if let objectiveThresholdText {
                    Label(objectiveThresholdText, systemImage: "target")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(ModernCommandDesignTokens.compactSpacing)
            .background(ModernCommandDesignTokens.insetPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))

            VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                Picker("New Operation Side", selection: $nextOperationPlayerFaction) {
                    ForEach(playableSides, id: \.rawValue) { side in
                        Text(side.shortDisplayName).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: ModernCommandDesignTokens.minimumTapSize)

                Button {
                    onNewOperation(nextOperationPlayerFaction)
                } label: {
                    Label("New Operation", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize, alignment: .leading)
                .accessibilityHint("Starts a new Grey Tide operation for the selected side.")

                HStack(spacing: ModernCommandDesignTokens.compactSpacing) {
                    Button("Save", systemImage: "square.and.arrow.down", action: onSaveSnapshot)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize)
                        .accessibilityHint("Saves the current playtest state locally.")

                    Button("Continue", systemImage: "play.fill", action: onLoadSnapshot)
                        .buttonStyle(.bordered)
                        .disabled(!canLoadSnapshot)
                        .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize)
                        .accessibilityHint("Loads the saved local playtest snapshot.")
                }

                Button("Clear Snapshot", systemImage: "trash", role: .destructive, action: onClearSnapshot)
                    .buttonStyle(.bordered)
                    .disabled(!canLoadSnapshot)
                    .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize, alignment: .leading)
                    .accessibilityHint("Deletes the saved local playtest snapshot.")

                Text(localSnapshotSummary ?? "No local snapshot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                Toggle("Observer AI", isOn: $observerModeEnabled)
                    .toggleStyle(.switch)

                Picker("Default Layer", selection: $mapDisplayLayer) {
                    ForEach(MapDisplayLayer.allCases) { layer in
                        Text(layer.displayName).tag(layer)
                    }
                }
                .pickerStyle(.menu)
            }

            c2LegendSection

            VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                Label("Field Prompts", systemImage: "lightbulb")
                    .font(.subheadline.bold())

                ForEach(guidanceItems, id: \.self) { item in
                    Label(item, systemImage: guidanceIcon(for: item))
                        .font(.caption)
                        .foregroundStyle(guidanceColor(for: item))
                }
            }

            if let lastCommandMessage {
                Label(lastCommandMessage, systemImage: commandFeedbackIcon)
                    .font(.caption)
                    .foregroundStyle(commandFeedbackColor)
                    .accessibilityLabel(commandFeedbackAccessibilityLabel(for: lastCommandMessage))
            }
        }
        .padding(ModernCommandDesignTokens.padding)
        .background(ModernCommandDesignTokens.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius)
                .stroke(ModernCommandDesignTokens.panelStroke, lineWidth: 1)
        }
    }

    private var resolvedCommandFeedbackTone: CommandFeedbackTone {
        lastCommandFeedbackTone ?? .info
    }

    private var commandFeedbackIcon: String {
        switch resolvedCommandFeedbackTone {
        case .info:
            return "bubble.left.and.text.bubble"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .failure:
            return "xmark.octagon"
        }
    }

    private var commandFeedbackColor: Color {
        switch resolvedCommandFeedbackTone {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }

    private func commandFeedbackAccessibilityLabel(for message: String) -> String {
        switch resolvedCommandFeedbackTone {
        case .info:
            return "Status: \(message)"
        case .success:
            return "Success: \(message)"
        case .warning:
            return "Warning: \(message)"
        case .failure:
            return "Failure: \(message)"
        }
    }

    private func guidanceIcon(for item: String) -> String {
        item.hasPrefix("Ready Tasks:") || item.contains("ready")
            ? "checkmark.circle"
            : "info.circle"
    }

    private var c2LegendSection: some View {
        VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
            Label("C2 Overlay Legend", systemImage: "map")
                .font(.subheadline.bold())

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                legendItem("Sensor", color: ModernCommandDesignTokens.sensor, systemImage: "dot.scope")
                legendItem("Jammed", color: ModernCommandDesignTokens.electronicWarfare, systemImage: "waveform.path.ecg")
                legendItem("EW Area", color: ModernCommandDesignTokens.electronicWarfare, systemImage: "antenna.radiowaves.left.and.right")
                legendItem("Fire Result", color: ModernCommandDesignTokens.fires, systemImage: "scope")
                legendItem("Low Contact", color: ModernCommandDesignTokens.contactLow, systemImage: "smallcircle.filled.circle")
                legendItem("Medium Contact", color: ModernCommandDesignTokens.contactMedium, systemImage: "smallcircle.filled.circle")
                legendItem("High Contact", color: ModernCommandDesignTokens.contactHigh, systemImage: "smallcircle.filled.circle")
                legendItem("Confirmed", color: ModernCommandDesignTokens.contactConfirmed, systemImage: "smallcircle.filled.circle")
                legendItem("Logistics", color: ModernCommandDesignTokens.sustainment, systemImage: "fuelpump")
            }

            Text("Contact codes: A armor, I infantry, F fires, AD air defense, L logistics, ? unknown.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .padding(ModernCommandDesignTokens.compactSpacing)
        .background(ModernCommandDesignTokens.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var legendColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 104), spacing: ModernCommandDesignTokens.compactSpacing)
        ]
    }

    private func legendItem(_ title: String, color: Color, systemImage: String) -> some View {
        Label {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 18, alignment: .center)
        }
        .foregroundStyle(.secondary)
    }

    private func guidanceColor(for item: String) -> Color {
        item.hasPrefix("Ready Tasks:") || item.contains("ready")
            ? .green
            : .secondary
    }
}
