import Foundation

struct MockAICommanderConfig {
    static let attackThreshold: Double = 1.2
    static let defendThreshold: Double = 1.2
}

struct MockAICommander {
    let attackRatio: Double
    let defendRatio: Double

    init(
        attackRatio: Double = MockAICommanderConfig.attackThreshold,
        defendRatio: Double = MockAICommanderConfig.defendThreshold
    ) {
        self.attackRatio = attackRatio
        self.defendRatio = defendRatio
    }

    func directive(
        for zoneId: FrontZoneId,
        in state: GameState,
        issuerId: String = "mock_ai"
    ) -> ZoneDirective? {
        guard let zone = state.warDeploymentState.frontZones[zoneId],
              !zone.frontSegments.isEmpty else {
            return nil
        }

        let agent = ZoneCommanderAgent(
            config: Self.defaultConfig(for: zone),
            classifier: BinaryTacticClassifier(attackThreshold: attackRatio)
        )
        guard var directive = agent.makeDirective(for: zone, in: state) else {
            return nil
        }

        if case .attack(let parameters) = directive.parameters,
           attackIntensity(for: zone, state: state) == .allOut {
            directive = ZoneDirective(
                zoneId: directive.zoneId,
                attack: AttackParameters(
                    targetTheaterId: parameters.targetTheaterId,
                    weightedRegions: parameters.weightedRegions,
                    intensity: .allOut,
                    focusRegionId: parameters.focusRegionId,
                    supportRegionIds: parameters.supportRegionIds,
                    convergenceRegionId: parameters.convergenceRegionId,
                    coordinatedZoneIds: parameters.coordinatedZoneIds,
                    maxCommittedUnits: parameters.maxCommittedUnits,
                    exploitDepth: parameters.exploitDepth
                ),
                category: directive.category,
                tactic: directive.tactic,
                commandTarget: directive.commandTarget
            )
        }

        return directive
    }

    func envelope(
        for faction: Faction,
        in state: GameState,
        issuerId: String = "mock_ai"
    ) -> DirectiveEnvelope {
        let directives = state.warDeploymentState.frontZones.values
            .filter { $0.faction == faction && !$0.frontSegments.isEmpty }
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .compactMap { directive(for: $0.id, in: state, issuerId: issuerId) }

        return DirectiveEnvelope(
            issuerId: issuerId,
            turn: state.turn,
            directives: directives,
            commanderAgentId: issuerId,
            theaterContext: "\(faction.displayName): \(directives.count) local planner directive(s)."
        )
    }

    func jsonEnvelope(
        for faction: Faction,
        in state: GameState,
        issuerId: String = "mock_ai"
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope(for: faction, in: state, issuerId: issuerId))
        return String(decoding: data, as: UTF8.self)
    }

    private static func defaultConfig(for zone: FrontZone) -> ZoneCommanderAgentConfig {
        ZoneCommanderAgentConfig(
            id: "mock_\(zone.id.rawValue)",
            name: "Local Planner (\(zone.id.rawValue))",
            faction: zone.faction,
            assignedZoneId: zone.id,
            skills: [],
            commandStyle: .balanced
        )
    }

    private func attackIntensity(for zone: FrontZone, state: GameState) -> AttackIntensity {
        let friendlyStrength = friendlyFrontStrength(zone: zone, state: state)
        let visibleEnemyStrength = visibleEnemyStrength(zone: zone, state: state)
        let ratio = visibleEnemyStrength == 0
            ? Double(friendlyStrength)
            : Double(friendlyStrength) / Double(visibleEnemyStrength)
        return ratio >= 2.0 ? .allOut : .limitedCounter
    }

    private func friendlyFrontStrength(zone: FrontZone, state: GameState) -> Int {
        let frontUnitIds = Set(zone.unitsFront + zone.frontSegments.flatMap(\.assignedFrontUnitIds))
        return state.divisions
            .filter { frontUnitIds.contains($0.id) && $0.faction == zone.faction && !$0.isDestroyed }
            .reduce(0) { $0 + max(1, $1.strength) + max(1, $1.attack) }
    }

    private func visibleEnemyStrength(zone: FrontZone, state: GameState) -> Int {
        let visibleRegionIds = Set(zone.frontSegments.flatMap { segment in
            [segment.regionId] + state.map.neighbors(of: segment.regionId)
        })
        return state.operationalAwareness.visibleContacts(for: zone.faction)
            .filter { contact in
                guard let regionId = state.map.region(for: contact.lastKnownCoord) else {
                    return false
                }
                return visibleRegionIds.contains(regionId)
            }
            .reduce(0) { $0 + VisibilityRules().contactStrengthEstimate($1) }
    }
}
