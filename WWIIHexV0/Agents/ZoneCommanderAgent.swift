import Foundation

struct ZoneCommanderAgentConfig: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let faction: Faction
    let assignedZoneId: FrontZoneId
    let skills: [String]
    let commandStyle: CommandStyle

    enum CommandStyle: String, Codable, Equatable {
        case aggressive
        case balanced
        case cautious
    }
}

struct TacticConditionChecker {
    func canUseTactic(
        _ tactic: TacticName,
        commander: ZoneCommanderAgentConfig?,
        zone: FrontZone,
        state: GameState
    ) -> Bool {
        let zoneUnitIds = Set(zone.unitsFront + zone.unitsDepth + zone.unitsGarrison)
        let zoneUnits = state.divisions.filter {
            zoneUnitIds.contains($0.id)
                && $0.faction == zone.faction
                && !$0.isDestroyed
        }

        switch tactic {
        case .standardAttack,
             .holdPosition,
             .elasticDefense,
             .lastStand:
            return true
        case .blitzkrieg,
             .guerrillaWarfare:
            return zoneUnits.contains { isMobile($0) }
        case .spearhead,
             .breakthrough,
             .pincerMovement:
            return !zoneUnits.filter(\.canAct).isEmpty
        case .fireCoverage:
            return zoneUnits.contains { $0.isArtillery || $0.range > 1 }
        case .feint:
            return !zone.unitsFront.isEmpty
        case .defenseInDepth:
            return !zone.unitsDepth.isEmpty
        }
    }

    private func isMobile(_ division: Division) -> Bool {
        division.isArmor
            || division.isMechanized
            || division.movement >= 5
    }
}

private struct RegionFocusSortKey: Comparable {
    let enemyStrength: Int
    let movementCost: Int
    let roadPenalty: Int
    let valueScore: Int
    let id: String

    static func < (lhs: RegionFocusSortKey, rhs: RegionFocusSortKey) -> Bool {
        if lhs.enemyStrength != rhs.enemyStrength {
            return lhs.enemyStrength < rhs.enemyStrength
        }
        if lhs.movementCost != rhs.movementCost {
            return lhs.movementCost < rhs.movementCost
        }
        if lhs.roadPenalty != rhs.roadPenalty {
            return lhs.roadPenalty < rhs.roadPenalty
        }
        if lhs.valueScore != rhs.valueScore {
            return lhs.valueScore > rhs.valueScore
        }
        return lhs.id < rhs.id
    }
}

struct BinaryTacticClassifier {
    let attackThreshold: Double

    init(attackThreshold: Double = MockAICommanderConfig.attackThreshold) {
        self.attackThreshold = attackThreshold
    }

    struct Classification: Equatable {
        let category: CommandCategory
        let tactic: TacticName
        let confidence: Double
        let reason: String
    }

    func classify(
        friendlyStrength: Int,
        visibleEnemyStrength: Int,
        hasContestedForwardPresence: Bool,
        hasStaticDefense: Bool,
        config: ZoneCommanderAgentConfig,
        mobileFriendlyStrength: Int = 0,
        artillerySupportStrength: Int = 0,
        depthStrength: Int = 0,
        pressure: Int = 0,
        supplyWarningCount: Int = 0,
        visibleEnemyRegionCount: Int = 0
    ) -> Classification {
        let ratio = visibleEnemyStrength == 0
            ? Double(friendlyStrength)
            : Double(friendlyStrength) / Double(visibleEnemyStrength)

        let styleBoost: Double
        switch config.commandStyle {
        case .aggressive:
            styleBoost = 0.15
        case .balanced:
            styleBoost = 0
        case .cautious:
            styleBoost = -0.15
        }

        let adjustedRatio = ratio + styleBoost
        let mobileRatio = friendlyStrength == 0
            ? 0
            : Double(mobileFriendlyStrength) / Double(friendlyStrength)
        let shouldAttack = adjustedRatio >= attackThreshold
            || hasContestedForwardPresence
            || hasStaticDefense

        if shouldAttack {
            if mobileFriendlyStrength > 0,
               mobileRatio >= 0.35,
               adjustedRatio >= 1.65 {
                return Classification(
                    category: .offense,
                    tactic: .blitzkrieg,
                    confidence: min(1, adjustedRatio / 2.4),
                    reason: "mobile_superiority"
                )
            }
            if mobileFriendlyStrength > 0,
               mobileRatio >= 0.25,
               adjustedRatio >= 1.35,
               visibleEnemyRegionCount > 0 {
                return Classification(
                    category: .offense,
                    tactic: .spearhead,
                    confidence: min(1, adjustedRatio / 2.25),
                    reason: "spearhead_focus"
                )
            }
            if adjustedRatio >= 1.35,
               visibleEnemyRegionCount > 0 {
                return Classification(
                    category: .offense,
                    tactic: .breakthrough,
                    confidence: min(1, adjustedRatio / 2.2),
                    reason: "breakthrough_odds"
                )
            }
            if artillerySupportStrength > 0,
               adjustedRatio < attackThreshold + 0.25 {
                return Classification(
                    category: .offense,
                    tactic: .fireCoverage,
                    confidence: min(1, 0.55 + Double(artillerySupportStrength) / Double(max(1, friendlyStrength)) / 2),
                    reason: "artillery_preparation"
                )
            }
            if adjustedRatio < attackThreshold,
               hasStaticDefense || hasContestedForwardPresence {
                return Classification(
                    category: .offense,
                    tactic: .feint,
                    confidence: min(1, 0.45 + adjustedRatio / 3),
                    reason: "limited_pressure"
                )
            }
            if mobileFriendlyStrength > 0,
               visibleEnemyRegionCount >= 2,
               adjustedRatio >= 0.85 {
                return Classification(
                    category: .offense,
                    tactic: .guerrillaWarfare,
                    confidence: min(1, 0.5 + adjustedRatio / 4),
                    reason: "mobile_raid_window"
                )
            }
            return Classification(
                category: .offense,
                tactic: .standardAttack,
                confidence: min(1, adjustedRatio / 2),
                reason: hasContestedForwardPresence ? "forward_presence" : "strength_ratio"
            )
        }

        if adjustedRatio <= 0.35,
           depthStrength == 0,
           pressure >= 3 {
            return Classification(
                category: .defense,
                tactic: .lastStand,
                confidence: min(1, 1 / max(0.01, adjustedRatio)),
                reason: "no_reserve_crisis"
            )
        }
        if depthStrength > 0,
           (pressure >= 2 || adjustedRatio < 1.0) {
            return Classification(
                category: .defense,
                tactic: .defenseInDepth,
                confidence: min(1, 0.55 + Double(depthStrength) / Double(max(1, friendlyStrength + depthStrength)) / 2),
                reason: "reserve_depth"
            )
        }
        if pressure >= 2 || supplyWarningCount > 0 || adjustedRatio < 0.75 {
            return Classification(
                category: .defense,
                tactic: .elasticDefense,
                confidence: min(1, 1 / max(0.01, adjustedRatio + 0.25)),
                reason: "elastic_risk_control"
            )
        }
        return Classification(
            category: .defense,
            tactic: .holdPosition,
            confidence: min(1, 1 / max(0.01, adjustedRatio)),
            reason: "outnumbered"
        )
    }
}

protocol ZoneCommanderProviding {
    var config: ZoneCommanderAgentConfig { get }
    func makeDirective(for zone: FrontZone, in state: GameState) -> ZoneDirective?
}

struct ZoneCommanderAgent: ZoneCommanderProviding {
    let config: ZoneCommanderAgentConfig
    let conditionChecker: TacticConditionChecker
    let classifier: BinaryTacticClassifier

    init(
        config: ZoneCommanderAgentConfig,
        conditionChecker: TacticConditionChecker = TacticConditionChecker(),
        classifier: BinaryTacticClassifier = BinaryTacticClassifier()
    ) {
        self.config = config
        self.conditionChecker = conditionChecker
        self.classifier = classifier
    }

    func makeDirective(for zone: FrontZone, in state: GameState) -> ZoneDirective? {
        guard !zone.frontSegments.isEmpty else {
            return nil
        }

        let visibleEnemy = visibleEnemyStrengthByRegion(zone: zone, state: state)
        let friendlyStrength = friendlyFrontStrength(zone: zone, state: state)
        let classification = classifier.classify(
            friendlyStrength: friendlyStrength,
            visibleEnemyStrength: visibleEnemy.values.reduce(0, +),
            hasContestedForwardPresence: hasContestedForwardPresence(zone: zone, state: state),
            hasStaticDefense: hasRecentStaticDefense(zone: zone, state: state),
            config: config,
            mobileFriendlyStrength: mobileFriendlyStrength(zone: zone, state: state),
            artillerySupportStrength: artillerySupportStrength(zone: zone, state: state),
            depthStrength: friendlyDepthStrength(zone: zone, state: state),
            pressure: zone.pressure,
            supplyWarningCount: supplyWarningCount(zone: zone, state: state),
            visibleEnemyRegionCount: visibleEnemy.count
        )

        guard conditionChecker.canUseTactic(classification.tactic, commander: config, zone: zone, state: state) else {
            return makeDefenseDirective(tactic: .holdPosition, zone: zone)
        }

        switch classification.category {
        case .offense:
            return makeOffenseDirective(
                tactic: classification.tactic,
                zone: zone,
                visibleEnemy: visibleEnemy,
                state: state
            )
        case .defense:
            return makeDefenseDirective(tactic: classification.tactic, zone: zone)
        }
    }

    private func makeOffenseDirective(
        tactic: TacticName,
        zone: FrontZone,
        visibleEnemy: [RegionId: Int],
        state: GameState
    ) -> ZoneDirective? {
        guard let targetZoneId = bestTargetZoneId(zone: zone, visibleEnemy: visibleEnemy, state: state) else {
            return makeDefenseDirective(tactic: .holdPosition, zone: zone)
        }

        let weightedRegions = visibleEnemy
            .sorted {
                if $0.value == $1.value {
                    return $0.key.rawValue < $1.key.rawValue
                }
                return $0.value > $1.value
            }
            .map(\.key)
        let focusRegionId = focusRegion(
            for: tactic,
            weightedRegions: weightedRegions,
            visibleEnemy: visibleEnemy,
            zone: zone,
            state: state
        )
        let supportRegionIds = stableUnique(
            zone.frontSegments
                .map(\.regionId)
                .filter { $0 != focusRegionId }
        )

        return ZoneDirective(
            zoneId: zone.id,
            attack: AttackParameters(
                targetTheaterId: TheaterId(targetZoneId.rawValue),
                weightedRegions: stableUnique([focusRegionId].compactMap { $0 } + weightedRegions),
                intensity: attackIntensity(for: tactic),
                focusRegionId: focusRegionId,
                supportRegionIds: supportRegionIds,
                coordinatedZoneIds: [zone.id],
                maxCommittedUnits: maxCommittedUnits(for: tactic, zone: zone),
                exploitDepth: exploitDepth(for: tactic)
            ),
            category: tactic.category,
            tactic: tactic,
            commandTarget: focusRegionId.map(DirectiveTarget.region) ?? .theater(TheaterId(targetZoneId.rawValue))
        )
    }

    private func makeDefenseDirective(tactic: TacticName, zone: FrontZone) -> ZoneDirective {
        ZoneDirective(
            zoneId: zone.id,
            defense: DefenseParameters(
                targetReserves: targetReserves(for: tactic, zone: zone),
                stance: defenseStance(for: tactic),
                fallbackRegionIds: fallbackRegions(for: tactic, zone: zone),
                counterattackRegionIds: nil,
                strongpointRegionIds: zone.frontSegments.map(\.regionId),
                maxFrontCommitment: maxFrontCommitment(for: tactic, zone: zone)
            ),
            category: tactic.category,
            tactic: tactic,
            commandTarget: .theater(TheaterId(zone.id.rawValue))
        )
    }

    private func attackIntensity(for tactic: TacticName) -> AttackIntensity {
        switch tactic {
        case .blitzkrieg,
             .spearhead,
             .pincerMovement,
             .breakthrough:
            return .allOut
        case .fireCoverage,
             .feint:
            return .limitedCounter
        case .guerrillaWarfare:
            return .infiltration
        case .standardAttack,
             .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            return .limitedCounter
        }
    }

    private func focusRegion(
        for tactic: TacticName,
        weightedRegions: [RegionId],
        visibleEnemy: [RegionId: Int],
        zone: FrontZone,
        state: GameState
    ) -> RegionId? {
        guard !weightedRegions.isEmpty else {
            return zone.frontSegments.map(\.regionId).sorted { $0.rawValue < $1.rawValue }.first
        }

        switch tactic {
        case .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .guerrillaWarfare:
            return weightedRegions.sorted {
                breakthroughRegionSortKey(for: $0, enemyStrength: visibleEnemy[$0, default: 0], state: state) <
                    breakthroughRegionSortKey(for: $1, enemyStrength: visibleEnemy[$1, default: 0], state: state)
            }.first
        case .fireCoverage:
            return weightedRegions.max {
                visibleEnemy[$0, default: 0] == visibleEnemy[$1, default: 0]
                    ? $0.rawValue > $1.rawValue
                    : visibleEnemy[$0, default: 0] < visibleEnemy[$1, default: 0]
            }
        case .feint:
            return weightedRegions.sorted { $0.rawValue < $1.rawValue }.last
        case .standardAttack,
             .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            return weightedRegions.first
        }
    }

    private func maxCommittedUnits(for tactic: TacticName, zone: FrontZone) -> Int? {
        switch tactic {
        case .feint:
            return max(1, max(zone.unitsFront.count, 1) / 3)
        case .fireCoverage:
            return nil
        case .blitzkrieg:
            return zone.unitsFront.count + zone.unitsDepth.count
        case .spearhead:
            return max(1, zone.unitsDepth.count + max(1, zone.unitsFront.count / 2))
        case .pincerMovement:
            return zone.unitsFront.count + zone.unitsDepth.count
        case .guerrillaWarfare:
            return max(1, (zone.unitsFront.count + zone.unitsDepth.count) / 2)
        case .breakthrough,
             .standardAttack,
             .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            return nil
        }
    }

    private func exploitDepth(for tactic: TacticName) -> Int? {
        switch tactic {
        case .blitzkrieg:
            return 2
        case .spearhead,
             .breakthrough,
             .pincerMovement,
             .guerrillaWarfare:
            return 1
        case .standardAttack,
             .fireCoverage,
             .feint,
             .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            return nil
        }
    }

    private func targetReserves(for tactic: TacticName, zone: FrontZone) -> Int {
        switch tactic {
        case .defenseInDepth:
            return max(1, min(2, zone.unitsDepth.count))
        case .elasticDefense:
            return max(1, min(1, zone.unitsDepth.count))
        case .lastStand:
            return 0
        case .holdPosition,
             .standardAttack,
             .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .fireCoverage,
             .feint,
             .guerrillaWarfare:
            return 1
        }
    }

    private func defenseStance(for tactic: TacticName) -> DefenseStance {
        switch tactic {
        case .elasticDefense,
             .defenseInDepth:
            return .flexible
        case .lastStand,
             .holdPosition,
             .standardAttack,
             .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .fireCoverage,
             .feint,
             .guerrillaWarfare:
            return .holdLine
        }
    }

    private func fallbackRegions(for tactic: TacticName, zone: FrontZone) -> [RegionId]? {
        switch tactic {
        case .elasticDefense,
             .defenseInDepth:
            return zone.regionIds.filter { regionId in
                !zone.frontSegments.contains { $0.regionId == regionId }
            }
        case .holdPosition,
             .lastStand,
             .standardAttack,
             .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .fireCoverage,
             .feint,
             .guerrillaWarfare:
            return nil
        }
    }

    private func maxFrontCommitment(for tactic: TacticName, zone: FrontZone) -> Int? {
        switch tactic {
        case .defenseInDepth:
            return max(1, max(zone.unitsFront.count, 1) / 2)
        case .elasticDefense:
            return zone.unitsFront.count
        case .lastStand:
            return nil
        case .holdPosition,
             .standardAttack,
             .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .fireCoverage,
             .feint,
             .guerrillaWarfare:
            return nil
        }
    }

    private func friendlyFrontStrength(zone: FrontZone, state: GameState) -> Int {
        let frontUnitIds = Set(zone.unitsFront + zone.frontSegments.flatMap(\.assignedFrontUnitIds))
        return state.divisions
            .filter { frontUnitIds.contains($0.id) && $0.faction == zone.faction && !$0.isDestroyed }
            .reduce(0) { $0 + combatPower($1, mode: .friendly) }
    }

    private func friendlyDepthStrength(zone: FrontZone, state: GameState) -> Int {
        state.divisions
            .filter { zone.unitsDepth.contains($0.id) && $0.faction == zone.faction && !$0.isDestroyed }
            .reduce(0) { $0 + combatPower($1, mode: .friendly) }
    }

    private func mobileFriendlyStrength(zone: FrontZone, state: GameState) -> Int {
        let unitIds = Set(zone.unitsFront + zone.unitsDepth + zone.frontSegments.flatMap(\.assignedFrontUnitIds))
        return state.divisions
            .filter {
                unitIds.contains($0.id)
                    && $0.faction == zone.faction
                    && !$0.isDestroyed
                    && isMobile($0)
            }
            .reduce(0) { $0 + combatPower($1, mode: .friendly) }
    }

    private func artillerySupportStrength(zone: FrontZone, state: GameState) -> Int {
        let unitIds = Set(zone.unitsFront + zone.unitsDepth + zone.frontSegments.flatMap(\.assignedFrontUnitIds))
        return state.divisions
            .filter {
                unitIds.contains($0.id)
                    && $0.faction == zone.faction
                    && !$0.isDestroyed
                    && ($0.isArtillery || $0.range > 1)
            }
            .reduce(0) { $0 + combatPower($1, mode: .friendly) }
    }

    private func supplyWarningCount(zone: FrontZone, state: GameState) -> Int {
        let unitIds = Set(zone.unitsFront + zone.unitsDepth + zone.unitsGarrison)
        return state.divisions.filter {
            unitIds.contains($0.id)
                && ($0.supplyState == .lowSupply || $0.supplyState == .encircled)
        }.count
    }

    private func visibleEnemyStrengthByRegion(zone: FrontZone, state: GameState) -> [RegionId: Int] {
        var strengthByRegion: [RegionId: Int] = [:]

        for contact in state.operationalAwareness.visibleContacts(for: zone.faction) {
            guard let regionId = state.map.region(for: contact.lastKnownCoord),
                  contactRegionIsRelevant(regionId, zone: zone, state: state) else {
                continue
            }
            strengthByRegion[regionId, default: 0] += VisibilityRules().contactStrengthEstimate(contact)
        }

        return strengthByRegion
    }

    private func visibleEnemyRegionIds(zone: FrontZone, state: GameState) -> [RegionId] {
        let regionIds = state.operationalAwareness.visibleContacts(for: zone.faction).compactMap { contact in
            state.map.region(for: contact.lastKnownCoord)
        }.filter { contactRegionIsRelevant($0, zone: zone, state: state) }

        return stableUnique(regionIds)
    }

    private func contactRegionIsRelevant(_ regionId: RegionId, zone: FrontZone, state: GameState) -> Bool {
        for segment in zone.frontSegments {
            if segment.regionId == regionId {
                return true
            }
            if state.map.neighbors(of: segment.regionId).contains(regionId) {
                return true
            }
        }
        return zone.regionIds.contains(regionId)
    }

    private func bestTargetZoneId(
        zone: FrontZone,
        visibleEnemy: [RegionId: Int],
        state: GameState
    ) -> FrontZoneId? {
        var scoreByZone: [FrontZoneId: Int] = [:]

        for (regionId, strength) in visibleEnemy {
            guard let enemyZoneId = dominantEnemyZoneId(for: regionId, zone: zone, state: state) else {
                continue
            }
            scoreByZone[enemyZoneId, default: 0] += strength
        }

        if let best = scoreByZone.sorted(by: {
            if $0.value == $1.value {
                return $0.key.rawValue < $1.key.rawValue
            }
            return $0.value > $1.value
        }).first?.key {
            return best
        }

        return zone.frontSegments.map(\.neighborEnemyZone).sorted { $0.rawValue < $1.rawValue }.first
    }

    private func dominantEnemyZoneId(
        for regionId: RegionId,
        zone: FrontZone,
        state: GameState
    ) -> FrontZoneId? {
        guard let region = state.map.region(id: regionId) else {
            return state.warDeploymentState.regionToFrontZone[regionId]
        }

        var counts: [FrontZoneId: Int] = [:]
        for hex in region.displayHexes {
            guard let zoneId = state.warDeploymentState.zoneId(for: hex, map: state.map),
                  zoneId != zone.id else {
                continue
            }
            counts[zoneId, default: 0] += 1
        }

        return counts.max {
            $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value
        }?.key ?? state.warDeploymentState.regionToFrontZone[regionId]
    }

    private func dynamicRegionTouchesZone(
        sourceRegionId: RegionId,
        neighborRegionId: RegionId,
        targetZoneId: FrontZoneId,
        state: GameState
    ) -> Bool {
        guard let sourceRegion = state.map.region(id: sourceRegionId),
              let neighborRegion = state.map.region(id: neighborRegionId) else {
            return false
        }
        let neighborHexes = Set(neighborRegion.displayHexes)
        for hex in sourceRegion.displayHexes {
            guard state.warDeploymentState.zoneId(for: hex, map: state.map) != targetZoneId else {
                continue
            }
            for neighborHex in hex.neighbors where neighborHexes.contains(neighborHex) {
                if state.warDeploymentState.zoneId(for: neighborHex, map: state.map) == targetZoneId {
                    return true
                }
            }
        }
        return false
    }

    private func hasEnemyPresence(
        in regionId: RegionId,
        zone: FrontZone,
        state: GameState
    ) -> Bool {
        state.divisions.contains { division in
            guard division.faction != zone.faction,
                  !division.isDestroyed else {
                return false
            }
            return division.location(in: state.map) == regionId
        }
    }

    private func hasContestedForwardPresence(zone: FrontZone, state: GameState) -> Bool {
        let zoneUnitIds = Set(zone.unitsFront + zone.unitsDepth + zone.unitsGarrison)
        return state.divisions.contains { division in
            guard zoneUnitIds.contains(division.id),
                  division.faction == zone.faction,
                  !division.isDestroyed,
                  let regionId = division.location(in: state.map),
                  let region = state.map.regions[regionId] else {
                return false
            }
            return region.controller != zone.faction
        }
    }

    private func hasRecentStaticDefense(zone: FrontZone, state: GameState) -> Bool {
        guard let previous = state.warDirectiveRecords
            .reversed()
            .first(where: { $0.zoneId == zone.id && $0.faction == zone.faction }) else {
            return false
        }

        guard previous.directiveType == .defend,
              !previous.commandResults.isEmpty else {
            return false
        }

        return previous.commandResults.allSatisfy { summary in
            summary.commandDisplayName?.hasPrefix("Hold") == true
        }
    }

    private enum StrengthMode {
        case friendly
        case enemy
    }

    private func combatPower(_ division: Division, mode: StrengthMode) -> Int {
        switch mode {
        case .friendly:
            return max(1, division.strength) + max(1, division.attack)
        case .enemy:
            return max(1, division.strength) + max(1, division.defense)
        }
    }

    private func breakthroughRegionSortKey(
        for regionId: RegionId,
        enemyStrength: Int,
        state: GameState
    ) -> RegionFocusSortKey {
        guard let region = state.map.region(id: regionId) else {
            return RegionFocusSortKey(
                enemyStrength: Int.max,
                movementCost: Int.max,
                roadPenalty: 1,
                valueScore: 0,
                id: regionId.rawValue
            )
        }

        let hasRoad = region.displayHexes.contains { state.map.tile(at: $0)?.hasRoad == true }
        let valueScore = (region.city?.victoryPoints ?? 0)
            + region.supplyValue
            + region.factories
            + region.infrastructure / 2
        return RegionFocusSortKey(
            enemyStrength: enemyStrength,
            movementCost: region.terrain.movementCost,
            roadPenalty: hasRoad ? 0 : 1,
            valueScore: valueScore,
            id: regionId.rawValue
        )
    }

    private func isMobile(_ division: Division) -> Bool {
        division.isArmor
            || division.isMechanized
            || division.movement >= 5
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct TheaterCommanderPool {
    private let commanders: [FrontZoneId: any ZoneCommanderProviding]

    init(commanders: [any ZoneCommanderProviding]) {
        self.commanders = Dictionary(
            uniqueKeysWithValues: commanders.map { ($0.config.assignedZoneId, $0) }
        )
    }

    func envelope(for faction: Faction, in state: GameState, issuerId: String = "theater_pool") -> DirectiveEnvelope {
        let directives = state.warDeploymentState.frontZones.values
            .filter { $0.faction == faction && !$0.frontSegments.isEmpty }
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .compactMap { zone -> ZoneDirective? in
                let commander = commanders[zone.id] ?? ZoneCommanderAgent(config: Self.defaultConfig(for: zone))
                return commander.makeDirective(for: zone, in: state)
            }

        return DirectiveEnvelope(
            issuerId: issuerId,
            turn: state.turn,
            directives: directives,
            commanderAgentId: issuerId,
            theaterContext: contextSummary(for: faction, directives: directives)
        )
    }

    static func automatic(for state: GameState) -> TheaterCommanderPool {
        TheaterCommanderPool(
            commanders: state.warDeploymentState.frontZones.values
                .sorted { $0.id.rawValue < $1.id.rawValue }
                .map { ZoneCommanderAgent(config: defaultConfig(for: $0)) }
        )
    }

    static func defaultConfig(for zone: FrontZone) -> ZoneCommanderAgentConfig {
        let style: ZoneCommanderAgentConfig.CommandStyle = zone.faction == .germany ? .aggressive : .balanced
        return ZoneCommanderAgentConfig(
            id: "auto_\(zone.id.rawValue)",
            name: "\(zone.faction.shortDisplayName) Commander (\(commandSectorDisplay(zone.id)))",
            faction: zone.faction,
            assignedZoneId: zone.id,
            skills: [],
            commandStyle: style
        )
    }

    private static func commandSectorDisplay(_ id: FrontZoneId) -> String {
        let cleaned = id.rawValue
            .replacingOccurrences(of: "front" + "_zone_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sector" : "Sector \(cleaned.capitalized)"
    }

    private func contextSummary(for faction: Faction, directives: [ZoneDirective]) -> String {
        "\(faction.displayName): \(directives.count) zone directive(s)."
    }
}

struct MarshalAgentConfig: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let faction: Faction
    let personality: String
    let strategicBias: StrategicBias
    let theaterGroupZoneIds: [FrontZoneId]

    enum StrategicBias: String, Codable, Equatable, CaseIterable {
        case offensive
        case balanced
        case defensive
    }

    init(
        id: String,
        name: String,
        faction: Faction,
        personality: String,
        strategicBias: StrategicBias,
        theaterGroupZoneIds: [FrontZoneId] = []
    ) {
        self.id = id
        self.name = name
        self.faction = faction
        self.personality = personality
        self.strategicBias = strategicBias
        self.theaterGroupZoneIds = theaterGroupZoneIds.sorted { $0.rawValue < $1.rawValue }
    }

    static func automatic(for faction: Faction, state: GameState) -> MarshalAgentConfig {
        let zoneIds = state.warDeploymentState.frontZones.values
            .filter { $0.faction == faction }
            .map(\.id)
        switch faction.alignment {
        case .red:
            return MarshalAgentConfig(
                id: "marshal_red_joint_command",
                name: "Red Joint Command",
                faction: faction,
                personality: "Operational commander; favors concentration of force, reserves, and controlled breakthroughs.",
                strategicBias: .offensive,
                theaterGroupZoneIds: zoneIds
            )
        case .blue:
            return MarshalAgentConfig(
                id: "marshal_blue_joint_command",
                name: "Blue Joint Command",
                faction: faction,
                personality: "Coalition commander; favors stable fronts, reserves, and coordinated limited counterattacks.",
                strategicBias: .balanced,
                theaterGroupZoneIds: zoneIds
            )
        case .green,
             .neutral:
            return MarshalAgentConfig(
                id: "marshal_\(faction.rawValue)",
                name: "\(faction.shortDisplayName) Command",
                faction: faction,
                personality: "Restrained command; favors protection, de-escalation, and limited commitments.",
                strategicBias: .defensive,
                theaterGroupZoneIds: zoneIds
            )
        }
    }
}

struct MarshalBattlefieldSummary: Codable, Equatable {
    let schemaVersion: Int
    let turn: Int
    let faction: Faction
    let marshalId: String
    let marshalName: String
    let personality: String
    let strategicBias: MarshalAgentConfig.StrategicBias
    let overallSupply: String
    let friendlyLowSupplyCount: Int
    let friendlyEncircledCount: Int
    let objectivesHeld: [String]
    let objectivesLost: [String]
    let fronts: [MarshalFrontSummary]
    let recentEvents: [String]
}

struct MarshalFrontSummary: Codable, Equatable, Identifiable {
    let id: FrontZoneId
    let name: String
    let state: WarState
    let pressure: Int
    let frontRegionIds: [RegionId]
    let enemyRegionIds: [RegionId]
    let enemyZoneIds: [FrontZoneId]
    let friendlyFrontStrength: Int
    let friendlyDepthStrength: Int
    let visibleEnemyStrength: Int
    let strengthRatio: Double
    let frontUnitCount: Int
    let depthUnitCount: Int
    let garrisonUnitCount: Int
    let supplyWarningCount: Int
    let keyObjectivesHeld: [String]
    let keyObjectivesLost: [String]
    let status: String
}

struct MarshalBattlefieldSummarizer {
    let maxRecentEvents: Int

    init(maxRecentEvents: Int = 8) {
        self.maxRecentEvents = maxRecentEvents
    }

    func summary(for config: MarshalAgentConfig, in state: GameState) -> MarshalBattlefieldSummary {
        let faction = config.faction
        let allFriendly = state.divisions.filter { $0.faction == faction && !$0.isDestroyed }
        let lowSupplyCount = allFriendly.filter { $0.supplyState == .lowSupply }.count
        let encircledCount = allFriendly.filter { $0.supplyState == .encircled }.count
        let overallSupply: String
        if encircledCount > 0 {
            overallSupply = "encircled_risk"
        } else if lowSupplyCount > max(1, allFriendly.count / 3) {
            overallSupply = "strained"
        } else {
            overallSupply = "adequate"
        }

        let zoneScope = Set(config.theaterGroupZoneIds)
        let frontSummaries = state.warDeploymentState.frontZones.values
            .filter { zone in
                zone.faction == faction
                    && !zone.frontSegments.isEmpty
                    && (zoneScope.isEmpty || zoneScope.contains(zone.id))
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { frontSummary(for: $0, faction: faction, state: state) }

        let heldObjectives = objectiveNames(controlledBy: faction, state: state)
        let lostObjectives = hostileObjectiveNames(to: faction, state: state)
        let recentEvents = Array(state.eventLog.suffix(maxRecentEvents)).map(\.message)

        return MarshalBattlefieldSummary(
            schemaVersion: 5,
            turn: state.turn,
            faction: faction,
            marshalId: config.id,
            marshalName: config.name,
            personality: config.personality,
            strategicBias: config.strategicBias,
            overallSupply: overallSupply,
            friendlyLowSupplyCount: lowSupplyCount,
            friendlyEncircledCount: encircledCount,
            objectivesHeld: heldObjectives,
            objectivesLost: lostObjectives,
            fronts: frontSummaries,
            recentEvents: recentEvents
        )
    }

    private func frontSummary(
        for zone: FrontZone,
        faction: Faction,
        state: GameState
    ) -> MarshalFrontSummary {
        let frontRegionIds = stableUnique(zone.frontSegments.map(\.regionId))
        let enemyRegionIds = visibleEnemyRegionIds(zone: zone, state: state)
        let enemyZoneIds = stableUnique(zone.frontSegments.map(\.neighborEnemyZone))
        let frontStrength = strength(for: zone.unitsFront, faction: faction, state: state, mode: .friendly)
            + strength(for: zone.frontSegments.flatMap(\.assignedFrontUnitIds), faction: faction, state: state, mode: .friendly)
        let depthStrength = strength(for: zone.unitsDepth, faction: faction, state: state, mode: .friendly)
        let enemyStrength = visibleContactStrength(
            faction: faction,
            regionIds: enemyRegionIds,
            state: state
        )
        let ratio = enemyStrength == 0 ? Double(max(1, frontStrength)) : Double(frontStrength) / Double(enemyStrength)
        let unitIds = Set(zone.unitsFront + zone.unitsDepth + zone.unitsGarrison)
        let supplyWarnings = state.divisions.filter {
            unitIds.contains($0.id)
                && ($0.supplyState == .lowSupply || $0.supplyState == .encircled)
        }.count

        return MarshalFrontSummary(
            id: zone.id,
            name: zone.name,
            state: zone.state,
            pressure: zone.pressure,
            frontRegionIds: frontRegionIds,
            enemyRegionIds: enemyRegionIds,
            enemyZoneIds: enemyZoneIds,
            friendlyFrontStrength: frontStrength,
            friendlyDepthStrength: depthStrength,
            visibleEnemyStrength: enemyStrength,
            strengthRatio: ratio,
            frontUnitCount: zone.unitsFront.count,
            depthUnitCount: zone.unitsDepth.count,
            garrisonUnitCount: zone.unitsGarrison.count,
            supplyWarningCount: supplyWarnings,
            keyObjectivesHeld: objectiveNames(in: frontRegionIds, controlledBy: faction, state: state),
            keyObjectivesLost: hostileObjectiveNames(in: enemyRegionIds, to: faction, state: state),
            status: status(for: zone, ratio: ratio, supplyWarnings: supplyWarnings)
        )
    }

    private enum StrengthMode {
        case friendly
        case enemy
    }

    private func strength(
        for unitIds: [String],
        faction: Faction,
        state: GameState,
        mode: StrengthMode
    ) -> Int {
        let ids = Set(unitIds)
        return state.divisions
            .filter { ids.contains($0.id) && $0.faction == faction && !$0.isDestroyed }
            .reduce(0) { total, division in
                switch mode {
                case .friendly:
                    return total + max(1, division.strength) + max(1, division.attack)
                case .enemy:
                    return total + max(1, division.strength) + max(1, division.defense)
                }
            }
    }

    private func visibleEnemyRegionIds(zone: FrontZone, state: GameState) -> [RegionId] {
        let regionIds = state.operationalAwareness.visibleContacts(for: zone.faction).compactMap { contact in
            state.map.region(for: contact.lastKnownCoord)
        }.filter { contactRegionIsRelevant($0, zone: zone, state: state) }

        return stableUnique(regionIds)
    }

    private func visibleContactStrength(
        faction: Faction,
        regionIds: [RegionId],
        state: GameState
    ) -> Int {
        let regionIdSet = Set(regionIds)
        return state.operationalAwareness.visibleContacts(for: faction)
            .filter { contact in
                guard let regionId = state.map.region(for: contact.lastKnownCoord) else {
                    return false
                }
                return regionIdSet.contains(regionId)
            }
            .reduce(0) { $0 + VisibilityRules().contactStrengthEstimate($1) }
    }

    private func contactRegionIsRelevant(_ regionId: RegionId, zone: FrontZone, state: GameState) -> Bool {
        for segment in zone.frontSegments {
            if segment.regionId == regionId {
                return true
            }
            if state.map.neighbors(of: segment.regionId).contains(regionId) {
                return true
            }
        }
        return zone.regionIds.contains(regionId)
    }

    private func dynamicRegionTouchesZone(
        sourceRegionId: RegionId,
        neighborRegionId: RegionId,
        targetZoneId: FrontZoneId,
        state: GameState
    ) -> Bool {
        guard let sourceRegion = state.map.region(id: sourceRegionId),
              let neighborRegion = state.map.region(id: neighborRegionId) else {
            return false
        }
        let neighborHexes = Set(neighborRegion.displayHexes)
        for hex in sourceRegion.displayHexes {
            guard state.warDeploymentState.zoneId(for: hex, map: state.map) != targetZoneId else {
                continue
            }
            for neighborHex in hex.neighbors where neighborHexes.contains(neighborHex) {
                if state.warDeploymentState.zoneId(for: neighborHex, map: state.map) == targetZoneId {
                    return true
                }
            }
        }
        return false
    }

    private func hasEnemyPresence(in regionId: RegionId, zone: FrontZone, state: GameState) -> Bool {
        state.divisions.contains { division in
            division.faction != zone.faction
                && !division.isDestroyed
                && division.location(in: state.map) == regionId
        }
    }

    private func objectiveNames(controlledBy faction: Faction, state: GameState) -> [String] {
        state.map.objectives
            .filter { state.map.tile(at: $0.coord)?.controller == faction }
            .map(\.name)
            .sorted()
    }

    private func hostileObjectiveNames(to faction: Faction, state: GameState) -> [String] {
        state.map.objectives
            .filter { state.map.tile(at: $0.coord)?.controller?.isHostile(to: faction) == true }
            .map(\.name)
            .sorted()
    }

    private func objectiveNames(
        in regionIds: [RegionId],
        controlledBy faction: Faction,
        state: GameState
    ) -> [String] {
        let regionSet = Set(regionIds)
        return state.map.objectives
            .filter { objective in
                guard state.map.tile(at: objective.coord)?.controller == faction,
                      let regionId = state.map.region(for: objective.coord) else {
                    return false
                }
                return regionSet.contains(regionId)
            }
            .map(\.name)
            .sorted()
    }

    private func hostileObjectiveNames(
        in regionIds: [RegionId],
        to faction: Faction,
        state: GameState
    ) -> [String] {
        let regionSet = Set(regionIds)
        return state.map.objectives
            .filter { objective in
                guard state.map.tile(at: objective.coord)?.controller?.isHostile(to: faction) == true,
                      let regionId = state.map.region(for: objective.coord) else {
                    return false
                }
                return regionSet.contains(regionId)
            }
            .map(\.name)
            .sorted()
    }

    private func status(for zone: FrontZone, ratio: Double, supplyWarnings: Int) -> String {
        if supplyWarnings > 0 {
            return "supply_warning"
        }
        if zone.pressure >= 3 {
            return "under_pressure"
        }
        if ratio >= 1.35 {
            return "advantage"
        }
        if ratio <= 0.85 {
            return "outnumbered"
        }
        return "stable_contact"
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

protocol MarshalLLMClient {
    func completeTheaterDirectiveJSON(
        summary: MarshalBattlefieldSummary,
        config: MarshalAgentConfig
    ) throws -> String
}

struct SimulatedMarshalLLMClient: MarshalLLMClient {
    func completeTheaterDirectiveJSON(
        summary: MarshalBattlefieldSummary,
        config: MarshalAgentConfig
    ) throws -> String {
        let directives = summary.fronts.map { front -> TheaterDirective in
            let shouldAttack = shouldAttack(front: front, bias: config.strategicBias)
            if shouldAttack {
                let tactic = offensiveTactic(front: front, bias: config.strategicBias)
                return TheaterDirective(
                    id: "marshal_\(summary.turn)_\(front.id.rawValue)",
                    zoneId: front.id,
                    category: .offense,
                    tactic: tactic,
                    priority: offensivePriority(front: front),
                    targetTheaterId: front.enemyZoneIds.first.map { TheaterId($0.rawValue) },
                    weightedRegions: front.enemyRegionIds,
                    focusRegionId: front.enemyRegionIds.first,
                    supportRegionIds: Array(front.frontRegionIds.prefix(2)),
                    convergenceRegionId: tactic == .pincerMovement ? front.enemyRegionIds.first : nil,
                    coordinatedZoneIds: tactic == .pincerMovement ? front.enemyZoneIds : [front.id],
                    reserveBias: 0,
                    intensity: front.strengthRatio >= 1.8 ? .allOut : .limitedCounter,
                    maxCommittedUnits: front.frontUnitCount + max(0, front.depthUnitCount / 2),
                    exploitDepth: front.strengthRatio >= 1.8 ? 1 : 0,
                    rationale: "Joint staff recommends \(tactic.displayName) from local combat balance \(String(format: "%.2f", front.strengthRatio))."
                )
            }

            let tactic = defensiveTactic(front: front)
            return TheaterDirective(
                id: "marshal_\(summary.turn)_\(front.id.rawValue)",
                zoneId: front.id,
                category: .defense,
                tactic: tactic,
                priority: defensivePriority(front: front),
                weightedRegions: front.frontRegionIds,
                focusRegionId: front.frontRegionIds.first,
                supportRegionIds: front.enemyRegionIds,
                reserveBias: max(1, min(3, front.depthUnitCount)),
                maxCommittedUnits: front.frontUnitCount,
                rationale: "Joint staff recommends \(tactic.displayName) for current contact pressure \(front.status)."
            )
        }

        let envelope = TheaterDirectiveEnvelope(
            issuerId: summary.marshalId,
            turn: summary.turn,
            faction: summary.faction,
            strategicIntent: strategicIntent(summary: summary, bias: config.strategicBias),
            directives: directives,
            summary: "\(summary.marshalName): \(directives.count) operational directive(s) from summarized fronts."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        return "```json\n\(String(decoding: data, as: UTF8.self))\n```"
    }

    private func shouldAttack(
        front: MarshalFrontSummary,
        bias: MarshalAgentConfig.StrategicBias
    ) -> Bool {
        guard !front.enemyZoneIds.isEmpty else {
            return false
        }
        if front.supplyWarningCount > 0 {
            return false
        }

        switch bias {
        case .offensive:
            return front.strengthRatio >= 1.05 || front.status == "advantage"
        case .balanced:
            return front.strengthRatio >= 1.25
        case .defensive:
            return front.strengthRatio >= 1.55 && front.pressure < 3
        }
    }

    private func offensivePriority(front: MarshalFrontSummary) -> Int {
        min(100, 60 + Int(front.strengthRatio * 10) + front.keyObjectivesLost.count * 5)
    }

    private func defensivePriority(front: MarshalFrontSummary) -> Int {
        min(100, 55 + front.pressure * 8 + front.supplyWarningCount * 10)
    }

    private func offensiveTactic(
        front: MarshalFrontSummary,
        bias: MarshalAgentConfig.StrategicBias
    ) -> TacticName {
        if front.enemyZoneIds.count >= 2,
           front.strengthRatio >= 1.25 {
            return .pincerMovement
        }
        if bias == .offensive,
           front.depthUnitCount > 0,
           front.strengthRatio >= 1.8 {
            return .blitzkrieg
        }
        if front.depthUnitCount > 0,
           front.strengthRatio >= 1.35 {
            return .spearhead
        }
        if front.strengthRatio >= 1.15 {
            return .breakthrough
        }
        if front.pressure > 0 {
            return .feint
        }
        return .standardAttack
    }

    private func defensiveTactic(front: MarshalFrontSummary) -> TacticName {
        if front.strengthRatio <= 0.35,
           front.depthUnitCount == 0 {
            return .lastStand
        }
        if front.depthUnitCount > 0,
           (front.pressure >= 2 || front.strengthRatio <= 0.9) {
            return .defenseInDepth
        }
        if front.supplyWarningCount > 0 || front.strengthRatio <= 0.75 {
            return .elasticDefense
        }
        return .holdPosition
    }

    private func strategicIntent(
        summary: MarshalBattlefieldSummary,
        bias: MarshalAgentConfig.StrategicBias
    ) -> String {
        switch bias {
        case .offensive:
            return "Concentrate active fronts with favorable odds; hold strained fronts with minimal reserves."
        case .balanced:
            return "Preserve front stability while attacking only where the summarized odds justify commitment."
        case .defensive:
            return "Stabilize threatened fronts and keep reserves available for counterattacks."
        }
    }
}

struct TheaterDirectiveCompiler {
    func compile(
        _ theaterEnvelope: TheaterDirectiveEnvelope,
        state: GameState,
        fallbackPool: TheaterCommanderPool,
        issuerId: String
    ) -> DirectiveEnvelope {
        let fallbackEnvelope = fallbackPool.envelope(for: theaterEnvelope.faction, in: state, issuerId: issuerId)
        let fallbackByZone = Dictionary(uniqueKeysWithValues: fallbackEnvelope.directives.map { ($0.zoneId, $0) })
        let directivesByZone = Dictionary(grouping: theaterEnvelope.directives, by: \.zoneId)
        let candidateZones = state.warDeploymentState.frontZones.values
            .filter { $0.faction == theaterEnvelope.faction && !$0.frontSegments.isEmpty }
            .sorted { $0.id.rawValue < $1.id.rawValue }

        let compiledDirectives = candidateZones.compactMap { zone -> ZoneDirective? in
            guard let theaterDirective = directivesByZone[zone.id]?.sorted(by: {
                if $0.priority == $1.priority {
                    return $0.id < $1.id
                }
                return $0.priority > $1.priority
            }).first else {
                return fallbackByZone[zone.id]
            }

            return compile(theaterDirective, zone: zone, state: state)
                ?? fallbackByZone[zone.id]
        }

        return DirectiveEnvelope(
            schemaVersion: max(2, fallbackEnvelope.schemaVersion),
            issuerId: theaterEnvelope.issuerId,
            turn: theaterEnvelope.turn,
            directives: compiledDirectives,
            commanderAgentId: theaterEnvelope.issuerId,
            theaterContext: "\(theaterEnvelope.strategicIntent) Compiled \(compiledDirectives.count) zone directive(s)."
        )
    }

    private func compile(
        _ directive: TheaterDirective,
        zone: FrontZone,
        state: GameState
    ) -> ZoneDirective? {
        let tactic = directive.tactic ?? defaultTactic(for: directive.category)
        switch directive.category {
        case .offense:
            guard let targetTheaterId = directive.targetTheaterId
                ?? zone.frontSegments.map(\.neighborEnemyZone).sorted(by: { $0.rawValue < $1.rawValue }).first.map({ TheaterId($0.rawValue) }) else {
                return nil
            }
            let weightedRegions = stableUnique(
                [directive.focusRegionId].compactMap { $0 }
                + directive.weightedRegions
                + directive.supportRegionIds
            )
            return ZoneDirective(
                zoneId: zone.id,
                attack: AttackParameters(
                    targetTheaterId: targetTheaterId,
                    weightedRegions: weightedRegions,
                    intensity: directive.intensity ?? .limitedCounter,
                    focusRegionId: directive.focusRegionId,
                    supportRegionIds: directive.supportRegionIds,
                    convergenceRegionId: directive.convergenceRegionId,
                    coordinatedZoneIds: directive.coordinatedZoneIds.isEmpty ? [zone.id] : directive.coordinatedZoneIds,
                    maxCommittedUnits: directive.maxCommittedUnits,
                    exploitDepth: directive.exploitDepth
                ),
                category: .offense,
                tactic: tactic.category == .offense ? tactic : .standardAttack,
                commandTarget: directive.focusRegionId.map(DirectiveTarget.region) ?? .theater(targetTheaterId)
            )
        case .defense:
            let strongpoints = stableUnique(
                [directive.focusRegionId].compactMap { $0 }
                + directive.weightedRegions
            )
            return ZoneDirective(
                zoneId: zone.id,
                defense: DefenseParameters(
                    targetReserves: max(1, directive.reserveBias),
                    stance: .holdLine,
                    fallbackRegionIds: directive.supportRegionIds,
                    strongpointRegionIds: strongpoints,
                    maxFrontCommitment: directive.maxCommittedUnits
                ),
                category: .defense,
                tactic: tactic.category == .defense ? tactic : .holdPosition,
                commandTarget: directive.focusRegionId.map(DirectiveTarget.region) ?? .theater(TheaterId(zone.id.rawValue))
            )
        }
    }

    private func defaultTactic(for category: CommandCategory) -> TacticName {
        switch category {
        case .offense:
            return .standardAttack
        case .defense:
            return .holdPosition
        }
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct MarshalDirectiveResolution {
    let rawTheaterJSON: String?
    let rawCommandChainJSON: String?
    let theaterEnvelope: TheaterDirectiveEnvelope?
    let commandChainPlan: ModernCommandChainPlan?
    let directiveEnvelope: DirectiveEnvelope
    let diagnostics: [String]
}

struct MarshalAgent {
    let config: MarshalAgentConfig
    let summarizer: MarshalBattlefieldSummarizer
    let llmClient: MarshalLLMClient
    let decoder: TheaterDirectiveDecoder
    let compiler: TheaterDirectiveCompiler
    let commandChainOrchestrator: ModernCommandChainOrchestrator
    let commandChainDecoder: ModernCommandChainDecoder

    init(
        config: MarshalAgentConfig,
        summarizer: MarshalBattlefieldSummarizer = MarshalBattlefieldSummarizer(),
        llmClient: MarshalLLMClient = SimulatedMarshalLLMClient(),
        decoder: TheaterDirectiveDecoder = TheaterDirectiveDecoder(),
        compiler: TheaterDirectiveCompiler = TheaterDirectiveCompiler(),
        commandChainOrchestrator: ModernCommandChainOrchestrator = ModernCommandChainOrchestrator(),
        commandChainDecoder: ModernCommandChainDecoder = ModernCommandChainDecoder()
    ) {
        self.config = config
        self.summarizer = summarizer
        self.llmClient = llmClient
        self.decoder = decoder
        self.compiler = compiler
        self.commandChainOrchestrator = commandChainOrchestrator
        self.commandChainDecoder = commandChainDecoder
    }

    func resolve(
        for faction: Faction,
        in state: GameState,
        fallbackPool: TheaterCommanderPool,
        issuerId: String
    ) -> MarshalDirectiveResolution {
        guard config.faction == faction else {
            let fallback = fallbackPool.envelope(for: faction, in: state, issuerId: issuerId)
            return MarshalDirectiveResolution(
                rawTheaterJSON: nil,
                rawCommandChainJSON: nil,
                theaterEnvelope: nil,
                commandChainPlan: nil,
                directiveEnvelope: fallback,
                diagnostics: ["Marshal \(config.id) belongs to \(config.faction.displayName), fallback used for \(faction.displayName)."]
            )
        }

        var rawTheaterJSON: String?
        do {
            let summary = summarizer.summary(for: config, in: state)
            let raw = try llmClient.completeTheaterDirectiveJSON(summary: summary, config: config)
            rawTheaterJSON = raw
            let theaterEnvelope = try decoder.parse(
                raw,
                expectedIssuerId: config.id,
                expectedTurn: state.turn,
                expectedFaction: faction,
                state: state
            )
            var rawCommandChainJSON: String?
            var commandChainPlan: ModernCommandChainPlan?
            var diagnostics: [String] = []
            do {
                let plan = commandChainOrchestrator.makePlan(
                    summary: summary,
                    theaterEnvelope: theaterEnvelope,
                    state: state
                )
                let rawPlan = try commandChainOrchestrator.fencedJSON(for: plan)
                rawCommandChainJSON = rawPlan
                commandChainPlan = try commandChainDecoder.parse(
                    rawPlan,
                    expectedIssuerId: config.id,
                    expectedTurn: state.turn,
                    expectedFaction: faction,
                    state: state
                )
            } catch {
                diagnostics.append("Modern command chain validation failed: \(error.localizedDescription). Advisory sub-directives were not executed.")
            }
            let directiveEnvelope = compiler.compile(
                theaterEnvelope,
                state: state,
                fallbackPool: fallbackPool,
                issuerId: issuerId
            )
            return MarshalDirectiveResolution(
                rawTheaterJSON: raw,
                rawCommandChainJSON: rawCommandChainJSON,
                theaterEnvelope: theaterEnvelope,
                commandChainPlan: commandChainPlan,
                directiveEnvelope: directiveEnvelope,
                diagnostics: diagnostics
            )
        } catch {
            let fallback = fallbackPool.envelope(for: faction, in: state, issuerId: issuerId)
            return MarshalDirectiveResolution(
                rawTheaterJSON: rawTheaterJSON,
                rawCommandChainJSON: nil,
                theaterEnvelope: nil,
                commandChainPlan: nil,
                directiveEnvelope: fallback,
                diagnostics: ["Operational directive decode/compile failed: \(error.localizedDescription). Fallback commander pool used."]
            )
        }
    }
}
