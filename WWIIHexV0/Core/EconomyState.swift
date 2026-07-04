import Foundation

struct EconomyResources: Codable, Equatable {
    var manpower: Int
    var industry: Int
    var supplies: Int

    init(manpower: Int = 0, industry: Int = 0, supplies: Int = 0) {
        self.manpower = max(0, manpower)
        self.industry = max(0, industry)
        self.supplies = max(0, supplies)
    }

    static var zero: EconomyResources {
        EconomyResources()
    }

    var isEmpty: Bool {
        manpower == 0 && industry == 0 && supplies == 0
    }

    func canAfford(_ cost: EconomyResources) -> Bool {
        manpower >= cost.manpower &&
            industry >= cost.industry &&
            supplies >= cost.supplies
    }

    mutating func add(_ resources: EconomyResources) {
        manpower = max(0, manpower + resources.manpower)
        industry = max(0, industry + resources.industry)
        supplies = max(0, supplies + resources.supplies)
    }

    mutating func subtract(_ resources: EconomyResources) {
        manpower = max(0, manpower - resources.manpower)
        industry = max(0, industry - resources.industry)
        supplies = max(0, supplies - resources.supplies)
    }
}

enum CityLevel: String, Codable, Equatable, CaseIterable {
    case none
    case village
    case town
    case metropolis

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .village:
            return "Village"
        case .town:
            return "Town"
        case .metropolis:
            return "Metropolis"
        }
    }

    var industryValue: Int {
        switch self {
        case .none:
            return 0
        case .village:
            return 1
        case .town:
            return 3
        case .metropolis:
            return 6
        }
    }

    var manpowerGrowth: Int {
        switch self {
        case .none:
            return 0
        case .village:
            return 8
        case .town:
            return 20
        case .metropolis:
            return 45
        }
    }
}

enum ProductionKind: String, Codable, Equatable, CaseIterable, Identifiable {
    case infantryDivision
    case panzerDivision
    case motorizedDivision
    case artilleryDivision
    case supplyStockpile

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .infantryDivision:
            return "Infantry Division"
        case .panzerDivision:
            return "Panzer Division"
        case .motorizedDivision:
            return "Motorized Division"
        case .artilleryDivision:
            return "Artillery Group"
        case .supplyStockpile:
            return "Supply Stockpile"
        }
    }

    var cost: EconomyResources {
        switch self {
        case .infantryDivision:
            return EconomyResources(manpower: 90, industry: 35, supplies: 12)
        case .panzerDivision:
            return EconomyResources(manpower: 70, industry: 95, supplies: 24)
        case .motorizedDivision:
            return EconomyResources(manpower: 80, industry: 65, supplies: 18)
        case .artilleryDivision:
            return EconomyResources(manpower: 55, industry: 55, supplies: 14)
        case .supplyStockpile:
            return EconomyResources(manpower: 0, industry: 25, supplies: 0)
        }
    }

    var buildTurns: Int {
        switch self {
        case .infantryDivision:
            return 2
        case .panzerDivision:
            return 4
        case .motorizedDivision:
            return 3
        case .artilleryDivision:
            return 2
        case .supplyStockpile:
            return 1
        }
    }

    var supplyOutput: Int {
        switch self {
        case .supplyStockpile:
            return 85
        case .infantryDivision,
             .panzerDivision,
             .motorizedDivision,
             .artilleryDivision:
            return 0
        }
    }
}

struct ProductionOrder: Identifiable, Codable, Equatable {
    let id: String
    let faction: Faction
    let kind: ProductionKind
    var remainingTurns: Int
    let totalTurns: Int
    let createdTurn: Int
    var deploymentRegionId: RegionId?

    init(
        id: String,
        faction: Faction,
        kind: ProductionKind,
        remainingTurns: Int? = nil,
        totalTurns: Int? = nil,
        createdTurn: Int,
        deploymentRegionId: RegionId? = nil
    ) {
        self.id = id
        self.faction = faction
        self.kind = kind
        self.remainingTurns = max(0, remainingTurns ?? kind.buildTurns)
        self.totalTurns = max(1, totalTurns ?? kind.buildTurns)
        self.createdTurn = max(1, createdTurn)
        self.deploymentRegionId = deploymentRegionId
    }

    var isReady: Bool {
        remainingTurns == 0
    }
}

struct FactionEconomyLedger: Codable, Equatable {
    let faction: Faction
    var stockpile: EconomyResources
    var lastIncome: EconomyResources
    var lastUpkeep: EconomyResources
    var lastReinforcementSpend: EconomyResources
    var productionQueue: [ProductionOrder]
    var lastUpdatedTurn: Int

    init(
        faction: Faction,
        stockpile: EconomyResources = .zero,
        lastIncome: EconomyResources = .zero,
        lastUpkeep: EconomyResources = .zero,
        lastReinforcementSpend: EconomyResources = .zero,
        productionQueue: [ProductionOrder] = [],
        lastUpdatedTurn: Int = 1
    ) {
        self.faction = faction
        self.stockpile = stockpile
        self.lastIncome = lastIncome
        self.lastUpkeep = lastUpkeep
        self.lastReinforcementSpend = lastReinforcementSpend
        self.productionQueue = productionQueue
        self.lastUpdatedTurn = max(1, lastUpdatedTurn)
    }
}

struct EconomyState: Codable, Equatable {
    var ledgers: [Faction: FactionEconomyLedger]
    var lastResolvedTurn: Int?

    init(
        ledgers: [Faction: FactionEconomyLedger] = [:],
        lastResolvedTurn: Int? = nil
    ) {
        self.ledgers = ledgers
        self.lastResolvedTurn = lastResolvedTurn
    }

    static var empty: EconomyState {
        EconomyState()
    }

    func ledger(for faction: Faction) -> FactionEconomyLedger {
        ledgers[faction] ?? FactionEconomyLedger(faction: faction)
    }

    mutating func updateLedger(_ ledger: FactionEconomyLedger) {
        ledgers[ledger.faction] = ledger
    }
}

extension Division {
    var isInfantryHeavy: Bool {
        components.contains { $0.type == .infantry && $0.weight >= 0.50 }
    }

    var isMechanizedHeavy: Bool {
        isArmor || components.contains { $0.type == .motorizedInfantry && $0.weight >= 0.50 }
    }
}
