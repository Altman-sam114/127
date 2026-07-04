import Foundation

struct FrontZoneSegment: Codable, Equatable, Identifiable {
    let id: String
    let regionId: RegionId
    let neighborEnemyZone: FrontZoneId
    var strength: Int
    var isEncircled: Bool
    var assignedFrontUnitIds: [String]

    init(
        id: String? = nil,
        regionId: RegionId,
        neighborEnemyZone: FrontZoneId,
        strength: Int = 0,
        isEncircled: Bool = false,
        assignedFrontUnitIds: [String] = []
    ) {
        self.id = id ?? "\(regionId.rawValue)__enemy_\(neighborEnemyZone.rawValue)"
        self.regionId = regionId
        self.neighborEnemyZone = neighborEnemyZone
        self.strength = max(0, strength)
        self.isEncircled = isEncircled
        self.assignedFrontUnitIds = assignedFrontUnitIds.sorted()
    }
}
