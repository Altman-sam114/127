import Foundation

enum ModernCommandAgentRole: String, Codable, Equatable, CaseIterable {
    case nationalCommand
    case jointCommand
    case chiefOfStaff
    case isrCoordinator
    case firesCoordinator
    case airTasking
    case ewCoordinator
    case logistics
    case brigadeCommander

    var displayName: String {
        switch self {
        case .nationalCommand:
            return "National Command"
        case .jointCommand:
            return "Joint Command"
        case .chiefOfStaff:
            return "Chief of Staff"
        case .isrCoordinator:
            return "ISR Coordinator"
        case .firesCoordinator:
            return "Fires Coordinator"
        case .airTasking:
            return "Air Tasking"
        case .ewCoordinator:
            return "EW Coordinator"
        case .logistics:
            return "Logistics"
        case .brigadeCommander:
            return "Brigade Commander"
        }
    }
}

enum ModernMissionType: String, Codable, Equatable, CaseIterable {
    case setROE
    case theaterObjective
    case deconflict
    case reconArea
    case confirmContact
    case fireMission
    case suppressAirDefense
    case airRecon
    case electronicWarfare
    case resupply
    case assault
    case hold
    case reserve

    var displayName: String {
        switch self {
        case .setROE:
            return "Set ROE"
        case .theaterObjective:
            return "Operational Objective"
        case .deconflict:
            return "Deconflict"
        case .reconArea:
            return "Recon Area"
        case .confirmContact:
            return "Confirm Contact"
        case .fireMission:
            return "Fire Mission"
        case .suppressAirDefense:
            return "Suppress Air Defense"
        case .airRecon:
            return "Air Recon"
        case .electronicWarfare:
            return "Electronic Warfare"
        case .resupply:
            return "Resupply"
        case .assault:
            return "Assault"
        case .hold:
            return "Hold"
        case .reserve:
            return "Reserve"
        }
    }
}

struct StrategicConstraintEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let issuerId: String
    let turn: Int
    let faction: Faction
    let role: ModernCommandAgentRole
    let roeSummary: String
    let riskTolerance: String
    let priorityObjectives: [String]
    let prohibitedActions: [String]
    let rationale: String

    init(
        schemaVersion: Int = 1,
        issuerId: String,
        turn: Int,
        faction: Faction,
        role: ModernCommandAgentRole = .nationalCommand,
        roeSummary: String,
        riskTolerance: String,
        priorityObjectives: [String],
        prohibitedActions: [String],
        rationale: String
    ) {
        self.schemaVersion = schemaVersion
        self.issuerId = issuerId
        self.turn = turn
        self.faction = faction
        self.role = role
        self.roeSummary = roeSummary
        self.riskTolerance = riskTolerance
        self.priorityObjectives = priorityObjectives.sorted()
        self.prohibitedActions = prohibitedActions.sorted()
        self.rationale = rationale
    }
}

struct ModernSubDirective: Identifiable, Codable, Equatable {
    let id: String
    let role: ModernCommandAgentRole
    let missionType: ModernMissionType
    let zoneId: FrontZoneId?
    let regionId: RegionId?
    let contactId: String?
    let priority: Int
    let rationale: String

    init(
        id: String,
        role: ModernCommandAgentRole,
        missionType: ModernMissionType,
        zoneId: FrontZoneId? = nil,
        regionId: RegionId? = nil,
        contactId: String? = nil,
        priority: Int,
        rationale: String
    ) {
        self.id = id
        self.role = role
        self.missionType = missionType
        self.zoneId = zoneId
        self.regionId = regionId
        self.contactId = contactId
        self.priority = max(0, min(100, priority))
        self.rationale = rationale
    }
}

struct JointCommandPlan: Codable, Equatable {
    let schemaVersion: Int
    let issuerId: String
    let turn: Int
    let faction: Faction
    let role: ModernCommandAgentRole
    let strategicIntent: String
    let theaterDirectiveIds: [String]
    let subDirectives: [ModernSubDirective]
    let rationale: String

    init(
        schemaVersion: Int = 1,
        issuerId: String,
        turn: Int,
        faction: Faction,
        role: ModernCommandAgentRole = .jointCommand,
        strategicIntent: String,
        theaterDirectiveIds: [String],
        subDirectives: [ModernSubDirective],
        rationale: String
    ) {
        self.schemaVersion = schemaVersion
        self.issuerId = issuerId
        self.turn = turn
        self.faction = faction
        self.role = role
        self.strategicIntent = strategicIntent
        self.theaterDirectiveIds = theaterDirectiveIds.sorted()
        self.subDirectives = subDirectives.sorted {
            if $0.priority == $1.priority {
                return $0.id < $1.id
            }
            return $0.priority > $1.priority
        }
        self.rationale = rationale
    }
}

struct ModernCommandChainPlan: Codable, Equatable {
    let schemaVersion: Int
    let issuerId: String
    let turn: Int
    let faction: Faction
    let strategicConstraints: StrategicConstraintEnvelope
    let jointPlan: JointCommandPlan
    let chiefOfStaffNotes: [String]
    let compiledZoneDirectiveCount: Int
    let summary: String

    init(
        schemaVersion: Int = 1,
        issuerId: String,
        turn: Int,
        faction: Faction,
        strategicConstraints: StrategicConstraintEnvelope,
        jointPlan: JointCommandPlan,
        chiefOfStaffNotes: [String],
        compiledZoneDirectiveCount: Int,
        summary: String
    ) {
        self.schemaVersion = schemaVersion
        self.issuerId = issuerId
        self.turn = turn
        self.faction = faction
        self.strategicConstraints = strategicConstraints
        self.jointPlan = jointPlan
        self.chiefOfStaffNotes = chiefOfStaffNotes
        self.compiledZoneDirectiveCount = max(0, compiledZoneDirectiveCount)
        self.summary = summary
    }
}

enum ModernCommandChainDecoderError: Error, Equatable, LocalizedError {
    case invalidUTF8
    case malformedJSON(String)
    case unsupportedSchemaVersion(Int)
    case issuerMismatch(expected: String, actual: String)
    case turnMismatch(expected: Int, actual: Int)
    case factionMismatch(expected: Faction, actual: Faction)
    case missingZone(FrontZoneId)
    case zoneFactionMismatch(zoneId: FrontZoneId, expected: Faction, actual: Faction)
    case missingRegion(RegionId)
    case missingContact(String)
    case contactOwnerMismatch(contactId: String, expected: Faction)
    case invalidEnvelopeRole(component: String, expected: ModernCommandAgentRole, actual: ModernCommandAgentRole)
    case invalidRoleMission(role: ModernCommandAgentRole, missionType: ModernMissionType)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Modern command chain JSON is not valid UTF-8."
        case .malformedJSON(let detail):
            return "Malformed modern command chain JSON: \(detail)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported modern command chain schemaVersion \(version)."
        case .issuerMismatch(let expected, let actual):
            return "Modern command chain issuer mismatch. Expected \(expected), got \(actual)."
        case .turnMismatch(let expected, let actual):
            return "Modern command chain turn mismatch. Expected \(expected), got \(actual)."
        case .factionMismatch(let expected, let actual):
            return "Modern command chain faction mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .missingZone(let zoneId):
            return "Modern command chain references missing \(Self.commandSectorDisplay(zoneId))."
        case .zoneFactionMismatch(let zoneId, let expected, let actual):
            return "Modern command chain \(Self.commandSectorDisplay(zoneId)) belongs to \(actual.displayName), expected \(expected.displayName)."
        case .missingRegion(let regionId):
            return "Modern command chain references missing \(Self.objectiveDisplay(regionId))."
        case .missingContact(let contactId):
            return "Modern command chain references missing \(Self.contactDisplay(contactId))."
        case .contactOwnerMismatch(let contactId, let expected):
            return "Modern command chain \(Self.contactDisplay(contactId)) is not visible to \(expected.displayName)."
        case .invalidEnvelopeRole(let component, let expected, let actual):
            return "Modern command chain \(component) role mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .invalidRoleMission(let role, let missionType):
            return "Modern command chain role \(role.displayName) cannot issue \(missionType.displayName)."
        }
    }

    private static func commandSectorDisplay(_ id: FrontZoneId) -> String {
        let cleaned = cleanIdentifier(id.rawValue)
        return cleaned.isEmpty ? "command sector" : "Sector \(cleaned.capitalized)"
    }

    private static func objectiveDisplay(_ id: RegionId) -> String {
        let cleaned = cleanIdentifier(id.rawValue)
        return cleaned.isEmpty ? "objective area" : "Objective \(cleaned.capitalized)"
    }

    private static func contactDisplay(_ id: String) -> String {
        let cleaned = cleanIdentifier(id)
        return cleaned.isEmpty ? "contact track" : "Contact Track \(cleaned.capitalized)"
    }

    private static func cleanIdentifier(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "region_", with: "")
            .replacingOccurrences(of: "objective_", with: "")
            .replacingOccurrences(of: "front_zone_", with: "")
            .replacingOccurrences(of: "zone_", with: "")
            .replacingOccurrences(of: "theater_", with: "")
            .replacingOccurrences(of: "contact_", with: "")
            .replacingOccurrences(of: "ct_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ModernCommandChainDecoder {
    let supportedSchemaVersions: Set<Int>
    private let decoder: JSONDecoder

    init(supportedSchemaVersions: Set<Int> = [1], decoder: JSONDecoder = JSONDecoder()) {
        self.supportedSchemaVersions = supportedSchemaVersions
        self.decoder = decoder
    }

    func parse(
        _ rawResponse: String,
        expectedIssuerId: String,
        expectedTurn: Int,
        expectedFaction: Faction,
        state: GameState
    ) throws -> ModernCommandChainPlan {
        let json = extractJSON(from: rawResponse)
        guard let data = json.data(using: .utf8) else {
            throw ModernCommandChainDecoderError.invalidUTF8
        }

        let plan: ModernCommandChainPlan
        do {
            plan = try decoder.decode(ModernCommandChainPlan.self, from: data)
        } catch {
            throw ModernCommandChainDecoderError.malformedJSON(error.localizedDescription)
        }

        guard supportedSchemaVersions.contains(plan.schemaVersion) else {
            throw ModernCommandChainDecoderError.unsupportedSchemaVersion(plan.schemaVersion)
        }
        guard plan.issuerId == expectedIssuerId else {
            throw ModernCommandChainDecoderError.issuerMismatch(expected: expectedIssuerId, actual: plan.issuerId)
        }
        guard plan.turn == expectedTurn else {
            throw ModernCommandChainDecoderError.turnMismatch(expected: expectedTurn, actual: plan.turn)
        }
        guard plan.faction == expectedFaction else {
            throw ModernCommandChainDecoderError.factionMismatch(expected: expectedFaction, actual: plan.faction)
        }

        try validate(plan, expectedFaction: expectedFaction, state: state)
        return plan
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

    private func validate(
        _ plan: ModernCommandChainPlan,
        expectedFaction: Faction,
        state: GameState
    ) throws {
        try validateEnvelopeMetadata(
            component: "strategicConstraints",
            schemaVersion: plan.strategicConstraints.schemaVersion,
            issuerId: plan.strategicConstraints.issuerId,
            turn: plan.strategicConstraints.turn,
            faction: plan.strategicConstraints.faction,
            role: plan.strategicConstraints.role,
            expectedRole: .nationalCommand,
            expectedIssuerId: plan.issuerId,
            expectedTurn: plan.turn,
            expectedFaction: expectedFaction
        )
        try validateEnvelopeMetadata(
            component: "jointPlan",
            schemaVersion: plan.jointPlan.schemaVersion,
            issuerId: plan.jointPlan.issuerId,
            turn: plan.jointPlan.turn,
            faction: plan.jointPlan.faction,
            role: plan.jointPlan.role,
            expectedRole: .jointCommand,
            expectedIssuerId: plan.issuerId,
            expectedTurn: plan.turn,
            expectedFaction: expectedFaction
        )
        for directive in plan.jointPlan.subDirectives {
            try validateRoleMission(directive)
            if let zoneId = directive.zoneId {
                guard let zone = state.warDeploymentState.frontZones[zoneId] else {
                    throw ModernCommandChainDecoderError.missingZone(zoneId)
                }
                guard zone.faction == expectedFaction else {
                    throw ModernCommandChainDecoderError.zoneFactionMismatch(
                        zoneId: zoneId,
                        expected: expectedFaction,
                        actual: zone.faction
                    )
                }
            }
            if let regionId = directive.regionId,
               state.map.region(id: regionId) == nil {
                throw ModernCommandChainDecoderError.missingRegion(regionId)
            }
            if let contactId = directive.contactId {
                guard let contact = state.operationalAwareness.contacts[contactId] else {
                    throw ModernCommandChainDecoderError.missingContact(contactId)
                }
                guard contact.ownerFaction == expectedFaction else {
                    throw ModernCommandChainDecoderError.contactOwnerMismatch(
                        contactId: contactId,
                        expected: expectedFaction
                    )
                }
            }
        }
    }

    private func validateEnvelopeMetadata(
        component: String,
        schemaVersion: Int,
        issuerId: String,
        turn: Int,
        faction: Faction,
        role: ModernCommandAgentRole,
        expectedRole: ModernCommandAgentRole,
        expectedIssuerId: String,
        expectedTurn: Int,
        expectedFaction: Faction
    ) throws {
        guard supportedSchemaVersions.contains(schemaVersion) else {
            throw ModernCommandChainDecoderError.unsupportedSchemaVersion(schemaVersion)
        }
        guard issuerId == expectedIssuerId else {
            throw ModernCommandChainDecoderError.issuerMismatch(expected: expectedIssuerId, actual: issuerId)
        }
        guard turn == expectedTurn else {
            throw ModernCommandChainDecoderError.turnMismatch(expected: expectedTurn, actual: turn)
        }
        guard faction == expectedFaction else {
            throw ModernCommandChainDecoderError.factionMismatch(expected: expectedFaction, actual: faction)
        }
        guard role == expectedRole else {
            throw ModernCommandChainDecoderError.invalidEnvelopeRole(
                component: component,
                expected: expectedRole,
                actual: role
            )
        }
    }

    private func validateRoleMission(_ directive: ModernSubDirective) throws {
        let allowed: Set<ModernMissionType>
        switch directive.role {
        case .nationalCommand:
            allowed = [.setROE]
        case .jointCommand:
            allowed = [.theaterObjective]
        case .chiefOfStaff:
            allowed = [.deconflict, .reserve]
        case .isrCoordinator:
            allowed = [.reconArea, .confirmContact, .airRecon]
        case .firesCoordinator:
            allowed = [.fireMission, .suppressAirDefense]
        case .airTasking:
            allowed = [.airRecon, .suppressAirDefense, .fireMission]
        case .ewCoordinator:
            allowed = [.electronicWarfare]
        case .logistics:
            allowed = [.resupply, .reserve]
        case .brigadeCommander:
            allowed = [.assault, .hold, .reserve]
        }
        guard allowed.contains(directive.missionType) else {
            throw ModernCommandChainDecoderError.invalidRoleMission(
                role: directive.role,
                missionType: directive.missionType
            )
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

struct ModernCommandChainOrchestrator {
    func makePlan(
        summary: MarshalBattlefieldSummary,
        theaterEnvelope: TheaterDirectiveEnvelope,
        state: GameState
    ) -> ModernCommandChainPlan {
        let constraints = makeConstraints(summary: summary)
        let subDirectives = makeSubDirectives(
            summary: summary,
            theaterEnvelope: theaterEnvelope,
            state: state
        )
        let jointPlan = JointCommandPlan(
            issuerId: theaterEnvelope.issuerId,
            turn: theaterEnvelope.turn,
            faction: theaterEnvelope.faction,
            strategicIntent: theaterEnvelope.strategicIntent,
            theaterDirectiveIds: theaterEnvelope.directives.map(\.id),
            subDirectives: subDirectives,
            rationale: "Joint command decomposed operational directives into ISR, fires, air, EW, logistics, and brigade tasks."
        )
        let notes = chiefOfStaffNotes(theaterEnvelope: theaterEnvelope, subDirectives: subDirectives)
        return ModernCommandChainPlan(
            issuerId: theaterEnvelope.issuerId,
            turn: theaterEnvelope.turn,
            faction: theaterEnvelope.faction,
            strategicConstraints: constraints,
            jointPlan: jointPlan,
            chiefOfStaffNotes: notes,
            compiledZoneDirectiveCount: theaterEnvelope.directives.count,
            summary: "\(summary.marshalName): \(subDirectives.count) coordinated sub-directive(s), \(theaterEnvelope.directives.count) operational directive(s)."
        )
    }

    func fencedJSON(for plan: ModernCommandChainPlan) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(plan)
        return "```json\n\(String(decoding: data, as: UTF8.self))\n```"
    }

    private func makeConstraints(summary: MarshalBattlefieldSummary) -> StrategicConstraintEnvelope {
        let riskTolerance: String
        switch summary.strategicBias {
        case .offensive:
            riskTolerance = summary.friendlyEncircledCount > 0 ? "controlled" : "elevated"
        case .balanced:
            riskTolerance = "controlled"
        case .defensive:
            riskTolerance = "low"
        }
        let priorities = (summary.objectivesLost + summary.objectivesHeld).isEmpty
            ? ["preserve combat power", "maintain front cohesion"]
            : summary.objectivesLost + summary.objectivesHeld
        return StrategicConstraintEnvelope(
            issuerId: summary.marshalId,
            turn: summary.turn,
            faction: summary.faction,
            roeSummary: "Hostile contacts may be engaged only through validated Command or ZoneDirective pipelines.",
            riskTolerance: riskTolerance,
            priorityObjectives: priorities,
            prohibitedActions: [
                "direct GameState mutation",
                "strike without sufficient contact quality",
                "execute malformed JSON",
                "bypass RuleEngine"
            ],
            rationale: "National command preserves ROE while allowing modern joint tasks inside existing rules."
        )
    }

    private func makeSubDirectives(
        summary: MarshalBattlefieldSummary,
        theaterEnvelope: TheaterDirectiveEnvelope,
        state: GameState
    ) -> [ModernSubDirective] {
        var directives: [ModernSubDirective] = []
        directives.append(
            ModernSubDirective(
                id: "roe_\(summary.turn)_\(summary.faction.rawValue)",
                role: .nationalCommand,
                missionType: .setROE,
                priority: 100,
                rationale: "All downstream agents must emit Codable directives and never mutate state directly."
            )
        )

        for theaterDirective in theaterEnvelope.directives {
            directives.append(
                ModernSubDirective(
                    id: "joint_\(theaterDirective.id)",
                    role: .jointCommand,
                    missionType: .theaterObjective,
                    zoneId: theaterDirective.zoneId,
                    regionId: theaterDirective.focusRegionId ?? theaterDirective.weightedRegions.first,
                    priority: theaterDirective.priority,
                    rationale: theaterDirective.rationale
                )
            )
            directives.append(contentsOf: coordinatorDirectives(
                theaterDirective: theaterDirective,
                summary: summary,
                state: state
            ))
        }

        if summary.friendlyLowSupplyCount > 0 || summary.friendlyEncircledCount > 0 {
            directives.append(
                ModernSubDirective(
                    id: "logistics_\(summary.turn)_\(summary.faction.rawValue)",
                    role: .logistics,
                    missionType: .resupply,
                    priority: 85,
                    rationale: "Supply state reports \(summary.friendlyLowSupplyCount) low-supply and \(summary.friendlyEncircledCount) encircled friendly unit(s)."
                )
            )
        }

        return stableUnique(directives)
    }

    private func coordinatorDirectives(
        theaterDirective: TheaterDirective,
        summary: MarshalBattlefieldSummary,
        state: GameState
    ) -> [ModernSubDirective] {
        var directives: [ModernSubDirective] = []
        let targetRegionIds = stableUnique(
            [theaterDirective.focusRegionId].compactMap { $0 }
            + theaterDirective.weightedRegions
            + theaterDirective.supportRegionIds
        )
        let contact = bestContact(in: targetRegionIds, faction: summary.faction, state: state)
        let regionId = targetRegionIds.first

        if contact == nil || contact?.confidence == .low {
            directives.append(
                ModernSubDirective(
                    id: "isr_\(theaterDirective.id)",
                    role: .isrCoordinator,
                    missionType: .reconArea,
                    zoneId: theaterDirective.zoneId,
                    regionId: regionId,
                    priority: max(60, theaterDirective.priority),
                    rationale: "ISR must confirm contacts before fires or ground commitment."
                )
            )
        } else if let contact {
            directives.append(
                ModernSubDirective(
                    id: "isr_confirm_\(theaterDirective.id)",
                    role: .isrCoordinator,
                    missionType: .confirmContact,
                    zoneId: theaterDirective.zoneId,
                    regionId: state.map.region(for: contact.lastKnownCoord),
                    contactId: contact.id,
                    priority: max(55, theaterDirective.priority - 5),
                    rationale: "\(contactDisplay(contact.id)) has \(contact.confidence.displayName) confidence and can seed follow-on tasks."
                )
            )
        }

        if let contact,
           theaterDirective.category == .offense {
            directives.append(
                ModernSubDirective(
                    id: "fires_\(theaterDirective.id)",
                    role: .firesCoordinator,
                    missionType: .fireMission,
                    zoneId: theaterDirective.zoneId,
                    regionId: state.map.region(for: contact.lastKnownCoord),
                    contactId: contact.id,
                    priority: max(50, theaterDirective.priority - 10),
                    rationale: "Fires coordinator can request a validated fire mission against the visible contact."
                )
            )
        }

        if contact?.estimatedType == .airDefense || hasAirDefenseContact(in: targetRegionIds, faction: summary.faction, state: state) {
            directives.append(
                ModernSubDirective(
                    id: "air_sead_\(theaterDirective.id)",
                    role: .airTasking,
                    missionType: .suppressAirDefense,
                    zoneId: theaterDirective.zoneId,
                    regionId: regionId,
                    contactId: contact?.id,
                    priority: max(50, theaterDirective.priority - 8),
                    rationale: "Air tasking must suppress observed air-defense risk before UAV or precision strike tasks."
                )
            )
        }

        if hasEWAsset(faction: summary.faction, state: state),
           theaterDirective.category == .offense {
            directives.append(
                ModernSubDirective(
                    id: "ew_\(theaterDirective.id)",
                    role: .ewCoordinator,
                    missionType: .electronicWarfare,
                    zoneId: theaterDirective.zoneId,
                    regionId: regionId,
                    priority: max(45, theaterDirective.priority - 15),
                    rationale: "EW coordinator can degrade enemy sensors before maneuver."
                )
            )
        }

        directives.append(
            ModernSubDirective(
                id: "brigade_\(theaterDirective.id)",
                role: .brigadeCommander,
                missionType: theaterDirective.category == .offense ? .assault : .hold,
                zoneId: theaterDirective.zoneId,
                regionId: regionId,
                priority: theaterDirective.priority,
                rationale: "Brigade commander converts joint intent into ZoneDirective execution."
            )
        )
        return directives
    }

    private func chiefOfStaffNotes(
        theaterEnvelope: TheaterDirectiveEnvelope,
        subDirectives: [ModernSubDirective]
    ) -> [String] {
        let zones = Set(theaterEnvelope.directives.map(\.zoneId))
        return [
            "ChiefOfStaffAgent deconflicted \(theaterEnvelope.directives.count) operational directive(s) across \(zones.count) zone(s).",
            "Sub-directives are advisory and compile back to ZoneDirective or Command before execution.",
            "No two coordinator roles execute directly; WarCommandExecutor and RuleEngine remain final authority.",
            "Generated \(subDirectives.count) auditable coordinator task(s)."
        ]
    }

    private func bestContact(
        in regionIds: [RegionId],
        faction: Faction,
        state: GameState
    ) -> ContactTrack? {
        let regionSet = Set(regionIds)
        return state.operationalAwareness.visibleContacts(for: faction)
            .filter { contact in
                if regionSet.isEmpty {
                    return contact.confidence >= .medium
                }
                guard let regionId = state.map.region(for: contact.lastKnownCoord) else {
                    return false
                }
                return regionSet.contains(regionId) && contact.confidence >= .medium
            }
            .first
    }

    private func contactDisplay(_ id: String) -> String {
        let cleaned = id
            .replacingOccurrences(of: "contact_", with: "")
            .replacingOccurrences(of: "ct_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Contact Track" : "Contact Track \(cleaned.capitalized)"
    }

    private func hasAirDefenseContact(
        in regionIds: [RegionId],
        faction: Faction,
        state: GameState
    ) -> Bool {
        let regionSet = Set(regionIds)
        return state.operationalAwareness.visibleContacts(for: faction).contains { contact in
            guard contact.estimatedType == .airDefense else {
                return false
            }
            if regionSet.isEmpty {
                return true
            }
            guard let regionId = state.map.region(for: contact.lastKnownCoord) else {
                return false
            }
            return regionSet.contains(regionId)
        }
    }

    private func hasEWAsset(faction: Faction, state: GameState) -> Bool {
        state.divisions.contains {
            $0.faction == faction &&
                !$0.isDestroyed &&
                $0.componentWeight(where: { $0 == .electronicWarfare }) >= 0.15
        }
    }

    private func stableUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func stableUnique(_ values: [ModernSubDirective]) -> [ModernSubDirective] {
        var seen: Set<String> = []
        var result: [ModernSubDirective] = []
        for value in values where !seen.contains(value.id) {
            seen.insert(value.id)
            result.append(value)
        }
        return result.sorted {
            if $0.priority == $1.priority {
                return $0.id < $1.id
            }
            return $0.priority > $1.priority
        }
    }
}
