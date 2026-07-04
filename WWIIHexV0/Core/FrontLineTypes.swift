import Foundation

enum FrontLineType: String, Codable, Equatable {
    case normal
    case encirclement
    case breakthrough
    case fallback
    case supplyDisruption
}

enum FrontLineOperationalState: String, Codable, Equatable {
    case stable
    case shifting
    case collapsing
}

enum FrontSegmentEdgeType: String, Codable, Equatable {
    case standard
    case road
    case riverCrossing
}

enum FrontSupplyImpact: String, Codable, Equatable {
    case none
    case low
    case medium
    case high
}

enum FrontLineUpdateMode: String, Codable, Equatable {
    case turnRebuild
    case eventDriven
}

enum FrontLineEvent: Equatable {
    case regionControllerChanged(RegionId)
    case theaterAssignmentChanged(RegionId)
    case unitEntered(RegionId)
    case unitLeft(RegionId)
    case occupationChanged(RegionId)
    case theaterChanged(TheaterId)
}
