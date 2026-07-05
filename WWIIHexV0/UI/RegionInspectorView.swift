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

                LabeledContent("Hex Dynamic Theater") {
                    Text(state.selectedHexDynamicTheaterId?.rawValue ?? "None")
                }

                LabeledContent("Hex FrontZone") {
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

            LabeledContent("Supply") {
                Text("\(state.region.supplyValue)")
            }

            LabeledContent("Factories") {
                Text("\(state.region.factories)")
            }

            LabeledContent("Output") {
                Text("MP \(state.economicOutput.manpower), IC \(state.economicOutput.industry), SUP \(state.economicOutput.supplies)")
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Theater") {
                Text(state.theaterId?.rawValue ?? "None")
            }

            LabeledContent("FrontZone") {
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

            LabeledContent("Friendly Units") {
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
        return divisions.map(\.name).joined(separator: ", ")
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
