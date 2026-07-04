import Foundation

/// v0.2 省份图数据集。从 ardennes_v02_regions.json 加载，映射到 Core 的 RegionGraph/MapState 叠加层。
/// 不依赖 ScenarioDefinition，独立 Codable 模型，与现有 hex 数据并存。
struct RegionDataSet: Codable, Equatable {
    let schemaVersion: Int
    let scenarioId: String
    let displayName: String
    let hexToRegion: [String: RegionId]
    let regions: [RegionNodeDefinition]
    let edges: [RegionEdgeDefinition]
    let supplySources: [RegionSupplySourceDefinition]
    let objectives: [RegionObjectiveDefinition]
}

/// JSON 中的省份定义。映射到 Core.RegionNode。
/// controller 省略时回退 owner；owner/controller 为 null 时映射 nil（中立）。
struct RegionNodeDefinition: Codable, Equatable {
    let id: RegionId
    let name: String
    let owner: Faction?
    let controller: Faction?
    let theaterId: TheaterId?
    let assignedGeneralId: String?
    let terrain: BaseTerrain
    let neighbors: [RegionId]
    let displayHexes: [HexCoord]
    let representativeHex: HexCoord
    let city: CityInfoDefinition?
    let infrastructure: Int
    let supplyValue: Int
    let factories: Int
    let resources: [ResourceAmountDefinition]
    let coreOf: [Faction]
    let occupationState: OccupationStateDefinition?
    let isPassable: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, owner, controller, theaterId, terrain, neighbors, displayHexes
        case assignedGeneralId
        case representativeHex, city, infrastructure, supplyValue, factories
        case resources, coreOf, occupationState, isPassable
    }

    init(
        id: RegionId,
        name: String,
        owner: Faction?,
        controller: Faction?,
        theaterId: TheaterId? = nil,
        assignedGeneralId: String? = nil,
        terrain: BaseTerrain,
        neighbors: [RegionId],
        displayHexes: [HexCoord],
        representativeHex: HexCoord,
        city: CityInfoDefinition? = nil,
        infrastructure: Int = 0,
        supplyValue: Int = 0,
        factories: Int = 0,
        resources: [ResourceAmountDefinition] = [],
        coreOf: [Faction] = [],
        occupationState: OccupationStateDefinition? = nil,
        isPassable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.owner = owner
        self.controller = controller
        self.theaterId = theaterId
        self.assignedGeneralId = assignedGeneralId
        self.terrain = terrain
        self.neighbors = neighbors
        self.displayHexes = displayHexes
        self.representativeHex = representativeHex
        self.city = city
        self.infrastructure = infrastructure
        self.supplyValue = supplyValue
        self.factories = factories
        self.resources = resources
        self.coreOf = coreOf
        self.occupationState = occupationState
        self.isPassable = isPassable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(RegionId.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.owner = try c.decodeIfPresent(Faction.self, forKey: .owner)
        self.controller = try c.decodeIfPresent(Faction.self, forKey: .controller)
        self.theaterId = try c.decodeIfPresent(TheaterId.self, forKey: .theaterId)
        self.assignedGeneralId = try c.decodeIfPresent(String.self, forKey: .assignedGeneralId)
        self.terrain = try c.decode(BaseTerrain.self, forKey: .terrain)
        self.neighbors = try c.decode([RegionId].self, forKey: .neighbors)
        self.displayHexes = try c.decode([HexCoord].self, forKey: .displayHexes)
        self.representativeHex = try c.decode(HexCoord.self, forKey: .representativeHex)
        self.city = try c.decodeIfPresent(CityInfoDefinition.self, forKey: .city)
        self.infrastructure = try c.decodeIfPresent(Int.self, forKey: .infrastructure) ?? 0
        self.supplyValue = try c.decodeIfPresent(Int.self, forKey: .supplyValue) ?? 0
        self.factories = try c.decodeIfPresent(Int.self, forKey: .factories) ?? 0
        self.resources = try c.decodeIfPresent([ResourceAmountDefinition].self, forKey: .resources) ?? []
        self.coreOf = try c.decodeIfPresent([Faction].self, forKey: .coreOf) ?? []
        self.occupationState = try c.decodeIfPresent(OccupationStateDefinition.self, forKey: .occupationState)
        self.isPassable = try c.decodeIfPresent(Bool.self, forKey: .isPassable) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(owner, forKey: .owner)
        try c.encodeIfPresent(controller, forKey: .controller)
        try c.encodeIfPresent(theaterId, forKey: .theaterId)
        try c.encodeIfPresent(assignedGeneralId, forKey: .assignedGeneralId)
        try c.encode(terrain, forKey: .terrain)
        try c.encode(neighbors, forKey: .neighbors)
        try c.encode(displayHexes, forKey: .displayHexes)
        try c.encode(representativeHex, forKey: .representativeHex)
        try c.encodeIfPresent(city, forKey: .city)
        try c.encode(infrastructure, forKey: .infrastructure)
        try c.encode(supplyValue, forKey: .supplyValue)
        try c.encode(factories, forKey: .factories)
        try c.encode(resources, forKey: .resources)
        try c.encode(coreOf, forKey: .coreOf)
        try c.encodeIfPresent(occupationState, forKey: .occupationState)
        try c.encode(isPassable, forKey: .isPassable)
    }
}

struct CityInfoDefinition: Codable, Equatable {
    let name: String
    let victoryPoints: Int
    let isCapital: Bool

    init(name: String, victoryPoints: Int = 0, isCapital: Bool = false) {
        self.name = name
        self.victoryPoints = victoryPoints
        self.isCapital = isCapital
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.victoryPoints = try c.decodeIfPresent(Int.self, forKey: .victoryPoints) ?? 0
        self.isCapital = try c.decodeIfPresent(Bool.self, forKey: .isCapital) ?? false
    }

    func toCityInfo() -> CityInfo {
        CityInfo(name: name, victoryPoints: victoryPoints, isCapital: isCapital)
    }
}

struct ResourceAmountDefinition: Codable, Equatable {
    let type: ResourceType
    let amount: Int

    init(type: ResourceType, amount: Int = 0) {
        self.type = type
        self.amount = amount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(ResourceType.self, forKey: .type)
        self.amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
    }

    func toResourceAmount() -> ResourceAmount {
        ResourceAmount(type: type, amount: amount)
    }
}

struct OccupationStateDefinition: Codable, Equatable {
    let resistance: Int
    let compliance: Int

    init(resistance: Int = 0, compliance: Int = 0) {
        self.resistance = resistance
        self.compliance = compliance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.resistance = try c.decodeIfPresent(Int.self, forKey: .resistance) ?? 0
        self.compliance = try c.decodeIfPresent(Int.self, forKey: .compliance) ?? 0
    }

    func toOccupationState() -> OccupationState {
        OccupationState(resistance: resistance, compliance: compliance)
    }
}

struct RegionEdgeDefinition: Codable, Equatable {
    let from: RegionId
    let to: RegionId
    let hasRoad: Bool
    let hasRiverCrossing: Bool
    let movementCostModifier: Int

    init(from: RegionId, to: RegionId, hasRoad: Bool = false, hasRiverCrossing: Bool = false, movementCostModifier: Int = 0) {
        self.from = from
        self.to = to
        self.hasRoad = hasRoad
        self.hasRiverCrossing = hasRiverCrossing
        self.movementCostModifier = movementCostModifier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try c.decode(RegionId.self, forKey: .from)
        self.to = try c.decode(RegionId.self, forKey: .to)
        self.hasRoad = try c.decodeIfPresent(Bool.self, forKey: .hasRoad) ?? false
        self.hasRiverCrossing = try c.decodeIfPresent(Bool.self, forKey: .hasRiverCrossing) ?? false
        self.movementCostModifier = try c.decodeIfPresent(Int.self, forKey: .movementCostModifier) ?? 0
    }

    func toRegionEdge() -> RegionEdge {
        RegionEdge(from: from, to: to, hasRoad: hasRoad, hasRiverCrossing: hasRiverCrossing, movementCostModifier: movementCostModifier)
    }
}

/// v0.2 省级补给源。regionId 指向省份（与现有 SupplySource 的 HexCoord 并存）。
struct RegionSupplySourceDefinition: Codable, Equatable {
    let id: String
    let faction: Faction?
    let regionId: RegionId

    init(id: String, faction: Faction? = nil, regionId: RegionId) {
        self.id = id
        self.faction = faction
        self.regionId = regionId
    }
}

/// v0.2 省级目标。regionId 指向省份（与现有 Objective 的 HexCoord 并存）。
struct RegionObjectiveDefinition: Codable, Equatable {
    let id: String
    let name: String
    let regionId: RegionId
    let type: ObjectiveType
    let victoryPoints: Int
    let mainObjective: Bool

    init(id: String, name: String, regionId: RegionId, type: ObjectiveType, victoryPoints: Int = 0, mainObjective: Bool = false) {
        self.id = id
        self.name = name
        self.regionId = regionId
        self.type = type
        self.victoryPoints = victoryPoints
        self.mainObjective = mainObjective
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.regionId = try c.decode(RegionId.self, forKey: .regionId)
        self.type = try c.decode(ObjectiveType.self, forKey: .type)
        self.victoryPoints = try c.decodeIfPresent(Int.self, forKey: .victoryPoints) ?? 0
        self.mainObjective = try c.decodeIfPresent(Bool.self, forKey: .mainObjective) ?? false
    }
}

// MARK: - RegionDataSet → Core 映射

extension RegionDataSet {
    /// 转 RegionNode 字典。controller 缺省回退 owner；owner/controller 都缺省时为 neutral。
    func toRegions() -> [RegionId: RegionNode] {
        var result: [RegionId: RegionNode] = [:]
        for def in regions {
            let resolvedController = def.controller ?? def.owner
            result[def.id] = RegionNode(
                id: def.id,
                name: def.name,
                owner: def.owner ?? .neutral,
                controller: resolvedController ?? .neutral,
                terrain: def.terrain,
                neighbors: def.neighbors,
                displayHexes: def.displayHexes,
                representativeHex: def.representativeHex,
                city: def.city?.toCityInfo(),
                infrastructure: def.infrastructure,
                supplyValue: def.supplyValue,
                factories: def.factories,
                resources: def.resources.map { $0.toResourceAmount() },
                coreOf: def.coreOf,
                occupationState: def.occupationState?.toOccupationState(),
                isPassable: def.isPassable
            )
        }
        return result
    }

    func toRegionEdges() -> Set<RegionEdge> {
        Set(edges.map { $0.toRegionEdge() })
    }

    /// "q,r" 字符串 → HexCoord。非法返回 nil。
    func toHexToRegion() -> [HexCoord: RegionId] {
        var result: [HexCoord: RegionId] = [:]
        for (key, regionId) in hexToRegion {
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let q = Int(parts[0]),
                  let r = Int(parts[1]) else {
                continue
            }
            result[HexCoord(q: q, r: r)] = regionId
        }
        return result
    }
}
