import Foundation

struct RegionCombatRules {
    func distance(from start: RegionId, to goal: RegionId, in map: MapState) -> Int? {
        map.regionDistance(from: start, to: goal)
    }

    func canStrategicallyAttack(from attackerRegion: RegionId, to defenderRegion: RegionId, range: Int, in map: MapState) -> Bool {
        guard let distance = distance(from: attackerRegion, to: defenderRegion, in: map) else {
            return false
        }
        return distance > 0 && distance <= max(0, range)
    }

    func pressure(on regionId: RegionId, for faction: Faction, in state: GameState, radius: Int = 1) -> Int {
        let graph = state.map.regionGraph
        guard graph.region(regionId) != nil else {
            return 0
        }

        var pressure = 0
        for division in state.divisions where division.faction.isHostile(to: faction) {
            guard let enemyRegion = state.map.region(for: division.coord),
                  let distance = graph.distance(from: enemyRegion, to: regionId),
                  distance <= radius else {
                continue
            }
            pressure += max(1, division.attack / max(1, distance))
        }
        return pressure
    }
}
