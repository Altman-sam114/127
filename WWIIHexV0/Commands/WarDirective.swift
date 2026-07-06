import Foundation

enum DirectiveType: String, Codable, Equatable, CaseIterable {
    case defend
    case attack
}

enum CommandCategory: String, Codable, Equatable, CaseIterable {
    case offense
    case defense
}

enum TacticName: String, Codable, Equatable, CaseIterable {
    case standardAttack
    case blitzkrieg
    case spearhead
    case breakthrough
    case pincerMovement
    case fireCoverage
    case feint
    case guerrillaWarfare
    case holdPosition
    case elasticDefense
    case defenseInDepth
    case lastStand

    var category: CommandCategory {
        switch self {
        case .standardAttack,
             .blitzkrieg,
             .spearhead,
             .breakthrough,
             .pincerMovement,
             .fireCoverage,
             .feint,
             .guerrillaWarfare:
            return .offense
        case .holdPosition,
             .elasticDefense,
             .defenseInDepth,
             .lastStand:
            return .defense
        }
    }

    var displayName: String {
        switch self {
        case .standardAttack:
            return "Direct Attack"
        case .blitzkrieg:
            return "Armored Thrust"
        case .spearhead:
            return "Spearhead"
        case .breakthrough:
            return "Breach"
        case .pincerMovement:
            return "Envelopment"
        case .fireCoverage:
            return "Suppression"
        case .feint:
            return "Fixing Attack"
        case .guerrillaWarfare:
            return "Raid"
        case .holdPosition:
            return "Hold Key Terrain"
        case .elasticDefense:
            return "Delay"
        case .defenseInDepth:
            return "Layered Defense"
        case .lastStand:
            return "Hold at All Costs"
        }
    }
}

struct TacticCondition: Codable, Equatable {
    let requiredCommanderSkills: [String]
    let minimumStrengthRatio: Double
    let requiresArmorUnit: Bool

    init(
        requiredCommanderSkills: [String],
        minimumStrengthRatio: Double,
        requiresArmorUnit: Bool
    ) {
        self.requiredCommanderSkills = requiredCommanderSkills
        self.minimumStrengthRatio = max(0, minimumStrengthRatio)
        self.requiresArmorUnit = requiresArmorUnit
    }

    static let none = TacticCondition(
        requiredCommanderSkills: [],
        minimumStrengthRatio: 0,
        requiresArmorUnit: false
    )
}

struct TacticDescriptor: Codable, Equatable {
    let name: TacticName
    let category: CommandCategory
    let condition: TacticCondition
    let description: String
}

enum DirectiveTarget: Equatable {
    case theater(TheaterId)
    case region(RegionId)
}

extension DirectiveTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case theater
        case region
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let theaterId = try container.decodeIfPresent(TheaterId.self, forKey: .theater) {
            self = .theater(theaterId)
            return
        }
        if let regionId = try container.decodeIfPresent(RegionId.self, forKey: .region) {
            self = .region(regionId)
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "DirectiveTarget requires operational zone or region.")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .theater(let theaterId):
            try container.encode(theaterId, forKey: .theater)
        case .region(let regionId):
            try container.encode(regionId, forKey: .region)
        }
    }
}

enum DefenseStance: String, Codable, Equatable, CaseIterable {
    case holdLine
    case flexible
}

enum AttackIntensity: String, Codable, Equatable, CaseIterable {
    case infiltration
    case limitedCounter
    case allOut
}

struct DefenseParameters: Codable, Equatable {
    let targetReserves: Int
    let stance: DefenseStance
    let fallbackRegionIds: [RegionId]?
    let counterattackRegionIds: [RegionId]?
    let strongpointRegionIds: [RegionId]?
    let maxFrontCommitment: Int?

    init(
        targetReserves: Int,
        stance: DefenseStance,
        fallbackRegionIds: [RegionId]? = nil,
        counterattackRegionIds: [RegionId]? = nil,
        strongpointRegionIds: [RegionId]? = nil,
        maxFrontCommitment: Int? = nil
    ) {
        self.targetReserves = max(0, targetReserves)
        self.stance = stance
        self.fallbackRegionIds = fallbackRegionIds
        self.counterattackRegionIds = counterattackRegionIds
        self.strongpointRegionIds = strongpointRegionIds
        self.maxFrontCommitment = maxFrontCommitment.map { max(0, $0) }
    }
}

struct AttackParameters: Codable, Equatable {
    let targetTheaterId: TheaterId
    let weightedRegions: [RegionId]
    let intensity: AttackIntensity
    let focusRegionId: RegionId?
    let supportRegionIds: [RegionId]?
    let convergenceRegionId: RegionId?
    let coordinatedZoneIds: [FrontZoneId]?
    let maxCommittedUnits: Int?
    let exploitDepth: Int?

    init(
        targetTheaterId: TheaterId,
        weightedRegions: [RegionId],
        intensity: AttackIntensity,
        focusRegionId: RegionId? = nil,
        supportRegionIds: [RegionId]? = nil,
        convergenceRegionId: RegionId? = nil,
        coordinatedZoneIds: [FrontZoneId]? = nil,
        maxCommittedUnits: Int? = nil,
        exploitDepth: Int? = nil
    ) {
        self.targetTheaterId = targetTheaterId
        self.weightedRegions = weightedRegions
        self.intensity = intensity
        self.focusRegionId = focusRegionId
        self.supportRegionIds = supportRegionIds
        self.convergenceRegionId = convergenceRegionId
        self.coordinatedZoneIds = coordinatedZoneIds
        self.maxCommittedUnits = maxCommittedUnits.map { max(0, $0) }
        self.exploitDepth = exploitDepth.map { max(0, $0) }
    }
}

enum DirectiveParameters: Equatable {
    case defend(DefenseParameters)
    case attack(AttackParameters)

    var defense: DefenseParameters? {
        if case .defend(let parameters) = self {
            return parameters
        }
        return nil
    }

    var attack: AttackParameters? {
        if case .attack(let parameters) = self {
            return parameters
        }
        return nil
    }
}

struct ZoneDirective: Codable, Equatable {
    let zoneId: FrontZoneId
    let type: DirectiveType
    let parameters: DirectiveParameters
    let category: CommandCategory?
    let tactic: TacticName?
    let commandTarget: DirectiveTarget?

    var targetRegionIds: [RegionId] {
        switch parameters {
        case .defend:
            return []
        case .attack(let attack):
            return attack.weightedRegions
        }
    }

    init(
        zoneId: FrontZoneId,
        type: DirectiveType,
        parameters: DirectiveParameters,
        category: CommandCategory? = nil,
        tactic: TacticName? = nil,
        commandTarget: DirectiveTarget? = nil
    ) {
        self.zoneId = zoneId
        self.type = type
        self.parameters = parameters
        self.category = category
        self.tactic = tactic
        self.commandTarget = commandTarget
    }

    init(
        zoneId: FrontZoneId,
        defense: DefenseParameters,
        category: CommandCategory? = nil,
        tactic: TacticName? = nil,
        commandTarget: DirectiveTarget? = nil
    ) {
        self.init(
            zoneId: zoneId,
            type: .defend,
            parameters: .defend(defense),
            category: category,
            tactic: tactic,
            commandTarget: commandTarget
        )
    }

    init(
        zoneId: FrontZoneId,
        attack: AttackParameters,
        category: CommandCategory? = nil,
        tactic: TacticName? = nil,
        commandTarget: DirectiveTarget? = nil
    ) {
        self.init(
            zoneId: zoneId,
            type: .attack,
            parameters: .attack(attack),
            category: category,
            tactic: tactic,
            commandTarget: commandTarget
        )
    }

    private enum CodingKeys: String, CodingKey {
        case zoneId
        case type
        case parameters
        case category
        case tactic
        case commandTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoneId = try container.decode(FrontZoneId.self, forKey: .zoneId)
        type = try container.decode(DirectiveType.self, forKey: .type)
        category = try container.decodeIfPresent(CommandCategory.self, forKey: .category)
        tactic = try container.decodeIfPresent(TacticName.self, forKey: .tactic)
        commandTarget = try container.decodeIfPresent(DirectiveTarget.self, forKey: .commandTarget)

        switch type {
        case .defend:
            parameters = .defend(try container.decode(DefenseParameters.self, forKey: .parameters))
        case .attack:
            parameters = .attack(try container.decode(AttackParameters.self, forKey: .parameters))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zoneId, forKey: .zoneId)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(tactic, forKey: .tactic)
        try container.encodeIfPresent(commandTarget, forKey: .commandTarget)

        switch parameters {
        case .defend(let defense):
            try container.encode(defense, forKey: .parameters)
        case .attack(let attack):
            try container.encode(attack, forKey: .parameters)
        }
    }
}

struct DirectiveEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let issuerId: String
    let turn: Int
    let directives: [ZoneDirective]
    let commanderAgentId: String?
    let theaterContext: String?

    init(
        schemaVersion: Int = 1,
        issuerId: String,
        turn: Int,
        directives: [ZoneDirective],
        commanderAgentId: String? = nil,
        theaterContext: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.issuerId = issuerId
        self.turn = turn
        self.directives = directives
        self.commanderAgentId = commanderAgentId
        self.theaterContext = theaterContext
    }
}

struct TheaterDirectiveEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let issuerId: String
    let turn: Int
    let faction: Faction
    let strategicIntent: String
    let directives: [TheaterDirective]
    let summary: String?

    init(
        schemaVersion: Int = 5,
        issuerId: String,
        turn: Int,
        faction: Faction,
        strategicIntent: String,
        directives: [TheaterDirective],
        summary: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.issuerId = issuerId
        self.turn = turn
        self.faction = faction
        self.strategicIntent = strategicIntent
        self.directives = directives.sorted {
            if $0.priority == $1.priority {
                return $0.zoneId.rawValue < $1.zoneId.rawValue
            }
            return $0.priority > $1.priority
        }
        self.summary = summary
    }
}

struct TheaterDirective: Codable, Equatable, Identifiable {
    let id: String
    let zoneId: FrontZoneId
    let category: CommandCategory
    let tactic: TacticName?
    let priority: Int
    let targetTheaterId: TheaterId?
    let weightedRegions: [RegionId]
    let focusRegionId: RegionId?
    let supportRegionIds: [RegionId]
    let convergenceRegionId: RegionId?
    let coordinatedZoneIds: [FrontZoneId]
    let reserveBias: Int
    let intensity: AttackIntensity?
    let maxCommittedUnits: Int?
    let exploitDepth: Int?
    let rationale: String

    private enum CodingKeys: String, CodingKey {
        case id
        case zoneId
        case category
        case tactic
        case priority
        case targetTheaterId
        case weightedRegions
        case focusRegionId
        case supportRegionIds
        case convergenceRegionId
        case coordinatedZoneIds
        case reserveBias
        case intensity
        case maxCommittedUnits
        case exploitDepth
        case rationale
    }

    init(
        id: String,
        zoneId: FrontZoneId,
        category: CommandCategory,
        tactic: TacticName? = nil,
        priority: Int = 50,
        targetTheaterId: TheaterId? = nil,
        weightedRegions: [RegionId] = [],
        focusRegionId: RegionId? = nil,
        supportRegionIds: [RegionId] = [],
        convergenceRegionId: RegionId? = nil,
        coordinatedZoneIds: [FrontZoneId] = [],
        reserveBias: Int = 1,
        intensity: AttackIntensity? = nil,
        maxCommittedUnits: Int? = nil,
        exploitDepth: Int? = nil,
        rationale: String
    ) {
        self.id = id
        self.zoneId = zoneId
        self.category = category
        self.tactic = tactic
        self.priority = max(0, min(100, priority))
        self.targetTheaterId = targetTheaterId
        self.weightedRegions = Self.unique(weightedRegions)
        self.focusRegionId = focusRegionId
        self.supportRegionIds = Self.unique(supportRegionIds)
        self.convergenceRegionId = convergenceRegionId
        self.coordinatedZoneIds = Self.unique(coordinatedZoneIds)
        self.reserveBias = max(0, reserveBias)
        self.intensity = intensity
        self.maxCommittedUnits = maxCommittedUnits.map { max(0, $0) }
        self.exploitDepth = exploitDepth.map { max(0, $0) }
        self.rationale = rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            zoneId: try container.decode(FrontZoneId.self, forKey: .zoneId),
            category: try container.decode(CommandCategory.self, forKey: .category),
            tactic: try container.decodeIfPresent(TacticName.self, forKey: .tactic),
            priority: try container.decodeIfPresent(Int.self, forKey: .priority) ?? 50,
            targetTheaterId: try container.decodeIfPresent(TheaterId.self, forKey: .targetTheaterId),
            weightedRegions: try container.decodeIfPresent([RegionId].self, forKey: .weightedRegions) ?? [],
            focusRegionId: try container.decodeIfPresent(RegionId.self, forKey: .focusRegionId),
            supportRegionIds: try container.decodeIfPresent([RegionId].self, forKey: .supportRegionIds) ?? [],
            convergenceRegionId: try container.decodeIfPresent(RegionId.self, forKey: .convergenceRegionId),
            coordinatedZoneIds: try container.decodeIfPresent([FrontZoneId].self, forKey: .coordinatedZoneIds) ?? [],
            reserveBias: try container.decodeIfPresent(Int.self, forKey: .reserveBias) ?? 1,
            intensity: try container.decodeIfPresent(AttackIntensity.self, forKey: .intensity),
            maxCommittedUnits: try container.decodeIfPresent(Int.self, forKey: .maxCommittedUnits),
            exploitDepth: try container.decodeIfPresent(Int.self, forKey: .exploitDepth),
            rationale: try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        )
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

enum TheaterDirectiveDecoderError: Error, Equatable, LocalizedError {
    case invalidUTF8
    case malformedJSON(String)
    case unsupportedSchemaVersion(Int)
    case issuerMismatch(expected: String, actual: String)
    case turnMismatch(expected: Int, actual: Int)
    case factionMismatch(expected: Faction, actual: Faction)
    case missingZone(FrontZoneId)
    case zoneFactionMismatch(zoneId: FrontZoneId, expected: Faction, actual: Faction)
    case missingTargetTheater(TheaterId)
    case missingRegion(RegionId)
    case tacticCategoryMismatch(directiveId: String, tactic: TacticName, category: CommandCategory)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Operational directive JSON is not valid UTF-8."
        case .malformedJSON(let detail):
            return "Malformed operational directive JSON: \(detail)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported operational directive schemaVersion \(version)."
        case .issuerMismatch(let expected, let actual):
            return "Operational directive issuer mismatch. Expected \(expected), got \(actual)."
        case .turnMismatch(let expected, let actual):
            return "Operational directive turn mismatch. Expected \(expected), got \(actual)."
        case .factionMismatch(let expected, let actual):
            return "Operational directive faction mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .missingZone(let zoneId):
            return "Operational directive references missing command sector \(zoneId.rawValue)."
        case .zoneFactionMismatch(let zoneId, let expected, let actual):
            return "Operational directive command sector \(zoneId.rawValue) belongs to \(actual.displayName), expected \(expected.displayName)."
        case .missingTargetTheater(let theaterId):
            return "Operational directive references missing target operational zone \(theaterId.rawValue)."
        case .missingRegion(let regionId):
            return "Operational directive references missing sector \(regionId.rawValue)."
        case .tacticCategoryMismatch(let directiveId, let tactic, let category):
            return "Operational directive \(directiveId) uses tactic \(tactic.rawValue) outside category \(category.rawValue)."
        }
    }
}

struct TheaterDirectiveDecoder {
    let supportedSchemaVersions: Set<Int>
    private let decoder: JSONDecoder

    init(supportedSchemaVersions: Set<Int> = [5], decoder: JSONDecoder = JSONDecoder()) {
        self.supportedSchemaVersions = supportedSchemaVersions
        self.decoder = decoder
    }

    func parse(
        _ rawResponse: String,
        expectedIssuerId: String? = nil,
        expectedTurn: Int? = nil,
        expectedFaction: Faction? = nil,
        state: GameState
    ) throws -> TheaterDirectiveEnvelope {
        let json = extractJSON(from: rawResponse)
        guard let data = json.data(using: .utf8) else {
            throw TheaterDirectiveDecoderError.invalidUTF8
        }

        let envelope: TheaterDirectiveEnvelope
        do {
            envelope = try decoder.decode(TheaterDirectiveEnvelope.self, from: data)
        } catch {
            throw TheaterDirectiveDecoderError.malformedJSON(error.localizedDescription)
        }

        guard supportedSchemaVersions.contains(envelope.schemaVersion) else {
            throw TheaterDirectiveDecoderError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        if let expectedIssuerId, envelope.issuerId != expectedIssuerId {
            throw TheaterDirectiveDecoderError.issuerMismatch(expected: expectedIssuerId, actual: envelope.issuerId)
        }
        if let expectedTurn, envelope.turn != expectedTurn {
            throw TheaterDirectiveDecoderError.turnMismatch(expected: expectedTurn, actual: envelope.turn)
        }
        if let expectedFaction, envelope.faction != expectedFaction {
            throw TheaterDirectiveDecoderError.factionMismatch(expected: expectedFaction, actual: envelope.faction)
        }

        try validate(envelope, state: state)
        return envelope
    }

    func extractJSON(from rawResponse: String) -> String {
        if let fenced = fencedJSON(in: rawResponse, marker: "```json") {
            return fenced
        }
        if let fenced = fencedJSON(in: rawResponse, marker: "```") {
            return fenced
        }
        return rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(_ envelope: TheaterDirectiveEnvelope, state: GameState) throws {
        for directive in envelope.directives {
            guard let zone = state.warDeploymentState.frontZones[directive.zoneId] else {
                throw TheaterDirectiveDecoderError.missingZone(directive.zoneId)
            }
            guard zone.faction == envelope.faction else {
                throw TheaterDirectiveDecoderError.zoneFactionMismatch(
                    zoneId: zone.id,
                    expected: envelope.faction,
                    actual: zone.faction
                )
            }
            if let tactic = directive.tactic, tactic.category != directive.category {
                throw TheaterDirectiveDecoderError.tacticCategoryMismatch(
                    directiveId: directive.id,
                    tactic: tactic,
                    category: directive.category
                )
            }
            if let targetTheaterId = directive.targetTheaterId,
               state.theaterState.theaters[targetTheaterId] == nil,
               state.warDeploymentState.frontZones[FrontZoneId(targetTheaterId.rawValue)] == nil {
                throw TheaterDirectiveDecoderError.missingTargetTheater(targetTheaterId)
            }

            let regionIds = directive.weightedRegions
                + directive.supportRegionIds
                + [directive.focusRegionId, directive.convergenceRegionId].compactMap { $0 }
            for regionId in regionIds where state.map.region(id: regionId) == nil {
                throw TheaterDirectiveDecoderError.missingRegion(regionId)
            }
            for zoneId in directive.coordinatedZoneIds where state.warDeploymentState.frontZones[zoneId] == nil {
                throw TheaterDirectiveDecoderError.missingZone(zoneId)
            }
        }
    }

    private func fencedJSON(in rawResponse: String, marker: String) -> String? {
        guard let start = rawResponse.range(of: marker) else {
            return nil
        }
        let contentStart = start.upperBound
        guard let end = rawResponse[contentStart...].range(of: "```") else {
            return nil
        }
        return String(rawResponse[contentStart..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
