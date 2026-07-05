import SwiftUI

struct ModernPlaytestPanelView: View {
    let scenarioName: String
    let playerSideName: String
    let opponentSideName: String
    let controlModeText: String
    let turnText: String
    let objectiveSummaryText: String?
    let objectiveThresholdText: String?
    let localSnapshotSummary: String?
    let canLoadSnapshot: Bool
    let lastCommandMessage: String?
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

                HStack(spacing: ModernCommandDesignTokens.compactSpacing) {
                    Button("Save", systemImage: "square.and.arrow.down", action: onSaveSnapshot)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize)

                    Button("Continue", systemImage: "play.fill", action: onLoadSnapshot)
                        .buttonStyle(.bordered)
                        .disabled(!canLoadSnapshot)
                        .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize)
                }

                Button("Clear Snapshot", systemImage: "trash", action: onClearSnapshot)
                    .buttonStyle(.bordered)
                    .disabled(!canLoadSnapshot)
                    .frame(maxWidth: .infinity, minHeight: ModernCommandDesignTokens.minimumTapSize, alignment: .leading)

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

            VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                Label("Field Prompts", systemImage: "lightbulb")
                    .font(.subheadline.bold())

                ForEach(guidanceItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastCommandMessage {
                Label(lastCommandMessage, systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}
