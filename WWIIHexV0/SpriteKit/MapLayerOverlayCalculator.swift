import Foundation

struct MapLayerOverlayBucket: Equatable {
    let hex: HexCoord
    let layer: MapDisplayLayer
    let bucketId: String?
    let pressure: Double
}

struct FrontLineOverlaySegment: Equatable {
    let id: String
    let lineId: String
    let theaterId: TheaterId
    let opposingTheaterIds: [TheaterId]
    let regionA: RegionId
    let regionB: RegionId
    let points: [HexCoord]
    let pressure: Double
    let type: FrontLineType
    let state: FrontLineOperationalState
}

struct MapLayerOverlayCalculator {
    let state: GameState

    func bucket(for hex: HexCoord, layer: MapDisplayLayer) -> MapLayerOverlayBucket {
        let regionId = state.map.region(for: hex)
        let bucketId: String?
        let pressure: Double

        switch layer {
        case .hex:
            bucketId = "\(hex.q),\(hex.r)"
            pressure = 0
        case .province:
            bucketId = regionId?.rawValue
            pressure = 0
        case .initialTheater:
            bucketId = regionId.flatMap { state.theaterState.initialSnapshot?.regionToTheater[$0]?.rawValue }
            pressure = 0
        case .dynamicTheater:
            bucketId = state.theaterState.dynamicTheaterId(for: hex, map: state.map)?.rawValue
            pressure = 0
        case .frontLine:
            if let regionId,
               let frontState = state.frontLineState.regionStates[regionId],
               !frontState.frontLines.isEmpty {
                bucketId = frontState.frontLines.map(\.id.rawValue).sorted().joined(separator: "+")
                pressure = frontState.frontLines
                    .flatMap(\.segments)
                    .map(\.pressureLevel)
                    .max() ?? 0
            } else {
                bucketId = nil
                pressure = 0
            }
        case .deployment:
            if let division = state.division(at: hex) {
                let role = WarDeploymentManager().deploymentRole(
                    for: division,
                    in: state.map,
                    state: state.warDeploymentState
                )
                bucketId = "\(division.faction.rawValue)_\(role.rawValue)"
            } else {
                bucketId = nil
            }
            pressure = 0
        }

        return MapLayerOverlayBucket(hex: hex, layer: layer, bucketId: bucketId, pressure: pressure)
    }

    func buckets(layer: MapDisplayLayer) -> [HexCoord: MapLayerOverlayBucket] {
        Dictionary(
            uniqueKeysWithValues: state.map.tiles.keys.map {
                ($0, bucket(for: $0, layer: layer))
            }
        )
    }

    func frontLineSegments() -> [FrontLineOverlaySegment] {
        state.frontLineState.frontLines.values
            .flatMap { frontLine in
                frontLine.segments.compactMap { segment in
                    let points = friendlyBoundaryHexes(
                        friendlyRegionId: segment.regionA,
                        enemyRegionId: segment.regionB,
                        friendlyTheaterId: frontLine.theaterId
                    )
                    guard points.count >= 1 else {
                        return nil
                    }
                    return FrontLineOverlaySegment(
                        id: "\(frontLine.id.rawValue)_\(segment.id)",
                        lineId: frontLine.id.rawValue,
                        theaterId: frontLine.theaterId,
                        opposingTheaterIds: frontLine.opposingTheaterIds,
                        regionA: segment.regionA,
                        regionB: segment.regionB,
                        points: points,
                        pressure: segment.pressureLevel,
                        type: frontLine.type,
                        state: frontLine.state
                    )
                }
            }
            .sorted {
                if $0.theaterId.rawValue == $1.theaterId.rawValue {
                    return $0.id < $1.id
                }
                return $0.theaterId.rawValue < $1.theaterId.rawValue
            }
    }

    func frontLineChains() -> [FrontLineOverlaySegment] {
        let segments = frontLineSegments()
        let grouped = Dictionary(grouping: segments) { $0.lineId }
        return grouped.values.flatMap { lineSegments in
            makeChains(from: lineSegments)
        }
        .sorted {
            if $0.theaterId.rawValue == $1.theaterId.rawValue {
                return $0.id < $1.id
            }
            return $0.theaterId.rawValue < $1.theaterId.rawValue
        }
    }

    private func friendlyBoundaryHexes(
        friendlyRegionId: RegionId,
        enemyRegionId: RegionId,
        friendlyTheaterId: TheaterId
    ) -> [HexCoord] {
        guard let friendlyRegion = state.map.region(id: friendlyRegionId) else {
            return []
        }

        let boundary = friendlyRegion.displayHexes.filter { hex in
            if state.theaterState.dynamicTheaterId(for: hex, map: state.map) != friendlyTheaterId {
                return false
            }
            return hex.neighbors.contains { neighbor in
                guard state.map.region(for: neighbor) == enemyRegionId else {
                    return false
                }
                if let neighborTheaterId = state.theaterState.dynamicTheaterId(for: neighbor, map: state.map) {
                    return neighborTheaterId != friendlyTheaterId
                }
                return true
            }
        }

        return boundary.isEmpty ? [friendlyRegion.representativeHex] : boundary
    }

    private func makeChains(from segments: [FrontLineOverlaySegment]) -> [FrontLineOverlaySegment] {
        guard let seed = segments.sorted(by: { $0.id < $1.id }).first else {
            return []
        }

        let uniquePoints = Array(Set(segments.flatMap(\.points)))
        let chains = uniquePoints.topologyChains()
        return chains.enumerated().compactMap { index, points in
            guard !points.isEmpty else { return nil }
            let pressure = segments.map(\.pressure).max() ?? seed.pressure
            let type: FrontLineType = segments.contains { $0.type == .encirclement } ? .encirclement : seed.type
            let state: FrontLineOperationalState = segments.contains { $0.state == .collapsing } ? .collapsing : seed.state
            return FrontLineOverlaySegment(
                id: "\(seed.lineId)_chain_\(index)",
                lineId: seed.lineId,
                theaterId: seed.theaterId,
                opposingTheaterIds: seed.opposingTheaterIds,
                regionA: seed.regionA,
                regionB: seed.regionB,
                points: points,
                pressure: pressure,
                type: type,
                state: state
            )
        }
    }
}

private extension Array where Element == HexCoord {
    func topologyChains() -> [[HexCoord]] {
        let allPoints = Set(self)
        var remaining = allPoints
        let adjacency = Dictionary(
            uniqueKeysWithValues: allPoints.map { point in
                (
                    point,
                    point.neighbors
                        .filter { allPoints.contains($0) }
                        .sortedByStableCoord()
                )
            }
        )
        var chains: [[HexCoord]] = []

        while !remaining.isEmpty {
            let start = nextChainStart(in: remaining, adjacency: adjacency)
            var chain: [HexCoord] = []
            var previous: HexCoord?
            var current: HexCoord? = start

            while let point = current, remaining.contains(point) {
                chain.append(point)
                remaining.remove(point)

                let next = (adjacency[point] ?? [])
                    .filter { $0 != previous && remaining.contains($0) }
                    .first
                previous = point
                current = next
            }

            chains.append(chain)
        }

        return chains
    }

    private func nextChainStart(
        in remaining: Set<HexCoord>,
        adjacency: [HexCoord: [HexCoord]]
    ) -> HexCoord {
        let sorted = Array(remaining).sortedByStableCoord()
        return sorted.first { (adjacency[$0] ?? []).filter { remaining.contains($0) }.count <= 1 } ?? sorted[0]
    }

    private func sortedByStableCoord() -> [HexCoord] {
        sorted {
            if $0.q == $1.q {
                return $0.r < $1.r
            }
            return $0.q < $1.q
        }
    }
}
