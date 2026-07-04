import SwiftUI

struct CommandPanelView: View {
    let selectedDivision: Division?
    let activeFaction: Faction
    let phase: GamePhase
    let playerFaction: Faction
    let observerModeEnabled: Bool
    let lastCommandMessage: String?
    let onHold: () -> Void
    let onAllowRetreat: () -> Void
    let onResupply: () -> Void
    let onEndTurn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commands")
                .font(.headline)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(action: onHold) {
                    Label("Hold", systemImage: "shield.fill")
                }
                .disabled(!canSetHold)

                Button(action: onAllowRetreat) {
                    Label("Retreat OK", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(!canSetRetreatable)

                Button(action: onResupply) {
                    Label("Reinforce", systemImage: "cross.circle")
                }
                .disabled(!canCommandSelectedUnit)
            }
            .buttonStyle(.bordered)

            Button(action: onEndTurn) {
                Label("End Turn", systemImage: "forward.end")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let lastCommandMessage {
                Text(lastCommandMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var canCommandSelectedUnit: Bool {
        guard !observerModeEnabled else {
            return false
        }

        guard let selectedDivision else {
            return false
        }

        return selectedDivision.faction == playerFaction &&
            activeFaction == playerFaction &&
            phase == .alliedPlayer &&
            !selectedDivision.hasActed
    }

    private var canSetHold: Bool {
        canCommandSelectedUnit && selectedDivision?.retreatMode != .hold
    }

    private var canSetRetreatable: Bool {
        canCommandSelectedUnit && selectedDivision?.retreatMode != .retreatable
    }

    private var statusText: String {
        if observerModeEnabled {
            return "Observer mode: commands disabled."
        }

        guard let selectedDivision else {
            return "No active unit selected."
        }

        guard selectedDivision.faction == playerFaction else {
            return "Enemy unit selected. Commands disabled."
        }

        guard activeFaction == playerFaction, phase == .alliedPlayer else {
            return "Commands unavailable during \(phase.displayName)."
        }

        guard !selectedDivision.hasActed else {
            return "Selected unit has acted."
        }

        return "Move/Attack ready."
    }
}
