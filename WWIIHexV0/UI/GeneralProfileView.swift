import SwiftUI

struct GeneralProfileView: View {
    let general: GeneralData
    let assignment: GeneralAssignment?
    let zone: FrontZone?
    let assignedDivisions: [Division]
    let hqUnderAttack: Bool
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    identityBlock
                    VStack(alignment: .leading, spacing: 12) {
                        biographyBlock
                        statusBlock
                    }
                }

                skillsBlock
                assignedUnitsBlock
            }
            .padding(18)
        }
        .background(.ultraThinMaterial)
        .safeAreaInset(edge: .top) {
            HStack {
                Text("General Profile")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: onClose)
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(PlatformStyles.systemBackground)
        }
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(initials)
                .font(.title.weight(.bold))
                .frame(width: 112, height: 144)
                .background(PlatformStyles.selectionTint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("\(general.localizedName) portrait placeholder")

            Text(general.localizedName)
                .font(.title3.weight(.semibold))
            Text(general.rank)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(general.faction.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PlatformStyles.tertiarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(minWidth: 132, alignment: .leading)
    }

    private var biographyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biography")
                .font(.headline)
            Text(general.biography)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Command Style") {
                Text(styleLabel(general.commandStyle))
            }
            if let zone {
                LabeledContent("Command Sector") {
                    Text(zone.name)
                        .multilineTextAlignment(.trailing)
                }
            }
            if hqUnderAttack {
                Label("HQ region contested", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Relationship")
                .font(.headline)
            metricBar(title: "Loyalty", value: assignment?.loyalty ?? general.baseLoyalty)
            metricBar(title: "Satisfaction", value: assignment?.satisfaction ?? general.baseSatisfaction)
            LabeledContent("Player Interventions") {
                Text("\(assignment?.interventionCount ?? 0)")
            }
        }
    }

    private var skillsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skills")
                .font(.headline)
            if general.skills.isEmpty {
                Text("No explicit skills configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(general.skills, id: \.self) { skill in
                        Label(skill.replacingOccurrences(of: "_", with: " "), systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PlatformStyles.tertiarySystemBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var assignedUnitsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assigned Formations")
                .font(.headline)
            if assignedDivisions.isEmpty {
                Text("No active formations assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assignedDivisions, id: \.id) { division in
                    LabeledContent(division.name) {
                        Text("\(division.strength)/\(division.maxStrength)")
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func metricBar(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
            }
            .font(.caption)
            ProgressView(value: Double(value), total: 100)
                .tint(value >= 65 ? .green : value >= 40 ? .orange : .red)
        }
    }

    private var initials: String {
        let words = general.localizedName.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? String(general.name.prefix(2)).uppercased() : String(letters).uppercased()
    }

    private func styleLabel(_ style: ZoneCommanderAgentConfig.CommandStyle) -> String {
        switch style {
        case .aggressive:
            return "Aggressive"
        case .balanced:
            return "Balanced"
        case .cautious:
            return "Cautious"
        }
    }
}
