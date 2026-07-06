import Foundation

enum MunitionClass: String, Codable, Equatable, CaseIterable {
    case tubeArtillery
    case rocket
    case precision
    case loitering

    var displayName: String {
        switch self {
        case .tubeArtillery:
            return "Tube Artillery"
        case .rocket:
            return "Rocket Fires"
        case .precision:
            return "Precision Strike"
        case .loitering:
            return "Loitering Munition"
        }
    }

    var baseDamage: Int {
        switch self {
        case .tubeArtillery:
            return 2
        case .rocket:
            return 3
        case .precision:
            return 4
        case .loitering:
            return 3
        }
    }

    var cooldownTurns: Int {
        switch self {
        case .tubeArtillery:
            return 1
        case .rocket:
            return 2
        case .precision,
             .loitering:
            return 2
        }
    }

    var usesAirTasking: Bool {
        self == .precision || self == .loitering
    }

    var canOperateInRestrictedFireZone: Bool {
        self == .precision || self == .loitering
    }
}

enum FireMissionTarget: Codable, Equatable {
    case contact(id: String)
    case hex(HexCoord)
    case region(RegionId)

    var displayName: String {
        switch self {
        case .contact(let id):
            return "Contact Track \(Self.trackDisplay(id))"
        case .hex(let coord):
            return "Hex \(coord.q),\(coord.r)"
        case .region(let regionId):
            return Self.objectiveDisplay(regionId)
        }
    }

    private static func trackDisplay(_ id: String) -> String {
        let cleaned = id
            .replacingOccurrences(of: "contact_", with: "")
            .replacingOccurrences(of: "ct_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Unknown" : cleaned.capitalized
    }

    private static func objectiveDisplay(_ id: RegionId) -> String {
        let cleaned = id.rawValue
            .replacingOccurrences(of: "region_", with: "")
            .replacingOccurrences(of: "objective_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Objective Area" : "Objective \(cleaned.capitalized)"
    }
}

enum FireRiskFlag: String, Codable, Equatable, CaseIterable {
    case lowTargetQuality
    case airDefenseThreat
    case electronicWarfare
    case friendlyProximity
    case staleContact
    case unsuppressedAirDefense
    case restrictedFireZone

    var displayName: String {
        switch self {
        case .lowTargetQuality:
            return "low target quality"
        case .airDefenseThreat:
            return "air-defense threat"
        case .electronicWarfare:
            return "EW interference"
        case .friendlyProximity:
            return "friendly proximity"
        case .staleContact:
            return "stale contact"
        case .unsuppressedAirDefense:
            return "unsuppressed air defense"
        case .restrictedFireZone:
            return "restricted fire zone"
        }
    }
}

struct FireMission: Identifiable, Codable, Equatable {
    let id: String
    let issuerId: String
    let side: OperationalSideAlignment
    let sourceAssetId: String?
    let target: FireMissionTarget
    let munitionClass: MunitionClass
    let targetQuality: ContactConfidence
    let expectedEffect: Int
    let riskFlags: [FireRiskFlag]
}

enum FireMissionOutcomeStatus: String, Codable, Equatable, CaseIterable {
    case success
    case degraded
    case failed
    case suppressed

    var displayName: String {
        switch self {
        case .success:
            return "success"
        case .degraded:
            return "degraded"
        case .failed:
            return "failed"
        case .suppressed:
            return "suppressed"
        }
    }
}

struct FireMissionResult: Identifiable, Codable, Equatable {
    let id: String
    let missionId: String
    let turn: Int
    let side: OperationalSideAlignment
    let status: FireMissionOutcomeStatus
    let target: FireMissionTarget
    let targetDivisionId: String?
    let munitionClass: MunitionClass
    let damage: Int
    let riskFlags: [FireRiskFlag]
    let narrative: String
}

struct FireSupportAmmoBudget: Codable, Equatable {
    var tubeArtillery: Int
    var rocket: Int
    var precision: Int
    var loitering: Int

    static func standard(for side: OperationalSideAlignment) -> FireSupportAmmoBudget {
        switch side {
        case .blue,
             .red:
            return FireSupportAmmoBudget(
                tubeArtillery: 6,
                rocket: 4,
                precision: 2,
                loitering: 3
            )
        case .green,
             .neutral:
            return FireSupportAmmoBudget(
                tubeArtillery: 0,
                rocket: 0,
                precision: 0,
                loitering: 0
            )
        }
    }

    func available(for munitionClass: MunitionClass) -> Int {
        switch munitionClass {
        case .tubeArtillery:
            return tubeArtillery
        case .rocket:
            return rocket
        case .precision:
            return precision
        case .loitering:
            return loitering
        }
    }

    mutating func consume(_ munitionClass: MunitionClass, amount: Int = 1) -> Bool {
        guard amount > 0,
              available(for: munitionClass) >= amount else {
            return false
        }

        switch munitionClass {
        case .tubeArtillery:
            tubeArtillery -= amount
        case .rocket:
            rocket -= amount
        case .precision:
            precision -= amount
        case .loitering:
            loitering -= amount
        }
        return true
    }
}

struct AirSortie: Identifiable, Codable, Equatable {
    let id: String
    let issuerId: String
    let side: OperationalSideAlignment
    let target: HexCoord
    let task: String
    let status: FireMissionOutcomeStatus
    var remainingTurns: Int
}

struct AirDefenseThreat: Identifiable, Codable, Equatable {
    let id: String
    let coord: HexCoord
    let side: OperationalSideAlignment
    let threatLevel: Int
    let remainingTurns: Int
}

struct AirDefenseSuppression: Identifiable, Codable, Equatable {
    let id: String
    let coord: HexCoord
    let side: OperationalSideAlignment
    let reduction: Int
    var remainingTurns: Int
}

struct AirTaskingState: Codable, Equatable {
    var sorties: [AirSortie]
    var airDefenseThreat: [AirDefenseThreat]
    var airSuperiority: [OperationalSideAlignment: Int]
    var suppressionEffects: [AirDefenseSuppression]
    var missionResults: [FireMissionResult]

    static let empty = AirTaskingState(
        sorties: [],
        airDefenseThreat: [],
        airSuperiority: [
            .blue: 0,
            .red: 0,
            .green: 0,
            .neutral: 0
        ],
        suppressionEffects: [],
        missionResults: []
    )
}

struct FireSupportState: Codable, Equatable {
    var ammoBudgetBySide: [OperationalSideAlignment: FireSupportAmmoBudget]
    var cooldownsByAsset: [String: Int]
    var scheduledMissions: [FireMission]
    var lastMissionResults: [FireMissionResult]
    var airTaskingState: AirTaskingState

    static let initial = FireSupportState(
        ammoBudgetBySide: Dictionary(
            uniqueKeysWithValues: OperationalSideAlignment.allCases.map {
                ($0, FireSupportAmmoBudget.standard(for: $0))
            }
        ),
        cooldownsByAsset: [:],
        scheduledMissions: [],
        lastMissionResults: [],
        airTaskingState: .empty
    )

    static let empty = FireSupportState.initial

    func budget(for side: OperationalSideAlignment) -> FireSupportAmmoBudget {
        ammoBudgetBySide[side] ?? FireSupportAmmoBudget.standard(for: side)
    }

    mutating func consume(_ munitionClass: MunitionClass, for side: OperationalSideAlignment) -> Bool {
        var budget = budget(for: side)
        guard budget.consume(munitionClass) else {
            return false
        }
        ammoBudgetBySide[side] = budget
        return true
    }

    mutating func recordResult(_ result: FireMissionResult) {
        lastMissionResults.append(result)
        lastMissionResults = Array(lastMissionResults.suffix(12))
        airTaskingState.missionResults.append(result)
        airTaskingState.missionResults = Array(airTaskingState.missionResults.suffix(12))
    }
}
