import CoreGraphics
import Foundation

struct MapEditorHexLayout: Equatable {
    var hexSize: CGFloat
    var origin: CGPoint

    init(hexSize: CGFloat = 22, origin: CGPoint = CGPoint(x: 48, y: 48)) {
        self.hexSize = hexSize
        self.origin = origin
    }

    func center(for coord: HexCoord) -> CGPoint {
        let q = CGFloat(coord.q)
        let r = CGFloat(coord.r)
        return CGPoint(
            x: origin.x + hexSize * sqrt(3) * (q + r / 2),
            y: origin.y - hexSize * 1.5 * r
        )
    }

    func corners(for coord: HexCoord) -> [CGPoint] {
        let center = center(for: coord)
        return (0..<6).map { index in
            let angle = CGFloat.pi / 180 * (60 * CGFloat(index) - 30)
            return CGPoint(
                x: center.x + hexSize * cos(angle),
                y: center.y + hexSize * sin(angle)
            )
        }
    }

    func coord(at point: CGPoint) -> HexCoord {
        let x = (point.x - origin.x) / hexSize
        let y = -(point.y - origin.y) / hexSize
        let q = sqrt(3) / 3 * x - 1.0 / 3.0 * y
        let r = 2.0 / 3.0 * y
        return cubeRound(q: q, r: r)
    }

    private func cubeRound(q: CGFloat, r: CGFloat) -> HexCoord {
        let x = q
        let z = r
        let y = -x - z

        var rx = round(x)
        var ry = round(y)
        var rz = round(z)

        let xDiff = abs(rx - x)
        let yDiff = abs(ry - y)
        let zDiff = abs(rz - z)

        if xDiff > yDiff && xDiff > zDiff {
            rx = -ry - rz
        } else if yDiff > zDiff {
            ry = -rx - rz
        } else {
            rz = -rx - ry
        }

        return HexCoord(q: Int(rx), r: Int(rz))
    }
}

enum MapEditorViewportMath {
    static func cameraPositionAfterPan(
        currentPosition: CGPoint,
        previousViewPoint: CGPoint,
        currentViewPoint: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: currentPosition.x + (previousViewPoint.x - currentViewPoint.x) * scale,
            y: currentPosition.y + (previousViewPoint.y - currentViewPoint.y) * scale
        )
    }

    static func cameraPositionAfterZoom(
        currentPosition: CGPoint,
        anchor: CGPoint,
        oldScale: CGFloat,
        newScale: CGFloat
    ) -> CGPoint {
        guard oldScale > 0 else { return currentPosition }
        let ratio = newScale / oldScale
        return CGPoint(
            x: anchor.x + (currentPosition.x - anchor.x) * ratio,
            y: anchor.y + (currentPosition.y - anchor.y) * ratio
        )
    }
}
