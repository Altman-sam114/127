import Foundation

enum ComponentType: String, Codable, Equatable, CaseIterable {
    case tank
    case motorizedInfantry
    case infantry
    case artillery
    case armor
    case mechanizedInfantry
    case lightInfantry
    case recon
    case rocketArtillery
    case airDefense
    case engineer
    case logistics
    case uav
    case loiteringMunition
    case specialForces
    case electronicWarfare

    var baseStats: EffectiveStats {
        switch self {
        case .tank:
            return EffectiveStats(attack: 8, defense: 5, movement: 5, range: 1, vision: 2)
        case .motorizedInfantry:
            return EffectiveStats(attack: 5, defense: 4, movement: 5, range: 1, vision: 3)
        case .infantry:
            return EffectiveStats(attack: 4, defense: 5, movement: 3, range: 1, vision: 2)
        case .artillery:
            return EffectiveStats(attack: 7, defense: 2, movement: 2, range: 2, vision: 2)
        case .armor:
            return EffectiveStats(attack: 8, defense: 5, movement: 5, range: 1, vision: 2)
        case .mechanizedInfantry:
            return EffectiveStats(attack: 5, defense: 4, movement: 5, range: 1, vision: 3)
        case .lightInfantry:
            return EffectiveStats(attack: 4, defense: 5, movement: 3, range: 1, vision: 3)
        case .recon:
            return EffectiveStats(attack: 3, defense: 3, movement: 6, range: 1, vision: 5)
        case .rocketArtillery:
            return EffectiveStats(attack: 8, defense: 2, movement: 3, range: 3, vision: 2)
        case .airDefense:
            return EffectiveStats(attack: 4, defense: 4, movement: 3, range: 2, vision: 4)
        case .engineer:
            return EffectiveStats(attack: 4, defense: 5, movement: 3, range: 1, vision: 2)
        case .logistics:
            return EffectiveStats(attack: 1, defense: 2, movement: 4, range: 1, vision: 2)
        case .uav:
            return EffectiveStats(attack: 2, defense: 1, movement: 6, range: 2, vision: 6)
        case .loiteringMunition:
            return EffectiveStats(attack: 7, defense: 1, movement: 5, range: 2, vision: 4)
        case .specialForces:
            return EffectiveStats(attack: 6, defense: 5, movement: 4, range: 1, vision: 5)
        case .electronicWarfare:
            return EffectiveStats(attack: 2, defense: 3, movement: 3, range: 2, vision: 5)
        }
    }

    var displayCode: String {
        switch self {
        case .tank,
             .armor:
            return "ARM"
        case .motorizedInfantry,
             .mechanizedInfantry:
            return "MECH"
        case .infantry,
             .lightInfantry:
            return "INF"
        case .artillery:
            return "ART"
        case .recon,
             .uav:
            return "ISR"
        case .rocketArtillery,
             .loiteringMunition:
            return "FIRES"
        case .airDefense:
            return "AD"
        case .engineer:
            return "ENG"
        case .logistics:
            return "LOG"
        case .specialForces:
            return "SOF"
        case .electronicWarfare:
            return "EW"
        }
    }

    var isArmorFamily: Bool {
        self == .tank || self == .armor
    }

    var isMechanizedFamily: Bool {
        self == .motorizedInfantry || self == .mechanizedInfantry
    }

    var isFiresFamily: Bool {
        self == .artillery || self == .rocketArtillery || self == .loiteringMunition
    }

    var isAirDefenseFamily: Bool {
        self == .airDefense || self == .electronicWarfare
    }

    var isEngineerFamily: Bool {
        self == .engineer
    }

    var isLogisticsFamily: Bool {
        self == .logistics
    }

    var isLightGroundFamily: Bool {
        self == .infantry || self == .lightInfantry || self == .specialForces
    }

    var isUnmannedFamily: Bool {
        self == .uav || self == .loiteringMunition
    }

    static func dataValue(_ value: String?) -> ComponentType? {
        guard let value else {
            return nil
        }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "tank", "armor", "armour", "armored", "armored_vehicles":
            return normalized == "tank" ? .tank : .armor
        case "motorizedinfantry", "motorized_infantry", "mechanizedinfantry", "mechanized_infantry", "mech_infantry":
            return normalized.hasPrefix("motorized") ? .motorizedInfantry : .mechanizedInfantry
        case "infantry", "light_infantry", "lightinfantry":
            return normalized == "infantry" ? .infantry : .lightInfantry
        case "artillery", "tube_artillery":
            return .artillery
        case "rocket_artillery", "rocketartillery", "mlrs":
            return .rocketArtillery
        case "air_defense", "airdefense", "shorad", "sam":
            return .airDefense
        case "engineer", "engineers", "combat_engineer":
            return .engineer
        case "logistics", "sustainment", "supply":
            return .logistics
        case "uav", "drone", "uas":
            return .uav
        case "loitering_munition", "loiteringmunition":
            return .loiteringMunition
        case "special_forces", "specialforces", "sof":
            return .specialForces
        case "electronic_warfare", "electronicwarfare", "ew":
            return .electronicWarfare
        case "recon", "reconnaissance", "isr":
            return .recon
        default:
            return ComponentType(rawValue: value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let componentType = ComponentType.dataValue(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown component type value: \(rawValue)"
            )
        }
        self = componentType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct DivisionComponent: Codable, Equatable {
    let type: ComponentType
    let weight: Double
}

struct EffectiveStats: Codable, Equatable {
    var attack: Int
    var defense: Int
    var movement: Int
    var range: Int
    var vision: Int
}

enum RetreatMode: String, Codable, Equatable, CaseIterable {
    case retreatable
    case hold
}

struct Division: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var faction: Faction
    var coord: HexCoord
    var facing: HexDirection
    var strength: Int {
        didSet {
            strength = Self.clamp(strength, min: 0, max: maxStrength)
        }
    }
    var maxStrength: Int {
        didSet {
            maxStrength = max(1, maxStrength)
            strength = Self.clamp(strength, min: 0, max: maxStrength)
        }
    }
    var components: [DivisionComponent]
    var supplyState: SupplyState
    var hasActed: Bool
    var retreatMode: RetreatMode
    var isRetreating: Bool
    var retreatTarget: HexCoord?
    var retreatTurnsRemaining: Int {
        didSet {
            retreatTurnsRemaining = max(0, retreatTurnsRemaining)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case faction
        case coord
        case facing
        case hp
        case maxHP
        case strength
        case maxStrength
        case components
        case supplyState
        case hasActed
        case retreatMode
        case isRetreating
        case retreatTarget
        case retreatTurnsRemaining
    }

    init(
        id: String,
        name: String,
        faction: Faction,
        coord: HexCoord,
        facing: HexDirection = .west,
        hp: Int = 10,
        maxHP: Int = 10,
        strength: Int? = nil,
        maxStrength: Int? = nil,
        components: [DivisionComponent],
        supplyState: SupplyState = .supplied,
        hasActed: Bool = false,
        retreatMode: RetreatMode = .retreatable,
        isRetreating: Bool = false,
        retreatTarget: HexCoord? = nil,
        retreatTurnsRemaining: Int = 0
    ) {
        self.id = id
        self.name = name
        self.faction = faction
        self.coord = coord
        self.facing = facing
        let resolvedMaxStrength = max(1, maxStrength ?? maxHP)
        let resolvedStrength = strength ?? hp
        self.maxStrength = resolvedMaxStrength
        self.strength = Self.clamp(resolvedStrength, min: 0, max: resolvedMaxStrength)
        self.components = components
        self.supplyState = supplyState
        self.hasActed = hasActed
        self.retreatMode = retreatMode
        self.isRetreating = isRetreating
        self.retreatTarget = retreatTarget
        self.retreatTurnsRemaining = max(0, retreatTurnsRemaining)
    }

    var hp: Int {
        get { strength }
        set { strength = Self.clamp(newValue, min: 0, max: maxStrength) }
    }

    var maxHP: Int {
        get { maxStrength }
        set {
            maxStrength = max(1, newValue)
            strength = Self.clamp(strength, min: 0, max: maxStrength)
        }
    }

    var isDestroyed: Bool {
        strength <= 0
    }

    var canAct: Bool {
        !hasActed && !isDestroyed && !isRetreating
    }

    var legacyCoord: HexCoord? {
        coord
    }

    func location(in map: MapState) -> RegionId? {
        map.region(for: coord)
    }

    mutating func receiveStrengthDamage(_ amount: Int) {
        guard amount > 0 else {
            return
        }
        strength = Self.clamp(strength - amount, min: 0, max: maxStrength)
    }

    mutating func reinforceStrength(_ amount: Int) {
        guard amount > 0 else {
            return
        }
        strength = Self.clamp(strength + amount, min: 0, max: maxStrength)
    }

    mutating func beginRetreat(to target: HexCoord?, turns: Int = 1) {
        isRetreating = true
        retreatTarget = target
        retreatTurnsRemaining = max(1, turns)
    }

    mutating func advanceRetreatTurn() {
        guard retreatTurnsRemaining > 0 else {
            isRetreating = false
            retreatTarget = nil
            return
        }

        retreatTurnsRemaining -= 1
        if retreatTurnsRemaining == 0 {
            isRetreating = false
            retreatTarget = nil
        }
    }

    mutating func cancelRetreat() {
        isRetreating = false
        retreatTarget = nil
        retreatTurnsRemaining = 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let maxStrength = try container.decodeIfPresent(Int.self, forKey: .maxStrength)
            ?? container.decodeIfPresent(Int.self, forKey: .maxHP)
            ?? 10
        let strength = try container.decodeIfPresent(Int.self, forKey: .strength)
            ?? container.decodeIfPresent(Int.self, forKey: .hp)
            ?? maxStrength

        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            faction: try container.decode(Faction.self, forKey: .faction),
            coord: try container.decode(HexCoord.self, forKey: .coord),
            facing: try container.decodeIfPresent(HexDirection.self, forKey: .facing) ?? .west,
            hp: strength,
            maxHP: maxStrength,
            strength: strength,
            maxStrength: maxStrength,
            components: try container.decode([DivisionComponent].self, forKey: .components),
            supplyState: try container.decodeIfPresent(SupplyState.self, forKey: .supplyState) ?? .supplied,
            hasActed: try container.decodeIfPresent(Bool.self, forKey: .hasActed) ?? false,
            retreatMode: try container.decodeIfPresent(RetreatMode.self, forKey: .retreatMode) ?? .retreatable,
            isRetreating: try container.decodeIfPresent(Bool.self, forKey: .isRetreating) ?? false,
            retreatTarget: try container.decodeIfPresent(HexCoord.self, forKey: .retreatTarget),
            retreatTurnsRemaining: try container.decodeIfPresent(Int.self, forKey: .retreatTurnsRemaining) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(faction, forKey: .faction)
        try container.encode(coord, forKey: .coord)
        try container.encode(facing, forKey: .facing)
        try container.encode(strength, forKey: .strength)
        try container.encode(maxStrength, forKey: .maxStrength)
        try container.encode(strength, forKey: .hp)
        try container.encode(maxStrength, forKey: .maxHP)
        try container.encode(components, forKey: .components)
        try container.encode(supplyState, forKey: .supplyState)
        try container.encode(hasActed, forKey: .hasActed)
        try container.encode(retreatMode, forKey: .retreatMode)
        try container.encode(isRetreating, forKey: .isRetreating)
        try container.encodeIfPresent(retreatTarget, forKey: .retreatTarget)
        try container.encode(retreatTurnsRemaining, forKey: .retreatTurnsRemaining)
    }

    var componentWeightTotal: Double {
        components.reduce(0) { $0 + $1.weight }
    }

    var hasValidComponentWeights: Bool {
        abs(componentWeightTotal - 1.0) <= 0.001
    }

    var baseStats: EffectiveStats {
        EffectiveStats(
            attack: weightedStat(\.attack),
            defense: weightedStat(\.defense),
            movement: weightedStat(\.movement),
            range: selectedMaxStat(\.range),
            vision: selectedMaxStat(\.vision)
        )
    }

    var effectiveStats: EffectiveStats {
        let stats = baseStats

        switch supplyState {
        case .supplied:
            return stats
        case .lowSupply:
            let attackFactor = hasLogisticsSupport ? 0.85 : 0.75
            let movementPenalty = hasLogisticsSupport ? 0 : 1
            return EffectiveStats(
                attack: max(1, Int(Double(stats.attack) * attackFactor)),
                defense: max(1, stats.defense - 1),
                movement: max(1, stats.movement - movementPenalty),
                range: stats.range,
                vision: stats.vision
            )
        case .encircled:
            let attackFactor = hasLogisticsSupport ? 0.60 : 0.50
            let defensePenalty = hasLogisticsSupport ? 1 : 2
            let movementPenalty = hasLogisticsSupport ? 1 : 2
            return EffectiveStats(
                attack: max(1, Int(Double(stats.attack) * attackFactor)),
                defense: max(1, stats.defense - defensePenalty),
                movement: max(1, stats.movement - movementPenalty),
                range: stats.range,
                vision: stats.vision
            )
        }
    }

    var attack: Int {
        effectiveStats.attack
    }

    var defense: Int {
        effectiveStats.defense
    }

    var movement: Int {
        effectiveStats.movement
    }

    var range: Int {
        effectiveStats.range
    }

    var vision: Int {
        effectiveStats.vision
    }

    var isArmor: Bool {
        componentWeight(where: \.isArmorFamily) >= 0.25
    }

    var isMechanized: Bool {
        componentWeight(where: \.isMechanizedFamily) >= 0.25
    }

    var isArtillery: Bool {
        componentWeight(where: \.isFiresFamily) >= 0.45
    }

    var hasAirDefenseSupport: Bool {
        componentWeight(where: \.isAirDefenseFamily) >= 0.20
    }

    var hasEngineerSupport: Bool {
        componentWeight(where: \.isEngineerFamily) >= 0.08
    }

    var hasLogisticsSupport: Bool {
        componentWeight(where: \.isLogisticsFamily) >= 0.10
    }

    var hasUnmannedSupport: Bool {
        componentWeight(where: \.isUnmannedFamily) >= 0.10
    }

    var hasLightGroundCore: Bool {
        componentWeight(where: \.isLightGroundFamily) >= 0.45
    }

    var dominantComponentType: ComponentType? {
        components.sorted { lhs, rhs in
            if lhs.weight == rhs.weight {
                return lhs.type.rawValue < rhs.type.rawValue
            }
            return lhs.weight > rhs.weight
        }.first?.type
    }

    func componentWeight(where predicate: (ComponentType) -> Bool) -> Double {
        components
            .filter { predicate($0.type) }
            .reduce(0.0) { $0 + $1.weight }
    }

    private func weightedStat(_ keyPath: KeyPath<EffectiveStats, Int>) -> Int {
        let value = components.reduce(0.0) { partial, component in
            partial + Double(component.type.baseStats[keyPath: keyPath]) * component.weight
        }
        return max(1, Int(value.rounded()))
    }

    private func selectedMaxStat(_ keyPath: KeyPath<EffectiveStats, Int>) -> Int {
        let weightedComponents = components.filter { $0.weight >= 0.25 }
        let candidates = weightedComponents.isEmpty ? components : weightedComponents
        return candidates.map { $0.type.baseStats[keyPath: keyPath] }.max() ?? 1
    }

    private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}

extension Division {
    var operationalDisplayName: String {
        name.modernFormationDisplayName
    }
}

private extension String {
    var modernFormationDisplayName: String {
        var value = self
        let replacements: [(String, String)] = [
            ("Panzer Division", "Armored Task Force"),
            ("Motorized Division", "Mechanized Task Force"),
            ("Infantry Division", "Infantry Task Force"),
            ("Artillery Division", "Fires Battery"),
            ("Artillery Group", "Fires Battery"),
            ("Anti-Tank Battalion", "Anti-Armor Team"),
            ("Allied Artillery", "Blue Fires"),
            ("Allied Fires", "Blue Fires"),
            ("Bastogne Garrison", "Objective Security Detachment")
        ]

        for replacement in replacements {
            value = value.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
        return value
    }
}

extension Division {
    static func panzer(id: String, name: String, faction: Faction, coord: HexCoord) -> Division {
        Division(
            id: id,
            name: name,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .west : .east,
            components: [
                DivisionComponent(type: .tank, weight: 0.55),
                DivisionComponent(type: .motorizedInfantry, weight: 0.25),
                DivisionComponent(type: .infantry, weight: 0.05),
                DivisionComponent(type: .artillery, weight: 0.15)
            ]
        )
    }

    static func motorized(id: String, name: String, faction: Faction, coord: HexCoord) -> Division {
        Division(
            id: id,
            name: name,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .west : .east,
            components: [
                DivisionComponent(type: .tank, weight: 0.15),
                DivisionComponent(type: .motorizedInfantry, weight: 0.55),
                DivisionComponent(type: .infantry, weight: 0.15),
                DivisionComponent(type: .artillery, weight: 0.15)
            ]
        )
    }

    static func infantry(id: String, name: String, faction: Faction, coord: HexCoord) -> Division {
        Division(
            id: id,
            name: name,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .west : .east,
            components: [
                DivisionComponent(type: .motorizedInfantry, weight: 0.10),
                DivisionComponent(type: .infantry, weight: 0.70),
                DivisionComponent(type: .artillery, weight: 0.20)
            ]
        )
    }

    static func artillery(id: String, name: String, faction: Faction, coord: HexCoord) -> Division {
        Division(
            id: id,
            name: name,
            faction: faction,
            coord: coord,
            facing: faction == .germany ? .west : .east,
            components: [
                DivisionComponent(type: .motorizedInfantry, weight: 0.10),
                DivisionComponent(type: .infantry, weight: 0.30),
                DivisionComponent(type: .artillery, weight: 0.60)
            ]
        )
    }
}
