import SwiftUI

struct AgentPanelView: View {
    let record: AgentDecisionRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Decision")
                .font(.headline)

            LabeledContent("Agent") {
                Text(record?.agentId ?? "guderian")
            }

            LabeledContent("Provider") {
                Text(record?.provider ?? "MockAI")
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

            if let record, !record.commandResults.isEmpty {
                Text("Command Results")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(record.commandResults) { result in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.commandDisplayName ?? result.orderType?.rawValue ?? "Order")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(resultLine(result))
                                .font(.caption2)
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
                            .font(.caption2)
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
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var rawJSONPlaceholder: String {
        """
        {
          "agentId": "guderian",
