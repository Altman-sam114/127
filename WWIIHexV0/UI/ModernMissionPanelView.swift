import SwiftUI

struct ModernMissionPanelView: View {
    let selectedDivision: Division?
    let selectedHex: HexCoord?
    let selectedRegion: RegionNode?
    let visibleContactCount: Int
    let fireBudgetSummary: String
    let missionAvailabilityText: String
    let canIssueReconMission: Bool
    let canIssueUAVMission: Bool
    let canIssueFireMission: Bool
    let canIssueSuppressAirDefenseMission: Bool
    let canIssueElectronicWarfareMission: Bool
    let canIssueResupplyRepairMission: Bool
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
        GridItem(
            .adaptive(minimum: ModernCommandDesignTokens.missionButtonMinWidth),
            spacing: ModernCommandDesignTokens.compactSpacing
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ModernCommandDesignTokens.spacing) {
            Label("Mission Planning", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.headline)

            missionSummary
            missionStatus

            missionSection(
                title: "ISR",
                actions: [
                    MissionAction(label: "Recon Area", icon: "scope", enabled: canIssueReconMission, action: onReconArea),
                    MissionAction(label: "UAV Orbit", icon: "airplane.circle", enabled: canIssueUAVMission, action: onUAVOrbit)
                ]
            )

            missionSection(
                title: "Fires",
                actions: [
                    MissionAction(label: "Fire Mission", icon: "target", enabled: canIssueFireMission, action: onFireMission),
                    MissionAction(label: "Air Support / SEAD", icon: "shield.lefthalf.filled", enabled: canIssueSuppressAirDefenseMission, action: onSuppressAirDefense)
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
                    MissionAction(label: "Sustain / Repair", icon: "cross.circle", enabled: canIssueResupplyRepairMission, action: onResupplyRepair),
                    MissionAction(label: "Jam / Counter-Drone", icon: "antenna.radiowaves.left.and.right", enabled: canIssueElectronicWarfareMission, action: onElectronicWarfare)
                ]
            )
        }
        .padding(ModernCommandDesignTokens.padding)
        .background(ModernCommandDesignTokens.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius)
                .stroke(ModernCommandDesignTokens.panelStroke, lineWidth: 1)
        }
    }

    private var missionStatus: some View {
        Label(
            missionAvailabilityText,
            systemImage: hasAvailableMission ? "checkmark.seal" : "info.circle"
        )
        .font(.caption)
        .foregroundStyle(hasAvailableMission ? .secondary : ModernCommandDesignTokens.warning)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Mission status: \(missionAvailabilityText)")
    }

    private var hasAvailableMission: Bool {
        !observerModeEnabled && (
            canIssueReconMission ||
                canIssueUAVMission ||
                canIssueFireMission ||
                canIssueSuppressAirDefenseMission ||
                canIssueElectronicWarfareMission ||
                canIssueResupplyRepairMission ||
                canAssaultObjective ||
                canHoldDelay
        )
    }

    private var missionSummary: some View {
        VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
            LabeledContent("Formation") {
                Text(selectedDivision?.operationalDisplayName ?? "None")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Target") {
                Text(targetSummary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: ModernCommandDesignTokens.compactSpacing) {
                ModernMissionMetricView(
                    title: "Readiness",
                    value: selectedDivision?.operationalReadinessDisplayText ?? "--",
                    icon: "gauge",
                    tint: selectedDivision.map(readinessTint) ?? .secondary
                )
                ModernMissionMetricView(
                    title: "Fuel",
                    value: selectedDivision?.fuelPostureDisplayText ?? "--",
                    icon: "fuelpump",
                    tint: selectedDivision.map(fuelTint) ?? .secondary
                )
                ModernMissionMetricView(
                    title: "Signature",
                    value: selectedDivision?.signaturePostureDisplayText ?? "--",
                    icon: "dot.radiowaves.left.and.right",
                    tint: ModernCommandDesignTokens.sensor
                )
            }
            HStack(spacing: ModernCommandDesignTokens.compactSpacing) {
                ModernMissionMetricView(
                    title: "Logistics",
                    value: selectedDivision.map(supplySummary) ?? "--",
                    icon: "cross.case",
                    tint: selectedDivision.map { ModernCommandDesignTokens.supplyColor(for: $0.supplyState) } ?? .secondary
                )
                ModernMissionMetricView(
                    title: "Contacts",
                    value: "\(visibleContactCount)",
                    icon: "dot.scope",
                    tint: ModernCommandDesignTokens.sensor
                )
                ModernMissionMetricView(
                    title: "Ammo",
                    value: fireBudgetSummary,
                    icon: "scope",
                    tint: ModernCommandDesignTokens.fires
                )
            }
        }
        .padding(ModernCommandDesignTokens.compactSpacing)
        .background(ModernCommandDesignTokens.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ModernCommandDesignTokens.cornerRadius))
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
        division.supplyState.shortDisplayName
    }

    private func missionSection(title: String, actions: [MissionAction]) -> some View {
        VStack(alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: ModernCommandDesignTokens.compactSpacing) {
                ForEach(actions) { action in
                    Button(action: action.action) {
                        Label(action.label, systemImage: action.icon)
                            .font(.caption)
                            .lineLimit(2)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ModernCommandDesignTokens.minimumTapSize,
                                alignment: .leading
                            )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!action.enabled || observerModeEnabled)
                    .accessibilityHint(
                        Text(
                            action.enabled && !observerModeEnabled
                                ? "Submits \(action.label) through the rules pipeline."
                                : missionAvailabilityText
                        )
                    )
                }
            }
        }
    }

    private func readinessTint(for division: Division) -> Color {
        if division.operationalReadinessPercent >= 70 {
            return ModernCommandDesignTokens.sustainment
        }
        if division.operationalReadinessPercent >= 40 {
            return ModernCommandDesignTokens.warning
        }
        return .red
    }

    private func fuelTint(for division: Division) -> Color {
        switch division.supplyState {
        case .supplied:
            return ModernCommandDesignTokens.sustainment
        case .lowSupply:
            return ModernCommandDesignTokens.warning
        case .encircled:
            return .red
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
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ModernCommandDesignTokens.minimumTapSize,
            alignment: .leading
        )
    }
}
