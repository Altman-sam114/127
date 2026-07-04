import XCTest
@testable import WWIIHexV0

enum RegionRuleTestFixtures {
    static func nodes() -> [RegionId: RegionNode] {
        [
            "allied_depot": RegionNode(
                id: "allied_depot",
                name: "Allied Depot",
                owner: .allies,
                controller: .allies,
                terrain: .city,
                neighbors: ["forest_road"],
                displayHexes: [HexCoord(q: 0, r: 0)],
                representativeHex: HexCoord(q: 0, r: 0),
                city: CityInfo(name: "Allied Depot"),
                supplyValue: 5
            ),
            "forest_road": RegionNode(
                id: "forest_road",
                name: "Forest Road",
                owner: .allies,
                controller: .allies,
                terrain: .forest,
                neighbors: ["allied_depot", "bastogne"],
                displayHexes: [HexCoord(q: 1, r: 0)],
                representativeHex: HexCoord(q: 1, r: 0)
            ),
            "bastogne": RegionNode(
                id: "bastogne",
                name: "Bastogne",
                owner: .allies,
                controller: .allies,
                terrain: .city,
                neighbors: ["forest_road", "st_vith"],
                displayHexes: [HexCoord(q: 2, r: 0)],
                representativeHex: HexCoord(q: 2, r: 0),
                city: CityInfo(name: "Bastogne", victoryPoints: 5)
            ),
            "st_vith": RegionNode(
                id: "st_vith",
                name: "St. Vith",
                owner: .allies,
                controller: .allies,
                terrain: .city,
                neighbors: ["bastogne", "german_depot"],
                displayHexes: [HexCoord(q: 3, r: 0)],
                representativeHex: HexCoord(q: 3, r: 0),
                city: CityInfo(name: "St. Vith", victoryPoints: 3)
            ),
            "german_depot": RegionNode(
                id: "german_depot",
                name: "German Depot",
                owner: .germany,
                controller: .germany,
                terrain: .city,
                neighbors: ["st_vith"],
                displayHexes: [HexCoord(q: 4, r: 0)],
                representativeHex: HexCoord(q: 4, r: 0),
                city: CityInfo(name: "German Depot"),
                supplyValue: 5
            )
        ]
    }

    static func map(
        regions: [RegionId: RegionNode] = nodes(),
        edges: Set<RegionEdge> = [
            RegionEdge(from: "allied_depot", to: "forest_road", hasRoad: true),
            RegionEdge(from: "forest_road", to: "bastogne", hasRoad: true),
            RegionEdge(from: "bastogne", to: "st_vith"),
            RegionEdge(from: "st_vith", to: "german_depot", hasRoad: true)
        ]
    ) -> MapState {
        var tiles: [HexCoord: HexTile] = [:]
        var hexToRegion: [HexCoord: RegionId] = [:]

        for (regionId, region) in regions {
            for hex in region.displayHexes {
                tiles[hex] = HexTile(
                    coord: hex,
                    baseTerrain: region.terrain,
                    controller: region.controller,
                    cityName: region.city?.name,
                    regionId: regionId
                )
                hexToRegion[hex] = regionId
            }
        }

        return MapState(
            width: 5,
            height: 1,
            tiles: tiles,
            supplySources: [
                SupplySource(id: "allied_supply", faction: .allies, coord: HexCoord(q: 0, r: 0)),
                SupplySource(id: "german_supply", faction: .germany, coord: HexCoord(q: 4, r: 0))
            ],
            objectives: [
                Objective(id: "bastogne", name: "Bastogne", coord: HexCoord(q: 2, r: 0), type: .city),
                Objective(id: "st_vith", name: "St. Vith", coord: HexCoord(q: 3, r: 0), type: .city)
            ],
            regions: regions,
            hexToRegion: hexToRegion,
            regionEdges: edges
        )
    }

    static func state(activeFaction: Faction = .allies, divisions: [Division]) -> GameState {
        GameState(
            scenarioId: "region_rules_test",
            turn: 1,
            maxTurns: 8,
            activeFaction: activeFaction,
            phase: activeFaction == .germany ? .germanAI : .alliedPlayer,
            map: map(),
            divisions: divisions,
            victoryState: .ongoing,
            selectedUnitSummary: nil,
            eventLog: []
        )
    }

    static func division(id: String, faction: Faction, coord: HexCoord) -> Division {
        Division(
            id: id,
            name: id,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .west : .east,
            components: [
                DivisionComponent(type: .infantry, weight: 1.0)
            ]
        )
    }
}

