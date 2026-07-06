import SwiftUI

struct UnitInspectorView: View {
    let division: Division?
    let playerFaction: Faction
    let strategicState: UnitInspectorStrategicState?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Formation Details")
                .font(.headline)

            if let division {
                unitDetails(division)
            } else {
                Text("No unit selected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func unitDetails(_ division: Division) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(division.operationalDisplayName)
                .font(.subheadline.weight(.semibold))

            LabeledContent("Side") {
                Text(division.faction.displayName)
            }

            LabeledContent("Mode") {
                Text(division.faction == playerFaction ? "Player" : "Read-only")
            }

            if let strategicState {
                LabeledContent("Hex") {
                    Text("\(strategicState.coord.q),\(strategicState.coord.r)")
                }

                LabeledContent("Region") {
                    Text(strategicState.regionId?.rawValue ?? "None")
                }

                LabeledContent("Operational Zone") {
                    Text(operationalZoneDisplay(strategicState.dynamicTheaterId))
                }

                LabeledContent("Command Sector") {
                    Text(commandSectorDisplay(strategicState.frontZoneId))
                }

                LabeledContent("Deploy") {
                    Text(strategicState.deploymentRole.displayName)
                }

                LabeledContent("Contact Line") {
                    Text(frontLineSummary(strategicState.frontLineIds))
                        .multilineTextAlignment(.trailing)
                }
            }

            LabeledContent("Strength") {
                Text(division.inspectorStrengthText)
            }

            LabeledContent("Readiness") {
                Text(division.operationalReadinessDisplayText)
            }

            LabeledContent("Fuel") {
                Text(division.fuelPostureDisplayText)
            }

            LabeledContent("Signature") {
                Text(division.signaturePostureDisplayText)
            }

            LabeledContent("Retreat Mode") {
                Text(division.retreatMode.displayName)
            }

            LabeledContent("Logistics") {
                Text(division.supplyState.displayName)
            }

            LabeledContent("Has Acted") {
                Text(division.hasActed ? "Yes" : "No")
            }

            LabeledContent("Status") {
                Text(division.inspectorStatusText)
            }

            LabeledContent("Composition") {
                Text(componentSummary(for: division))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func componentSummary(for division: Division) -> String {
        division.components
            .map { "\($0.type.displayCode) \(Int(($0.weight * 100).rounded()))%" }
            .joined(separator: " / ")
    }

    private func frontLineSummary(_ ids: [FrontLineId]) -> String {
        ids.isEmpty ? "None" : ids.map(\.rawValue).joined(separator: ", ")
    }

    private func operationalZoneDisplay(_ id: TheaterId?) -> String {
        guard let value = id?.rawValue else {
            return "None"
        }
        return displayName(for: value, fallbackPrefix: "Zone")
    }

    private func commandSectorDisplay(_ id: FrontZoneId?) -> String {
        guard let value = id?.rawValue else {
            return "None"
        }
        return displayName(for: value, fallbackPrefix: "Sector")
    }

    private func displayName(for rawValue: String, fallbackPrefix: String) -> String {
        let cleaned = rawValue
            .replacingOccurrences(of: "the" + "ater_", with: "")
            .replacingOccurrences(of: "front" + "_zone_", with: "")
            .replacingOccurrences(of: "zone_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return fallbackPrefix
        }

        return "\(fallbackPrefix) \(cleaned.capitalized)"
    }
}

private extension Division {
    var inspectorStrengthText: String {
        "\(strength) / \(maxStrength)"
    }

    var inspectorStatusText: String {
        var statuses: [String] = []

        if isRetreating {
            statuses.append("Retreating")
        }

        if isDestroyed {
            statuses.append("Destroyed")
        }

        return statuses.isEmpty ? "Ready" : statuses.joined(separator: ", ")
    }
}

private extension RetreatMode {
    var displayName: String {
        switch self {
        case .retreatable:
            return "Retreatable"
        case .hold:
            return "Hold"
        }
    }
}

private extension SupplyState {
    var displayName: String {
        switch self {
        case .supplied:
            return "Ready"
        case .lowSupply:
            return "Low Logistics"
        case .encircled:
            return "Logistics Cut"
        }
    }
}

private extension UnitDeploymentRole {
    var displayName: String {
        switch self {
        case .frontUnit:
            return "FRONT"
        case .depthUnit:
            return "DEPTH"
        case .garrisonUnit:
            return "SECURITY"
        }
    }
}

private extension Set where Element == HexDirection {
    var displaySummary: String {
        HexDirection.ordered
            .filter { contains($0) }
            .map(\.displayCode)
            .joined(separator: ", ")
    }
}

private extension HexDirection {
    var displayCode: String {
        switch self {
        case .east:
            return "E"
        case .northEast:
            return "NE"
        case .northWest:
            return "NW"
        case .west:
            return "W"
        case .southWest:
            return "SW"
        case .southEast:
            return "SE"
        }
    }
}
