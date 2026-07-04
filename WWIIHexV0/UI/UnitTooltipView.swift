import SwiftUI

struct UnitTooltipView: View {
    let division: Division?

    var body: some View {
        if let division {
            VStack(alignment: .leading, spacing: 6) {
                Text(division.operationalDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        label("Role")
                        value(division.tooltipTypeCode)
                    }
                    GridRow {
                        label("Strength")
                        value("\(division.strength)/\(division.maxStrength)")
                    }
                    GridRow {
                        label("Supply")
                        value(division.supplyState.tooltipDisplayName)
                    }
                    GridRow {
                        label("Retreat")
                        value(division.retreatMode.tooltipDisplayName)
                    }
                    GridRow {
                        label("Acted")
                        value(division.hasActed ? "Yes" : "No")
                    }
                }
            }
            .padding(10)
            .frame(width: 220, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.35), lineWidth: 1)
            }
            .padding(10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(division.operationalDisplayName), \(division.tooltipTypeCode), strength \(division.strength) of \(division.maxStrength)")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private extension Division {
    var tooltipTypeCode: String {
        if isArtillery {
            return "ART"
        }
        if isArmor {
            return "ARM"
        }
        if components.contains(where: { $0.type == .motorizedInfantry && $0.weight >= 0.40 }) {
            return "MECH"
        }
        return "INF"
    }
}

private extension RetreatMode {
    var tooltipDisplayName: String {
        switch self {
        case .retreatable:
            return "Retreatable"
        case .hold:
            return "Hold"
        }
    }
}

private extension SupplyState {
    var tooltipDisplayName: String {
        switch self {
        case .supplied:
            return "Supplied"
        case .lowSupply:
            return "Low"
        case .encircled:
            return "Encircled"
        }
    }
}
