    var victoryState: VictoryState
    var selectedUnitSummary: String?
    var eventLog: [GameLogEntry]
    var cabinetState: CabinetState = .empty
    var directiveBoard: DirectiveBoard = .empty

    static func initial(cabinetState: CabinetState = .empty) -> GameState {
        let map = MapState.ardennesV0()

        return GameState(
            divisions: [
                .panzer(
                    id: "ger_panzer_1",
                    name: "1st Panzer Division",
                    faction: .germany,
                    coord: HexCoord(q: 9, r: 3)
                ),
                .motorized(
                    id: "ger_motorized_1",
                    name: "2nd Motorized Division",
                    faction: .germany,
                    coord: HexCoord(q: 9, r: 4)
                ),
                .infantry(
                    id: "ger_infantry_1",
                    name: "26th Infantry Division",
                    faction: .germany,
                    coord: HexCoord(q: 10, r: 5)
                ),
                .artillery(
                    id: "ger_artillery_1",
                    name: "7th Artillery Division",
                    faction: .germany,
                    coord: HexCoord(q: 10, r: 3)
                ),
                .infantry(
                    id: "all_infantry_1",
                    name: "101st Infantry Division",
                    faction: .allies,
                    coord: HexCoord(q: 4, r: 5)
                ),
                .infantry(
                    id: "all_anti_tank_1",
                    name: "9th Anti-Tank Battalion",
                    faction: .allies,
                    coord: HexCoord(q: 5, r: 5)
                ),
                .artillery(
                    id: "all_artillery_1",
                    name: "4th Allied Artillery Group",
                    faction: .allies,
                    coord: HexCoord(q: 3, r: 5)
                ),
                .infantry(
                    id: "all_garrison_1",
                    name: "Bastogne Garrison",
                    faction: .allies,
                    coord: HexCoord(q: 5, r: 6)
                )
            ],
            victoryState: .ongoing,
                    message: "Ardennes V0 scenario initialized."
                )
            ],
            cabinetState: cabinetState,
            directiveBoard: .empty
        )
    }
