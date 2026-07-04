import XCTest
@testable import WWIIHexV0

final class Stage035CampaignSimulationTests: XCTestCase {
    @MainActor
    func testV0354RealAppContainerAlliedSkipGermanActivityProbe() async throws {
        let container = AppContainer.bootstrap()
        var reports: [RealAppTurnReport] = []
        container.runAIIfNeeded()
        try await Self.waitForGermanAIToReturnToAllies(
            container,
            expectedMinimumTurn: container.gameState.turn
        )

        for step in 1...12 {
            let before = RealAppSnapshot(state: container.gameState)
            container.endTurn()
            try await Self.waitForGermanAIToReturnToAllies(container, expectedMinimumTurn: before.turn + 1)
            let after = RealAppSnapshot(state: container.gameState)
            let records = container.lastWarDirectiveRecords.filter { $0.faction == .germany }
            reports.append(
                RealAppTurnReport(
                    step: step,
                    startTurn: before.turn,
                    endTurn: after.turn,
                    directives: records.map(Self.realDirectiveSummary),
                    germanCommands: records.flatMap(\.commandResults).compactMap(\.commandDisplayName),
                    germanMovedUnitIds: before.movedGermanUnitIds(comparedTo: after),
                    damagedAlliedUnitIds: before.damagedAlliedUnitIds(comparedTo: after),
                    germanDeployment: Self.germanDeploymentSummary(in: container.gameState),
                    activeFaction: container.gameState.activeFaction,
                    phase: container.gameState.phase,
                    lastMessage: container.lastCommandMessage ?? ""
                )
            )
        }

        let report = reports.map(\.summaryLine).joined(separator: "\n")
        print("v0.354 real AppContainer allied-skip report\n\(report)")

        let afterTurnSix = reports.filter { $0.step >= 6 }
        XCTAssertTrue(
            afterTurnSix.contains { !$0.germanMovedUnitIds.isEmpty || !$0.damagedAlliedUnitIds.isEmpty },
            "German AI produced no real movement or allied damage after step 6.\n\(report)"
        )
    }

    func testV0354TwelveTurnDiagnosticObserverSimulation() throws {
        let completion = DispatchSemaphore(value: 0)
        var result: Result<CampaignDiagnosticSummary, Error>?

        Task {
            do {
                let summary = try await self.runObserverSimulation(turns: 20, reportPath: "/private/tmp/wwiihex_v0354_diagnostic_report.txt")
                result = .success(summary)
            } catch {
                result = .failure(error)
            }
            completion.signal()
        }

        XCTAssertEqual(completion.wait(timeout: .now() + 90), .success)
        let summary = try XCTUnwrap(result?.get())

        XCTAssertGreaterThan(summary.germanRecordsAfterTurnSix, 0, "Germany stopped generating directives after turn 6.")
        XCTAssertTrue(summary.changedRegionInSameTurn, "No same-turn region controller changes were observed.")
        XCTAssertLessThan(summary.rejectionRatio, 0.41, "v0.354 should reduce the 41% rejected-command baseline.")
        if summary.rejectionRatio > 0 {
            XCTAssertFalse(summary.rejectionReasons.isEmpty, "Diagnostic run should classify rejected command reasons when any commands are rejected.")
        }
    }

    func testDefaultMapRunsThirtyFiveTurnObserverSimulation() throws {
        let completion = DispatchSemaphore(value: 0)
        var result: Result<Void, Error>?

        Task {
            do {
                try await self.runThirtyFiveTurnObserverSimulation()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            completion.signal()
        }

        XCTAssertEqual(completion.wait(timeout: .now() + 180), .success)
        switch result {
        case .success:
            break
        case .failure(let error):
            throw error
        case .none:
            XCTFail("35-turn observer simulation did not return a result.")
        }
    }

    private func runThirtyFiveTurnObserverSimulation() async throws {
        _ = try await runObserverSimulation(turns: 35, reportPath: "/private/tmp/wwiihex_v0353_campaign_report.txt")
    }

    private func runObserverSimulation(turns: Int, reportPath: String) async throws -> CampaignDiagnosticSummary {
        var state = DataLoader().loadInitialGameState()
        state.maxTurns = max(state.maxTurns, state.turn + turns + 5)
        state = Self.refreshStrategicState(state)

        let initialControllers = state.map.regions.mapValues(\.controller)
        var allRecords: [WarDirectiveRecord] = []
        var reports: [CampaignTurnReport] = []
        var previousSupplyCounts = Self.supplyCounts(in: state)
        var observedSupplyChange = false
        var observedCapturedSupplyAvailable = false
        var sameTurnRegionChangeObserved = false

        for step in 1...turns {
            let clickStartTurn = state.turn
            let beforeControllers = state.map.regions.mapValues(\.controller)
            let beforeDivisionIds = Set(state.divisions.map(\.id))
            var clickRecords: [WarDirectiveRecord] = []
            var clickCommandResults: [CommandResultSummary] = []

            let germanOutcome = await Self.runAITurn(state, faction: .germany)
            state = Self.refreshStrategicState(germanOutcome.state)
            clickRecords.append(contentsOf: germanOutcome.directiveRecords)
            clickCommandResults.append(contentsOf: germanOutcome.record.commandResults)

            let alliedOutcome = await Self.runAITurn(state, faction: .allies)
            state = Self.refreshStrategicState(alliedOutcome.state)
            clickRecords.append(contentsOf: alliedOutcome.directiveRecords)
            clickCommandResults.append(contentsOf: alliedOutcome.record.commandResults)
            allRecords.append(contentsOf: clickRecords)

            let supplyCounts = Self.supplyCounts(in: state)
            if supplyCounts != previousSupplyCounts {
                observedSupplyChange = true
            }
            previousSupplyCounts = supplyCounts

            let ownerChanges = state.map.regions
                .filter { regionId, region in beforeControllers[regionId] != region.controller }
                .map(\.key)
                .sorted { $0.rawValue < $1.rawValue }
            if !ownerChanges.isEmpty && Self.capturedSupplyIsAvailable(in: state, changedRegionIds: ownerChanges) {
                observedCapturedSupplyAvailable = true
            }
            if !ownerChanges.isEmpty {
                sameTurnRegionChangeObserved = true
            }

            let destroyedIds = Array(beforeDivisionIds.subtracting(Set(state.divisions.map(\.id)))).sorted()
            reports.append(
                CampaignTurnReport(
                    step: step,
                    startTurn: clickStartTurn,
                    endTurn: state.turn,
                    theaterSummary: Self.theaterSummary(in: state),
                    directivesByFaction: Self.directiveSummary(clickRecords),
                    commandCounts: Self.commandCounts(clickCommandResults),
                    rejectedCommands: Self.rejectedCommandCount(clickCommandResults),
                    ownerChanges: ownerChanges,
                    supplyCounts: supplyCounts,
                    destroyedDivisionIds: destroyedIds,
                    consistencyErrors: Self.consistencyErrors(in: state)
                )
            )

            XCTAssertEqual(state.turn, clickStartTurn + 1, "Observer mode must advance exactly one turn per simulated click.")
            XCTAssertTrue(reports.last?.consistencyErrors.isEmpty == true)
        }

        let directiveTypes = allRecords.compactMap(\.directiveType)
        XCTAssertGreaterThan(directiveTypes.count, 0)
        XCTAssertTrue(directiveTypes.contains(.attack), "\(turns)-turn run produced no attack directive.")
        XCTAssertTrue(directiveTypes.contains(.defend), "\(turns)-turn run produced no defend directive.")

        let changedRegion = state.map.regions.contains { regionId, region in
            initialControllers[regionId] != region.controller
        }
        XCTAssertTrue(changedRegion, "\(turns)-turn run produced no region controller changes.")
        XCTAssertFalse(Self.hasAttackWithdrawOscillation(records: allRecords, limit: max(4, turns / 2)))
        XCTAssertTrue(observedSupplyChange || reports.contains { report in
            report.supplyCounts.germany.lowSupply + report.supplyCounts.germany.encircled + report.supplyCounts.allies.lowSupply + report.supplyCounts.allies.encircled > 0
        }, "\(turns)-turn run never observed lowSupply/encircled appearance or resolution.")
        if turns >= 35 {
            XCTAssertTrue(observedCapturedSupplyAvailable, "\(turns)-turn run never observed captured supply becoming available to the occupier.")
        }

        let report = Self.renderReport(reports: reports, records: allRecords)
        try report.write(
            to: URL(fileURLWithPath: reportPath),
            atomically: true,
            encoding: .utf8
        )
        print(report)
        return CampaignDiagnosticSummary(
            germanRecordsAfterTurnSix: allRecords.filter { $0.faction == .germany && $0.turn > 6 }.count,
            changedRegionInSameTurn: sameTurnRegionChangeObserved,
            rejectionRatio: Self.rejectionRatio(reports: reports),
            rejectionReasons: Self.rejectionReasons(records: allRecords)
        )
    }

    private static func runAITurn(_ state: GameState, faction: Faction) async -> AgentTurnOutcome {
        var prepared = state
        prepared.activeFaction = faction
        prepared.phase = faction == .germany ? .germanAI : .alliedPlayer

        let agent: GameAgent
        switch faction {
        case .germany:
            agent = GameAgent.guderianFallback(
                assignedDivisionIds: prepared.divisions.filter { $0.faction == .germany && !$0.isDestroyed }.map(\.id)
            )
        case .allies:
            agent = GameAgent.sample(
                id: "allied_observer_commander",
                name: "Allied Observer Commander",
                faction: .allies,
                role: .armyCommander,
                assignedDivisionIds: prepared.divisions.filter { $0.faction == .allies && !$0.isDestroyed }.map(\.id)
            )
        }

        let manager = TurnManager(
            agent: agent,
            provider: MockAIClient(),
            providerName: "MockAI",
            commandHandler: RuleEngine(),
            commanderPool: TheaterCommanderPool.automatic(for: prepared)
        )
        return await manager.runAITurn(state: prepared, faction: faction, pipelineMode: .zoneDirective)
    }

    private static func refreshStrategicState(_ state: GameState) -> GameState {
        var next = state
        _ = RegionOccupationRules().aggregateControl(in: &next)
        next.theaterState = TheaterSystem().updateTheaters(
            state: next.theaterState,
            map: next.map,
            divisions: next.divisions,
            turn: next.turn
        )
        next.frontLineState = FrontLineManager().makeInitialState(
            map: next.map,
            theaterState: next.theaterState,
            divisions: next.divisions,
            turn: next.turn
        )
        next.warDeploymentState = WarDeploymentManager().makeInitialState(
            map: next.map,
            theaterState: next.theaterState,
            divisions: next.divisions,
            turn: next.turn
        )
        return StrategicStateBootstrapper().bootstrapIfNeeded(next)
    }

    private static func theaterSummary(in state: GameState) -> String {
        state.theaterState.theaters.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { theater in
                let faction = theater.controllingFaction?.rawValue ?? "nil"
                let german = theater.controlRatios[.germany] ?? 0
                let allies = theater.controlRatios[.allies] ?? 0
                return "\(theater.id.rawValue)=\(faction)(G:\(Self.percent(german)),A:\(Self.percent(allies)))"
            }
            .joined(separator: " ")
    }

    private static func directiveSummary(_ records: [WarDirectiveRecord]) -> [Faction: [DirectiveType]] {
        var result: [Faction: [DirectiveType]] = [:]
        for record in records {
            guard let type = record.directiveType else { continue }
            result[record.faction, default: []].append(type)
        }
        return result
    }

    private static func commandCounts(_ summaries: [CommandResultSummary]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for summary in summaries {
            guard let name = summary.commandDisplayName else { continue }
            let type: String
            if name.hasPrefix("Move") {
                type = "move"
            } else if name.hasPrefix("Attack") {
                type = "attack"
            } else if name.hasPrefix("Hold") {
                type = "hold"
            } else if name.hasPrefix("AllowRetreat") {
                type = "allowRetreat"
            } else if name.hasPrefix("End Turn") {
                type = "endTurn"
            } else {
                type = "other"
            }
            counts[type, default: 0] += 1
        }
        return counts
    }

    private static func rejectedCommandCount(_ summaries: [CommandResultSummary]) -> Int {
        summaries.filter { $0.validationSucceeded == false || !$0.executed }.count
    }

    private static func rejectionRatio(reports: [CampaignTurnReport]) -> Double {
        let totalCommands = reports.reduce(0) { $0 + $1.commandCounts.values.reduce(0, +) }
        let rejected = reports.reduce(0) { $0 + $1.rejectedCommands }
        return totalCommands == 0 ? 0 : Double(rejected) / Double(totalCommands)
    }

    private static func rejectionReasons(records: [WarDirectiveRecord]) -> [String: Int] {
        var reasons: [String: Int] = [:]
        for record in records {
            for result in record.commandResults where result.validationSucceeded == false || !result.executed {
                for error in result.errors {
                    reasons[error, default: 0] += 1
                }
            }
        }
        return reasons
    }

    private static func supplyCounts(in state: GameState) -> FactionSupplyCounts {
        var counts = FactionSupplyCounts()
        for division in state.divisions where !division.isDestroyed {
            counts.increment(faction: division.faction, supplyState: division.supplyState)
        }
        return counts
    }

    private static func capturedSupplyIsAvailable(in state: GameState, changedRegionIds: [RegionId]) -> Bool {
        for source in state.map.supplySources {
            guard let regionId = state.map.region(for: source.coord),
                  changedRegionIds.contains(regionId),
                  let region = state.map.regions[regionId] else {
                continue
            }
            if state.map.controllingFaction(for: source) == region.controller {
                return true
            }
        }
        return false
    }

    private static func consistencyErrors(in state: GameState) -> [String] {
        var errors = state.map.validateRegionGraph().map(\.description)
        for (regionId, theaterId) in state.theaterState.regionToTheater {
            if state.map.regions[regionId] == nil {
                errors.append("Missing region \(regionId.rawValue) in theater map.")
            }
            if state.theaterState.theaters[theaterId] == nil {
                errors.append("Missing theater \(theaterId.rawValue).")
            }
        }
        for (regionId, zoneId) in state.warDeploymentState.regionToFrontZone {
            if state.map.regions[regionId] == nil {
                errors.append("Missing region \(regionId.rawValue) in front zone map.")
            }
            if state.warDeploymentState.frontZones[zoneId] == nil {
                errors.append("Missing zone \(zoneId.rawValue).")
            }
        }
        return errors
    }

    private static func hasAttackWithdrawOscillation(records: [WarDirectiveRecord], limit: Int) -> Bool {
        var streak = 0
        var previousKey: String?
        for record in records where record.zoneId != nil && record.directiveType != nil {
            let key = "\(record.zoneId?.rawValue ?? "none"):\(record.targetRegionIds.first?.rawValue ?? "none"):\(record.directiveType?.rawValue ?? "none")"
            if key == previousKey {
                streak += 1
            } else {
                streak = 1
                previousKey = key
            }
            if streak > limit {
                return true
            }
        }
        return false
    }

    private static func renderReport(reports: [CampaignTurnReport], records: [WarDirectiveRecord]) -> String {
        let totalCommands = reports.reduce(0) { $0 + $1.commandCounts.values.reduce(0, +) }
        let rejected = reports.reduce(0) { $0 + $1.rejectedCommands }
        let rejectionRatio = Self.rejectionRatio(reports: reports)
        let changedTurns = reports.filter { !$0.ownerChanges.isEmpty }.map(\.step)
        let supplyFirstTurn = reports.first {
            $0.supplyCounts.germany.lowSupply + $0.supplyCounts.germany.encircled + $0.supplyCounts.allies.lowSupply + $0.supplyCounts.allies.encircled > 0
        }?.step
        var lines: [String] = []
        lines.append("v0.35x campaign report")
        lines.append("totalDirectives=\(records.compactMap(\.directiveType).count) rejectionRatio=\(Self.percent(rejectionRatio)) changedTurns=\(changedTurns) firstLowSupplyOrEncircled=\(supplyFirstTurn.map(String.init) ?? "none")")
        lines.append("rejectionReasons=\(Self.rejectionReasons(records: records).sorted { $0.key < $1.key })")
        lines.append("turn | directives | commands | rejected | ownerChanges | supply | destroyed")
        for report in reports {
            lines.append(report.summaryLine)
        }
        return lines.joined(separator: "\n")
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func realDirectiveSummary(_ record: WarDirectiveRecord) -> String {
        let zone = record.zoneId?.rawValue ?? "nil"
        let type = record.directiveType?.rawValue ?? "nil"
        let targets = record.targetRegionIds.map(\.rawValue).joined(separator: "/")
        let diagnostics = record.diagnostics.joined(separator: ";")
        return "\(zone):\(type):\(targets.isEmpty ? "-" : targets):\(diagnostics.isEmpty ? "-" : diagnostics)"
    }

    private static func germanDeploymentSummary(in state: GameState) -> [String] {
        state.divisions
            .filter { $0.faction == .germany && !$0.isDestroyed }
            .sorted { $0.id < $1.id }
            .map { division in
                let regionId = division.location(in: state.map)?.rawValue ?? "nil"
                let zoneId = division.location(in: state.map).flatMap { state.warDeploymentState.regionToFrontZone[$0] }?.rawValue ?? "nil"
                let role = WarDeploymentManager().deploymentRole(for: division, in: state.map, state: state.warDeploymentState).rawValue
                return "\(division.id)@\(regionId)/\(zoneId)/\(role)/acted:\(division.hasActed)/str:\(division.strength)"
            }
    }

    @MainActor
    private static func waitForGermanAIToReturnToAllies(
        _ container: AppContainer,
        expectedMinimumTurn: Int,
        timeoutSeconds: TimeInterval = 12
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if container.gameState.activeFaction == .allies,
               container.gameState.phase == .alliedPlayer,
               container.gameState.turn >= expectedMinimumTurn {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for German AI to return control to Allies. turn=\(container.gameState.turn) faction=\(container.gameState.activeFaction) phase=\(container.gameState.phase)")
    }
}

private struct RealAppSnapshot {
    let turn: Int
    let germanCoords: [String: HexCoord]
    let alliedStrength: [String: Int]

    init(state: GameState) {
        turn = state.turn
        germanCoords = Dictionary(
            uniqueKeysWithValues: state.divisions
                .filter { $0.faction == .germany && !$0.isDestroyed }
                .map { ($0.id, $0.coord) }
        )
        alliedStrength = Dictionary(
            uniqueKeysWithValues: state.divisions
                .filter { $0.faction == .allies && !$0.isDestroyed }
                .map { ($0.id, $0.strength) }
        )
    }

    func movedGermanUnitIds(comparedTo after: RealAppSnapshot) -> [String] {
        germanCoords.compactMap { id, coord in
            after.germanCoords[id] != nil && after.germanCoords[id] != coord ? id : nil
        }.sorted()
    }

    func damagedAlliedUnitIds(comparedTo after: RealAppSnapshot) -> [String] {
        alliedStrength.compactMap { id, strength in
            guard let afterStrength = after.alliedStrength[id] else {
                return id
            }
            return afterStrength < strength ? id : nil
        }.sorted()
    }
}

private struct RealAppTurnReport {
    let step: Int
    let startTurn: Int
    let endTurn: Int
    let directives: [String]
    let germanCommands: [String]
    let germanMovedUnitIds: [String]
    let damagedAlliedUnitIds: [String]
    let germanDeployment: [String]
    let activeFaction: Faction
    let phase: GamePhase
    let lastMessage: String

    var summaryLine: String {
        let commands = germanCommands.joined(separator: ",")
        let directivesText = directives.joined(separator: " | ")
        let deploymentText = germanDeployment.joined(separator: " | ")
        return "\(step) turn \(startTurn)->\(endTurn) directives=[\(directivesText)] commands=[\(commands)] moved=\(germanMovedUnitIds) damaged=\(damagedAlliedUnitIds) german=[\(deploymentText)] state=\(activeFaction.rawValue)/\(phase.rawValue) msg=\(lastMessage)"
    }
}

private struct CampaignDiagnosticSummary {
    let germanRecordsAfterTurnSix: Int
    let changedRegionInSameTurn: Bool
    let rejectionRatio: Double
    let rejectionReasons: [String: Int]
}

private struct CampaignTurnReport {
    let step: Int
    let startTurn: Int
    let endTurn: Int
    let theaterSummary: String
    let directivesByFaction: [Faction: [DirectiveType]]
    let commandCounts: [String: Int]
    let rejectedCommands: Int
    let ownerChanges: [RegionId]
    let supplyCounts: FactionSupplyCounts
    let destroyedDivisionIds: [String]
    let consistencyErrors: [String]

    var summaryLine: String {
        let directives = Faction.allCases.map { faction in
            let value = directivesByFaction[faction]?.map(\.rawValue).joined(separator: "/") ?? "none"
            return "\(faction.rawValue):\(value)"
        }.joined(separator: " ")
        let commands = commandCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let changes = ownerChanges.map(\.rawValue).joined(separator: "/")
        let destroyed = destroyedDivisionIds.joined(separator: "/")
        return "\(step) | \(directives) | \(commands) | \(rejectedCommands) | \(changes.isEmpty ? "-" : changes) | \(supplyCounts.compactDescription) | \(destroyed.isEmpty ? "-" : destroyed)"
    }
}

private struct FactionSupplyCounts: Equatable {
    var germany = SupplyCount()
    var allies = SupplyCount()

    mutating func increment(faction: Faction, supplyState: SupplyState) {
        switch faction {
        case .germany:
            germany.increment(supplyState)
        case .allies:
            allies.increment(supplyState)
        }
    }

    var compactDescription: String {
        "G[\(germany.compactDescription)] A[\(allies.compactDescription)]"
    }
}

private struct SupplyCount: Equatable {
    var supplied = 0
    var lowSupply = 0
    var encircled = 0

    mutating func increment(_ state: SupplyState) {
        switch state {
        case .supplied:
            supplied += 1
        case .lowSupply:
            lowSupply += 1
        case .encircled:
            encircled += 1
        }
    }

    var compactDescription: String {
        "S:\(supplied),L:\(lowSupply),E:\(encircled)"
    }
}
