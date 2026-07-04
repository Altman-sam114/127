import Foundation

struct NationalCabinetCatalogDefinition: Codable, Equatable {
    let schemaVersion: Int
    let cabinets: [NationalCabinetDefinition]
}

struct NationalCabinetDefinition: Codable, Equatable {
    let faction: String
    let agents: [GameAgentDefinition]
}

struct GameAgentDefinition: Codable, Equatable {
    let id: String
    let name: String
    let faction: String
    let role: String
    let authority: String
    let personality: AgentPersonalityDefinition
    let relationship: AgentRelationshipDefinition
    let memory: AgentMemoryDefinition?
    let assignedDivisionIds: [String]
}

struct AgentPersonalityDefinition: Codable, Equatable {
    let prompt: String
    let traits: [String]
    let aggression: Int
    let riskTolerance: Int
    let autonomy: Int
}

struct AgentRelationshipDefinition: Codable, Equatable {
    let loyalty: Int
    let trust: Int
    let satisfaction: Int
}

struct AgentMemoryDefinition: Codable, Equatable {
    let shortTermBattleNotes: [String]
    let longTermTendencies: [String]
    let recentDirectiveIds: [String]
}

extension NationalCabinetCatalogDefinition {
    func makeCabinetState() throws -> CabinetState {
        let cabinets = try cabinets.map { try $0.makeCabinet() }
        return CabinetState(cabinets: cabinets)
    }
}

extension NationalCabinetDefinition {
    func makeCabinet() throws -> NationalCabinet {
        guard let faction = Faction(rawValue: faction) else {
            throw DataLoaderError.validationFailed([
                DataValidationError(message: "Unknown cabinet faction \(self.faction).")
            ])
        }

        return NationalCabinet(
            faction: faction,
            agents: try agents.map { try $0.makeGameAgent(defaultFaction: faction) }
        )
    }
}

extension GameAgentDefinition {
    func makeGameAgent(defaultFaction: Faction) throws -> GameAgent {
        let resolvedFaction: Faction
        if faction.isEmpty {
            resolvedFaction = defaultFaction
        } else if let parsedFaction = Faction(rawValue: faction) {
            resolvedFaction = parsedFaction
        } else {
            throw DataLoaderError.validationFailed([
                DataValidationError(message: "Unknown agent faction \(faction) for \(id).")
            ])
        }

        guard let parsedRole = AgentRole(rawValue: role) else {
            throw DataLoaderError.validationFailed([
                DataValidationError(message: "Unknown agent role \(role) for \(id).")
            ])
        }

        guard let parsedAuthority = AgentAuthorityLevel(rawValue: authority) else {
            throw DataLoaderError.validationFailed([
                DataValidationError(message: "Unknown agent authority \(authority) for \(id).")
            ])
        }

        return GameAgent(
            id: id,
            name: name,
            faction: resolvedFaction,
            role: parsedRole,
            authority: parsedAuthority,
            personality: AgentPersonality(
                prompt: personality.prompt,
                traits: personality.traits,
                aggression: personality.aggression,
                riskTolerance: personality.riskTolerance,
                autonomy: personality.autonomy
            ),
            relationship: AgentRelationship(
                loyalty: relationship.loyalty,
                trust: relationship.trust,
                satisfaction: relationship.satisfaction
            ),
            memory: memory.map {
                AgentMemory(
                    shortTermBattleNotes: $0.shortTermBattleNotes,
                    longTermTendencies: $0.longTermTendencies,
                    recentDirectiveIds: $0.recentDirectiveIds
                )
            } ?? .empty,
            assignedDivisionIds: assignedDivisionIds
        )
    }
}
