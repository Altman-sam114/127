import Foundation

struct FireMissionPlan: Equatable {
    let mission: FireMission
    let contact: ContactTrack?
    let targetCoord: HexCoord
    let targetDivisionId: String?
    let airDefenseThreat: Int
    let electronicWarfarePenalty: Int
}

struct FireSupportRules {
    private let visibilityRules = VisibilityRules()
    private let supplyRules = SupplyRules()

    func advanceTurn(_ state: FireSupportState) -> FireSupportState {
        var next = state
        next.cooldownsByAsset = Dictionary(uniqueKeysWithValues: next.cooldownsByAsset.compactMap { assetId, turns in
            let remaining = turns - 1
            return remaining > 0 ? (assetId, remaining) : nil
        })
        next.scheduledMissions.removeAll()
        next.airTaskingState.sorties = next.airTaskingState.sorties.compactMap { sortie in
            var updated = sortie
            updated.remainingTurns -= 1
            return updated.remainingTurns > 0 ? updated : nil
        }
        next.airTaskingState.suppressionEffects = next.airTaskingState.suppressionEffects.compactMap { effect in
            var updated = effect
            updated.remainingTurns -= 1
            return updated.remainingTurns > 0 ? updated : nil
        }
        next.airTaskingState.airDefenseThreat = next.airTaskingState.airDefenseThreat.filter { $0.remainingTurns > 1 }
        return next
    }

    func validateFireMission(
        issuer: Division,
        target: FireMissionTarget,
        munitionClass: MunitionClass,
        in state: GameState
    ) -> CommandValidation {
        guard canUse(issuer: issuer, munitionClass: munitionClass) else {
            return .invalid(.invalidSourceAsset)
        }
        guard cooldown(for: issuer.id, in: state.fireSupportState) <= 0 else {
            return .invalid(.assetOnCooldown)
        }
        guard state.fireSupportState.budget(for: issuer.faction.alignment).available(for: munitionClass) > 0 else {
            return .invalid(.insufficientAmmo)
        }
        guard let plan = makeFireMissionPlan(
            issuer: issuer,
            target: target,
            munitionClass: munitionClass,
            in: state
        ) else {
            return .invalid(.targetNotFound)
        }
        guard issuer.coord.distance(to: plan.targetCoord) <= fireRange(for: issuer, munitionClass: munitionClass) else {
            return .invalid(.targetOutOfRange)
        }
        guard plan.mission.targetQuality >= .medium else {
            return .invalid(.insufficientTargetQuality)
        }
        if let targetDivisionId = plan.targetDivisionId,
           let targetDivision = state.division(id: targetDivisionId),
           !targetDivision.faction.isHostile(to: issuer.faction) {
            return .invalid(.invalidTargetFaction)
        }
        guard !wouldCreateFriendlyProximityRejection(plan: plan, issuer: issuer, munitionClass: munitionClass, in: state) else {
            return .invalid(.friendlyProximityRisk)
        }
        if munitionClass.usesAirTasking,
           plan.airDefenseThreat >= 5 {
            return .invalid(.airDefenseThreatTooHigh)
        }
        return .valid
    }

    func validateUAVRecon(issuer: Division, target: HexCoord, in state: GameState) -> CommandValidation {
        guard issuer.hasUnmannedSupport else {
            return .invalid(.invalidSourceAsset)
        }
        guard cooldown(for: "uav_\(issuer.id)", in: state.fireSupportState) <= 0 else {
            return .invalid(.assetOnCooldown)
        }
        let threat = airDefenseThreat(near: target, against: issuer.faction.alignment, in: state)
        guard threat < 6 else {
            return .invalid(.airDefenseThreatTooHigh)
        }
        return .valid
    }

    func validateSuppressAirDefense(issuer: Division, target: HexCoord, in state: GameState) -> CommandValidation {
        guard canSuppressAirDefense(issuer) else {
            return .invalid(.invalidSourceAsset)
        }
        guard cooldown(for: issuer.id, in: state.fireSupportState) <= 0 else {
            return .invalid(.assetOnCooldown)
        }
        guard suppressionMunition(for: issuer, in: state) != nil else {
            return .invalid(.insufficientAmmo)
        }
        guard state.map.contains(target) else {
            return .invalid(.destinationOutOfBounds)
        }
        return .valid
    }

    func executeFireMission(
        issuerId: String,
        target: FireMissionTarget,
        munitionClass: MunitionClass,
        in state: GameState
    ) -> GameState {
        var next = state
        guard let issuerIndex = next.divisionIndex(id: issuerId) else {
            return next
        }
        let issuer = next.divisions[issuerIndex]
        guard let plan = makeFireMissionPlan(
            issuer: issuer,
            target: target,
            munitionClass: munitionClass,
            in: next
        ) else {
            return next
        }

        _ = next.fireSupportState.consume(munitionClass, for: issuer.faction.alignment)
        next.fireSupportState.cooldownsByAsset[issuer.id] = munitionClass.cooldownTurns
        next.fireSupportState.scheduledMissions.append(plan.mission)
        next.divisions[issuerIndex].hasActed = true

        let resolved = resolveDamage(plan: plan, munitionClass: munitionClass)
        let resultId = "\(plan.mission.id)_result"
        let result: FireMissionResult

        if resolved.damage > 0,
           let targetDivisionId = plan.targetDivisionId,
           let targetIndex = next.divisionIndex(id: targetDivisionId) {
            let before = next.divisions[targetIndex]
            next.divisions[targetIndex].receiveStrengthDamage(resolved.damage)
            let afterDamage = next.divisions[targetIndex]
            let wasDestroyed = afterDamage.isDestroyed

            if wasDestroyed {
                next.victoryState.recordEliminatedDivision(faction: before.faction)
                next.removeDivision(id: before.id)
                removeContacts(linkedTo: before.id, in: &next)
            } else {
                strengthenFireObservation(for: before.id, owner: issuer.faction, in: &next)
                if shouldForceRetreat(before: before, damage: resolved.damage),
                   next.division(id: before.id)?.isDestroyed == false {
                    supplyRules.resolveRetreat(for: before.id, in: &next)
                }
            }

            result = FireMissionResult(
                id: resultId,
                missionId: plan.mission.id,
                turn: next.turn,
                side: issuer.faction.alignment,
                status: resolved.status,
                target: target,
                targetDivisionId: before.id,
                munitionClass: munitionClass,
                damage: resolved.damage,
                riskFlags: plan.mission.riskFlags,
                narrative: "\(munitionClass.displayName) \(resolved.status.displayName) against \(before.operationalDisplayName): -\(resolved.damage) strength\(wasDestroyed ? ", target destroyed" : "")."
            )
        } else {
            result = FireMissionResult(
                id: resultId,
                missionId: plan.mission.id,
                turn: next.turn,
                side: issuer.faction.alignment,
                status: .failed,
                target: target,
                targetDivisionId: plan.targetDivisionId,
                munitionClass: munitionClass,
                damage: 0,
                riskFlags: plan.mission.riskFlags,
                narrative: "\(munitionClass.displayName) failed to achieve effect on \(target.displayName)."
            )
        }

        record(result: result, mission: plan.mission, issuer: issuer, targetCoord: plan.targetCoord, in: &next)
        next.fireSupportState.scheduledMissions.removeAll { $0.id == plan.mission.id }
        return next
    }

    func executeUAVRecon(divisionId: String, target: HexCoord, in state: GameState) -> GameState {
        var next = state
        guard let index = next.divisionIndex(id: divisionId) else {
            return next
        }
        let issuer = next.divisions[index]
        let threat = airDefenseThreat(near: target, against: issuer.faction.alignment, in: next)
        let ewPenalty = electronicWarfarePenalty(at: target, against: issuer.faction.alignment, in: next)
        let risk = threat + ewPenalty
        let status: FireMissionOutcomeStatus

        if risk >= 5 {
            status = .failed
            next.divisions[index].hasActed = true
            next.appendEvent(
                "\(issuer.operationalDisplayName) UAV recon failed near \(target.q),\(target.r): AD/EW risk \(risk).",
                category: .fireSupport
            )
        } else {
            let confidencePenalty = risk >= 3 ? 1 : 0
            let recon = visibilityRules.performUAVRecon(
                divisionId: divisionId,
                target: target,
                confidencePenalty: confidencePenalty,
                in: next
            )
            next = recon.state
            status = confidencePenalty > 0 ? .degraded : .success
            next.appendEvent(
                "\(issuer.operationalDisplayName) UAV recon \(status.displayName) near \(target.q),\(target.r): \(recon.refreshed) contact(s) refreshed.",
                category: .fireSupport
            )
        }

        next.fireSupportState.cooldownsByAsset["uav_\(divisionId)"] = 1
        appendSortie(
            issuer: issuer,
            target: target,
            task: "UAV Recon",
            status: status,
            in: &next
        )
        return next
    }

    func executeSuppressAirDefense(divisionId: String, target: HexCoord, in state: GameState) -> GameState {
        var next = state
        guard let index = next.divisionIndex(id: divisionId),
              let munitionClass = suppressionMunition(for: next.divisions[index], in: next) else {
            return next
        }

        let issuer = next.divisions[index]
        let targetSide = hostileSide(near: target, for: issuer.faction, in: next)
        _ = next.fireSupportState.consume(munitionClass, for: issuer.faction.alignment)
        next.fireSupportState.cooldownsByAsset[issuer.id] = max(1, munitionClass.cooldownTurns)
        next.divisions[index].hasActed = true

        let effect = AirDefenseSuppression(
            id: "ad_supp_\(next.turn)_\(issuer.id)_\(target.q)_\(target.r)",
            coord: target,
            side: targetSide,
            reduction: 3,
            remainingTurns: 3
        )
        next.fireSupportState.airTaskingState.suppressionEffects.removeAll { $0.id == effect.id }
        next.fireSupportState.airTaskingState.suppressionEffects.append(effect)

        let threat = airDefenseThreatSnapshot(near: target, side: targetSide, in: next)
        next.fireSupportState.airTaskingState.airDefenseThreat.removeAll { $0.id == threat.id }
        next.fireSupportState.airTaskingState.airDefenseThreat.append(threat)

        let mission = FireMission(
            id: "ad_supp_\(next.turn)_\(issuer.id)_\(target.q)_\(target.r)",
            issuerId: issuer.id,
            side: issuer.faction.alignment,
            sourceAssetId: issuer.id,
            target: .hex(target),
            munitionClass: munitionClass,
            targetQuality: .medium,
            expectedEffect: effect.reduction,
            riskFlags: threat.threatLevel > 0 ? [.airDefenseThreat] : []
        )
        let result = FireMissionResult(
            id: "\(mission.id)_result",
            missionId: mission.id,
            turn: next.turn,
            side: issuer.faction.alignment,
            status: .suppressed,
            target: mission.target,
            targetDivisionId: nil,
            munitionClass: munitionClass,
            damage: 0,
            riskFlags: mission.riskFlags,
            narrative: "\(issuer.operationalDisplayName) suppressed \(targetSide.rawValue) air defenses near \(target.q),\(target.r) for \(effect.remainingTurns) turns."
        )
        next.fireSupportState.recordResult(result)
        next.appendEvent(result.narrative, category: .fireSupport)
        return next
    }

    func makeFireMissionPlan(
        issuer: Division,
        target: FireMissionTarget,
        munitionClass: MunitionClass,
        in state: GameState
    ) -> FireMissionPlan? {
        guard let resolved = resolveTarget(target, for: issuer.faction, in: state) else {
            return nil
        }

        let adThreat = airDefenseThreat(near: resolved.coord, against: issuer.faction.alignment, in: state)
        let ewPenalty = electronicWarfarePenalty(at: resolved.coord, against: issuer.faction.alignment, in: state)
        let risks = riskFlags(
            contact: resolved.contact,
            targetCoord: resolved.coord,
            issuer: issuer,
            munitionClass: munitionClass,
            airDefenseThreat: adThreat,
            electronicWarfarePenalty: ewPenalty,
            in: state
        )
        let expectedEffect = max(
            0,
            munitionClass.baseDamage + resolved.quality.rank - (munitionClass.usesAirTasking ? adThreat / 2 : 0) - ewPenalty
        )
        let mission = FireMission(
            id: "fm_\(state.turn)_\(issuer.id)_\(targetStableId(target))_\(munitionClass.rawValue)",
            issuerId: issuer.id,
            side: issuer.faction.alignment,
            sourceAssetId: issuer.id,
            target: target,
            munitionClass: munitionClass,
            targetQuality: resolved.quality,
            expectedEffect: expectedEffect,
            riskFlags: risks
        )

        return FireMissionPlan(
            mission: mission,
            contact: resolved.contact,
            targetCoord: resolved.coord,
            targetDivisionId: resolved.targetDivisionId,
            airDefenseThreat: adThreat,
            electronicWarfarePenalty: ewPenalty
        )
    }

    private func resolveTarget(
        _ target: FireMissionTarget,
        for faction: Faction,
        in state: GameState
    ) -> (contact: ContactTrack?, coord: HexCoord, quality: ContactConfidence, targetDivisionId: String?)? {
        switch target {
        case .contact(let id):
            guard let contact = state.operationalAwareness.contacts[id],
                  contact.ownerFaction == faction else {
                return nil
            }
            return (contact, contact.lastKnownCoord, contact.confidence, contact.linkedDivisionId)
        case .hex(let coord):
            guard state.map.contains(coord),
                  let contact = bestContact(for: faction, matching: { $0.lastKnownCoord == coord }, in: state) else {
                return nil
            }
            return (contact, coord, contact.confidence, contact.linkedDivisionId)
        case .region(let regionId):
            guard let contact = bestContact(
                for: faction,
                matching: { state.map.region(for: $0.lastKnownCoord) == regionId },
                in: state
            ) else {
                return nil
            }
            return (contact, contact.lastKnownCoord, contact.confidence, contact.linkedDivisionId)
        }
    }

    private func bestContact(
        for faction: Faction,
        matching predicate: (ContactTrack) -> Bool,
        in state: GameState
    ) -> ContactTrack? {
        state.operationalAwareness.visibleContacts(for: faction)
            .filter(predicate)
            .first
    }

    private func resolveDamage(
        plan: FireMissionPlan,
        munitionClass: MunitionClass
    ) -> (damage: Int, status: FireMissionOutcomeStatus) {
        guard plan.targetDivisionId != nil else {
            return (0, .failed)
        }

        let airDefensePenalty = munitionClass.usesAirTasking ? plan.airDefenseThreat / 2 : 0
        let rawDamage = munitionClass.baseDamage + plan.mission.targetQuality.rank - airDefensePenalty - plan.electronicWarfarePenalty
        if rawDamage <= 0 {
            return (0, .failed)
        }
        let damage = max(1, min(7, rawDamage))
        let degraded = airDefensePenalty > 0 || plan.electronicWarfarePenalty > 0 || plan.mission.targetQuality == .medium
        return (damage, degraded ? .degraded : .success)
    }

    private func canUse(issuer: Division, munitionClass: MunitionClass) -> Bool {
        switch munitionClass {
        case .tubeArtillery:
            return issuer.componentWeight(where: { $0 == .artillery }) >= 0.20 || issuer.isArtillery
        case .rocket:
            return issuer.componentWeight(where: { $0 == .rocketArtillery }) >= 0.20 || issuer.isArtillery
        case .precision:
            return issuer.componentWeight(where: \.isFiresFamily) >= 0.20 || issuer.hasUnmannedSupport
        case .loitering:
            return issuer.componentWeight(where: { $0 == .loiteringMunition || $0 == .uav }) >= 0.10
        }
    }

    private func canSuppressAirDefense(_ issuer: Division) -> Bool {
        issuer.isArtillery ||
            issuer.hasUnmannedSupport ||
            issuer.componentWeight(where: { $0 == .electronicWarfare || $0 == .airDefense }) >= 0.15
    }

    private func suppressionMunition(for issuer: Division, in state: GameState) -> MunitionClass? {
        let budget = state.fireSupportState.budget(for: issuer.faction.alignment)
        let preferred: [MunitionClass] = issuer.componentWeight(where: { $0 == .rocketArtillery }) >= 0.20
            ? [.rocket, .tubeArtillery, .precision]
            : [.tubeArtillery, .rocket, .precision]
        return preferred.first { budget.available(for: $0) > 0 && canUse(issuer: issuer, munitionClass: $0) }
    }

    private func cooldown(for assetId: String, in state: FireSupportState) -> Int {
        state.cooldownsByAsset[assetId, default: 0]
    }

    private func fireRange(for issuer: Division, munitionClass: MunitionClass) -> Int {
        let baseRange = max(issuer.range, issuer.vision / 2)
        switch munitionClass {
        case .tubeArtillery:
            return max(2, baseRange + 1)
        case .rocket:
            return max(3, baseRange + 2)
        case .precision,
             .loitering:
            return max(3, baseRange + 2)
        }
    }

    private func airDefenseThreat(
        near coord: HexCoord,
        against side: OperationalSideAlignment,
        in state: GameState
    ) -> Int {
        let hostileThreat = state.divisions
            .filter { $0.faction.alignment != side && $0.faction.alignment != .neutral && !$0.isDestroyed }
            .filter { $0.hasAirDefenseSupport && $0.coord.distance(to: coord) <= 2 }
            .map { max(1, $0.defense / 2) }
            .reduce(0, +)
        let suppression = state.fireSupportState.airTaskingState.suppressionEffects
            .filter { $0.side != side && $0.coord.distance(to: coord) <= 2 && $0.remainingTurns > 0 }
            .map(\.reduction)
            .reduce(0, +)
        return max(0, hostileThreat - suppression)
    }

    private func airDefenseThreatSnapshot(
        near coord: HexCoord,
        side: OperationalSideAlignment,
        in state: GameState
    ) -> AirDefenseThreat {
        let threatLevel = state.divisions
            .filter { $0.faction.alignment == side && $0.hasAirDefenseSupport && !$0.isDestroyed }
            .filter { $0.coord.distance(to: coord) <= 2 }
            .map { max(1, $0.defense / 2) }
            .reduce(0, +)
        return AirDefenseThreat(
            id: "ad_threat_\(side.rawValue)_\(coord.q)_\(coord.r)",
            coord: coord,
            side: side,
            threatLevel: threatLevel,
            remainingTurns: 3
        )
    }

    private func electronicWarfarePenalty(
        at coord: HexCoord,
        against side: OperationalSideAlignment,
        in state: GameState
    ) -> Int {
        state.operationalAwareness.ewEffects
            .filter { $0.side == side && $0.area.contains(coord) && $0.remainingTurns > 0 }
            .map(\.strength)
            .max() ?? 0
    }

    private func hostileSide(
        near target: HexCoord,
        for faction: Faction,
        in state: GameState
    ) -> OperationalSideAlignment {
        if let hostile = state.divisions
            .filter({ $0.faction.isHostile(to: faction) && !$0.isDestroyed })
            .min(by: { $0.coord.distance(to: target) < $1.coord.distance(to: target) }) {
            return hostile.faction.alignment
        }
        return .neutral
    }

    private func riskFlags(
        contact: ContactTrack?,
        targetCoord: HexCoord,
        issuer: Division,
        munitionClass: MunitionClass,
        airDefenseThreat: Int,
        electronicWarfarePenalty: Int,
        in state: GameState
    ) -> [FireRiskFlag] {
        var flags: [FireRiskFlag] = []
        if let contact {
            if contact.confidence == .low || contact.confidence == .medium {
                flags.append(.lowTargetQuality)
            }
            if contact.ageInTurns > 0 {
                flags.append(.staleContact)
            }
        }
        if airDefenseThreat > 0 {
            flags.append(.airDefenseThreat)
        }
        if munitionClass.usesAirTasking && airDefenseThreat > 2 {
            flags.append(.unsuppressedAirDefense)
        }
        if electronicWarfarePenalty > 0 {
            flags.append(.electronicWarfare)
        }
        if hasFriendlyNear(targetCoord, faction: issuer.faction, radius: 1, in: state) {
            flags.append(.friendlyProximity)
        }
        return stableUnique(flags)
    }

    private func wouldCreateFriendlyProximityRejection(
        plan: FireMissionPlan,
        issuer: Division,
        munitionClass: MunitionClass,
        in state: GameState
    ) -> Bool {
        guard munitionClass == .rocket else {
            return false
        }
        return hasFriendlyNear(plan.targetCoord, faction: issuer.faction, radius: 0, in: state)
    }

    private func hasFriendlyNear(_ coord: HexCoord, faction: Faction, radius: Int, in state: GameState) -> Bool {
        state.divisions.contains {
            $0.faction == faction && !$0.isDestroyed && $0.coord.distance(to: coord) <= radius
        }
    }

    private func shouldForceRetreat(before division: Division, damage: Int) -> Bool {
        division.retreatMode == .retreatable && Double(damage) / Double(max(1, division.strength)) >= 0.30
    }

    private func strengthenFireObservation(for targetDivisionId: String, owner: Faction, in state: inout GameState) {
        for key in state.operationalAwareness.contacts.keys {
            guard var contact = state.operationalAwareness.contacts[key],
                  contact.ownerFaction == owner,
                  contact.linkedDivisionId == targetDivisionId else {
                continue
            }
            contact.source = .fireObservation
            contact.ageInTurns = 0
            if contact.confidence < .high {
                contact.confidence = .high
            }
            state.operationalAwareness.contacts[key] = contact
        }
    }

    private func removeContacts(linkedTo targetDivisionId: String, in state: inout GameState) {
        state.operationalAwareness.contacts = state.operationalAwareness.contacts.filter {
            $0.value.linkedDivisionId != targetDivisionId
        }
    }

    private func appendSortie(
        issuer: Division,
        target: HexCoord,
        task: String,
        status: FireMissionOutcomeStatus,
        in state: inout GameState
    ) {
        let sortie = AirSortie(
            id: "sortie_\(state.turn)_\(issuer.id)_\(target.q)_\(target.r)_\(task.replacingOccurrences(of: " ", with: "_"))",
            issuerId: issuer.id,
            side: issuer.faction.alignment,
            target: target,
            task: task,
            status: status,
            remainingTurns: 1
        )
        state.fireSupportState.airTaskingState.sorties.append(sortie)
        state.fireSupportState.airTaskingState.sorties = Array(state.fireSupportState.airTaskingState.sorties.suffix(12))
    }

    private func record(
        result: FireMissionResult,
        mission: FireMission,
        issuer: Division,
        targetCoord: HexCoord,
        in state: inout GameState
    ) {
        state.fireSupportState.recordResult(result)
        if mission.munitionClass.usesAirTasking {
            appendSortie(
                issuer: issuer,
                target: targetCoord,
                task: mission.munitionClass.displayName,
                status: result.status,
                in: &state
            )
        }
        let risks = result.riskFlags.isEmpty
            ? "no major risks"
            : result.riskFlags.map(\.displayName).joined(separator: ", ")
        state.appendEvent(
            "\(result.narrative) Risks: \(risks).",
            category: .fireSupport
        )
    }

    private func targetStableId(_ target: FireMissionTarget) -> String {
        switch target {
        case .contact(let id):
            return id
        case .hex(let coord):
            return "hex_\(coord.q)_\(coord.r)"
        case .region(let regionId):
            return "region_\(regionId.rawValue)"
        }
    }

    private func stableUnique(_ flags: [FireRiskFlag]) -> [FireRiskFlag] {
        var seen: Set<FireRiskFlag> = []
        var result: [FireRiskFlag] = []
        for flag in flags where !seen.contains(flag) {
            seen.insert(flag)
            result.append(flag)
        }
        return result
    }
}
