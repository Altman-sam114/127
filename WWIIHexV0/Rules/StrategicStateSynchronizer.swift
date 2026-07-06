import Foundation

struct StrategicStateSyncResult: Equatable {
    let affectedRegionIds: [RegionId]
    let changedRegionIds: [RegionId]
    let updatedFrontLineRegionIds: Set<RegionId>
}

struct StrategicStateSynchronizer {
    @discardableResult
    func synchronizeAfterOccupationChange(
        in state: inout GameState,
        affectedRegionIds: [RegionId],
        turn: Int? = nil,
        relatedRecordId: String? = nil,
        emitRegionOwnerEvents: Bool = true
    ) -> StrategicStateSyncResult {
        let changedRegionIds = RegionOccupationRules().aggregateControl(in: &state)
        let affected = stableUnique(affectedRegionIds + changedRegionIds)
        guard !affected.isEmpty else {
            return StrategicStateSyncResult(
                affectedRegionIds: [],
                changedRegionIds: [],
                updatedFrontLineRegionIds: []
            )
        }

        let syncTurn = turn ?? state.turn
        state.theaterState = TheaterSystem().updateTheaters(
            state: state.theaterState,
            map: state.map,
            divisions: state.divisions,
            turn: syncTurn,
            force: true
        )

        let frontEvents = affected.map { regionId in
            changedRegionIds.contains(regionId)
                ? FrontLineEvent.regionControllerChanged(regionId)
                : FrontLineEvent.occupationChanged(regionId)
        }
        state.frontLineState = FrontLineManager().update(
            state: state.frontLineState,
            map: state.map,
            theaterState: state.theaterState,
            divisions: state.divisions,
            turn: syncTurn,
            events: frontEvents
        )

        let deploymentEvents = affected.map(WarDeploymentEvent.regionControllerChanged)
        state.warDeploymentState = WarDeploymentManager().update(
            state: state.warDeploymentState,
            map: state.map,
            divisions: state.divisions,
            turn: syncTurn,
            events: deploymentEvents
        )

        if emitRegionOwnerEvents {
            for regionId in changedRegionIds {
                guard let region = state.map.region(id: regionId) else { continue }
                state.appendEvent(
                    "\(region.name) controller changed to \(region.controller.displayName).",
                    category: .regionOwnerChange,
                    relatedRecordId: relatedRecordId
                )
            }
        }

        return StrategicStateSyncResult(
            affectedRegionIds: affected,
            changedRegionIds: changedRegionIds,
            updatedFrontLineRegionIds: state.frontLineState.diagnostics.updatedRegionIds.reduce(into: Set<RegionId>()) {
                $0.insert($1)
            }
        )
    }

    private func stableUnique(_ values: [RegionId]) -> [RegionId] {
        var seen: Set<RegionId> = []
        var result: [RegionId] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result.sorted { $0.rawValue < $1.rawValue }
    }
}
