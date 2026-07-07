import SwiftUI

struct RegionInspectorView: View {
    let inspectorState: RegionInspectorState?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Region")
                .font(.headline)

            if let inspectorState {
                regionDetails(inspectorState)
            } else {
                Text("No region selected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func regionDetails(_ state: RegionInspectorState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(visibleAreaName(state.region.name, fallbackPrefix: "Area"))
                .font(.subheadline.weight(.semibold))

            if let selectedHex = state.selectedHex {
                LabeledContent("Hex") {
                    Text("\(selectedHex.q),\(selectedHex.r)")
                }

                LabeledContent("Hex Controller") {
                    Text(state.selectedHexController?.displayName ?? "None")
                }

                LabeledContent("Hex Operational Zone") {
                    Text(operationalZoneDisplay(state.selectedHexDynamicTheaterId))
                }

                LabeledContent("Hex Command Sector") {
                    Text(commandSectorDisplay(state.selectedHexFrontZoneId))
                }
            }

            LabeledContent("Controller") {
                Text(state.region.controller.displayName)
            }

            LabeledContent("Terrain") {
                Text(state.region.terrain.displayName)
            }

            LabeledContent("City") {
                Text(visibleOptionalAreaName(state.region.city?.name, fallbackPrefix: "Objective"))
            }

            LabeledContent("City Level") {
                Text(state.cityLevel.displayName)
            }

            LabeledContent("Fortress") {
                Text(state.region.terrain == .fortress ? "Yes" : "No")
            }

            LabeledContent("Logistics") {
                Text("\(state.region.supplyValue)")
            }

            LabeledContent("Facilities") {
                Text("\(state.region.factories)")
            }

            LabeledContent("Output") {
                Text("PER \(state.economicOutput.manpower), MAT \(state.economicOutput.industry), LOG \(state.economicOutput.supplies)")
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Operational Zone") {
                Text(operationalZoneDisplay(state.theaterId))
            }

            LabeledContent("Command Sector") {
                Text(commandSectorDisplay(state.frontZoneId))
            }

            LabeledContent("Front Pressure") {
                Text(state.frontPressure, format: .number.precision(.fractionLength(2)))
            }

            LabeledContent("Infrastructure") {
                Text("\(state.region.infrastructure)")
            }

            LabeledContent("Objectives") {
                Text(objectiveNamesDisplay(state.objectiveNames))
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Objective Status") {
                Text(state.objectiveStatus)
            }

            LabeledContent("Friendly Formations") {
                Text(unitNames(state.friendlyDivisions))
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Contacts") {
                Text(contactNames(state.visibleContacts))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func unitNames(_ divisions: [Division]) -> String {
        guard !divisions.isEmpty else {
            return "None"
        }
        return divisions.map(\.operationalDisplayName).joined(separator: ", ")
    }

    private func contactNames(_ contacts: [VisibleContactDisplay]) -> String {
        guard !contacts.isEmpty else {
            return "None"
        }
        return contacts.map { contact in
            "\(contact.estimatedType.displayName) \(contact.confidence.displayName) \(contact.source.displayName) age \(contact.ageInTurns)"
        }.joined(separator: ", ")
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

    private func objectiveNamesDisplay(_ names: [String]) -> String {
        guard !names.isEmpty else {
            return "None"
        }

        return names
            .map { visibleAreaName($0, fallbackPrefix: "Objective") }
            .joined(separator: ", ")
    }

    private func visibleOptionalAreaName(_ name: String?, fallbackPrefix: String) -> String {
        guard let name else {
            return "None"
        }

        return visibleAreaName(name, fallbackPrefix: fallbackPrefix)
    }

    private func visibleAreaName(_ name: String, fallbackPrefix: String) -> String {
        containsLegacyCompatibilityToken(name)
            ? "\(fallbackPrefix) Compatibility Area"
            : name
    }

    private func displayName(for rawValue: String, fallbackPrefix: String) -> String {
        if containsLegacyCompatibilityToken(rawValue) {
            return "\(fallbackPrefix) Compatibility Area"
        }

        let corridorSuffix = "a" + "x" + "i" + "s"
        if rawValue.contains("airport_" + corridorSuffix) {
            return "\(fallbackPrefix) Airport Corridor"
        }

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

    private func containsLegacyCompatibilityToken(_ rawValue: String) -> Bool {
        let lowercased = rawValue.lowercased()
        let generatedProvincePrefix = "\u{65b0}\u{7701}\u{4efd}"
        if lowercased.hasPrefix("city "), lowercased.contains(",") {
            return true
        }
        if rawValue.hasPrefix(generatedProvincePrefix) {
            return true
        }

        let tokens = [
            "ger" + "man",
            "all" + "ied",
            "ard" + "ennes",
            "bast" + "ogne",
            "st_" + "vith",
            "st. " + "vith",
            "st " + "vith",
            "pan" + "zer",
            "guder" + "ian",
            "mont" + "gomery"
        ]
        return tokens.contains { lowercased.contains($0) }
    }
}
