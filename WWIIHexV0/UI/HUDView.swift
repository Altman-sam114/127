import SwiftUI

struct HUDView: View {
    let gameState: GameState
    let onEndTurn: () -> Void
    let onNewGame: (() -> Void)?

    private let statusColumns = [
        GridItem(.adaptive(minimum: ModernCommandDesignTokens.metricMinWidth), spacing: ModernCommandDesignTokens.compactSpacing)
    ]

    init(gameState: GameState, onEndTurn: @escaping () -> Void, onNewGame: (() -> Void)? = nil) {
        self.gameState = gameState
        self.onEndTurn = onEndTurn
        self.onNewGame = onNewGame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ModernCommandDesignTokens.spacing) {
            HStack(alignment: .center, spacing: ModernCommandDesignTokens.spacing) {
                Label("Modern Command Agent", systemImage: "scope")
                    .font(.headline)
                    .foregroundStyle(ModernCommandDesignTokens.sideColor(for: gameState.activeFaction.alignment))

                Spacer()

                if let onNewGame {
                    NewGameButton(action: onNewGame)
                }

                Button(action: onEndTurn) {
                    Label("End Turn", systemImage: "forward.end")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minHeight: ModernCommandDesignTokens.minimumTapSize)
                }
                .buttonStyle(.borderedProminent)
            }

            LazyVGrid(columns: statusColumns, alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                metric("Turn", "\(gameState.turn) / \(gameState.maxTurns)", icon: "clock")
                metric("Side", gameState.activeFaction.shortDisplayName, icon: "flag")
                metric("Phase", gameState.phase.displayName, icon: "arrow.triangle.2.circlepath")
                metric("Victory", victoryText, icon: "checkmark.seal")
                metric("Contacts", "\(visibleContacts.count)", icon: "dot.scope", tint: ModernCommandDesignTokens.sensor)
                metric("EW Zones", "\(activeEWEffects.count)", icon: "antenna.radiowaves.left.and.right", tint: ModernCommandDesignTokens.electronicWarfare)
                metric("Ammo", fireBudgetText, icon: "scope", tint: ModernCommandDesignTokens.fires)
                metric("Air", airTaskingText, icon: "airplane", tint: airTaskingTint)
                metric("Supply Risk", "\(supplyRiskCount)", icon: "cross.case", tint: supplyRiskTint)
                metric("C2 Queue", "\(activeLedger.productionQueue.count)", icon: "tray.full")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ModernCommandDesignTokens.padding)
        .background(ModernCommandDesignTokens.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius)
                .stroke(ModernCommandDesignTokens.panelStroke, lineWidth: 1)
        }
    }

    private func metric(_ label: String, _ value: String, icon: String, tint: Color = .secondary) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ModernCommandDesignTokens.compactSpacing)
        .padding(.vertical, 5)
        .frame(minHeight: ModernCommandDesignTokens.minimumTapSize, alignment: .leading)
        .background(ModernCommandDesignTokens.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))
    }

    private var victoryText: String {
        guard let winner = gameState.victoryState.winner else {
            return "Ongoing"
        }
        return "\(winner.shortDisplayName) Secured"
    }

    private var activeLedger: FactionEconomyLedger {
        gameState.economyState.ledger(for: gameState.activeFaction)
    }

    private var visibleContacts: [ContactTrack] {
        gameState.operationalAwareness.visibleContacts(for: gameState.activeFaction)
    }

    private var activeEWEffects: [EWEffect] {
        gameState.operationalAwareness.ewEffects.filter {
            $0.side == gameState.activeFaction.alignment
        }
    }

    private var fireBudgetText: String {
        let budget = gameState.fireSupportState.budget(for: gameState.activeFaction.alignment)
        return "T\(budget.tubeArtillery) R\(budget.rocket) P\(budget.precision) L\(budget.loitering)"
    }

    private var airTaskingText: String {
        let side = gameState.activeFaction.alignment
        let sorties = gameState.fireSupportState.airTaskingState.sorties.filter { $0.side == side }.count
        let superiority = gameState.fireSupportState.airTaskingState.airSuperiority[side] ?? 0
        return "\(sorties) / \(superiority)"
    }

    private var airTaskingTint: Color {
        let side = gameState.activeFaction.alignment
        let superiority = gameState.fireSupportState.airTaskingState.airSuperiority[side] ?? 0
        if superiority > 0 {
            return ModernCommandDesignTokens.sensor
        }
        if superiority < 0 {
            return ModernCommandDesignTokens.warning
        }
        return .secondary
    }

    private var supplyRiskCount: Int {
        gameState.divisions.filter {
            $0.faction == gameState.activeFaction && $0.supplyState != .supplied && !$0.isDestroyed
        }.count
    }

    private var supplyRiskTint: Color {
        supplyRiskCount > 0 ? ModernCommandDesignTokens.warning : ModernCommandDesignTokens.sustainment
    }
}
