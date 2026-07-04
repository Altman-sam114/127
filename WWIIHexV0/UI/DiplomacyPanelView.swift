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
                        Text("\(country.faction.displayName) | \(country.blocId.rawValue)")
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
                        Text("\(relation.firstCountryId.rawValue) - \(relation.secondCountryId.rawValue)")
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
            Text("Ruler")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Agent") {
                Text(record.rulerAgentId)
            }
            LabeledContent("Posture") {
                Text(record.posture.displayName)
            }
            if let zoneId = record.preferredFrontZoneId {
                LabeledContent("Focus") {
                    Text(zoneId.rawValue)
                }
            }
            Text(record.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
