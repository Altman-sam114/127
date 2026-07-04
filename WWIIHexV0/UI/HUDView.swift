import SwiftUI

struct HUDView: View {
    let gameState: GameState
    let onEndTurn: () -> Void
    let onNewGame: (() -> Void)?

    init(gameState: GameState, onEndTurn: @escaping () -> Void, onNewGame: (() -> Void)? = nil) {
        self.gameState = gameState
        self.onEndTurn = onEndTurn
        self.onNewGame = onNewGame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ardennes V0")
                    .font(.headline)

                Spacer()

                if let onNewGame {
                    NewGameButton(action: onNewGame)
                }

                Button(action: onEndTurn) {
                    Label("End Turn", systemImage: "forward.end")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .buttonStyle(.borderedProminent)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    metric("Turn", "\(gameState.turn) / \(gameState.maxTurns)")
                    metric("Faction", gameState.activeFaction.displayName)
                }

                GridRow {
                    metric("Phase", gameState.phase.displayName)
                    metric("Victory", victoryText)
                }

                GridRow {
                    metric("Manpower", "\(activeLedger.stockpile.manpower)")
                    metric("Industry", "\(activeLedger.stockpile.industry)")
                }

                GridRow {
                    metric("Supplies", "\(activeLedger.stockpile.supplies)")
                    metric("Queue", "\(activeLedger.productionQueue.count)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var victoryText: String {
        guard let winner = gameState.victoryState.winner else {
            return "Ongoing"
        }
        return "\(winner.displayName) Victory"
    }

    private var activeLedger: FactionEconomyLedger {
        gameState.economyState.ledger(for: gameState.activeFaction)
    }
}
