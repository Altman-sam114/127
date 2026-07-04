import XCTest
@testable import WWIIHexV0

/// v0.2 阿登省份数据完整性测试。
/// 验证 ardennes_v02_regions.json 可加载、通过 validateRegionGraph、路径连通、MapState 挂载正确。
final class ArdennesV02DataTests: XCTestCase {

    private func makeLoader() throws -> (DataLoader, RegionDataSet) {
        let loader = DataLoader()
        let data = try loader.loadArdennesV02Regions()
        return (loader, data)
    }

    // MARK: - 加载 + 解码

    func testRegionDataDecodesSuccessfully() throws {
        XCTAssertNoThrow(try DataLoader().loadArdennesV02Regions())
    }

    func testRegionCountInRange() throws {
        let (_, data) = try makeLoader()
        XCTAssertGreaterThanOrEqual(data.regions.count, 4)
        XCTAssertLessThanOrEqual(data.regions.count, 32)
    }

    func testHexToRegionCoversAllDisplayHexes() throws {
        let (_, data) = try makeLoader()
        let regions = data.toRegions()
        let hexToRegion = data.toHexToRegion()

        for (_, node) in regions {
            for hex in node.displayHexes {
                XCTAssertEqual(hexToRegion[hex], node.id, "displayHex \(hex.q),\(hex.r) not mapped to its region \(node.id.rawValue)")
            }
        }
    }

    // MARK: - 校验

    func testValidateRegionGraphPasses() throws {
        let (loader, data) = try makeLoader()
        XCTAssertNoThrow(try loader.validate(data), "Province data failed region graph validation")
    }

    func testValidateRegionGraphOnMountedMapStateIsEmpty() throws {
        let state = DataLoader().loadInitialGameState()
        let errors = state.map.validateRegionGraph()
        XCTAssertTrue(errors.isEmpty, "Mounted MapState has region errors: \(errors)")
    }

    // MARK: - 邻接 + 路径

    func testAllNeighborsExist() throws {
        let (_, data) = try makeLoader()
        let regions = data.toRegions()
        let validIds = Set(regions.keys)

        for (id, node) in regions {
            for neighbor in node.neighbors {
                XCTAssertTrue(validIds.contains(neighbor), "Region \(id.rawValue) references missing neighbor \(neighbor.rawValue)")
            }
        }
    }

    func testNeighborsBidirectional() throws {
        let (_, data) = try makeLoader()
        let regions = data.toRegions()

        for (id, node) in regions {
            for neighbor in node.neighbors {
                guard let neighborNode = regions[neighbor] else { continue }
                XCTAssertTrue(neighborNode.neighbors.contains(id), "Neighbor \(neighbor.rawValue) of \(id.rawValue) missing back-reference")
            }
        }
    }

    func testRepresentativeHexBelongsToDisplayHexes() throws {
        let (_, data) = try makeLoader()
        let regions = data.toRegions()

        for (id, node) in regions {
            XCTAssertTrue(node.displayHexes.contains(node.representativeHex), "Region \(id.rawValue) representativeHex not in its displayHexes")
        }
    }

    func testDeclaredEdgesAreAdjacent() throws {
        let (_, data) = try makeLoader()
        let map = makeProbeMap(from: data)

        for edge in data.edges {
            XCTAssertTrue(map.areAdjacent(edge.from, edge.to), "Edge \(edge.from.rawValue)-\(edge.to.rawValue) is not adjacent.")
            XCTAssertTrue(map.areAdjacent(edge.to, edge.from), "Edge \(edge.to.rawValue)-\(edge.from.rawValue) is not adjacent.")
        }
    }

    func testRegionGraphIsConnectedFromFirstRegion() throws {
        let (_, data) = try makeLoader()
        let map = makeProbeMap(from: data)
        let regionIds = data.regions.map(\.id).sorted { $0.rawValue < $1.rawValue }
        let start = try XCTUnwrap(regionIds.first)

        for regionId in regionIds.dropFirst() {
            XCTAssertNotNil(map.regionDistance(from: start, to: regionId), "\(start.rawValue) cannot reach \(regionId.rawValue)")
        }
    }

    // MARK: - 补给源 + 目标

    func testSupplySourcesPointToValidRegions() throws {
        let (_, data) = try makeLoader()
        let validIds = Set(data.toRegions().keys)

        for source in data.supplySources {
            XCTAssertTrue(validIds.contains(source.regionId), "Supply source \(source.id) points to missing region \(source.regionId.rawValue)")
        }

        XCTAssertFalse(data.supplySources.isEmpty, "Expected at least one supply source.")
    }

    func testObjectivesPointToValidRegions() throws {
        let (_, data) = try makeLoader()
        let validIds = Set(data.toRegions().keys)

        for objective in data.objectives {
            XCTAssertTrue(validIds.contains(objective.regionId), "Objective \(objective.id) points to missing region \(objective.regionId.rawValue)")
        }

        XCTAssertEqual(Set(data.objectives.map(\.id)).count, data.objectives.count)
    }

    // MARK: - 关键省存在性

    func testMapEditorDefaultTheatersExist() throws {
        let (_, data) = try makeLoader()
        let theaterIds = Set(data.regions.compactMap(\.theaterId))

        XCTAssertEqual(theaterIds, Set([TheaterId("theater_1"), TheaterId("theater_2"), TheaterId("theater_3"), TheaterId("theater_4")]))
    }

    func testDefaultMapInitialTheaterOwnershipAndFrontLineComeFromHexControllers() throws {
        let state = DataLoader().loadInitialGameState()
        let expected: [TheaterId: Faction] = [
            "theater_1": .allies,
            "theater_2": .allies,
            "theater_3": .germany,
            "theater_4": .germany
        ]

        XCTAssertEqual(Set(state.theaterState.theaters.keys), Set(expected.keys))
        for (theaterId, faction) in expected {
            XCTAssertEqual(state.theaterState.theaters[theaterId]?.controllingFaction, faction)
        }

        XCTAssertFalse(state.frontLineState.frontLines.isEmpty)
        XCTAssertTrue(state.frontLineState.frontLines.values.contains { frontLine in
            frontLine.segments.contains { segment in
                guard let left = state.theaterState.regionToTheater[segment.regionA],
                      let right = state.theaterState.regionToTheater[segment.regionB] else {
                    return false
                }
                let leftFaction = state.theaterState.theaters[left]?.controllingFaction
                let rightFaction = state.theaterState.theaters[right]?.controllingFaction
                return leftFaction != nil && rightFaction != nil && leftFaction != rightFaction
            }
        })
    }

    // MARK: - 辅助

    /// 用省份数据构造探针 MapState（只填 province 层，tiles 留空），供邻接/路径测试用。
    private func makeProbeMap(from data: RegionDataSet) -> MapState {
        MapState(
            width: 11,
            height: 9,
            tiles: [:],
            supplySources: [],
            objectives: [],
            regions: data.toRegions(),
            hexToRegion: data.toHexToRegion(),
            regionEdges: data.toRegionEdges()
        )
    }
}
