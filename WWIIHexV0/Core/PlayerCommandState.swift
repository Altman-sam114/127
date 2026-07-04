import Foundation

struct PlayerCommandState: Codable, Equatable {
    var micromanagedDivisionIds: Set<String>
    var plannedOperations: [PlayerPlannedOperation]

    init(
        micromanagedDivisionIds: Set<String> = [],
        plannedOperations: [PlayerPlannedOperation] = []
    ) {
        self.micromanagedDivisionIds = micromanagedDivisionIds
        self.plannedOperations = plannedOperations.sorted { lhs, rhs in
            if lhs.turn == rhs.turn {
                return lhs.id < rhs.id
            }
            return lhs.turn < rhs.turn
        }
    }

    static var empty: PlayerCommandState {
        PlayerCommandState()
    }

    mutating func lockDivision(_ divisionId: String) {
        micromanagedDivisionIds.insert(divisionId)
    }

    mutating func recordOperation(_ operation: PlayerPlannedOperation) {
        plannedOperations.removeAll { $0.id == operation.id }
        plannedOperations.append(operation)
        plannedOperations.sort {
            if $0.turn == $1.turn {
                return $0.id < $1.id
            }
            return $0.turn < $1.turn
        }
    }

    mutating func clearTurnLocks() {
        micromanagedDivisionIds.removeAll()
    }
}

struct PlayerPlannedOperation: Identifiable, Codable, Equatable {
    let id: String
    let turn: Int
    let zoneId: FrontZoneId
    let faction: Faction
    let directiveType: DirectiveType
    let sourceRegionId: RegionId?
    let targetRegionId: RegionId?
    let createdByGeneralId: String?

    init(
        id: String,
        turn: Int,
        zoneId: FrontZoneId,
        faction: Faction,
        directiveType: DirectiveType,
        sourceRegionId: RegionId? = nil,
        targetRegionId: RegionId? = nil,
        createdByGeneralId: String? = nil
    ) {
        self.id = id
        self.turn = max(1, turn)
        self.zoneId = zoneId
        self.faction = faction
        self.directiveType = directiveType
        self.sourceRegionId = sourceRegionId
        self.targetRegionId = targetRegionId
        self.createdByGeneralId = createdByGeneralId
    }
}
