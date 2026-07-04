import Foundation

struct GeneralAssignment: Codable, Equatable, Identifiable {
    let id: String
    var generalId: String { id }
    var hqRegionId: RegionId?
    var assignedDivisionIds: [String]
    var loyalty: Int
    var satisfaction: Int
    var interventionCount: Int

    init(
        generalId: String,
        hqRegionId: RegionId? = nil,
        assignedDivisionIds: [String] = [],
        loyalty: Int = 70,
        satisfaction: Int = 70,
        interventionCount: Int = 0
    ) {
        self.id = generalId
        self.hqRegionId = hqRegionId
        self.assignedDivisionIds = assignedDivisionIds.sorted()
        self.loyalty = Self.clampPercent(loyalty)
        self.satisfaction = Self.clampPercent(satisfaction)
        self.interventionCount = max(0, interventionCount)
    }

    func withAssignedDivisionIds(_ divisionIds: [String]) -> GeneralAssignment {
        GeneralAssignment(
            generalId: generalId,
            hqRegionId: hqRegionId,
            assignedDivisionIds: divisionIds,
            loyalty: loyalty,
            satisfaction: satisfaction,
            interventionCount: interventionCount
        )
    }

    func registeringPlayerIntervention(cost: Int = 4) -> GeneralAssignment {
        GeneralAssignment(
            generalId: generalId,
            hqRegionId: hqRegionId,
            assignedDivisionIds: assignedDivisionIds,
            loyalty: loyalty,
            satisfaction: satisfaction - max(0, cost),
            interventionCount: interventionCount + 1
        )
    }

    private static func clampPercent(_ value: Int) -> Int {
        max(0, min(100, value))
    }
}
