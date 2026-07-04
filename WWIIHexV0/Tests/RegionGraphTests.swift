import XCTest
@testable import WWIIHexV0

/// v0.2 Agent 1 任务 1.5：覆盖 RegionGraph 查询 + MapState province 层 + validateRegionGraph。
/// 不依赖 JSON（Agent 2 才填数据），全部 in-code fixture。
final class RegionGraphTests: XCTestCase {

    // MARK: - RegionId 编解码

    func testRegionIdCodableRoundTrip() throws {
        let original = RegionId(rawValue: "bastogne")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RegionId.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testRegionIdStringLiteralAndValueInit() {
        let a: RegionId = "bastogne"
        let b = RegionId("bastogne")
        let c = RegionId(rawValue: "bastogne")
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, c)
    }

    // MARK: - RegionGraph 查询

    func testNeighborsReturnsAdjacentRegions() {
        let graph = Self.twoRegionGraph()
        XCTAssertEqual(Set(graph.neighbors(of: "bastogne")), ["bastogne_fortress"])
        XCTAssertEqual(Set(graph.neighbors(of: "bastogne_fortress")), ["bastogne"])
    }

    func testNeighborsOfUnknownRegionIsEmpty() {
        let graph = Self.twoRegionGraph()
        XCTAssertTrue(graph.neighbors(of: "nowhere").isEmpty)
    }

    func testAreAdjacentForAdjacentAndNonAdjacent() {
        let graph = Self.twoRegionGraph()
        XCTAssertTrue(graph.areAdjacent("bastogne", "bastogne_fortress"))
        XCTAssertTrue(graph.areAdjacent("bastogne_fortress", "bastogne")) // 对称
        XCTAssertFalse(graph.areAdjacent("bastogne", "bastogne"))
        XCTAssertFalse(graph.areAdjacent("bastogne", "nowhere"))
    }

    func testEdgeBetweenReturnsEdgeWhenPresent() {
        let edge = RegionEdge(from: "bastogne", to: "bastogne_fortress", hasRoad: true)
        let graph = RegionGraph(
            regions: Self.twoRegionNodes(),
            edges: [edge]
        )
        let found = graph.edgeBetween("bastogne", "bastogne_fortress")
        XCTAssertNotNil(found)
        XCTAssertTrue(found?.hasRoad ?? false)
        // 对称查询
        XCTAssertEqual(graph.edgeBetween("bastogne_fortress", "bastogne"), found)
        XCTAssertNil(graph.edgeBetween("bastogne", "nowhere"))
    }

    func testRepresentativeHexBelongsToRegion() {
        let graph = Self.twoRegionGraph()
        XCTAssertEqual(graph.representativeHex(for: "bastogne"), HexCoord(q: 5, r: 4))
        XCTAssertNil(graph.representativeHex(for: "nowhere"))
    }

    func testDistanceBetweenConnectedAndDisconnected() {
        let graph = Self.chainGraph() // a - b - c
        XCTAssertEqual(graph.distance(from: "a", to: "a"), 0)
        XCTAssertEqual(graph.distance(from: "a", to: "b"), 1)
        XCTAssertEqual(graph.distance(from: "a", to: "c"), 2)
        XCTAssertNil(graph.distance(from: "a", to: "z")) // z 不存在
    }

    // MARK: - MapState province 层

    func testMapStateRegionForHexPrefersHexToRegionMapping() {
        let map = Self.mapWithRegions()
        // hexToRegion 映射优先
        XCTAssertEqual(map.region(for: HexCoord(q: 5, r: 4)), "bastogne")
        // 无映射时 fallback tile.regionId
        XCTAssertEqual(map.region(for: HexCoord(q: 5, r: 5)), "bastogne")
        // 都无 → nil
        XCTAssertNil(map.region(for: HexCoord(q: 0, r: 0)))
    }

    func testMapStateRegionDistanceUsesGraph() {
        let map = Self.chainMap() // a - b - c
        XCTAssertEqual(map.regionDistance(from: "a", to: "c"), 2)
        XCTAssertNil(map.regionDistance(from: "a", to: "z"))
    }

    // MARK: - validateRegionGraph：合法图无错误

    func testValidatePassesForValidGraph() {
        let map = Self.mapWithRegions()
        XCTAssertTrue(map.validateRegionGraph().isEmpty)
    }

    func testValidatePassesForEmptyProvinces() {
        // v0/v0.1 默认状态：无 province，合法
        let map = MapState.ardennesV0()
        XCTAssertTrue(map.validateRegionGraph().isEmpty)
    }

    // MARK: - validateRegionGraph：各类错误

    func testValidateDetectsMissingNeighbor() {
        var nodes = Self.twoRegionNodes()
        // bastogne 引用不存在的 neighbor
        nodes["bastogne"]!.neighbors = ["bastogne_fortress", "nowhere"]
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes, hexToRegion: [:], regionEdges: []
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(.neighborNotFound(regionId: "bastogne", missingNeighbor: "nowhere")))
    }

    func testValidateDetectsNonBidirectionalNeighbor() {
        var nodes = Self.twoRegionNodes()
        // bastogne 列 fortress，fortress 不列 bastogne
        nodes["bastogne_fortress"]!.neighbors = []
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes, hexToRegion: [:], regionEdges: []
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(.neighborNotBidirectional(from: "bastogne", to: "bastogne_fortress")))
    }

    func testValidateDetectsEmptyDisplayHexes() {
        var nodes = Self.twoRegionNodes()
        nodes["bastogne"]!.displayHexes = []
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes, hexToRegion: [:], regionEdges: []
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(.emptyDisplayHexes(regionId: "bastogne")))
    }

    func testValidateDetectsRepresentativeHexNotInDisplayHexes() {
        var nodes = Self.twoRegionNodes()
        nodes["bastogne"]!.representativeHex = HexCoord(q: 99, r: 99)
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes, hexToRegion: [:], regionEdges: []
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(.representativeHexNotInDisplayHexes(regionId: "bastogne")))
    }

    func testValidateDetectsHexToRegionPointsToMissingRegion() {
        let nodes = Self.twoRegionNodes()
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes,
            hexToRegion: [HexCoord(q: 1, r: 1): "ghost"],
            regionEdges: []
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(.hexToRegionPointsToMissingRegion(hex: "1,1", regionId: "ghost")))
    }

    func testValidateDetectsOverlappingDisplayHexes() {
        var nodes = Self.twoRegionNodes()
        // 两省都声称拥有 (5,4)
        nodes["bastogne_fortress"]!.displayHexes = [HexCoord(q: 4, r: 4), HexCoord(q: 5, r: 4)]
        nodes["bastogne_fortress"]!.representativeHex = HexCoord(q: 4, r: 4)
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes, hexToRegion: [:], regionEdges: []
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(where: { error in
            if case .displayHexesOverlap(let hex, _, _) = error {
                return hex == "5,4"
            }
            return false
        }))
    }

    func testValidateDetectsEdgeEndpointNotFound() {
        let nodes = Self.twoRegionNodes()
        let badEdge = RegionEdge(from: "bastogne", to: "ghost")
        let map = MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: nodes, hexToRegion: [:], regionEdges: [badEdge]
        )
        let errors = map.validateRegionGraph()
        XCTAssertTrue(errors.contains(.edgeEndpointNotFound(regionId: "ghost")))
    }

    // MARK: - Fixtures

    /// 两个相邻省份：bastogne (5,4) - bastogne_fortress (4,4)。
    private static func twoRegionGraph() -> RegionGraph {
        RegionGraph(regions: twoRegionNodes(), edges: [])
    }

    private static func twoRegionNodes() -> [RegionId: RegionNode] {
        [
            "bastogne": RegionNode(
                id: "bastogne", name: "Bastogne", owner: .allies, controller: .allies,
                terrain: .city,
                neighbors: ["bastogne_fortress"],
                displayHexes: [HexCoord(q: 5, r: 4), HexCoord(q: 5, r: 5)],
                representativeHex: HexCoord(q: 5, r: 4),
                city: CityInfo(name: "Bastogne", victoryPoints: 5)
            ),
            "bastogne_fortress": RegionNode(
                id: "bastogne_fortress", name: "Bastogne Fortress", owner: .allies, controller: .allies,
                terrain: .fortress,
                neighbors: ["bastogne"],
                displayHexes: [HexCoord(q: 4, r: 4)],
                representativeHex: HexCoord(q: 4, r: 4),
                city: CityInfo(name: "Bastogne Fortress", victoryPoints: 3)
            )
        ]
    }

    /// 三省链 a - b - c，供 distance 测试。
    private static func chainGraph() -> RegionGraph {
        RegionGraph(regions: chainNodes(), edges: [])
    }

    private static func chainNodes() -> [RegionId: RegionNode] {
        [
            "a": simpleRegion("a", neighbors: ["b"], hex: HexCoord(q: 0, r: 0)),
            "b": simpleRegion("b", neighbors: ["a", "c"], hex: HexCoord(q: 1, r: 0)),
            "c": simpleRegion("c", neighbors: ["b"], hex: HexCoord(q: 2, r: 0))
        ]
    }

    private static func simpleRegion(_ id: RegionId, neighbors: [RegionId], hex: HexCoord) -> RegionNode {
        RegionNode(
            id: id, name: id.rawValue, owner: .allies, controller: .allies,
            terrain: .plain, neighbors: neighbors,
            displayHexes: [hex], representativeHex: hex
        )
    }

    /// 带 province + hexToRegion + tile.regionId 的 MapState。
    private static func mapWithRegions() -> MapState {
        var tiles: [HexCoord: HexTile] = [:]
        // (5,5) 不在 hexToRegion，但 tile 带 regionId，测 fallback
        tiles[HexCoord(q: 5, r: 5)] = HexTile(
            coord: HexCoord(q: 5, r: 5), baseTerrain: .plain, regionId: "bastogne"
        )
        return MapState(
            width: 11, height: 9, tiles: tiles, supplySources: [], objectives: [],
            regions: twoRegionNodes(),
            hexToRegion: [HexCoord(q: 5, r: 4): "bastogne"],
            regionEdges: []
        )
    }

    private static func chainMap() -> MapState {
        MapState(
            width: 11, height: 9, tiles: [:], supplySources: [], objectives: [],
            regions: chainNodes(), hexToRegion: [:], regionEdges: []
        )
    }
}
