import Foundation

struct MockAIClient: DecisionProvider {
    func decide(context: AgentContext) async throws -> AgentDecisionEnvelope {
        var orders: [AgentOrder] = []
        var reservedDestinations = Set(context.friendlyDivisions.map(\.coord) + context.enemyDivisions.map(\.coord))
        let objective = context.objectives.first { $0.name == "Bastogne" } ?? context.objectives.first

        for division in context.friendlyDivisions.sorted(by: orderPriority) {
            guard !division.hasActed else {
                continue
            }

            if division.supplyState == .lowSupply || division.supplyState == .encircled {
                orders.append(
                    AgentOrder(
                        type: .resupply,
                        divisionId: division.id,
                        to: nil,
                        targetDivisionId: nil,
                        stance: "recover",
                        reason: "Unit is \(division.supplyState.rawValue); recover supply before continuing the attack."
                    )
                )
                continue
            }

            if let attackTarget = bestAttackTarget(for: division, context: context) {
                orders.append(
                    AgentOrder(
                        type: .attack,
                        divisionId: division.id,
                        to: nil,
                        targetDivisionId: attackTarget.id,
                        stance: division.isArtillery ? "fireSupport" : "breakthrough",
                        reason: attackReason(attacker: division, target: attackTarget, context: context)
                    )
                )
                continue
            }

            if let objective,
               let destination = bestMoveDestination(
                for: division,
                toward: objective.coord,
                context: context,
                reservedDestinations: reservedDestinations
               ) {
                reservedDestinations.remove(division.coord)
                reservedDestinations.insert(destination)
                orders.append(
                    AgentOrder(
                        type: .move,
                        divisionId: division.id,
                        to: destination,
                        targetDivisionId: nil,
                        stance: division.isArmor ? "roadAdvance" : "advance",
                        reason: "Advance toward \(objective.name), preferring road movement and open routes."
                    )
                )
                continue
            }

            orders.append(
                AgentOrder(
                    type: .hold,
                    divisionId: division.id,
                    to: nil,
                    targetDivisionId: nil,
                    stance: "hold",
                    reason: "No useful visible move or attack is available."
                )
            )
        }

        return AgentDecisionEnvelope(
            schemaVersion: 1,
            agentId: context.agentId,
            turn: context.turn,
            intent: "Break through toward Bastogne using armor on roads and artillery support.",
            orders: orders
        )
    }

    private func orderPriority(_ lhs: DivisionSummary, _ rhs: DivisionSummary) -> Bool {
        if lhs.isArtillery != rhs.isArtillery {
            return !lhs.isArtillery
        }
        if lhs.isArmor != rhs.isArmor {
            return lhs.isArmor
        }
        return lhs.id < rhs.id
    }

    private func bestAttackTarget(
        for division: DivisionSummary,
        context: AgentContext
    ) -> DivisionSummary? {
        context.enemyDivisions
            .filter { division.coord.distance(to: $0.coord) <= division.range }
            .sorted { lhs, rhs in
                let lhsScore = attackScore(attacker: division, target: lhs, context: context)
                let rhsScore = attackScore(attacker: division, target: rhs, context: context)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.hp < rhs.hp
            }
            .first
    }

    private func attackScore(
        attacker: DivisionSummary,
        target: DivisionSummary,
        context: AgentContext
    ) -> Int {
        let targetTile = context.visibleTiles.first { $0.coord == target.coord }
        let objectiveTileBonus = targetTile?.baseTerrain == .city || targetTile?.baseTerrain == .fortress ? 20 : 0
        let lowHPBonus = max(0, 12 - target.hp)
        let distanceBonus = max(0, 4 - attacker.coord.distance(to: target.coord))
        let artilleryBonus = attacker.isArtillery ? objectiveTileBonus : 0
        return lowHPBonus + distanceBonus + artilleryBonus
    }

    private func attackReason(
        attacker: DivisionSummary,
        target: DivisionSummary,
        context: AgentContext
    ) -> String {
        let targetTile = context.visibleTiles.first { $0.coord == target.coord }
        if attacker.isArtillery,
           targetTile?.baseTerrain == .city || targetTile?.baseTerrain == .fortress {
            return "Artillery fires on defender in a city or fortress hex."
        }
        return "Target is within range and vulnerable enough for a local attack."
    }

    private func bestMoveDestination(
        for division: DivisionSummary,
        toward objectiveCoord: HexCoord,
        context: AgentContext,
        reservedDestinations: Set<HexCoord>
    ) -> HexCoord? {
        let currentDistance = division.coord.distance(to: objectiveCoord)
        let tileByCoord = Dictionary(uniqueKeysWithValues: context.visibleTiles.map { ($0.coord, $0) })

        return division.coord.neighbors
            .compactMap { coord -> TileSummary? in
                guard let tile = tileByCoord[coord],
                      tile.isPassable,
                      !reservedDestinations.contains(coord),
                      coord.distance(to: objectiveCoord) <= currentDistance else {
                    return nil
                }
                return tile
            }
            .sorted { lhs, rhs in
                let lhsDistance = lhs.coord.distance(to: objectiveCoord)
                let rhsDistance = rhs.coord.distance(to: objectiveCoord)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.hasRoad != rhs.hasRoad {
                    return lhs.hasRoad
                }
                return terrainMoveCost(lhs.baseTerrain) < terrainMoveCost(rhs.baseTerrain)
            }
            .first?
            .coord
    }

    private func terrainMoveCost(_ terrain: BaseTerrain) -> Int {
        terrain.movementCost
    }
}
