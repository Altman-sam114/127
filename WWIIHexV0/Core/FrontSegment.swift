import Foundation

struct FrontSegment: Codable, Equatable, Identifiable {
    let id: String
    let regionA: RegionId
    let regionB: RegionId
    let edgeType: FrontSegmentEdgeType?
    let pressureLevel: Double
    let supplyImpact: FrontSupplyImpact
    let isEncirclementCandidate: Bool

    init(
        id: String? = nil,
        regionA: RegionId,
        regionB: RegionId,
        edgeType: FrontSegmentEdgeType? = nil,
        pressureLevel: Double,
        supplyImpact: FrontSupplyImpact,
        isEncirclementCandidate: Bool = false
    ) {
        self.id = id ?? Self.makeId(regionA, regionB)
        self.regionA = regionA
        self.regionB = regionB
        self.edgeType = edgeType
        self.pressureLevel = min(1, max(0, pressureLevel))
        self.supplyImpact = supplyImpact
        self.isEncirclementCandidate = isEncirclementCandidate
    }

    static func makeId(_ a: RegionId, _ b: RegionId) -> String {
        a.rawValue < b.rawValue
            ? "\(a.rawValue)__\(b.rawValue)"
            : "\(b.rawValue)__\(a.rawValue)"
    }
}
