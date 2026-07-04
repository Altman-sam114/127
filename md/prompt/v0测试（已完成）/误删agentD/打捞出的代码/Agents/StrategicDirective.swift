import Foundation

enum DirectiveDomain: String, Codable, Equatable, CaseIterable {
    case operations
    case logistics
    case production
    case research
    case army
    case diplomacy
    case intelligence
    case politics

    var displayName: String {
        rawValue.capitalized
    }
}

enum DirectiveKind: String, Codable, Equatable, CaseIterable {
    case attackAxis
    case defendObjective
    case reinforceFront
    case improveSupply
    case productionPriority
    case researchPriority
    case manpowerRecovery
    case diplomaticRisk
    case threatAssessment
    case playerOrder
}

enum DirectiveStatus: String, Codable, Equatable, CaseIterable {
    case proposed
    case approved
    case rejected
    case active
    case expired
    case completed
}

enum DirectiveUrgency: String, Codable, Equatable, CaseIterable {
    case low
    case normal
    case high
    case critical

    var score: Int {
        switch self {
        case .low:
            return 10
        case .normal:
            return 20
        case .high:
            return 30
        case .critical:
            return 40
        }
    }
}

struct StrategicDirective: Identifiable, Codable, Equatable {
    let id: String
    var faction: Faction
    var issuedByAgentId: String
    var issuedByRole: AgentRole
    var domain: DirectiveDomain
    var kind: DirectiveKind
    var title: String
    var summary: String
    var targetRegionId: String?
    var targetObjectiveId: String?
    var targetAgentId: String?
    var urgency: DirectiveUrgency
    var status: DirectiveStatus
    var rationale: String
    var createdTurn: Int
    var expiresOnTurn: Int?
    var sourceJSON: String?

    var isUnitLevelCommand: Bool {
        false
    }
}

struct DirectiveDecisionLog: Identifiable, Codable, Equatable {
    let id: UUID
    let turn: Int
    let directiveId: String
    let status: DirectiveStatus
    let reason: String

    init(
        id: UUID = UUID(),
        turn: Int,
        directiveId: String,
        status: DirectiveStatus,
        reason: String
    ) {
        self.id = id
        self.turn = turn
        self.directiveId = directiveId
        self.status = status
        self.reason = reason
    }
}

struct TheaterDirective: Identifiable, Codable, Equatable {
    let id: String
    let sourceDirectiveId: String
    let faction: Faction
    let targetAgentId: String?
    let summary: String
    let targetObjectiveId: String?
    let targetRegionId: String?
    let priority: Int
}

struct PlayerDirectiveInput: Codable, Equatable {
    let faction: Faction
    let playerText: String
    let targetAgentId: String?
    let createdTurn: Int
}

struct DirectiveBoard: Codable, Equatable {
    var directives: [StrategicDirective]
    var theaterDirectives: [TheaterDirective]
    var decisionLog: [DirectiveDecisionLog]

    static var empty: DirectiveBoard {
        DirectiveBoard(directives: [], theaterDirectives: [], decisionLog: [])
    }

    var proposedDirectives: [StrategicDirective] {
        directives.filter { $0.status == .proposed }
    }

    var approvedDirectives: [StrategicDirective] {
        directives.filter { [.approved, .active].contains($0.status) }
    }

    var rejectedDirectives: [StrategicDirective] {
        directives.filter { $0.status == .rejected }
    }

    mutating func submit(_ directive: StrategicDirective) {
        directives.append(directive)
    }

    mutating func arbitrate(cabinetState: CabinetState, turn: Int) {
        let proposed = proposedDirectives
        guard !proposed.isEmpty else {
            return
        }

        let groups = Dictionary(grouping: proposed, by: conflictKey)
        for group in groups.values {
            approveBestDirective(in: group, cabinetState: cabinetState, turn: turn)
        }
    }

    mutating func expireDirectives(currentTurn: Int) {
        for index in directives.indices {
            guard let expiresOnTurn = directives[index].expiresOnTurn,
                  currentTurn > expiresOnTurn,
                  [.proposed, .approved, .active].contains(directives[index].status) else {
                continue
            }

            directives[index].status = .expired
            decisionLog.append(
                DirectiveDecisionLog(
                    turn: currentTurn,
                    directiveId: directives[index].id,
                    status: .expired,
                    reason: "Directive expired on turn \(expiresOnTurn)."
                )
            )
        }
    }

    mutating func downlinkApprovedDirectives(cabinetState: CabinetState) {
        for directive in approvedDirectives where !theaterDirectives.contains(where: { $0.sourceDirectiveId == directive.id }) {
            let theaterDirective = TheaterDirective(
                id: "theater_\(directive.id)",
                sourceDirectiveId: directive.id,
                faction: directive.faction,
                targetAgentId: directive.targetAgentId ?? defaultCommanderId(for: directive, cabinetState: cabinetState),
                summary: directive.summary,
                targetObjectiveId: directive.targetObjectiveId,
                targetRegionId: directive.targetRegionId,
                priority: directive.urgency.score + cabinetState.authorityRank(for: directive.issuedByAgentId)
            )
            theaterDirectives.append(theaterDirective)
        }
    }

    private func conflictKey(for directive: StrategicDirective) -> String {
        [
            directive.faction.rawValue,
            directive.domain.rawValue,
            directive.targetObjectiveId ?? directive.targetRegionId ?? directive.targetAgentId ?? "general"
        ].joined(separator: ":")
    }

    private mutating func approveBestDirective(
        in group: [StrategicDirective],
        cabinetState: CabinetState,
        turn: Int
    ) {
        guard let winner = group.max(by: { directiveScore($0, cabinetState: cabinetState) < directiveScore($1, cabinetState: cabinetState) }) else {
            return
        }

        for directive in group {
            guard let index = directives.firstIndex(where: { $0.id == directive.id }) else {
                continue
            }

            if directive.id == winner.id {
                directives[index].status = .approved
                decisionLog.append(
                    DirectiveDecisionLog(
                        turn: turn,
                        directiveId: directive.id,
                        status: .approved,
                        reason: "Approved by authority and urgency score."
                    )
                )
            } else {
                directives[index].status = .rejected
                decisionLog.append(
                    DirectiveDecisionLog(
                        turn: turn,
                        directiveId: directive.id,
                        status: .rejected,
                        reason: "Rejected due to conflict with \(winner.title)."
                    )
                )
            }
        }
    }

    private func directiveScore(_ directive: StrategicDirective, cabinetState: CabinetState) -> Int {
        cabinetState.authorityRank(for: directive.issuedByAgentId) + directive.urgency.score
    }

    private func defaultCommanderId(for directive: StrategicDirective, cabinetState: CabinetState) -> String? {
        cabinetState
            .cabinet(for: directive.faction)?
            .agents
            .first(where: { $0.role == .fieldMarshal || $0.role == .armyCommander })?
            .id
    }
}
