import Foundation

struct WarDirectiveRecord: Identifiable, Codable, Equatable {
    let id: String
    let issuerId: String
    let turn: Int
    let faction: Faction
    let zoneId: FrontZoneId?
    let directiveType: DirectiveType?
    let targetRegionIds: [RegionId]
    let commandResults: [CommandResultSummary]
    let diagnostics: [String]
    let category: CommandCategory?
    let tactic: TacticName?
    let commanderAgentId: String?
    let commandTarget: DirectiveTarget?

    init(
        id: String,
        issuerId: String,
        turn: Int,
        faction: Faction,
        zoneId: FrontZoneId?,
        directiveType: DirectiveType?,
        targetRegionIds: [RegionId] = [],
        commandResults: [CommandResultSummary] = [],
        diagnostics: [String] = [],
        category: CommandCategory? = nil,
        tactic: TacticName? = nil,
        commanderAgentId: String? = nil,
        commandTarget: DirectiveTarget? = nil
    ) {
        self.id = id
        self.issuerId = issuerId
        self.turn = turn
        self.faction = faction
        self.zoneId = zoneId
        self.directiveType = directiveType
        self.targetRegionIds = targetRegionIds
        self.commandResults = commandResults
        self.diagnostics = diagnostics
        self.category = category
        self.tactic = tactic
        self.commanderAgentId = commanderAgentId
        self.commandTarget = commandTarget
    }
}
