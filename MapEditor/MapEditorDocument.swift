import Foundation

enum MapEditorMode: String, Codable, CaseIterable, Identifiable {
    case hexPainter
    case regionBuilder
    case theaterAssignment
    case unitPlanner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hexPainter:
            return "地块"
        case .regionBuilder:
            return "区域"
        case .theaterAssignment:
            return "作战区"
        case .unitPlanner:
            return "任务编组"
        }
    }
}

enum MapEditorEditAction: String, Codable, CaseIterable, Identifiable {
    case idle
    case adding
    case deleting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle:
            return "未编辑"
        case .adding:
            return "添加"
        case .deleting:
            return "删除"
        }
    }
}

enum MapEditorHexTool: String, Codable, CaseIterable, Identifiable {
    case paint
    case extend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paint:
            return "覆盖"
        case .extend:
            return "扩展"
        }
    }
}

struct MapEditorHex: Codable, Equatable, Identifiable {
    var coord: HexCoord
    var terrain: BaseTerrain
    var hasRoad: Bool
    var controller: Faction?
    var cityName: String?
    var fortressName: String?
    var isSupplySource: Bool
    var supplyFaction: Faction?
    var objectiveId: String?
    var regionId: RegionId?

    var id: String { coord.mapEditorKey }

    init(
        coord: HexCoord,
        terrain: BaseTerrain = .plain,
        hasRoad: Bool = false,
        controller: Faction? = nil,
        cityName: String? = nil,
        fortressName: String? = nil,
        isSupplySource: Bool = false,
        supplyFaction: Faction? = nil,
        objectiveId: String? = nil,
        regionId: RegionId? = nil
    ) {
        self.coord = coord
        self.terrain = terrain
        self.hasRoad = hasRoad
        self.controller = controller
        self.cityName = cityName
        self.fortressName = fortressName
        self.isSupplySource = isSupplySource
        self.supplyFaction = supplyFaction
        self.objectiveId = objectiveId
        self.regionId = regionId
    }
}

struct MapEditorRegionDraft: Codable, Equatable, Identifiable {
    var id: RegionId
    var name: String
    var owner: Faction?
    var controller: Faction?
    var infrastructure: Int
    var supplyValue: Int
    var factories: Int
    var coreOf: [Faction]
    var assignedGeneralId: String?

    init(
        id: RegionId,
        name: String? = nil,
        owner: Faction? = nil,
        controller: Faction? = nil,
        infrastructure: Int = 0,
        supplyValue: Int = 0,
        factories: Int = 0,
        coreOf: [Faction] = [],
        assignedGeneralId: String? = nil
    ) {
        self.id = id
        self.name = name ?? id.rawValue
        self.owner = owner
        self.controller = controller
        self.infrastructure = infrastructure
        self.supplyValue = supplyValue
        self.factories = factories
        self.coreOf = coreOf
        self.assignedGeneralId = assignedGeneralId
    }
}

struct MapEditorTheaterDraft: Codable, Equatable, Identifiable {
    var id: TheaterId
    var name: String

    init(id: TheaterId, name: String? = nil) {
        self.id = id
        self.name = name ?? id.rawValue
    }
}

struct MapEditorUnitDraft: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var faction: Faction
    var templateId: String
    var coord: HexCoord
    var facing: HexDirection
    var hp: Int
    var retreatMode: RetreatMode
    var supplyState: SupplyState
    var assignedAgentId: String?

    init(
        id: String,
        name: String,
        faction: Faction,
        templateId: String,
        coord: HexCoord,
        facing: HexDirection = .west,
        hp: Int = 10,
        retreatMode: RetreatMode = .retreatable,
        supplyState: SupplyState = .supplied,
        assignedAgentId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.faction = faction
        self.templateId = templateId
        self.coord = coord
        self.facing = facing
        self.hp = hp
        self.retreatMode = retreatMode
        self.supplyState = supplyState
        self.assignedAgentId = assignedAgentId
    }
}

struct MapEditorBackgroundImage: Codable, Equatable {
    var filePath: String
    var opacity: Double
    var scale: Double
    var positionX: Double
    var positionY: Double

    init(
        filePath: String,
        opacity: Double = 0.45,
        scale: Double = 1,
        positionX: Double = 0,
        positionY: Double = 0
    ) {
        self.filePath = filePath
        self.opacity = opacity
        self.scale = scale
        self.positionX = positionX
        self.positionY = positionY
    }
}

struct MapEditorDocument: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var width: Int
    var height: Int
    var hexes: [HexCoord: MapEditorHex]
    var regions: [RegionId: MapEditorRegionDraft]
    var theaters: [TheaterId: MapEditorTheaterDraft]
    var regionTheaterAssignments: [RegionId: TheaterId]
    var initialUnits: [MapEditorUnitDraft]
    var backgroundImage: MapEditorBackgroundImage?

    init(
        id: String,
        displayName: String,
        width: Int,
        height: Int,
        hexes: [HexCoord: MapEditorHex],
        regions: [RegionId: MapEditorRegionDraft] = [:],
        theaters: [TheaterId: MapEditorTheaterDraft] = [:],
        regionTheaterAssignments: [RegionId: TheaterId] = [:],
        initialUnits: [MapEditorUnitDraft] = [],
        backgroundImage: MapEditorBackgroundImage? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.width = width
        self.height = height
        self.hexes = hexes
        self.regions = regions
        self.theaters = theaters
        self.regionTheaterAssignments = regionTheaterAssignments
        self.initialUnits = initialUnits
        self.backgroundImage = backgroundImage
    }

    static func new(id: String = "mapeditor_scenario", displayName: String = "MapEditor Scenario", width: Int, height: Int) -> MapEditorDocument {
        var hexes: [HexCoord: MapEditorHex] = [:]
        for q in 0..<max(1, width) {
            for r in 0..<max(1, height) {
                let coord = HexCoord(q: q, r: r)
                hexes[coord] = MapEditorHex(coord: coord)
            }
        }
        return MapEditorDocument(
            id: id,
            displayName: displayName,
            width: max(1, width),
            height: max(1, height),
            hexes: hexes
        )
    }

    var sortedHexes: [MapEditorHex] {
        hexes.values.sorted { lhs, rhs in
            lhs.coord.r == rhs.coord.r ? lhs.coord.q < rhs.coord.q : lhs.coord.r < rhs.coord.r
        }
    }

    var isSparse: Bool {
        hexes.count != width * height
    }

    mutating func resize(width newWidth: Int, height newHeight: Int) {
        let clampedWidth = max(1, newWidth)
        let clampedHeight = max(1, newHeight)
        var next: [HexCoord: MapEditorHex] = [:]

        for q in 0..<clampedWidth {
            for r in 0..<clampedHeight {
                let coord = HexCoord(q: q, r: r)
                next[coord] = hexes[coord] ?? MapEditorHex(coord: coord)
            }
        }

        let validRegions = Set(next.values.compactMap(\.regionId))
        regions = regions.filter { validRegions.contains($0.key) }
        regionTheaterAssignments = regionTheaterAssignments.filter { validRegions.contains($0.key) }
        initialUnits.removeAll { next[$0.coord] == nil }
        width = clampedWidth
        height = clampedHeight
        hexes = next
    }

    mutating func setHex(_ hex: MapEditorHex) {
        guard contains(hex.coord) else { return }
        hexes[hex.coord] = hex
    }

    @discardableResult
    mutating func addHex(at coord: HexCoord, terrain: BaseTerrain = .plain) -> Bool {
        guard !contains(coord) else { return false }
        guard hexes.isEmpty || coord.neighbors.contains(where: { hexes[$0] != nil }) else {
            return false
        }
        hexes[coord] = MapEditorHex(coord: coord, terrain: terrain)
        updateBoundsToFitHexes()
        return true
    }

    mutating func deleteHex(at coord: HexCoord) {
        guard contains(coord) else { return }
        let removedRegionId = hexes[coord]?.regionId
        hexes.removeValue(forKey: coord)
        initialUnits.removeAll { $0.coord == coord }

        if let removedRegionId,
           !hexes.values.contains(where: { $0.regionId == removedRegionId }) {
            regions.removeValue(forKey: removedRegionId)
            regionTheaterAssignments.removeValue(forKey: removedRegionId)
        }

        let validRegions = Set(hexes.values.compactMap(\.regionId))
        regionTheaterAssignments = regionTheaterAssignments.filter { validRegions.contains($0.key) }
        updateBoundsToFitHexes()
    }

    mutating func resetHex(at coord: HexCoord) {
        guard contains(coord) else { return }
        hexes[coord] = MapEditorHex(coord: coord)
        initialUnits.removeAll { $0.coord == coord }
    }

    mutating func createRegion(id: RegionId, name: String? = nil, controller: Faction? = nil) {
        regions[id] = MapEditorRegionDraft(id: id, name: name, controller: controller)
    }

    mutating func createTheater(id: TheaterId, name: String? = nil) {
        theaters[id] = MapEditorTheaterDraft(id: id, name: name)
    }

    mutating func assign(_ coord: HexCoord, to regionId: RegionId?) {
        guard contains(coord), var hex = hexes[coord] else { return }
        hex.regionId = regionId
        hexes[coord] = hex
    }

    mutating func assign(regionId: RegionId, to theaterId: TheaterId?) {
        if let theaterId {
            regionTheaterAssignments[regionId] = theaterId
        } else {
            regionTheaterAssignments.removeValue(forKey: regionId)
        }
    }

    func contains(_ coord: HexCoord) -> Bool {
        hexes[coord] != nil
    }

    private mutating func updateBoundsToFitHexes() {
        guard !hexes.isEmpty else {
            width = 1
            height = 1
            return
        }

        let qValues = hexes.keys.map(\.q)
        let rValues = hexes.keys.map(\.r)
        let minQ = qValues.min() ?? 0
        let maxQ = qValues.max() ?? 0
        let minR = rValues.min() ?? 0
        let maxR = rValues.max() ?? 0
        width = max(1, maxQ - minQ + 1)
        height = max(1, maxR - minR + 1)
    }
}

enum MapEditorStorage {
    static func save(_ document: MapEditorDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> MapEditorDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MapEditorDocument.self, from: data)
    }
}

extension HexCoord {
    var mapEditorKey: String {
        "\(q),\(r)"
    }
}
