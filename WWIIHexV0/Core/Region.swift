import Foundation

// MARK: - RegionId

/// 规则层省份/区块标识。RawRepresentable<String>，可 Codable / Hashable / Equatable。
/// v0.2：province 是叠加的战略层，hex（HexCoord）仍是战术层权威坐标。
struct RegionId: Hashable, Codable, Equatable, RawRepresentable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    init(_ value: String) {
        self.rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - 辅助值类型

/// 省份内城市/要塞的战略信息。
/// v0.2 只挂数据，不实现经济逻辑（留 v1.0）。
struct CityInfo: Codable, Equatable {
    var name: String
    var victoryPoints: Int
    var isCapital: Bool

    init(name: String, victoryPoints: Int = 0, isCapital: Bool = false) {
        self.name = name
        self.victoryPoints = max(0, victoryPoints)
        self.isCapital = isCapital
    }
}

/// 省份资源产出。v0.2 仅记录，不参与生产计算。
struct ResourceAmount: Codable, Equatable {
    var type: ResourceType
    var amount: Int

    init(type: ResourceType, amount: Int = 0) {
        self.type = type
        self.amount = max(0, amount)
    }
}

enum ResourceType: String, Codable, Equatable, CaseIterable {
    case steel
    case oil
    case aluminum
    case rubber
    case tungsten
    case chromium
}

/// 占领区状态。v0.2 占位，抵抗/顺从逻辑留 v1.0。
struct OccupationState: Codable, Equatable {
    var resistance: Int
    var compliance: Int

    init(resistance: Int = 0, compliance: Int = 0) {
        self.resistance = max(0, min(100, resistance))
        self.compliance = max(0, min(100, compliance))
    }
}

// MARK: - RegionNode

/// 省份/区块节点。规则层战略单位。
/// controller 当前控制方（战斗/占领改变），owner 原始归属（核心区判定用）。
/// displayHexes 是该省份在战术层覆盖的 hex，representativeHex 是单位/图标的默认显示格。
struct RegionNode: Codable, Equatable, Identifiable {
    let id: RegionId
    var name: String
    var owner: Faction
    var controller: Faction
    var terrain: BaseTerrain
    var neighbors: [RegionId]
    var displayHexes: [HexCoord]
    var representativeHex: HexCoord
    var city: CityInfo?
    var infrastructure: Int
    var supplyValue: Int
    var factories: Int
    var resources: [ResourceAmount]
    var coreOf: [Faction]
    var occupationState: OccupationState?
    var isPassable: Bool

    init(
        id: RegionId,
        name: String,
        owner: Faction,
        controller: Faction,
        terrain: BaseTerrain,
        neighbors: [RegionId],
        displayHexes: [HexCoord],
        representativeHex: HexCoord,
        city: CityInfo? = nil,
        infrastructure: Int = 0,
        supplyValue: Int = 0,
        factories: Int = 0,
        resources: [ResourceAmount] = [],
        coreOf: [Faction] = [],
        occupationState: OccupationState? = nil,
        isPassable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.controller = controller
        self.terrain = terrain
        self.neighbors = neighbors
        self.displayHexes = displayHexes
        self.representativeHex = representativeHex
        self.city = city
        self.infrastructure = max(0, infrastructure)
        self.supplyValue = max(0, supplyValue)
        self.factories = max(0, factories)
        self.resources = resources
        self.coreOf = coreOf
        self.occupationState = occupationState
        self.isPassable = isPassable
    }
}

// MARK: - RegionEdge

/// 省份间相邻边。描述两省之间的移动/补给通道属性。
/// 与 RegionNode.neighbors 对应：neighbors 列 id，edge 存细节。
struct RegionEdge: Codable, Equatable, Hashable {
    let from: RegionId
    let to: RegionId
    var hasRoad: Bool
    var hasRiverCrossing: Bool
    var movementCostModifier: Int

    init(
        from: RegionId,
        to: RegionId,
        hasRoad: Bool = false,
        hasRiverCrossing: Bool = false,
        movementCostModifier: Int = 0
    ) {
        self.from = from
        self.to = to
        self.hasRoad = hasRoad
        self.hasRiverCrossing = hasRiverCrossing
        self.movementCostModifier = movementCostModifier
    }

    /// 边的对称键，from/to 顺序无关。
    static func key(_ a: RegionId, _ b: RegionId) -> RegionEdgeKey {
        a.rawValue < b.rawValue
            ? RegionEdgeKey(lesser: a, greater: b)
            : RegionEdgeKey(lesser: b, greater: a)
    }

    var symmetricKey: RegionEdgeKey {
        Self.key(from, to)
    }
}

/// 省份边的对称键。from/to 较小者放 lesser，保证双向一致查找。
struct RegionEdgeKey: Hashable, Equatable {
    let lesser: RegionId
    let greater: RegionId
}

// MARK: - RegionGraph

/// 省份图。regions 是权威节点表，edges 是相邻边集合。
/// v0.2：作为 MapState 的叠加层存在，不替换 HexCoord 规则。
struct RegionGraph: Codable, Equatable {
    var regions: [RegionId: RegionNode]
    var edges: Set<RegionEdge>

    init(regions: [RegionId: RegionNode] = [:], edges: Set<RegionEdge> = []) {
        self.regions = regions
        self.edges = edges
    }

    /// 空图。MapState 无 province 数据时用（保持现有行为）。
    static var empty: RegionGraph {
        RegionGraph(regions: [:], edges: [])
    }

    var isEmpty: Bool {
        regions.isEmpty
    }

    func region(_ id: RegionId) -> RegionNode? {
        regions[id]
    }

    func neighbors(of regionId: RegionId) -> [RegionId] {
        regions[regionId]?.neighbors ?? []
    }

    func areAdjacent(_ a: RegionId, _ b: RegionId) -> Bool {
        guard regions[a] != nil, regions[b] != nil else { return false }
        if edges.isEmpty {
            // 无显式 edge 时退化为 neighbors 判断
            return neighbors(of: a).contains(b)
        }
        return edges.contains { $0.symmetricKey == RegionEdge.key(a, b) }
    }

    func edgeBetween(_ a: RegionId, _ b: RegionId) -> RegionEdge? {
        let key = RegionEdge.key(a, b)
        return edges.first { $0.symmetricKey == key }
    }

    func representativeHex(for regionId: RegionId) -> HexCoord? {
        regions[regionId]?.representativeHex
    }

    /// 两个省份之间的图距离（BFS，跳数）。不连通返回 nil。
    func distance(from start: RegionId, to goal: RegionId) -> Int? {
        guard start == goal || regions[start] != nil,
              regions[goal] != nil else {
            return nil
        }
        if start == goal { return 0 }

        var visited: Set<RegionId> = [start]
        var frontier: [(id: RegionId, depth: Int)] = [(start, 0)]

        while !frontier.isEmpty {
            let current = frontier.removeFirst()
            for neighbor in neighbors(of: current.id) where !visited.contains(neighbor) {
                if neighbor == goal { return current.depth + 1 }
                visited.insert(neighbor)
                frontier.append((neighbor, current.depth + 1))
            }
        }
        return nil
    }

    /// 校验省份图自身一致性（不含 hexToRegion，那需 MapState 级校验）。
    /// 检查：region 唯一（由 Dictionary 保证，跳过）、neighbor 引用存在、neighbor 双向一致、
    /// displayHexes 非空、representativeHex 属于 displayHexes、edges 端点存在、edges 与 neighbors 一致。
    func validate() -> [RegionValidationError] {
        var errors: [RegionValidationError] = []

        for (id, node) in regions {
            if node.id != id {
                errors.append(.idMismatch(dictionaryKey: id.rawValue, nodeId: node.id.rawValue))
            }

            if node.displayHexes.isEmpty {
                errors.append(.emptyDisplayHexes(regionId: id.rawValue))
            }

            if !node.displayHexes.contains(node.representativeHex) {
                errors.append(.representativeHexNotInDisplayHexes(regionId: id.rawValue))
            }

            for neighborId in node.neighbors {
                if regions[neighborId] == nil {
                    errors.append(.neighborNotFound(regionId: id.rawValue, missingNeighbor: neighborId.rawValue))
                } else if !regions[neighborId]!.neighbors.contains(id) {
                    errors.append(.neighborNotBidirectional(from: id.rawValue, to: neighborId.rawValue))
                }
            }
        }

        // edges 端点存在 + 与 neighbors 一致
        for edge in edges {
            if regions[edge.from] == nil {
                errors.append(.edgeEndpointNotFound(regionId: edge.from.rawValue))
            }
            if regions[edge.to] == nil {
                errors.append(.edgeEndpointNotFound(regionId: edge.to.rawValue))
            }
            // edge 应对应 neighbors（双向）
            if let from = regions[edge.from], let to = regions[edge.to] {
                if !from.neighbors.contains(edge.to) || !to.neighbors.contains(edge.from) {
                    errors.append(.edgeNotInNeighbors(from: edge.from.rawValue, to: edge.to.rawValue))
                }
            }
        }

        return errors
    }
}

/// 省份图校验错误。描述性 enum，便于测试断言 + 数据加载报错。
enum RegionValidationError: Error, Equatable, CustomStringConvertible {
    case idMismatch(dictionaryKey: String, nodeId: String)
    case emptyDisplayHexes(regionId: String)
    case representativeHexNotInDisplayHexes(regionId: String)
    case neighborNotFound(regionId: String, missingNeighbor: String)
    case neighborNotBidirectional(from: String, to: String)
    case edgeEndpointNotFound(regionId: String)
    case edgeNotInNeighbors(from: String, to: String)
    case hexToRegionPointsToMissingRegion(hex: String, regionId: String)
    case displayHexesOverlap(hex: String, regionA: String, regionB: String)

    var description: String {
        switch self {
        case .idMismatch(let key, let node):
            return "Region dictionary key \(key) != node id \(node)."
        case .emptyDisplayHexes(let id):
            return "Region \(id) has empty displayHexes."
        case .representativeHexNotInDisplayHexes(let id):
            return "Region \(id) representativeHex not in its displayHexes."
        case .neighborNotFound(let id, let missing):
            return "Region \(id) references missing neighbor \(missing)."
        case .neighborNotBidirectional(let from, let to):
            return "Neighbor \(to) of \(from) is not bidirectional (missing back-reference)."
        case .edgeEndpointNotFound(let id):
            return "Edge references missing region \(id)."
        case .edgeNotInNeighbors(let from, let to):
            return "Edge \(from)-\(to) not reflected in neighbors lists."
        case .hexToRegionPointsToMissingRegion(let hex, let id):
            return "hexToRegion[\(hex)] points to missing region \(id)."
        case .displayHexesOverlap(let hex, let a, let b):
            return "Hex \(hex) belongs to both \(a) and \(b)."
        }
    }
}
