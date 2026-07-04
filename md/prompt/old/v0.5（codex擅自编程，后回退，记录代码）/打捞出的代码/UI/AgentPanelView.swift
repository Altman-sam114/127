import SwiftUI

struct AgentPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Decision")
                .font(.headline)

            LabeledContent("Agent") {
                Text("guderian")
            }

            LabeledContent("Summary") {
                Text("MockAI pending")
            }

            LabeledContent("Validation") {
                Text("No decision submitted")
            }

            Text("Raw JSON")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(rawJSONPlaceholder)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var rawJSONPlaceholder: String {
        """
