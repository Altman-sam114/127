import Foundation

struct HexCoord: Codable, Hashable, Equatable {
    let q: Int
    let r: Int

    var s: Int {
        -q - r
    }

    func neighbor(in direction: HexDirection) -> HexCoord {
        HexCoord(q: q + direction.dq, r: r + direction.dr)
    }

    var neighbors: [HexCoord] {
        HexDirection.ordered.map { neighbor(in: $0) }
    }

    func distance(to other: HexCoord) -> Int {
        let dq = q - other.q
        let dr = r - other.r
        let ds = s - other.s
        return (abs(dq) + abs(dr) + abs(ds)) / 2
    }

    func direction(to other: HexCoord) -> HexDirection? {
        let distance = distance(to: other)
        guard distance > 0 else {
            return nil
        }

        return HexDirection.ordered.first { direction in
            q + direction.dq * distance == other.q &&
                r + direction.dr * distance == other.r
        }
    }

    func coordsWithin(distance maxDistance: Int) -> Set<HexCoord> {
        guard maxDistance >= 0 else {
            return []
        }

        var coords = Set<HexCoord>()
        for dq in -maxDistance...maxDistance {
            for dr in -maxDistance...maxDistance {
                let coord = HexCoord(q: q + dq, r: r + dr)
                if self.distance(to: coord) <= maxDistance {
                    coords.insert(coord)
                }
            }
        }
        return coords
    }
}
