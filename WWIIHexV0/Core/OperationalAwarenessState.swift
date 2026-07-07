import Foundation

enum ContactConfidence: String, Codable, Equatable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case confirmed

    static func < (lhs: ContactConfidence, rhs: ContactConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        case .confirmed:
            return 3
        }
    }

    var degraded: ContactConfidence? {
        switch self {
        case .confirmed:
            return .high
        case .high:
            return .medium
        case .medium:
            return .low
        case .low:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .confirmed:
            return "Confirmed"
        }
    }
}

enum EstimatedContactType: String, Codable, Equatable, CaseIterable {
    case armor
    case infantry
    case artillery
    case airDefense
    case logistics
    case unknown

    var displayName: String {
        switch self {
        case .armor:
            return "Armor"
        case .infantry:
            return "Infantry"
        case .artillery:
            return "Artillery"
        case .airDefense:
            return "Air Defense"
        case .logistics:
            return "Logistics"
        case .unknown:
            return "Unknown"
        }
    }
}

enum ContactSource: String, Codable, Equatable, CaseIterable {
    case groundRecon
    case uav
    case signal
    case visual
    case fireObservation

    var displayName: String {
        switch self {
        case .groundRecon:
            return "Ground Recon"
        case .uav:
            return "UAV"
        case .signal:
            return "Signal"
        case .visual:
            return "Visual"
        case .fireObservation:
            return "Fire Observation"
        }
    }
}

struct ContactTrack: Identifiable, Codable, Equatable {
    let id: String
    var ownerFaction: Faction
    var observerSide: OperationalSideAlignment
    var lastKnownCoord: HexCoord
    var confidence: ContactConfidence
    var estimatedType: EstimatedContactType
    var source: ContactSource
    var ageInTurns: Int
    var linkedDivisionId: String?
}

struct SensorCoverage: Identifiable, Codable, Equatable {
    var id: String {
        "\(side.rawValue)_\(coord.q)_\(coord.r)"
    }

    let coord: HexCoord
    let side: OperationalSideAlignment
    let quality: Int
    let sources: [ContactSource]
    let jammed: Bool
}

enum EWEffectType: String, Codable, Equatable, CaseIterable {
    case jamming
    case commsDegrade
    case droneDisrupt
    case sensorSpoof

    var displayName: String {
        switch self {
        case .jamming:
            return "Jamming"
        case .commsDegrade:
            return "Comms Degradation"
        case .droneDisrupt:
            return "Drone Disruption"
        case .sensorSpoof:
            return "Sensor Spoofing"
        }
    }
}

struct EWEffect: Identifiable, Codable, Equatable {
    let id: String
    let area: [HexCoord]
    let side: OperationalSideAlignment
    let effectType: EWEffectType
    let strength: Int
    var remainingTurns: Int
}

struct OperationalAwarenessState: Codable, Equatable {
    var contacts: [String: ContactTrack]
    var sensorCoverage: [SensorCoverage]
    var ewEffects: [EWEffect]

    static let empty = OperationalAwarenessState(
        contacts: [:],
        sensorCoverage: [],
        ewEffects: []
    )

    func visibleContacts(for faction: Faction) -> [ContactTrack] {
        contacts.values
            .filter { $0.ownerFaction == faction }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                if lhs.ageInTurns != rhs.ageInTurns {
                    return lhs.ageInTurns < rhs.ageInTurns
                }
                return lhs.id < rhs.id
            }
    }

    func visibleContact(
        for faction: Faction,
        linkedTo targetDivisionId: String,
        minimumConfidence: ContactConfidence,
        maximumAgeInTurns: Int? = nil
    ) -> ContactTrack? {
        visibleContacts(for: faction).first { contact in
            guard contact.linkedDivisionId == targetDivisionId,
                  contact.confidence >= minimumConfidence else {
                return false
            }

            if let maximumAgeInTurns {
                return contact.ageInTurns <= maximumAgeInTurns
            }

            return true
        }
    }
}
