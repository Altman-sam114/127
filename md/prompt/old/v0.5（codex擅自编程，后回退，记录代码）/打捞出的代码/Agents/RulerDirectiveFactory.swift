import Foundation

struct RulerDirectiveFactory {
    func directive(from input: PlayerDirectiveInput, ruler: GameAgent?) -> StrategicDirective {
        let text = input.playerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = inferredDomain(from: text)
        let kind = inferredKind(from: text, domain: domain)
        let targetObjectiveId = inferredObjectiveId(from: text)
        let title = titleForDirective(text: text, kind: kind)

        return StrategicDirective(
            id: "player_directive_\(input.faction.rawValue)_turn_\(input.createdTurn)_\(abs(text.hashValue))",
            faction: input.faction,
            issuedByAgentId: ruler?.id ?? "\(input.faction.rawValue)_player_ruler",
            issuedByRole: .ruler,
            domain: domain,
            kind: kind,
            title: title,
            summary: text.isEmpty ? "Player issued an empty strategic directive." : text,
            targetRegionId: nil,
            targetObjectiveId: targetObjectiveId,
            targetAgentId: input.targetAgentId,
            urgency: inferredUrgency(from: text),
            status: .proposed,
            rationale: "Player-issued national directive.",
            createdTurn: input.createdTurn,
            expiresOnTurn: input.createdTurn + 3,
            sourceJSON: nil
        )
    }

    private func inferredDomain(from text: String) -> DirectiveDomain {
        let lower = text.lowercased()
        if lower.contains("生产") || lower.contains("工厂") || lower.contains("装备") || lower.contains("production") {
            return .production
        }
        if lower.contains("科技") || lower.contains("research") || lower.contains("tech") {
            return .research
        }
        if lower.contains("外交") || lower.contains("停战") || lower.contains("diplomacy") {
            return .diplomacy
        }
        if lower.contains("情报") || lower.contains("侦察") || lower.contains("intelligence") {
            return .intelligence
        }
        if lower.contains("补给") || lower.contains("休整") || lower.contains("补员") || lower.contains("supply") {
            return .logistics
        }
        return .operations
    }

    private func inferredKind(from text: String, domain: DirectiveDomain) -> DirectiveKind {
        let lower = text.lowercased()
        switch domain {
        case .production:
            return .productionPriority
        case .research:
            return .researchPriority
        case .diplomacy:
            return .diplomaticRisk
        case .intelligence:
            return .threatAssessment
        case .logistics:
            return .improveSupply
        default:
            if lower.contains("防守") || lower.contains("守住") || lower.contains("defend") {
                return .defendObjective
            }
            return .attackAxis
        }
    }

    private func inferredObjectiveId(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("bastogne") || lower.contains("巴斯托涅") {
            return "bastogne"
        }
        if lower.contains("st. vith") || lower.contains("圣维特") {
            return "st_vith"
        }
        if lower.contains("houffalize") || lower.contains("乌法利兹") {
            return "houffalize"
        }
        return nil
    }

    private func inferredUrgency(from text: String) -> DirectiveUrgency {
        let lower = text.lowercased()
        if lower.contains("立即") || lower.contains("马上") || lower.contains("critical") {
            return .critical
        }
        if lower.contains("优先") || lower.contains("尽快") || lower.contains("high") {
            return .high
        }
        return .normal
    }

    private func titleForDirective(text: String, kind: DirectiveKind) -> String {
        if text.isEmpty {
            return "Player strategic directive"
        }

        switch kind {
        case .attackAxis:
            return "Player attack directive"
        case .defendObjective:
            return "Player defense directive"
        case .productionPriority:
            return "Player production directive"
        case .researchPriority:
            return "Player research directive"
        case .diplomaticRisk:
            return "Player diplomacy directive"
        case .threatAssessment:
            return "Player intelligence directive"
        case .improveSupply:
            return "Player logistics directive"
        default:
            return "Player strategic directive"
        }
    }
}
