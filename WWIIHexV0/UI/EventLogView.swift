import SwiftUI

struct EventLogView: View {
    let entries: [GameLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Log")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if recentEntries.isEmpty {
                        Text("No events yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentEntries) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.category.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.category.foregroundStyle)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(item.category.backgroundStyle)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text(metadata(for: item.entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(item.entry.message)
                                    .font(.body)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minHeight: 120)
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var recentEntries: [LogDisplayEntry] {
        entries
            .suffix(60)
            .reversed()
            .map { LogDisplayEntry(entry: $0, category: LogDisplayCategory(entry: $0)) }
    }

    private func metadata(for entry: GameLogEntry) -> String {
        let faction = entry.faction?.displayName ?? "System"
        let phase = entry.phase?.displayName ?? "Setup"
        if entry.relatedRecordId != nil {
            return "Turn \(entry.turn) - \(faction) - \(phase) - Directive linked"
        }
        return "Turn \(entry.turn) - \(faction) - \(phase)"
    }
}

private struct LogDisplayEntry: Identifiable {
    let entry: GameLogEntry
    let category: LogDisplayCategory

    var id: UUID {
        entry.id
    }
}

private enum LogDisplayCategory {
    case combat
    case retreat
    case reinforcement
    case encirclement
    case supply
    case frontChange
    case theaterChange
    case regionOwnerChange
    case diplomacy
    case intelligence
    case electronicWarfare
    case fireSupport
    case event

    init(entry: GameLogEntry) {
        switch entry.category {
        case .combat:
            self = .combat
            return
        case .retreat:
            self = .retreat
            return
        case .reinforce:
            self = .reinforcement
            return
        case .encircle:
            self = .encirclement
            return
        case .supply:
            self = .supply
            return
        case .frontChange:
            self = .frontChange
            return
        case .theaterChange:
            self = .theaterChange
            return
        case .regionOwnerChange:
            self = .regionOwnerChange
            return
        case .diplomacy:
            self = .diplomacy
            return
        case .intelligence:
            self = .intelligence
            return
        case .electronicWarfare:
            self = .electronicWarfare
            return
        case .fireSupport:
            self = .fireSupport
            return
        case .event:
            break
        }

        let message = entry.message
        let text = message.lowercased()

        if text.contains("retreat") || text.contains("routed") || text.contains("routing") {
            self = .retreat
        } else if text.contains("reinforce") || text.contains("replacement") || text.contains("replenish") {
            self = .reinforcement
        } else if text.contains("encircle") || text.contains("encircled") {
            self = .encirclement
        } else if text.contains("attack") || text.contains("damage") || text.contains("combat") || text.contains("hit") {
            self = .combat
        } else if text.contains("supply") || text.contains("supplied") {
            self = .supply
        } else {
            self = .event
        }
    }

    var displayName: String {
        switch self {
        case .combat:
            return "Combat"
        case .retreat:
            return "Retreat"
        case .reinforcement:
            return "Reinforce"
        case .encirclement:
            return "Encircle"
        case .supply:
            return "Logistics"
        case .frontChange:
            return "Front"
        case .theaterChange:
            return "Operational"
        case .regionOwnerChange:
            return "Region"
        case .diplomacy:
            return "Diplomacy"
        case .intelligence:
            return "Intel"
        case .electronicWarfare:
            return "EW"
        case .fireSupport:
            return "Fires"
        case .event:
            return "Event"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .combat:
            return .red
        case .retreat:
            return .orange
        case .reinforcement:
            return .green
        case .encirclement:
            return .purple
        case .supply:
            return .teal
        case .frontChange:
            return .blue
        case .theaterChange:
            return .indigo
        case .regionOwnerChange:
            return .mint
        case .diplomacy:
            return .cyan
        case .intelligence:
            return .yellow
        case .electronicWarfare:
            return .pink
        case .fireSupport:
            return .orange
        case .event:
            return .secondary
        }
    }

    var backgroundStyle: Color {
        foregroundStyle.opacity(0.12)
    }
}
