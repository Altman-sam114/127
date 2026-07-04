        for cabinet in dataSet.cabinetState.cabinets {
            if cabinet.ruler == nil {
                errors.append(DataValidationError(message: "\(cabinet.faction.rawValue) cabinet is missing a ruler agent."))
            }
        }
