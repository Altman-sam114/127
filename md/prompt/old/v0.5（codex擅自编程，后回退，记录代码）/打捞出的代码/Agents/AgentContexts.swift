import Foundation

struct ForceSummary: Codable, Equatable {
    let faction: Faction
    let totalDivisions: Int
    let armorDivisions: Int
    let artilleryDivisions: Int
    let averageHP: Int
    let averageOrganization: Int
    let supplied: Int
    let lowSupply: Int
    let encircled: Int
}

struct ObjectiveSummary: Codable, Equatable {
    let id: String
    let name: String
    let controller: Faction?
    let type: ObjectiveType
}

struct FrontLineSummary: Codable, Equatable {
    let faction: Faction
    let contestedEdges: Int
    let friendlyControlledTiles: Int
    let enemyControlledTiles: Int
    let vulnerableObjectives: [String]
}

struct NationalContext: Codable, Equatable {
    let faction: Faction
    let turn: Int
    let maxTurns: Int
    let victorySummary: String
    let ownForces: ForceSummary
    let enemyForces: ForceSummary
    let objectives: [ObjectiveSummary]
    let frontLine: FrontLineSummary
    let activeDirectives: [String]
    let resourceStatus: String
    let threatSummary: String
}

struct MinisterContext: Codable, Equatable {
    let agentId: String
    let role: AgentRole
    let nationalContext: NationalContext
    let departmentFocus: String
    let facts: [String]
}

struct TheaterContext: Codable, Equatable {
    let faction: Faction
    let turn: Int
    let assignedDirectiveSummaries: [String]
    let frontLine: FrontLineSummary
    let availableDivisions: [String]
    let priorityObjectives: [ObjectiveSummary]
}

struct CommanderContext: Codable, Equatable {
    let agentId: String
    let faction: Faction
    let turn: Int
    let assignedDivisions: [Division]
    let nearbyKnownEnemies: [Division]
    let activeDirectives: [TheaterDirective]
}

struct AgentContextBuilder {
    let maxFacts: Int
    let maxActiveDirectives: Int

    init(maxFacts: Int = 8, maxActiveDirectives: Int = 6) {
        self.maxFacts = maxFacts
        self.maxActiveDirectives = maxActiveDirectives
    }

    func nationalContext(for faction: Faction, state: GameState) -> NationalContext {
        let activeDirectiveSummaries = state.directiveBoard
            .approvedDirectives
            .filter { $0.faction == faction }
            .prefix(maxActiveDirectives)
            .map { "\($0.title): \($0.summary)" }

        return NationalContext(
            faction: faction,
            turn: state.turn,
            maxTurns: state.maxTurns,
            victorySummary: victorySummary(state.victoryState),
            ownForces: forceSummary(for: faction, state: state),
            enemyForces: forceSummary(for: faction.opponent, state: state),
            objectives: objectiveSummaries(state: state),
            frontLine: frontLineSummary(for: faction, state: state),
            activeDirectives: Array(activeDirectiveSummaries),
            resourceStatus: "V0.5 placeholder: resources and factories are advisory only.",
            threatSummary: threatSummary(for: faction, state: state)
        )
    }

    func ministerContext(for agent: GameAgent, state: GameState) -> MinisterContext {
        let national = nationalContext(for: agent.faction, state: state)
        return MinisterContext(
            agentId: agent.id,
            role: agent.role,
            nationalContext: national,
            departmentFocus: departmentFocus(for: agent.role),
            facts: Array(departmentFacts(for: agent.role, nationalContext: national).prefix(maxFacts))
        )
    }

    func theaterContext(for faction: Faction, state: GameState) -> TheaterContext {
        let directives = state.directiveBoard
            .theaterDirectives
            .filter { $0.faction == faction }
            .prefix(maxActiveDirectives)
            .map(\.summary)

        return TheaterContext(
            faction: faction,
            turn: state.turn,
            assignedDirectiveSummaries: Array(directives),
            frontLine: frontLineSummary(for: faction, state: state),
            availableDivisions: state.divisions.filter { $0.faction == faction }.map(\.name),
            priorityObjectives: objectiveSummaries(state: state).filter { $0.controller != faction }
        )
    }

    func commanderContext(for agent: GameAgent, state: GameState) -> CommanderContext {
        let assigned = state.divisions.filter { agent.assignedDivisionIds.contains($0.id) }
        let activeDirectives = state.directiveBoard
            .theaterDirectives
            .filter { $0.faction == agent.faction && ($0.targetAgentId == nil || $0.targetAgentId == agent.id) }

        return CommanderContext(
            agentId: agent.id,
            faction: agent.faction,
            turn: state.turn,
            assignedDivisions: assigned,
            nearbyKnownEnemies: nearbyEnemies(for: assigned, faction: agent.faction, state: state),
            activeDirectives: activeDirectives
        )
    }

    private func forceSummary(for faction: Faction, state: GameState) -> ForceSummary {
        let divisions = state.divisions.filter { $0.faction == faction }
        let totalHP = divisions.reduce(0) { $0 + $1.hp }
        let totalOrganization = divisions.reduce(0) { $0 + $1.organization }
        let divisor = max(1, divisions.count)

        return ForceSummary(
            faction: faction,
            totalDivisions: divisions.count,
            armorDivisions: divisions.filter(\.isArmor).count,
            artilleryDivisions: divisions.filter(\.isArtillery).count,
            averageHP: totalHP / divisor,
            averageOrganization: totalOrganization / divisor,
            supplied: divisions.filter { $0.supplyState == .supplied }.count,
            lowSupply: divisions.filter { $0.supplyState == .lowSupply }.count,
            encircled: divisions.filter { $0.supplyState == .encircled }.count
        )
    }

    private func objectiveSummaries(state: GameState) -> [ObjectiveSummary] {
        state.map.objectives.map { objective in
            ObjectiveSummary(
                id: objective.id,
                name: objective.name,
                controller: state.map.tile(at: objective.coord)?.controller,
                type: objective.type
            )
        }
    }

    private func frontLineSummary(for faction: Faction, state: GameState) -> FrontLineSummary {
        var contestedEdges = 0
        var vulnerableObjectives: [String] = []

        for tile in state.map.tiles.values where tile.controller == faction {
            for neighborCoord in tile.coord.neighbors() {
                guard let neighbor = state.map.tile(at: neighborCoord), neighbor.controller == faction.opponent else {
                    continue
                }
                contestedEdges += 1
            }
        }

        for objective in state.map.objectives {
            guard let tile = state.map.tile(at: objective.coord), tile.controller == faction else {
                continue
            }

            let hasEnemyNeighbor = objective.coord.neighbors().contains {
                state.map.tile(at: $0)?.controller == faction.opponent
            }
            if hasEnemyNeighbor {
                vulnerableObjectives.append(objective.name)
            }
        }

        return FrontLineSummary(
            faction: faction,
            contestedEdges: contestedEdges,
            friendlyControlledTiles: state.map.tiles.values.filter { $0.controller == faction }.count,
            enemyControlledTiles: state.map.tiles.values.filter { $0.controller == faction.opponent }.count,
            vulnerableObjectives: vulnerableObjectives
        )
    }

    private func nearbyEnemies(for divisions: [Division], faction: Faction, state: GameState) -> [Division] {
        state.divisions
            .filter { enemy in
                enemy.faction == faction.opponent && divisions.contains { $0.coord.distance(to: enemy.coord) <= 4 }
            }
            .prefix(6)
            .map { $0 }
    }

    private func victorySummary(_ victoryState: VictoryState) -> String {
        if let winner = victoryState.winner {
            return "\(winner.displayName) victory: \(victoryState.reason?.displayName ?? "resolved")."
        }
        return "Victory unresolved."
    }

    private func threatSummary(for faction: Faction, state: GameState) -> String {
        let enemy = forceSummary(for: faction.opponent, state: state)
        if enemy.armorDivisions >= 2 {
            return "Enemy armored concentration detected."
        }
        if enemy.artilleryDivisions > 0 {
            return "Enemy artillery can shape key objectives."
        }
        return "No decisive enemy concentration detected."
    }

    private func departmentFocus(for role: AgentRole) -> String {
        switch role {
        case .armamentsMinister:
            return "Production, factories, equipment losses, and future research priorities."
        case .armyMinister:
            return "Manpower, organization, replacement priorities, training, and command assignments."
        case .foreignMinister:
            return "Diplomatic risks, alliance posture, escalation, and negotiation options."
        case .intelligenceMinister:
            return "Enemy threats, unknowns, weak points, and risk warnings."
        case .ruler:
            return "National strategy and final prioritization."
        case .fieldMarshal:
            return "Theater-level front planning."
        case .armyCommander:
            return "Operational execution with assigned divisions."
        }
    }

    private func departmentFacts(for role: AgentRole, nationalContext: NationalContext) -> [String] {
        switch role {
        case .armamentsMinister:
            return [
                "Own divisions: \(nationalContext.ownForces.totalDivisions).",
                "Average HP: \(nationalContext.ownForces.averageHP).",
                "Armored divisions: \(nationalContext.ownForces.armorDivisions).",
                nationalContext.resourceStatus
            ]
        case .armyMinister:
            return [
                "Average organization: \(nationalContext.ownForces.averageOrganization).",
                "Low supply divisions: \(nationalContext.ownForces.lowSupply).",
                "Encircled divisions: \(nationalContext.ownForces.encircled).",
                "Enemy divisions: \(nationalContext.enemyForces.totalDivisions)."
            ]
        case .foreignMinister:
            return [
                "War remains active.",
                "No v0.5 diplomatic action mutates state.",
                "Objectives contested: \(nationalContext.objectives.filter { $0.controller != nationalContext.faction }.count)."
            ]
        case .intelligenceMinister:
            return [
                nationalContext.threatSummary,
                "Contested front edges: \(nationalContext.frontLine.contestedEdges).",
                "Vulnerable objectives: \(nationalContext.frontLine.vulnerableObjectives.joined(separator: ", "))."
            ]
        default:
            return [
                nationalContext.victorySummary,
                "Active directives: \(nationalContext.activeDirectives.count)."
            ]
        }
    }
}
