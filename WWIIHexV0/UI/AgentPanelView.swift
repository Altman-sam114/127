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
                Text(record?.agentId ?? "No active agent")
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
                    Text(rulerRecord.rulerAgentId)
                }
                LabeledContent("Posture") {
                    Text(rulerRecord.posture.displayName)
                }
                if let zoneId = rulerRecord.preferredFrontZoneId {
                    LabeledContent("Focus") {
                        Text(zoneId.rawValue)
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
                            Text(result.commandDisplayName ?? result.orderType?.rawValue ?? "Order")
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

            if !directiveRecords.isEmpty {
                Text("Operational Directives")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(directiveRecords) { directive in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(directive.zoneId?.rawValue ?? "global")
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

            Text("Raw JSON")
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
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func directiveSummary(_ directive: WarDirectiveRecord) -> String {
        let type = directive.directiveType?.rawValue ?? "diagnostic"
        let tactic = directive.tacticDisplayName ?? directive.category?.rawValue ?? "none"
        let executed = directive.commandResults.filter(\.executed).count
        let rejected = directive.commandResults.count - executed
        let targets = directive.targetRegionIds.map(\.rawValue).joined(separator: ", ")
        let targetText = targets.isEmpty ? "no target" : targets
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
        switch provider {
        case "MockAI":
            return "Local Planner"
        case "MockAI+MarshalDirective":
            return "Local Planner + Operational Directive"
        case "MockAI+Directive":
            return "Local Planner + Directive"
        case let provider?:
            return provider
        case nil:
            return "System Planner"
        }
    }

    private func commandChainTargetLine(_ item: ModernCommandChainReplayItem) -> String {
        var targets: [String] = []
        if let zoneId = item.zoneId {
            targets.append("command sector \(zoneId.rawValue)")
        }
        if let regionId = item.regionId {
            targets.append("objective \(regionId.rawValue)")
        }
        if let contactId = item.contactId {
            targets.append("contact \(contactId)")
        }
        return targets.isEmpty ? "global coordination" : targets.joined(separator: " / ")
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
