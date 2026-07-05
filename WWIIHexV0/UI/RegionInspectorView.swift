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
            Text(state.region.name)
                .font(.subheadline.weight(.semibold))

            if let selectedHex = state.selectedHex {
                LabeledContent("Hex") {
                    Text("\(selectedHex.q),\(selectedHex.r)")
                }

                LabeledContent("Hex Controller") {
                    Text(state.selectedHexController?.displayName ?? "None")
                }

                LabeledContent("Hex Operational Zone") {
                    Text(state.selectedHexDynamicTheaterId?.rawValue ?? "None")
                }

                LabeledContent("Hex Command Sector") {
                    Text(state.selectedHexFrontZoneId?.rawValue ?? "None")
                }
            }

            LabeledContent("Controller") {
                Text(state.region.controller.displayName)
            }

            LabeledContent("Terrain") {
                Text(state.region.terrain.displayName)
            }

            LabeledContent("City") {
                Text(state.region.city?.name ?? "None")
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
                Text(state.theaterId?.rawValue ?? "None")
            }

            LabeledContent("Command Sector") {
                Text(state.frontZoneId?.rawValue ?? "None")
            }

            LabeledContent("Front Pressure") {
                Text(state.frontPressure, format: .number.precision(.fractionLength(2)))
            }

            LabeledContent("Infrastructure") {
                Text("\(state.region.infrastructure)")
            }

            LabeledContent("Objectives") {
                Text(state.objectiveNames.isEmpty ? "None" : state.objectiveNames.joined(separator: ", "))
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
}
