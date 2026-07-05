import SwiftUI

enum ModernCommandDesignTokens {
    static let cornerRadius: CGFloat = 8
    static let compactSpacing: CGFloat = 6
    static let spacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 14
    static let padding: CGFloat = 12
    static let minimumTapSize: CGFloat = 44
    static let metricMinWidth: CGFloat = 118
    static let missionButtonMinWidth: CGFloat = 132

    static var panelBackground: Color {
        PlatformStyles.systemBackground
    }

    static var insetPanelBackground: Color {
        PlatformStyles.secondarySystemBackground
    }

    static var panelStroke: Color {
        PlatformStyles.panelStroke
    }

    static let blueForce = Color(red: 0.16, green: 0.46, blue: 0.84)
    static let redForce = Color(red: 0.83, green: 0.23, blue: 0.20)
    static let greenForce = Color(red: 0.18, green: 0.57, blue: 0.34)
    static let neutralForce = Color(red: 0.48, green: 0.50, blue: 0.54)
    static let sensor = Color(red: 0.20, green: 0.66, blue: 0.82)
    static let fires = Color(red: 0.95, green: 0.54, blue: 0.18)
    static let electronicWarfare = Color(red: 0.62, green: 0.28, blue: 0.84)
    static let sustainment = Color(red: 0.17, green: 0.62, blue: 0.46)
    static let warning = Color(red: 0.91, green: 0.42, blue: 0.18)

    static func sideColor(for alignment: OperationalSideAlignment) -> Color {
        switch alignment {
        case .blue:
            return blueForce
        case .red:
            return redForce
        case .green:
            return greenForce
        case .neutral:
            return neutralForce
        }
    }

    static func supplyColor(for supplyState: SupplyState) -> Color {
        switch supplyState {
        case .supplied:
            return sustainment
        case .lowSupply:
            return warning
        case .encircled:
            return redForce
        }
    }
}
