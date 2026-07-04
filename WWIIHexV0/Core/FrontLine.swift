import Foundation

struct FrontLine: Codable, Equatable, Identifiable {
    let id: FrontLineId
    var theaterId: TheaterId
    var opposingTheaterIds: [TheaterId]
    var factionA: Faction
    var factionB: Faction
    var segments: [FrontSegment]
    var type: FrontLineType
    var state: FrontLineOperationalState

    init(
        id: FrontLineId,
        theaterId: TheaterId,
        opposingTheaterIds: [TheaterId],
        factionA: Faction,
        factionB: Faction,
        segments: [FrontSegment],
        type: FrontLineType = .normal,
        state: FrontLineOperationalState = .stable
    ) {
        self.id = id
        self.theaterId = theaterId
        self.opposingTheaterIds = opposingTheaterIds.sorted { $0.rawValue < $1.rawValue }
        self.factionA = factionA
        self.factionB = factionB
        self.segments = segments.sorted {
            if $0.regionA.rawValue == $1.regionA.rawValue {
                return $0.regionB.rawValue < $1.regionB.rawValue
            }
            return $0.regionA.rawValue < $1.regionA.rawValue
        }
        self.type = type
        self.state = state
    }
}
