import Foundation

struct VisibilityRules {
    func refreshAwareness(in state: GameState) -> OperationalAwarenessState {
        var awareness = state.operationalAwareness
        awareness.sensorCoverage = makeSensorCoverage(in: state)

        for faction in activeObserverFactions(in: state) {
            refreshContacts(for: faction, state: state, awareness: &awareness)
        }

        return awareness
    }

    func advanceTurn(_ awareness: OperationalAwarenessState) -> OperationalAwarenessState {
        var next = awareness
        next.ewEffects = next.ewEffects.compactMap { effect in
            var updated = effect
            updated.remainingTurns -= 1
            return updated.remainingTurns > 0 ? updated : nil
        }

        next.contacts = Dictionary(uniqueKeysWithValues: next.contacts.compactMap { key, contact in
            var updated = contact
            updated.ageInTurns += 1
            guard let degraded = updated.confidence.degraded else {
                return nil
            }
            updated.confidence = degraded
            return (key, updated)
        })
        return next
    }

    func performRecon(
        divisionId: String,
        target: HexCoord,
        in state: GameState
    ) -> (state: GameState, refreshed: Int) {
        var next = state
        guard let index = next.divisionIndex(id: divisionId) else {
            return (next, 0)
        }

        let observer = next.divisions[index]
        var awareness = next.operationalAwareness
        let before = awareness.visibleContacts(for: observer.faction).count
        awareness.sensorCoverage = makeSensorCoverage(in: next)
        refreshContacts(
            for: observer.faction,
            state: next,
            focus: target,
            forcedSource: observer.hasUnmannedSupport ? .uav : .groundRecon,
            awareness: &awareness
        )
        next.operationalAwareness = awareness
        next.divisions[index].hasActed = true

        let after = awareness.visibleContacts(for: observer.faction).count
        let refreshed = max(0, after - before)
        next.appendEvent(
            "\(observer.operationalDisplayName) recon sweep refreshed \(after) contact(s) near \(target.q),\(target.r).",
            category: .intelligence
        )
        return (next, refreshed)
    }

    func applyElectronicWarfare(
        divisionId: String,
        target: HexCoord,
        in state: GameState
    ) -> GameState {
        var next = state
        guard let index = next.divisionIndex(id: divisionId) else {
            return next
        }

        let emitter = next.divisions[index]
        let affectedSide = targetSide(for: emitter.faction, near: target, in: next)
        let area = target.coordsWithin(distance: 1)
            .filter { next.map.contains($0) }
            .sorted {
                if $0.q == $1.q {
                    return $0.r < $1.r
                }
                return $0.q < $1.q
            }

        let effect = EWEffect(
            id: "ew_\(next.turn)_\(emitter.id)_\(target.q)_\(target.r)",
            area: area,
            side: affectedSide,
            effectType: emitter.hasUnmannedSupport ? .droneDisrupt : .jamming,
            strength: max(1, emitter.vision / 2),
            remainingTurns: 2
        )

        next.operationalAwareness.ewEffects.removeAll { $0.id == effect.id }
        next.operationalAwareness.ewEffects.append(effect)
        next.operationalAwareness = refreshAwareness(in: next)
        if let updatedIndex = next.divisionIndex(id: divisionId) {
            next.divisions[updatedIndex].hasActed = true
        }
        next.appendEvent(
            "\(emitter.operationalDisplayName) established \(effect.effectType.displayName.lowercased()) over \(target.q),\(target.r).",
            category: .electronicWarfare
        )
        return next
    }

    func targetQuality(contactId: String, for faction: Faction, in state: GameState) -> ContactConfidence? {
        guard let contact = state.operationalAwareness.contacts[contactId],
              contact.ownerFaction == faction else {
            return nil
        }
        return contact.confidence
    }

    func contactStrengthEstimate(_ contact: ContactTrack) -> Int {
        let base: Int
        switch contact.estimatedType {
        case .armor:
            base = 10
        case .artillery,
             .airDefense:
            base = 7
        case .infantry:
            base = 6
        case .logistics:
            base = 3
        case .unknown:
            base = 4
        }
        return max(1, base + contact.confidence.rank * 2 - contact.ageInTurns)
    }

    private func makeSensorCoverage(in state: GameState) -> [SensorCoverage] {
        var bestById: [String: SensorCoverage] = [:]

        for division in state.divisions where !division.isDestroyed {
            let source = sensorSource(for: division)
            let range = sensorRange(for: division)
            let side = division.faction.alignment
            for coord in division.coord.coordsWithin(distance: range) where state.map.contains(coord) {
                let jamStrength = jammingStrength(at: coord, for: side, awareness: state.operationalAwareness)
                let rawQuality = sensorQuality(for: division) - jamStrength
                let coverage = SensorCoverage(
                    coord: coord,
                    side: side,
                    quality: max(1, rawQuality),
                    sources: [source],
                    jammed: jamStrength > 0
                )

                if let current = bestById[coverage.id], current.quality >= coverage.quality {
                    continue
                }
                bestById[coverage.id] = coverage
            }
        }

        return bestById.values.sorted {
            if $0.side != $1.side {
                return $0.side.rawValue < $1.side.rawValue
            }
            if $0.coord.q == $1.coord.q {
                return $0.coord.r < $1.coord.r
            }
            return $0.coord.q < $1.coord.q
        }
    }

    private func refreshContacts(
        for faction: Faction,
        state: GameState,
        focus: HexCoord? = nil,
        forcedSource: ContactSource? = nil,
        awareness: inout OperationalAwarenessState
    ) {
        let side = faction.alignment
        let coverageByCoord = Dictionary(grouping: awareness.sensorCoverage.filter { $0.side == side }) {
            $0.coord
        }

        for division in state.divisions where division.faction.isHostile(to: faction) && !division.isDestroyed {
            if let focus, division.coord.distance(to: focus) > 2 {
                continue
            }

            guard let coverage = coverageByCoord[division.coord]?.max(by: { $0.quality < $1.quality }) else {
                continue
            }

            let source = forcedSource ?? coverage.sources.first ?? .visual
            let confidence = contactConfidence(quality: coverage.quality, jammed: coverage.jammed, source: source)
            let contact = ContactTrack(
                id: contactId(owner: faction, division: division),
                ownerFaction: faction,
                observerSide: side,
                lastKnownCoord: division.coord,
                confidence: confidence,
                estimatedType: estimatedType(for: division, confidence: confidence),
                source: source,
                ageInTurns: 0,
                linkedDivisionId: division.id
            )
            awareness.contacts[contact.id] = contact
        }
    }

    private func contactId(owner: Faction, division: Division) -> String {
        let type = estimatedType(for: division, confidence: .confirmed)
        return "ct_\(owner.rawValue)_\(division.coord.q)_\(division.coord.r)_\(type.rawValue)"
    }

    private func sensorRange(for division: Division) -> Int {
        let bonus = division.hasUnmannedSupport ? 1 : 0
        return max(1, min(6, division.vision / 2 + bonus))
    }

    private func sensorQuality(for division: Division) -> Int {
        var quality = division.vision
        if division.hasUnmannedSupport {
            quality += 2
        }
        if division.componentWeight(where: { $0 == .recon }) >= 0.25 {
            quality += 2
        }
        if division.componentWeight(where: \.isAirDefenseFamily) >= 0.20 {
            quality += 1
        }
        return quality
    }

    private func sensorSource(for division: Division) -> ContactSource {
        if division.hasUnmannedSupport {
            return .uav
        }
        if division.componentWeight(where: { $0 == .recon || $0 == .specialForces }) >= 0.20 {
            return .groundRecon
        }
        if division.componentWeight(where: \.isAirDefenseFamily) >= 0.20 {
            return .signal
        }
        return .visual
    }

    private func contactConfidence(
        quality: Int,
        jammed: Bool,
        source: ContactSource
    ) -> ContactConfidence {
        var adjusted = quality
        if jammed {
            adjusted -= 2
        }
        if source == .uav || source == .signal {
            adjusted += 1
        }

        if adjusted >= 8 {
            return .confirmed
        }
        if adjusted >= 6 {
            return .high
        }
        if adjusted >= 4 {
            return .medium
        }
        return .low
    }

    private func estimatedType(for division: Division, confidence: ContactConfidence) -> EstimatedContactType {
        guard confidence >= .medium else {
            return .unknown
        }
        if division.hasAirDefenseSupport {
            return .airDefense
        }
        if division.isArtillery {
            return .artillery
        }
        if division.isArmor || division.isMechanized {
            return .armor
        }
        if division.hasLogisticsSupport && division.attack <= 3 {
            return .logistics
        }
        if division.hasLightGroundCore {
            return .infantry
        }
        return .unknown
    }

    private func jammingStrength(
        at coord: HexCoord,
        for side: OperationalSideAlignment,
        awareness: OperationalAwarenessState
    ) -> Int {
        awareness.ewEffects
            .filter { $0.side == side && $0.area.contains(coord) && $0.remainingTurns > 0 }
            .map(\.strength)
            .max() ?? 0
    }

    private func targetSide(
        for faction: Faction,
        near target: HexCoord,
        in state: GameState
    ) -> OperationalSideAlignment {
        if let hostile = state.divisions
            .filter({ $0.faction.isHostile(to: faction) })
            .min(by: { $0.coord.distance(to: target) < $1.coord.distance(to: target) }) {
            return hostile.faction.alignment
        }
        return faction.opponent.alignment
    }

    private func activeObserverFactions(in state: GameState) -> [Faction] {
        Array(Set(state.divisions.map(\.faction)))
            .filter { !$0.isNeutralLike }
            .sorted { $0.rawValue < $1.rawValue }
    }
}
