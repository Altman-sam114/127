import SwiftUI

struct ModernMissionPanelView: View {
    let selectedDivision: Division?
    let selectedHex: HexCoord?
    let selectedRegion: RegionNode?
    let visibleContactCount: Int
    let fireBudgetSummary: String
    let canIssueUnitMission: Bool
    let canAssaultObjective: Bool
    let canHoldDelay: Bool
    let observerModeEnabled: Bool
    let onReconArea: () -> Void
    let onUAVOrbit: () -> Void
    let onFireMission: () -> Void
    let onSuppressAirDefense: () -> Void
    let onElectronicWarfare: () -> Void
    let onResupplyRepair: () -> Void
    let onAssaultObjective: () -> Void
    let onHoldDelay: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 132), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mission Planning")
                .font(.headline)

            missionSummary

            missionSection(
                title: "ISR",
                actions: [
                    MissionAction(label: "Recon Area", icon: "scope", enabled: canIssueUnitMission, action: onReconArea),
                    MissionAction(label: "UAV Orbit", icon: "airplane.circle", enabled: canIssueUnitMission, action: onUAVOrbit)
                ]
            )

            missionSection(
                title: "Fires",
                actions: [
                    MissionAction(label: "Fire Mission", icon: "target", enabled: canIssueUnitMission, action: onFireMission),
                    MissionAction(label: "Air Support / SEAD", icon: "shield.lefthalf.filled", enabled: canIssueUnitMission, action: onSuppressAirDefense)
                ]
            )

            missionSection(
                title: "Maneuver",
                actions: [
                    MissionAction(label: "Assault Objective", icon: "arrow.up.right.circle", enabled: canAssaultObjective, action: onAssaultObjective),
                    MissionAction(label: "Hold / Delay", icon: "shield.fill", enabled: canHoldDelay, action: onHoldDelay)
                ]
            )

            missionSection(
                title: "Sustainment / EW",
                actions: [
                    MissionAction(label: "Resupply / Repair", icon: "cross.circle", enabled: canIssueUnitMission, action: onResupplyRepair),
                    MissionAction(label: "Jam / Counter-Drone", icon: "antenna.radiowaves.left.and.right", enabled: canIssueUnitMission, action: onElectronicWarfare)
                ]
            )
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var missionSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Formation") {
                Text(selectedDivision?.operationalDisplayName ?? "None")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Target") {
                Text(targetSummary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: 8) {
                ModernMissionMetricView(title: "Supply", value: selectedDivision.map(supplySummary) ?? "--")
                ModernMissionMetricView(title: "Contacts", value: "\(visibleContactCount)")
                ModernMissionMetricView(title: "Ammo", value: fireBudgetSummary)
            }
        }
        .font(.caption)
        .foregroundStyle(observerModeEnabled ? .secondary : .primary)
    }

    private var targetSummary: String {
        if let selectedRegion {
            return selectedRegion.name
        }
        if let selectedHex {
            return "\(selectedHex.q),\(selectedHex.r)"
        }
        return "None"
    }

    private func supplySummary(for division: Division) -> String {
        switch division.supplyState {
        case .supplied:
            return "Ready"
        case .lowSupply:
            return "Low"
        case .encircled:
            return "Cut"
        }
    }

    private func missionSection(title: String, actions: [MissionAction]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(actions) { action in
                    Button(action: action.action) {
                        Label(action.label, systemImage: action.icon)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!action.enabled || observerModeEnabled)
                }
            }
        }
    }
}

private struct MissionAction: Identifiable {
    let label: String
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var id: String {
        label
    }
}

private struct ModernMissionMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
