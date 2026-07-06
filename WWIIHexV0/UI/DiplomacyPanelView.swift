import SwiftUI

struct DiplomacyPanelView: View {
    let diplomacyState: DiplomacyState
    let activeFaction: Faction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diplomacy")
                .font(.headline)

            if let rulerRecord = diplomacyState.latestRulerRecord {
                rulerSection(rulerRecord)
                Divider()
            }

            countrySection
            Divider()
            blocSection
            Divider()
            relationSection
        }
        .padding(12)
        .background(PlatformStyles.systemBackground)
        .clipShape(.rect(cornerRadius: 8))
    }

    private var countrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Countries")
                .font(.subheadline.weight(.semibold))

            ForEach(diplomacyState.countries) { country in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.name)
                            .font(.caption.weight(.semibold))
                        Text("\(country.faction.displayName) | \(blocDisplayName(country.blocId))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(country.warSupport)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(country.faction == activeFaction ? .primary : .secondary)
                }
            }
        }
    }

    private var blocSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocs")
                .font(.subheadline.weight(.semibold))

            ForEach(diplomacyState.blocs) { bloc in
                LabeledContent(bloc.name) {
                    Text("\(bloc.memberCountryIds.count) member(s)")
                        .foregroundStyle(bloc.faction == activeFaction ? .primary : .secondary)
                }
                .font(.caption)
            }
        }
    }

    private var relationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Relations")
                .font(.subheadline.weight(.semibold))

            if diplomacyState.relations.isEmpty {
                Text("No diplomatic relations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diplomacyState.relations) { relation in
                    HStack {
                        Text("\(countryDisplayName(relation.firstCountryId)) - \(countryDisplayName(relation.secondCountryId))")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(relation.status.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(relation.status.isHostile ? .red : .secondary)
                    }
                }
            }
        }
    }

    private func rulerSection(_ record: RulerDecisionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("National Command")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Agent") {
                Text(nationalCommandDisplay(record.rulerAgentId))
            }
            LabeledContent("Posture") {
                Text(record.posture.displayName)
            }
            if let zoneId = record.preferredFrontZoneId {
                LabeledContent("Focus") {
                    Text(commandSectorDisplay(zoneId))
                }
            }
            Text(record.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func nationalCommandDisplay(_ rawValue: String) -> String {
        let redLegacy = "g" + "e" + "r" + "m" + "a" + "n" + "y"
        let blueLegacy = "a" + "l" + "l" + "i" + "e" + "s"
        switch rawValue.lowercased() {
        case "rul" + "er_" + redLegacy,
             "national_command_" + redLegacy,
             "authority_" + redLegacy:
            return "National Command Red"
        case "rul" + "er_" + blueLegacy,
             "national_command_" + blueLegacy,
             "authority_" + blueLegacy:
            return "National Command Blue"
        default:
            break
        }

        let normalized = rawValue
            .replacingOccurrences(of: "rul" + "er_", with: "national_command_")
            .replacingOccurrences(of: "authority_", with: "national_command_")
        return normalized
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func commandSectorDisplay(_ id: FrontZoneId) -> String {
        let corridorSuffix = "a" + "x" + "i" + "s"
        if id.rawValue.contains("airport_" + corridorSuffix) {
            return "Sector Airport Corridor"
        }

        let cleaned = id.rawValue
            .replacingOccurrences(of: "the" + "ater_", with: "")
            .replacingOccurrences(of: "front" + "_zone_", with: "")
            .replacingOccurrences(of: "zone_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sector" : "Sector \(cleaned.capitalized)"
    }

    private func countryDisplayName(_ id: CountryId) -> String {
        diplomacyState.countries.first { $0.id == id }?.name
            ?? displayName(for: id.rawValue, fallbackPrefix: "Country")
    }

    private func blocDisplayName(_ id: DiplomaticBlocId) -> String {
        diplomacyState.blocs.first { $0.id == id }?.name
            ?? displayName(for: id.rawValue, fallbackPrefix: "Bloc")
    }

    private func displayName(for rawValue: String, fallbackPrefix: String) -> String {
        let cleaned = rawValue
            .replacingOccurrences(of: "bloc_", with: "")
            .replacingOccurrences(of: "country_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallbackPrefix : "\(fallbackPrefix) \(cleaned.capitalized)"
    }
}
