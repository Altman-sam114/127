import Foundation

enum WarState: String, Codable, Equatable {
    case peace
    case lowIntensity
    case highIntensity
    case totalWar
}

enum DeploymentLayer: String, Codable, Equatable {
    case front
    case depth
    case garrison
}

enum UnitDeploymentRole: String, Codable, Equatable {
    case frontUnit
    case depthUnit
    case garrisonUnit
}

struct NavalZone: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var linkedCoastalRegionIds: [RegionId]

    init(id: String, name: String, linkedCoastalRegionIds: [RegionId] = []) {
        self.id = id
        self.name = name
        self.linkedCoastalRegionIds = linkedCoastalRegionIds
    }
}

enum WarDeploymentEvent: Equatable {
    case regionControllerChanged(RegionId)
    case frontZoneAssignmentChanged(RegionId)
    case unitEntered(RegionId)
    case unitLeft(RegionId)
    case frontZoneChanged(FrontZoneId)
}
