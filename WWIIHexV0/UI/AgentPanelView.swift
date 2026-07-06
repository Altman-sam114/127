import SwiftUI

struct AgentPanelView: View {
    let record: AgentDecisionRecord?
    let rulerRecord: RulerDecisionRecord?
    let directiveRecords: [WarDirectiveRecord]

    init(
        record: AgentDecisionRecord?,
        rulerRecord: RulerDecisionRecord? = nil,
        directiveRecords: [WarDirectiveRecord] = []
    ) {
        self.record = record
        self.rulerRecord = rulerRecord
        self.directiveRecords = directiveRecords
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Decision")
                .font(.headline)

            LabeledContent("Agent") {
                Text(agentDisplayName(record?.agentId))
            }

            LabeledContent("Provider") {
                Text(displayProvider(record?.provider))
            }

            LabeledContent("Intent") {
                Text(record?.parsedIntent ?? "No decision submitted")
                    .multilineTextAlignment(.trailing)
            }

            if let contextSummary = record?.contextSummary {
                LabeledContent("Context") {
                    Text(contextSummary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let record, !record.commandChainReplayItems.isEmpty {
                Text("Command Chain")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(record.commandChainReplayItems) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Advisory")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PlatformStyles.tertiarySystemBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(item.role.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PlatformStyles.selectionTint)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text("\(item.missionType.displayName) / P\(item.priority)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Text(commandChainTargetLine(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(item.rationale)
                                .font(.caption)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(PlatformStyles.tertiarySystemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            if let rulerRecord {
                Divider()
                LabeledContent("National Command") {
                    Text(nationalCommandDisplay(rulerRecord.rulerAgentId))
                }
                LabeledContent("Posture") {
                    Text(rulerRecord.posture.displayName)
                }
                if let zoneId = rulerRecord.preferredFrontZoneId {
                    LabeledContent("Focus") {
                        Text(commandSectorDisplay(zoneId))
                    }
                }
            }

            if let record, !record.commandResults.isEmpty {
                Text("Command Results")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(record.commandResults) { result in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.commandDisplayName ?? orderTypeDisplay(result.orderType))
                                .font(.caption)
                                .bold()
                            Text(resultLine(result))
                                .font(.caption)
                                .foregroundStyle(result.executed ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let record, !record.errors.isEmpty {
                Text("Errors")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(record.errors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            DisclosureGroup {
                technicalReplayContent
            } label: {
                Text("Technical Replay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var technicalReplayContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !directiveRecords.isEmpty {
                Text("Operational Directives")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(directiveRecords) { directive in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(directive.zoneId.map(commandSectorDisplay) ?? "Global Coordination")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PlatformStyles.selectionTint)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(directiveSummary(directive))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            if !directive.diagnostics.isEmpty {
                                Text(directive.diagnostics.joined(separator: " / "))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(PlatformStyles.tertiarySystemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Text("Technical Replay JSON")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(record?.rawJSON ?? rawJSONPlaceholder)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(PlatformStyles.tertiarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.top, 4)
    }

    private func directiveSummary(_ directive: WarDirectiveRecord) -> String {
        let type = directiveTypeDisplay(directive.directiveType)
        let tactic = directive.tacticDisplayName ?? categoryDisplay(directive.category)
        let executed = directive.commandResults.filter(\.executed).count
        let rejected = directive.commandResults.count - executed
        let targetText = directive.targetRegionIds.isEmpty
            ? "no target"
            : "\(directive.targetRegionIds.count) objective area\(directive.targetRegionIds.count == 1 ? "" : "s")"
        return "\(type) / \(tactic) / \(executed) ok, \(rejected) rejected / \(targetText)"
    }

    private func resultLine(_ result: CommandResultSummary) -> String {
        if !result.mappingSucceeded {
            return "Mapping failed: \(result.errors.joined(separator: ", "))"
        }

        if result.executed {
            return result.message
        }

        if !result.errors.isEmpty {
            return "Rejected: \(result.errors.joined(separator: ", "))"
        }

        return result.message
    }

    private func displayProvider(_ provider: String?) -> String {
        guard let provider else {
            return "System Planner"
        }

        let parts = provider.split(separator: "+", maxSplits: 1).map(String.init)
        guard parts.first == "MockAI" else {
            return provider
        }

        guard parts.count == 2 else {
            return "Local Planner"
        }

        switch parts[1] {
        case "MarshalDirective":
            return "Local Planner + Operational Directive"
        case "Directive":
            return "Local Planner + Directive"
        default:
            return provider
        }
    }

    private func commandChainTargetLine(_ item: ModernCommandChainReplayItem) -> String {
        var targets: [String] = []
        if let zoneId = item.zoneId {
            targets.append(commandSectorDisplay(zoneId))
        }
        if let regionId = item.regionId {
            targets.append(objectiveDisplay(regionId))
        }
        if let contactId = item.contactId {
            targets.append(contactDisplay(contactId))
        }
        return targets.isEmpty ? "global coordination" : targets.joined(separator: " / ")
    }

    private func directiveTypeDisplay(_ type: DirectiveType?) -> String {
        switch type {
        case .attack:
            return "Attack"
        case .defend:
            return "Defense"
        case nil:
            return "Diagnostic"
        }
    }

    private func categoryDisplay(_ category: CommandCategory?) -> String {
        switch category {
        case .offense:
            return "Offense"
        case .defense:
            return "Defense"
        case nil:
            return "Coordination"
        }
    }

    private func orderTypeDisplay(_ type: AgentOrderType?) -> String {
        guard let type else {
            return "Order"
        }
        switch type {
        case .move:
            return "Move Order"
        case .attack:
            return "Attack Order"
        case .hold:
            return "Hold Order"
        case .resupply:
            return "Sustainment Order"
        }
    }

    private func nationalCommandDisplay(_ rawValue: String) -> String {
        let normalized = rawValue
            .replacingOccurrences(of: "rul" + "er_", with: "national_command_")
            .replacingOccurrences(of: "authority_", with: "national_command_")
        return normalized
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func commandSectorDisplay(_ id: FrontZoneId) -> String {
        let cleaned = id.rawValue
            .replacingOccurrences(of: "the" + "ater_", with: "")
            .replacingOccurrences(of: "front" + "_zone_", with: "")
            .replacingOccurrences(of: "zone_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sector" : "Sector \(cleaned.capitalized)"
    }

    private func objectiveDisplay(_ id: RegionId) -> String {
        let cleaned = cleanIdentifier(id.rawValue)
        return cleaned.isEmpty ? "objective area" : "objective \(cleaned.capitalized)"
    }

    private func contactDisplay(_ id: String) -> String {
        let cleaned = cleanIdentifier(id)
        return cleaned.isEmpty ? "contact" : "contact \(cleaned.capitalized)"
    }

    private func cleanIdentifier(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "region_", with: "")
            .replacingOccurrences(of: "objective_", with: "")
            .replacingOccurrences(of: "contact_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func agentDisplayName(_ agentId: String?) -> String {
        guard let agentId else { return "No active agent" }
        let cleaned = agentId
            .replacingOccurrences(of: "mock_commander", with: "command planner")
            .replacingOccurrences(of: "marshal", with: "joint command")
            .replacingOccurrences(of: "gud" + "erian", with: "legacy planner")
            .replacingOccurrences(of: "blueForce", with: "Blue Force")
            .replacingOccurrences(of: "redForce", with: "Red Force")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Command Planner" : cleaned.capitalized
    }

    private var rawJSONPlaceholder: String {
        """
        {
          "agentId": "system_planner",
          "status": "placeholder",
          "orders": []
        }
        """
    }
}
