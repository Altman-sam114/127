import Foundation

struct MinisterDecisionEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let agentId: String
    let role: AgentRole
    let turn: Int
    let directives: [StrategicDirective]
}

protocol MinisterDecisionProviding {
    func decisions(for agent: GameAgent, context: MinisterContext) -> MinisterDecisionEnvelope
}

struct MockMinisterDecisionProvider: MinisterDecisionProviding {
    func decisions(for agent: GameAgent, context: MinisterContext) -> MinisterDecisionEnvelope {
        let directive: StrategicDirective

        switch agent.role {
        case .armamentsMinister:
            directive = armamentsDirective(agent: agent, context: context)
        case .armyMinister:
            directive = armyDirective(agent: agent, context: context)
        case .foreignMinister:
            directive = foreignDirective(agent: agent, context: context)
        case .intelligenceMinister:
            directive = intelligenceDirective(agent: agent, context: context)
        default:
            directive = genericDirective(agent: agent, context: context)
        }

        return MinisterDecisionEnvelope(
            schemaVersion: 1,
            agentId: agent.id,
            role: agent.role,
            turn: context.nationalContext.turn,
            directives: [directive]
        )
    }

    private func armamentsDirective(agent: GameAgent, context: MinisterContext) -> StrategicDirective {
        let own = context.nationalContext.ownForces
        let needsArmor = own.armorDivisions < context.nationalContext.enemyForces.armorDivisions
        return makeDirective(
            agent: agent,
            context: context,
            domain: .production,
            kind: .productionPriority,
            title: needsArmor ? "Prioritize armored replacements" : "Maintain artillery and vehicle output",
            summary: needsArmor
                ? "Shift advisory production priority toward tanks and recovery vehicles."
                : "Keep production balanced while preserving artillery support capacity.",
            urgency: own.averageHP <= 7 ? .high : .normal,
            rationale: context.facts.joined(separator: " ")
        )
    }

    private func armyDirective(agent: GameAgent, context: MinisterContext) -> StrategicDirective {
        let own = context.nationalContext.ownForces
        let urgentRecovery = own.averageOrganization < 65 || own.lowSupply + own.encircled > 0
        return makeDirective(
            agent: agent,
            context: context,
            domain: urgentRecovery ? .logistics : .army,
            kind: urgentRecovery ? .manpowerRecovery : .reinforceFront,
            title: urgentRecovery ? "Recover organization before major push" : "Keep frontline reserves ready",
            summary: urgentRecovery
                ? "Advise rest, replacements, and supply recovery before committing to a broad attack."
                : "Maintain reserves and prepare reinforcement routes behind key objectives.",
            urgency: urgentRecovery ? .high : .normal,
            rationale: context.facts.joined(separator: " ")
        )
    }

    private func foreignDirective(agent: GameAgent, context: MinisterContext) -> StrategicDirective {
        makeDirective(
            agent: agent,
            context: context,
            domain: .diplomacy,
            kind: .diplomaticRisk,
            title: "Monitor diplomatic escalation",
            summary: "No diplomatic state mutation in v0.5; keep the player informed about escalation risk.",
            urgency: .low,
            rationale: context.facts.joined(separator: " ")
        )
    }

    private func intelligenceDirective(agent: GameAgent, context: MinisterContext) -> StrategicDirective {
        let objective = context.nationalContext.objectives.first { $0.controller == context.nationalContext.faction.opponent }
        return makeDirective(
            agent: agent,
            context: context,
            domain: .intelligence,
            kind: .threatAssessment,
            title: "Assess enemy concentration",
            summary: context.nationalContext.threatSummary,
            targetObjectiveId: objective?.id,
            urgency: context.nationalContext.enemyForces.armorDivisions >= 2 ? .high : .normal,
            rationale: context.facts.joined(separator: " ")
        )
    }

    private func genericDirective(agent: GameAgent, context: MinisterContext) -> StrategicDirective {
        makeDirective(
            agent: agent,
            context: context,
            domain: agent.allowedDirectiveDomains.first ?? .politics,
            kind: .playerOrder,
            title: "Review national posture",
            summary: "Provide role-appropriate advisory input.",
            urgency: .normal,
            rationale: context.facts.joined(separator: " ")
        )
    }

    private func makeDirective(
        agent: GameAgent,
        context: MinisterContext,
        domain: DirectiveDomain,
        kind: DirectiveKind,
        title: String,
        summary: String,
        targetObjectiveId: String? = nil,
        urgency: DirectiveUrgency,
        rationale: String
    ) -> StrategicDirective {
        StrategicDirective(
            id: "\(agent.id)_\(kind.rawValue)_turn_\(context.nationalContext.turn)",
            faction: agent.faction,
            issuedByAgentId: agent.id,
            issuedByRole: agent.role,
            domain: domain,
            kind: kind,
            title: title,
            summary: summary,
            targetRegionId: nil,
            targetObjectiveId: targetObjectiveId,
            targetAgentId: nil,
            urgency: urgency,
            status: .proposed,
            rationale: rationale,
            createdTurn: context.nationalContext.turn,
            expiresOnTurn: context.nationalContext.turn + 2,
            sourceJSON: nil
        )
    }
}
