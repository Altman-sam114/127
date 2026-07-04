import Foundation
@testable import WWIIHexV0

enum WarDeploymentTestFixtures {
    struct Spec {
        let id: RegionId
        let faction: Faction
        let zone: FrontZoneId
        let neighbors: [RegionId]
        let city: Bool
        let factories: Int

        init(
            id: RegionId,
            faction: Faction,
            zone: FrontZoneId,
            neighbors: [RegionId],
            city: Bool = false,
            factories: Int = 0
        ) {
            self.id = id
            self.faction = faction
            self.zone = zone
            self.neighbors = neighbors
            self.city = city
            self.factories = factories
        }
    }

    static let germanyFront = FrontZoneId("germany_front")
    static let germanyDepth = FrontZoneId("germany_depth")
    static let germanyCore = FrontZoneId("germany_core")
    static let franceFront = FrontZoneId("france_front")
    static let sovietFront = FrontZoneId("soviet_front")
    static let sovietDepth = FrontZoneId("soviet_depth")

    static func state(specs: [Spec], divisions: [Division] = []) -> (map: MapState, theaterState: TheaterState, state: WarDeploymentState) {
        var regions: [RegionId: RegionNode] = [:]
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]
        var edges: Set<RegionEdge> = []
        var grouped: [FrontZoneId: [RegionId]] = [:]
        var regionToTheater: [RegionId: TheaterId] = [:]

        let coords = coordinates(for: specs)
        for (index, spec) in specs.enumerated() {
            let coord = coords[spec.id] ?? HexCoord(q: index, r: 0)
            let theaterId = TheaterId(spec.zone.rawValue)
            regions[spec.id] = RegionNode(
                id: spec.id,
                name: spec.id.rawValue,
                owner: spec.faction,
                controller: spec.faction,
                terrain: .plain,
                neighbors: spec.neighbors,
                displayHexes: [coord],
                representativeHex: coord,
                city: spec.city ? CityInfo(name: spec.id.rawValue, victoryPoints: 1) : nil,
                supplyValue: spec.city ? 1 : 0,
                factories: spec.factories,
                coreOf: spec.city || spec.factories > 0 ? [spec.faction] : []
            )
            tiles[coord] = HexTile(coord: coord, baseTerrain: .plain, controller: spec.faction, regionId: spec.id)
            hexToRegion[coord] = spec.id
            edges.formUnion(spec.neighbors.map { RegionEdge(from: spec.id, to: $0) })
            grouped[spec.zone, default: []].append(spec.id)
            regionToTheater[spec.id] = theaterId
        }

        var theaters: [TheaterId: TheaterNode] = [:]
        for (zoneId, regionIds) in grouped {
            let theaterId = TheaterId(zoneId.rawValue)
            let faction = regions[regionIds[0]]!.controller
            theaters[theaterId] = TheaterNode(
                id: theaterId,
                name: zoneId.rawValue,
                status: .active,
                regionIds: regionIds,
                controllingFaction: faction,
                frontWeight: regionIds.count
            )
        }

        let map = MapState(
            width: max(1, specs.count),
            height: 1,
            tiles: tiles,
            supplySources: [],
            objectives: [],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: edges
        )
        let theaterState = TheaterState(theaters: theaters, regionToTheater: regionToTheater)
        let state = WarDeploymentManager().makeInitialState(
            map: map,
            theaterState: theaterState,
            divisions: divisions,
            turn: 1
        )
        return (map, theaterState, state)
    }

    private static func coordinates(for specs: [Spec]) -> [RegionId: HexCoord] {
        let ids = Set(specs.map(\.id))

        if ids == Set(["g_north", "g_center", "g_south", "s_north", "s_center", "s_south", "s_reserve"]) {
            return [
                "g_north": HexCoord(q: 0, r: 0),
                "s_north": HexCoord(q: 1, r: 0),
                "g_center": HexCoord(q: 0, r: 2),
                "s_center": HexCoord(q: 1, r: 2),
                "g_south": HexCoord(q: 0, r: 4),
                "s_south": HexCoord(q: 1, r: 4),
                "s_reserve": HexCoord(q: 3, r: 2)
            ]
        }

        if ids == Set(["pincer_n", "pincer_s", "pocket"]) {
            return [
                "pincer_n": HexCoord(q: 0, r: 0),
                "pocket": HexCoord(q: 1, r: 0),
                "pincer_s": HexCoord(q: 1, r: -1)
            ]
        }

        if ids == Set(["rhein", "berlin", "ardennes", "sedan", "paris"]) {
            return [
                "rhein": HexCoord(q: 0, r: 0),
                "berlin": HexCoord(q: 0, r: -1),
                "ardennes": HexCoord(q: 1, r: 0),
                "sedan": HexCoord(q: 2, r: 0),
                "paris": HexCoord(q: 3, r: 0)
            ]
        }

        return Dictionary(uniqueKeysWithValues: specs.enumerated().map {
            ($0.element.id, HexCoord(q: $0.offset, r: 0))
        })
    }

    static func invasionFrance(divisions: [Division] = []) -> (map: MapState, theaterState: TheaterState, state: WarDeploymentState) {
        state(
            specs: [
                .init(id: "rhein", faction: .germany, zone: germanyDepth, neighbors: ["ardennes", "berlin"]),
                .init(id: "berlin", faction: .germany, zone: germanyCore, neighbors: ["rhein"], city: true, factories: 3),
                .init(id: "ardennes", faction: .germany, zone: germanyFront, neighbors: ["rhein", "sedan"]),
                .init(id: "sedan", faction: .allies, zone: franceFront, neighbors: ["ardennes", "paris"]),
                .init(id: "paris", faction: .allies, zone: franceFront, neighbors: ["sedan"], city: true, factories: 4)
            ],
            divisions: divisions
        )
    }

    static func frontCity(divisions: [Division] = []) -> (map: MapState, theaterState: TheaterState, state: WarDeploymentState) {
        state(
            specs: [
                .init(id: "rhein", faction: .germany, zone: germanyDepth, neighbors: ["ardennes"]),
                .init(id: "ardennes", faction: .germany, zone: germanyFront, neighbors: ["rhein", "sedan"], city: true, factories: 2),
                .init(id: "sedan", faction: .allies, zone: franceFront, neighbors: ["ardennes"])
            ],
            divisions: divisions
        )
    }

    static func easternFront(divisions: [Division] = []) -> (map: MapState, theaterState: TheaterState, state: WarDeploymentState) {
        state(
            specs: [
                .init(id: "g_north", faction: .germany, zone: germanyFront, neighbors: ["s_north"]),
                .init(id: "g_center", faction: .germany, zone: germanyFront, neighbors: ["s_center"]),
                .init(id: "g_south", faction: .germany, zone: germanyFront, neighbors: ["s_south"]),
                .init(id: "s_north", faction: .allies, zone: sovietFront, neighbors: ["g_north", "s_reserve"]),
                .init(id: "s_center", faction: .allies, zone: sovietFront, neighbors: ["g_center", "s_reserve"]),
                .init(id: "s_south", faction: .allies, zone: sovietFront, neighbors: ["g_south", "s_reserve"]),
                .init(id: "s_reserve", faction: .allies, zone: sovietDepth, neighbors: ["s_north", "s_center", "s_south"])
            ],
            divisions: divisions
        )
    }

    static func localBreakthrough(divisions: [Division] = []) -> (map: MapState, theaterState: TheaterState, state: WarDeploymentState) {
        state(
            specs: [
                .init(id: "pincer_n", faction: .germany, zone: germanyFront, neighbors: ["pocket"]),
                .init(id: "pincer_s", faction: .germany, zone: germanyFront, neighbors: ["pocket"]),
                .init(id: "pocket", faction: .allies, zone: franceFront, neighbors: ["pincer_n", "pincer_s"])
            ],
            divisions: divisions
        )
    }

    static func division(id: String, faction: Faction, regionIndex: Int) -> Division {
        return Division(
            id: id,
            name: id,
            faction: faction,
            coord: HexCoord(q: regionIndex, r: 0),
            components: [DivisionComponent(type: .infantry, weight: 1)]
        )
    }
}
