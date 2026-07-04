import Foundation

struct RegionFrontState: Codable, Equatable, Identifiable {
    var id: RegionId { regionId }

    let regionId: RegionId
    var frontLines: [FrontLine]
    var lastUpdatedTurn: Int?
    var dirtyFlag: Bool

    init(
        regionId: RegionId,
        frontLines: [FrontLine] = [],
        lastUpdatedTurn: Int? = nil,
        dirtyFlag: Bool = false
    ) {
        self.regionId = regionId
        self.frontLines = frontLines
        self.lastUpdatedTurn = lastUpdatedTurn
        self.dirtyFlag = dirtyFlag
    }
}
