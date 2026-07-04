import Foundation

struct CabinetPanelModel: Equatable {
    struct AgentRow: Identifiable, Equatable {
        let id: String
        let name: String
        let role: String
        let authority: String
        let relationship: String
    }

    struct DirectiveRow: Identifiable, Equatable {
        let id: String
        let title: String
        let status: String
        let issuer: String
        let domain: String
        let summary: String
    }

    let factionName: String
    let agents: [AgentRow]
    let proposedDirectives: [DirectiveRow]
    let approvedDirectives: [DirectiveRow]
    let rejectedDirectives: [DirectiveRow]
    let theaterDirectives: [DirectiveRow]
    let decisionLog: [String]
    let rawJSON: String

    init(gameState: GameState, faction: Faction) {
        factionName = faction.displayName
        let cabinet = gameState.cabinetState.cabinet(for: faction)
        let agentLookup = Dictionary(uniqueKeysWithValues: (cabinet?.agents ?? []).map { ($0.id, $0) })

        agents = (cabinet?.agents ?? []).map {
            AgentRow(
                id: $0.id,
                name: $0.name,
                role: $0.role.displayName,
                authority: $0.authority.displayName,
                relationship: "L\($0.relationship.loyalty) T\($0.relationship.trust) S\($0.relationship.satisfaction)"
            )
        }

        proposedDirectives = Self.directiveRows(
            gameState.directiveBoard.proposedDirectives.filter { $0.faction == faction },
            agentLookup: agentLookup
        )
        approvedDirectives = Self.directiveRows(
            gameState.directiveBoard.approvedDirectives.filter { $0.faction == faction },
            agentLookup: agentLookup
        )
        rejectedDirectives = Self.directiveRows(
            gameState.directiveBoard.rejectedDirectives.filter { $0.faction == faction },
            agentLookup: agentLookup
        )
        theaterDirectives = gameState.directiveBoard
            .theaterDirectives
            .filter { $0.faction == faction }
            .map {
                DirectiveRow(
                    id: $0.id,
                    title: "Downlinked order",
                    status: "theater",
                    issuer: $0.targetAgentId ?? "unassigned",
                    domain: "operations",
                    summary: $0.summary
                )
            }

        decisionLog = gameState.directiveBoard
            .decisionLog
            .suffix(8)
            .map { "\($0.status.rawValue): \($0.directiveId) - \($0.reason)" }

        rawJSON = Self.rawJSON(for: gameState.directiveBoard, faction: faction)
    }

    private static func directiveRows(
        _ directives: [StrategicDirective],
        agentLookup: [String: GameAgent]
    ) -> [DirectiveRow] {
        directives.map {
            DirectiveRow(
                id: $0.id,
                title: $0.title,
                status: $0.status.rawValue,
                issuer: agentLookup[$0.issuedByAgentId]?.name ?? $0.issuedByAgentId,
                domain: $0.domain.displayName,
                summary: $0.summary
            )
        }
    }

    private static func rawJSON(for board: DirectiveBoard, faction: Faction) -> String {
        let directives = board.directives.filter { $0.faction == faction }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(directives),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }
}
