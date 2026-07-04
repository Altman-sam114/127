import Foundation

struct FrontLineDiagnostics: Codable, Equatable {
    var updateMode: FrontLineUpdateMode?
    var scannedRegionCount: Int
    var scannedNeighborLinkCount: Int
    var updatedTheaterIds: [TheaterId]
    var updatedRegionIds: [RegionId]

    init(
        updateMode: FrontLineUpdateMode? = nil,
        scannedRegionCount: Int = 0,
        scannedNeighborLinkCount: Int = 0,
        updatedTheaterIds: [TheaterId] = [],
        updatedRegionIds: [RegionId] = []
    ) {
        self.updateMode = updateMode
        self.scannedRegionCount = max(0, scannedRegionCount)
        self.scannedNeighborLinkCount = max(0, scannedNeighborLinkCount)
        self.updatedTheaterIds = updatedTheaterIds.sorted { $0.rawValue < $1.rawValue }
        self.updatedRegionIds = updatedRegionIds.sorted { $0.rawValue < $1.rawValue }
    }
}

struct FrontLineState: Codable, Equatable {
    var frontLines: [FrontLineId: FrontLine]
    var regionStates: [RegionId: RegionFrontState]
    var enemyNeighborCache: [RegionId: [RegionId]]
    var dirtyRegionIds: Set<RegionId>
    var lastUpdatedTurn: Int?
    var diagnostics: FrontLineDiagnostics

    init(
        frontLines: [FrontLineId: FrontLine] = [:],
        regionStates: [RegionId: RegionFrontState] = [:],
        enemyNeighborCache: [RegionId: [RegionId]] = [:],
        dirtyRegionIds: Set<RegionId> = [],
        lastUpdatedTurn: Int? = nil,
        diagnostics: FrontLineDiagnostics = FrontLineDiagnostics()
    ) {
        self.frontLines = frontLines
        self.regionStates = regionStates
        self.enemyNeighborCache = enemyNeighborCache
        self.dirtyRegionIds = dirtyRegionIds
        self.lastUpdatedTurn = lastUpdatedTurn
        self.diagnostics = diagnostics
    }

    static var empty: FrontLineState {
        FrontLineState()
    }

    func frontLines(for theaterId: TheaterId) -> [FrontLine] {
        frontLines.values
            .filter { $0.theaterId == theaterId }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func regionState(for regionId: RegionId) -> RegionFrontState? {
        regionStates[regionId]
    }
}
