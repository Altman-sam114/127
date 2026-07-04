import Foundation
@testable import WWIIHexV0

enum FrontLineTestFixtures {
    struct RegionSpec {
        let id: RegionId
        let faction: Faction
        let theaterId: TheaterId
        let neighbors: [RegionId]
        let supplyValue: Int

        init(
            id: RegionId,
            faction: Faction,
            theaterId: TheaterId,
            neighbors: [RegionId],
            supplyValue: Int = 0
        ) {
            self.id = id
            self.faction = faction
            self.theaterId = theaterId
            self.neighbors = neighbors
            self.supplyValue = supplyValue
        }
    }

    static let theaterA = TheaterId("A")
    static let theaterB = TheaterId("B")
    static let theaterC = TheaterId("C")
    static let theaterD = TheaterId("D")

    static func mapAndTheaters(
        specs: [RegionSpec],
        inactiveTheaters: Set<TheaterId> = []
    ) -> (map: MapState, theaterState: TheaterState) {
        var regions: [RegionId: RegionNode] = [:]
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        var edges: Set<RegionEdge> = []
        var groupedRegions: [TheaterId: [RegionId]] = [:]
        var regionToTheater: [RegionId: TheaterId] = [:]
        let displayHexesByRegion = displayHexes(for: specs)

        for spec in specs {
            let displayHexes = displayHexesByRegion[spec.id] ?? [HexCoord(q: 0, r: 0)]
            regions[spec.id] = RegionNode(
                id: spec.id,
                name: spec.id.rawValue,
                owner: spec.faction,
                controller: spec.faction,
                terrain: .plain,
                neighbors: spec.neighbors,
                displayHexes: displayHexes,
                representativeHex: displayHexes[0],
                supplyValue: spec.supplyValue
            )
            for coord in displayHexes {
                tiles[coord] = HexTile(coord: coord, baseTerrain: .plain, controller: spec.faction, regionId: spec.id)
                hexToRegion[coord] = spec.id
            }
            groupedRegions[spec.theaterId, default: []].append(spec.id)
            regionToTheater[spec.id] = spec.theaterId

            for neighbor in spec.neighbors {
                edges.insert(RegionEdge(from: spec.id, to: neighbor))
            }
        }

        var theaters: [TheaterId: TheaterNode] = [:]
        for (theaterId, regionIds) in groupedRegions {
            let factions = regionIds.compactMap { regions[$0]?.controller }
            let controllingFaction = Faction.allCases.max { lhs, rhs in
                factions.count(where: { $0 == lhs }) < factions.count(where: { $0 == rhs })
            }
            theaters[theaterId] = TheaterNode(
                id: theaterId,
                name: theaterId.rawValue,
                status: inactiveTheaters.contains(theaterId) ? .inactive : .active,
                regionIds: regionIds.sorted { $0.rawValue < $1.rawValue },
                controllingFaction: controllingFaction
            )
        }

        let map = MapState(
            width: max(1, (tiles.keys.map(\.q).max() ?? 0) + 1),
            height: max(1, (tiles.keys.map(\.r).max() ?? 0) + 1),
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: edges
        )
        let theaterState = TheaterState(theaters: theaters, regionToTheater: regionToTheater)
        return (map, theaterState)
    }

    private static func displayHexes(for specs: [RegionSpec]) -> [RegionId: [HexCoord]] {
        let knownIds = Set(specs.map(\.id))
        var hexes: [RegionId: [HexCoord]] = [:]
        var edgeIndex = 0
        var seenEdges: Set<String> = []

        for spec in specs {
            for neighborId in spec.neighbors where knownIds.contains(neighborId) {
                let key = [spec.id.rawValue, neighborId.rawValue].sorted().joined(separator: "__")
                guard !seenEdges.contains(key) else {
                    continue
                }
                seenEdges.insert(key)
                let baseQ = edgeIndex * 4
                hexes[spec.id, default: []].append(HexCoord(q: baseQ, r: 0))
                hexes[neighborId, default: []].append(HexCoord(q: baseQ + 1, r: 0))
                edgeIndex += 1
            }
        }

        for (index, spec) in specs.enumerated() where hexes[spec.id] == nil {
            hexes[spec.id] = [HexCoord(q: edgeIndex * 4 + index, r: 0)]
        }

        return hexes.mapValues {
            $0.sorted {
                if $0.q == $1.q {
                    return $0.r < $1.r
                }
                return $0.q < $1.q
            }
        }
    }

    static func division(id: String, faction: Faction, coord: HexCoord, strength: Int = 10) -> Division {
        Division(
            id: id,
            name: id,
            faction: faction,
            coord: coord,
            strength: strength,
            components: [DivisionComponent(type: .infantry, weight: 1)]
        )
    }

    static func largeGrid(width: Int, height: Int) -> (map: MapState, theaterState: TheaterState) {
        var specs: [RegionSpec] = []

        for q in 0..<width {
            for r in 0..<height {
                let id = RegionId("r_\(q)_\(r)")
                var neighbors: [RegionId] = []
                if q > 0 { neighbors.append(RegionId("r_\(q - 1)_\(r)")) }
                if q < width - 1 { neighbors.append(RegionId("r_\(q + 1)_\(r)")) }
                if r > 0 { neighbors.append(RegionId("r_\(q)_\(r - 1)")) }
                if r < height - 1 { neighbors.append(RegionId("r_\(q)_\(r + 1)")) }
                specs.append(
                    RegionSpec(
                        id: id,
                        faction: q < width / 2 ? .allies : .germany,
                        theaterId: q < width / 2 ? theaterA : theaterB,
                        neighbors: neighbors
                    )
                )
            }
        }

        return mapAndTheaters(specs: specs)
    }
}
