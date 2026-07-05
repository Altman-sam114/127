import SwiftUI

struct InfoPanelToggle<Summary: View, Content: View>: View {
    @State private var isExpanded = false
    @ViewBuilder let summary: Summary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "Hide Info" : "Info", systemImage: "info.circle")
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(isExpanded ? "Hide information panel" : "Show information panel")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                Spacer(minLength: 8)
            }

            if isExpanded {
                content
            } else {
                summary
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
