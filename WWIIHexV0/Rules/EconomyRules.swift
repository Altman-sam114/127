import Foundation

struct EconomyRules {
    private let baseManpowerReserve = 320
    private let baseIndustryReserve = 160
    private let baseSupplyReserve = 180
    private let maxAutomaticReinforcementPerDivision = 2

    func makeInitialState(map: MapState, factions: [Faction], turn: Int) -> EconomyState {
        var state = EconomyState(lastResolvedTurn: turn)
        let uniqueFactions = Set(factions).isEmpty ? Set(Faction.legacyBelligerents) : Set(factions)

        for faction in uniqueFactions {
            let income = income(for: faction, map: map)
            state.updateLedger(
                FactionEconomyLedger(
                    faction: faction,
                    stockpile: EconomyResources(
                        manpower: baseManpowerReserve + income.manpower * 2,
                        industry: baseIndustryReserve + income.industry,
                        supplies: baseSupplyReserve + income.supplies
                    ),
                    lastIncome: income,
                    lastUpdatedTurn: turn
                )
            )
        }

        return state
    }

    func bootstrapIfNeeded(_ state: GameState) -> GameState {
        guard state.economyState.ledgers.isEmpty else {
            return state
        }

        var next = state
        let factions = next.divisions.map(\.faction) + Faction.legacyBelligerents
        next.economyState = makeInitialState(map: next.map, factions: factions, turn: next.turn)
        next.appendEvent(
            "Economy state bootstrapped from controlled cities, factories, supply hubs, and regions.",
            category: .supply
        )
        return next
    }

    func canQueueProduction(kind: ProductionKind, faction: Faction, in state: GameState) -> Bool {
        state.economyState.ledger(for: faction).stockpile.canAfford(kind.cost)
    }

    func queueProduction(kind: ProductionKind, faction: Faction, in state: inout GameState) -> Bool {
        var ledger = state.economyState.ledger(for: faction)
        guard ledger.stockpile.canAfford(kind.cost) else {
            state.appendEvent(
                "\(faction.displayName) lacks resources for \(kind.displayName).",
                category: .supply
            )
            return false
        }

        ledger.stockpile.subtract(kind.cost)
        let order = ProductionOrder(
            id: productionOrderId(kind: kind, faction: faction, turn: state.turn, index: ledger.productionQueue.count),
            faction: faction,
            kind: kind,
            createdTurn: state.turn
        )
        ledger.productionQueue.append(order)
        ledger.lastUpdatedTurn = state.turn
        state.economyState.updateLedger(ledger)
        state.appendEvent(
            "\(faction.displayName) queued \(kind.displayName): cost \(resourceSummary(kind.cost)), \(kind.buildTurns) turn(s).",
            category: .supply
        )
        return true
    }

    func resolveFactionTurn(for faction: Faction, in state: inout GameState) {
        ensureLedger(for: faction, in: &state)

        var ledger = state.economyState.ledger(for: faction)
        let turnIncome = income(for: faction, map: state.map)
        ledger.stockpile.add(turnIncome)
        ledger.lastIncome = turnIncome

        let upkeep = supplyUpkeep(for: faction, in: state)
        let paidUpkeep = EconomyResources(supplies: min(ledger.stockpile.supplies, upkeep.supplies))
        ledger.stockpile.subtract(paidUpkeep)
        ledger.lastUpkeep = upkeep
        let supplyShortfall = max(0, upkeep.supplies - paidUpkeep.supplies)

        if supplyShortfall > 0 {
            applyStrategicSupplyShortfall(for: faction, in: &state)
        }

        let reinforcementSpend = applyAutomaticReinforcement(for: faction, ledger: &ledger, in: &state)
        ledger.lastReinforcementSpend = reinforcementSpend

        advanceProduction(for: faction, ledger: &ledger, in: &state)

        ledger.lastUpdatedTurn = state.turn
        state.economyState.updateLedger(ledger)
        state.economyState.lastResolvedTurn = state.turn
        state.appendEvent(
            "\(faction.displayName) economy: +\(resourceSummary(turnIncome)); upkeep \(resourceSummary(upkeep)); reinforcement \(resourceSummary(reinforcementSpend)); stockpile \(resourceSummary(ledger.stockpile)).",
            category: .supply
        )
    }

    func cityLevel(for region: RegionNode, map: MapState) -> CityLevel {
        let hasHexCity = region.displayHexes.contains { hex in
            guard let tile = map.tile(at: hex) else {
                return false
            }
            return tile.baseTerrain == .city || tile.cityName != nil || tile.fortressName != nil
        }

        guard region.city != nil || hasHexCity || region.factories > 0 else {
            return .none
        }

        if region.city?.isCapital == true ||
            (region.city?.victoryPoints ?? 0) >= 5 ||
            region.factories >= 5 {
            return .metropolis
        }

        if (region.city?.victoryPoints ?? 0) >= 2 ||
            region.factories >= 2 ||
            region.supplyValue >= 3 {
            return .town
        }

        return .village
    }

    func income(for faction: Faction, map: MapState) -> EconomyResources {
        var income = EconomyResources()

        for region in map.regions.values where region.controller == faction && region.isPassable {
            guard hasControlledHex(in: region, faction: faction, map: map) else {
                continue
            }

            let level = cityLevel(for: region, map: map)
            let coreBonus = region.coreOf.isEmpty || region.coreOf.contains(faction) ? 1 : 0
            let regionManpower = max(1, level.manpowerGrowth + coreBonus * 4 + region.infrastructure)
            let regionIndustry = max(0, region.factories + level.industryValue + region.infrastructure / 3)
            let regionSupplies = max(1, region.supplyValue * 3 + region.factories + region.infrastructure / 2)

            income.add(
                EconomyResources(
                    manpower: regionManpower,
                    industry: regionIndustry,
                    supplies: regionSupplies
                )
            )
        }

        if map.regions.isEmpty {
            let controlledTiles = map.tiles.values.filter { $0.controller == faction }
            income.add(
                EconomyResources(
                    manpower: max(12, controlledTiles.count * 2),
                    industry: max(8, controlledTiles.filter { $0.baseTerrain == .city || $0.cityName != nil }.count * 4),
                    supplies: max(12, map.supplySources(for: faction).count * 12)
                )
            )
        }

        return income
    }

    private func ensureLedger(for faction: Faction, in state: inout GameState) {
        if state.economyState.ledgers[faction] == nil {
            let income = income(for: faction, map: state.map)
            state.economyState.updateLedger(
                FactionEconomyLedger(
                    faction: faction,
                    stockpile: EconomyResources(
                        manpower: baseManpowerReserve + income.manpower,
                        industry: baseIndustryReserve + income.industry,
                        supplies: baseSupplyReserve + income.supplies
                    ),
                    lastIncome: income,
                    lastUpdatedTurn: state.turn
                )
            )
        }
    }

    private func supplyUpkeep(for faction: Faction, in state: GameState) -> EconomyResources {
        let upkeep = state.divisions
            .filter { $0.faction == faction && !$0.isDestroyed }
            .reduce(0) { partial, division in
                partial + 2 + (division.isArmor ? 2 : 0) + (division.isArtillery ? 1 : 0)
            }
        return EconomyResources(supplies: upkeep)
    }

    private func applyStrategicSupplyShortfall(for faction: Faction, in state: inout GameState) {
        for index in state.divisions.indices
            where state.divisions[index].faction == faction &&
            state.divisions[index].supplyState == .supplied {
            state.divisions[index].supplyState = .lowSupply
        }

        state.appendEvent(
            "\(faction.displayName) strategic supply stockpile is depleted; supplied units degrade to Low Supply this turn.",
            category: .supply
        )
    }

    private func applyAutomaticReinforcement(
        for faction: Faction,
        ledger: inout FactionEconomyLedger,
        in state: inout GameState
    ) -> EconomyResources {
        var spend = EconomyResources()
        let candidateIds = state.divisions
            .filter { division in
                division.faction == faction &&
                    !division.isDestroyed &&
                    !division.isRetreating &&
                    division.supplyState == .supplied &&
                    division.strength < division.maxStrength &&
                    !isAdjacentToEnemy(division, in: state)
            }
            .sorted { lhs, rhs in
                let lhsMissing = lhs.maxStrength - lhs.strength
                let rhsMissing = rhs.maxStrength - rhs.strength
                if lhsMissing != rhsMissing {
                    return lhsMissing > rhsMissing
                }
                return lhs.id < rhs.id
            }
            .map(\.id)

        for divisionId in candidateIds {
            guard let index = state.divisionIndex(id: divisionId) else {
                continue
            }

            let missing = state.divisions[index].maxStrength - state.divisions[index].strength
            let desired = min(maxAutomaticReinforcementPerDivision, missing)
            let perStrengthCost = reinforcementCostPerStrength(for: state.divisions[index])
            var restored = 0

            for _ in 0..<desired where ledger.stockpile.canAfford(perStrengthCost) {
                ledger.stockpile.subtract(perStrengthCost)
                spend.add(perStrengthCost)
                restored += 1
            }

            if restored > 0 {
                state.divisions[index].reinforceStrength(restored)
                state.appendEvent(
                    "\(state.divisions[index].name) received automatic replacements: +\(restored) strength.",
                    category: .reinforce
                )
            }
        }

        return spend
    }

    private func reinforcementCostPerStrength(for division: Division) -> EconomyResources {
        let armorWeight = division.componentWeight(where: \.isArmorFamily)
        let mobilityWeight = division.componentWeight {
            $0.isMechanizedFamily || $0.isLogisticsFamily
        }
        let firesWeight = division.componentWeight {
            $0.isFiresFamily || $0.isAirDefenseFamily || $0.isUnmannedFamily
        }
        let sustainmentWeight = division.componentWeight {
            $0.isEngineerFamily || $0.isLogisticsFamily
        }

        return EconomyResources(
            manpower: max(4, Int((8 + 6 * (1 - armorWeight)).rounded())),
            industry: max(1, Int((1 + armorWeight * 5 + mobilityWeight * 2 + firesWeight * 3).rounded())),
            supplies: max(1, Int((1 + sustainmentWeight * 2 + firesWeight).rounded()))
        )
    }

    private func advanceProduction(
        for faction: Faction,
        ledger: inout FactionEconomyLedger,
        in state: inout GameState
    ) {
        var remainingOrders: [ProductionOrder] = []

        for var order in ledger.productionQueue {
            guard order.faction == faction else {
                remainingOrders.append(order)
                continue
            }

            if order.remainingTurns > 0 {
                order.remainingTurns -= 1
            }

            guard order.isReady else {
                remainingOrders.append(order)
                continue
            }

            if order.kind == .supplyStockpile {
                ledger.stockpile.add(EconomyResources(supplies: order.kind.supplyOutput))
                state.appendEvent(
                    "\(faction.displayName) completed \(order.kind.displayName): +\(order.kind.supplyOutput) supplies.",
                    category: .supply
                )
                continue
            }

            if let deployment = deploymentHex(for: faction, preferredRegionId: order.deploymentRegionId, in: state) {
                let division = makeProducedDivision(
                    order: order,
                    faction: faction,
                    coord: deployment.coord,
                    index: state.divisions.count
                )
                state.divisions.append(division)
                order.deploymentRegionId = deployment.regionId
                state.appendEvent(
                    "\(faction.displayName) deployed \(division.name) at \(deployment.coord.q),\(deployment.coord.r).",
                    category: .reinforce
                )
            } else {
                remainingOrders.append(order)
                state.appendEvent(
                    "\(order.kind.displayName) is ready, but no safe rear deployment hex is available.",
                    category: .reinforce
                )
            }
        }

        ledger.productionQueue = remainingOrders
    }

    private func deploymentHex(
        for faction: Faction,
        preferredRegionId: RegionId?,
        in state: GameState
    ) -> (coord: HexCoord, regionId: RegionId?)? {
        let preferredRegions = (preferredRegionId
            .flatMap { state.map.region(id: $0).map { [$0] } } ?? [])
            .filter {
                $0.controller == faction &&
                    hasControlledHex(in: $0, faction: faction, map: state.map) &&
                    deploymentRegionIsQualified($0, map: state.map)
            }
        let controlledRegions = state.map.regions.values
            .filter {
                $0.controller == faction &&
                    hasControlledHex(in: $0, faction: faction, map: state.map) &&
                    deploymentRegionIsQualified($0, map: state.map)
            }
            .sorted {
                deploymentRegionScore($0, map: state.map) == deploymentRegionScore($1, map: state.map)
                    ? $0.id.rawValue < $1.id.rawValue
                    : deploymentRegionScore($0, map: state.map) > deploymentRegionScore($1, map: state.map)
            }
        let regions = preferredRegions + controlledRegions

        for region in regions {
            let hexes = ([region.representativeHex] + region.displayHexes)
                .filter { state.map.tile(at: $0)?.isPassable == true }
                .filter { state.map.tile(at: $0)?.controller == faction }
                .filter { state.division(at: $0) == nil }
                .filter { !isEnemyAdjacent(to: $0, faction: faction, in: state) }
                .sorted {
                    if $0 == region.representativeHex {
                        return true
                    }
                    if $1 == region.representativeHex {
                        return false
                    }
                    if $0.q == $1.q {
                        return $0.r < $1.r
                    }
                    return $0.q < $1.q
                }

            if let hex = hexes.first {
                return (hex, region.id)
            }
        }

        let supplyHexes = state.map.supplySources(for: faction)
            .map(\.coord)
            .filter { state.map.tile(at: $0)?.isPassable == true }
            .filter { state.division(at: $0) == nil }
            .filter { !isEnemyAdjacent(to: $0, faction: faction, in: state) }
        if let hex = supplyHexes.first {
            return (hex, state.map.region(for: hex))
        }

        return nil
    }

    private func hasControlledHex(in region: RegionNode, faction: Faction, map: MapState) -> Bool {
        regionHexes(for: region).contains { coord in
            map.tile(at: coord)?.controller == faction
        }
    }

    private func regionHexes(for region: RegionNode) -> [HexCoord] {
        Array(Set([region.representativeHex] + region.displayHexes))
    }

    private func deploymentRegionIsQualified(_ region: RegionNode, map: MapState) -> Bool {
        let level = cityLevel(for: region, map: map)
        if region.city?.isCapital == true {
            return true
        }

        switch level {
        case .metropolis,
             .town:
            return true
        case .none,
             .village:
            break
        }

        return region.factories >= 2 ||
            region.infrastructure >= 4 ||
            region.supplyValue >= 3
    }

    private func deploymentRegionScore(_ region: RegionNode, map: MapState) -> Int {
        let level = cityLevel(for: region, map: map)
        return level.industryValue * 3 + region.factories * 2 + region.supplyValue + region.infrastructure
    }

    private func makeProducedDivision(
        order: ProductionOrder,
        faction: Faction,
        coord: HexCoord,
        index: Int
    ) -> Division {
        let id = "prod_\(faction.rawValue)_\(order.kind.rawValue)_\(order.createdTurn)_\(index)"
        let name = "\(order.kind.displayName) \(order.createdTurn)-\(index)"

        switch order.kind {
        case .infantryDivision:
            return .infantry(id: id, name: name, faction: faction, coord: coord)
        case .panzerDivision:
            return .panzer(id: id, name: name, faction: faction, coord: coord)
        case .motorizedDivision:
            return .motorized(id: id, name: name, faction: faction, coord: coord)
        case .artilleryDivision:
            return .artillery(id: id, name: name, faction: faction, coord: coord)
        case .supplyStockpile:
            return .infantry(id: id, name: name, faction: faction, coord: coord)
        }
    }

    private func isAdjacentToEnemy(_ division: Division, in state: GameState) -> Bool {
        isEnemyAdjacent(to: division.coord, faction: division.faction, in: state)
    }

    private func isEnemyAdjacent(to coord: HexCoord, faction: Faction, in state: GameState) -> Bool {
        state.divisions.contains { other in
            other.faction != faction && !other.isDestroyed && other.coord.distance(to: coord) <= 1
        }
    }

    private func productionOrderId(kind: ProductionKind, faction: Faction, turn: Int, index: Int) -> String {
        "order_\(faction.rawValue)_\(kind.rawValue)_\(turn)_\(index)"
    }

    private func resourceSummary(_ resources: EconomyResources) -> String {
        "MP \(resources.manpower), IC \(resources.industry), SUP \(resources.supplies)"
    }
}
