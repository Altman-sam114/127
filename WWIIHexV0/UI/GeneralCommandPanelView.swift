import SwiftUI

struct GeneralCommandPanelView: View {
    let zone: FrontZone?
    let general: GeneralData?
    let assignment: GeneralAssignment?
    let assignedDivisions: [Division]
    let targetRegion: RegionNode?
    let targetZone: FrontZone?
    let hqUnderAttack: Bool
    let plannedOperations: [PlayerPlannedOperation]
    let canHoldLine: Bool
    let canAttackRegion: Bool
    let onShowProfile: () -> Void
    let onHoldLine: () -> Void
    let onAttackRegion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commander Cell")
                .font(.headline)

            if let zone {
                LabeledContent("Command Sector") {
                    Text(zone.name)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                Text("No command sector selected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let general {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        Button(action: onShowProfile) {
                            portraitBadge(for: general)
                        }
                            .accessibilityLabel("Open profile for \(general.localizedName)")
                            .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(general.localizedName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(general.rank) / \(styleLabel(general.commandStyle))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(general.biography)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if !general.skills.isEmpty {
                        Text(general.skills.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let assignment {
                        metricBar(title: "Trust", value: assignment.loyalty)
                        metricBar(title: "Readiness", value: assignment.satisfaction)
                        LabeledContent("Manual Overrides") {
                            Text("\(assignment.interventionCount)")
                        }
                    }

                    Button("View Profile", systemImage: "person.text.rectangle", action: onShowProfile)
                        .buttonStyle(.bordered)
                }
            } else if zone != nil {
                Text("No commander assigned to this command sector.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if hqUnderAttack {
                Label("Command post contested", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if !assignedDivisions.isEmpty {
                Text("Assigned Formations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(assignedDivisions.prefix(5)), id: \.id) { division in
                        Label(division.operationalDisplayName, systemImage: unitIcon(for: division))
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            if let targetRegion, targetZone?.faction != zone?.faction {
                LabeledContent("Objective") {
                    Text(targetRegion.name)
                }
            }

            HStack(spacing: 8) {
                Button("Hold Line", systemImage: "shield.fill", action: onHoldLine)
                    .disabled(!canHoldLine)
                Button("Assault Objective", systemImage: "arrow.up.right.circle", action: onAttackRegion)
                    .disabled(!canAttackRegion)
            }
            .buttonStyle(.bordered)

            if !plannedOperations.isEmpty {
                Text("Planned Operations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plannedOperations) { operation in
                        Label(operationSummary(operation), systemImage: operationIcon(operation))
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func portraitBadge(for general: GeneralData) -> some View {
        Text(initials(for: general))
            .font(.caption.weight(.bold))
            .frame(width: 40, height: 40)
            .background(PlatformStyles.selectionTint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("\(general.localizedName) portrait placeholder")
    }

    private func metricBar(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
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

    private func initials(for general: GeneralData) -> String {
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

    private func unitIcon(for division: Division) -> String {
        if division.isArmor {
            return "shield.lefthalf.filled"
        }
        if division.isArtillery {
            return "scope"
        }
        return "person.3.fill"
    }

    private func operationIcon(_ operation: PlayerPlannedOperation) -> String {
        operation.directiveType == .attack ? "arrow.up.right.circle" : "shield.fill"
    }

    private func operationSummary(_ operation: PlayerPlannedOperation) -> String {
        let target = operation.targetRegionId
            .map(objectiveDisplay)
            ?? operation.sourceRegionId.map(objectiveDisplay)
            ?? commandSectorDisplay(operation.zoneId)
        return "\(directiveTypeDisplay(operation.directiveType)) / \(target)"
    }

    private func directiveTypeDisplay(_ type: DirectiveType) -> String {
        switch type {
        case .attack:
            return "Attack"
        case .defend:
            return "Defense"
        }
    }

    private func objectiveDisplay(_ id: RegionId) -> String {
        let cleaned = cleanIdentifier(id.rawValue)
        return cleaned.isEmpty ? "Objective Area" : "Objective \(cleaned.capitalized)"
    }

    private func commandSectorDisplay(_ id: FrontZoneId) -> String {
        let cleaned = cleanIdentifier(id.rawValue)
        return cleaned.isEmpty ? "Command Sector" : "Sector \(cleaned.capitalized)"
    }

    private func cleanIdentifier(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "region_", with: "")
            .replacingOccurrences(of: "objective_", with: "")
            .replacingOccurrences(of: "front_zone_", with: "")
            .replacingOccurrences(of: "zone_", with: "")
            .replacingOccurrences(of: "theater_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
