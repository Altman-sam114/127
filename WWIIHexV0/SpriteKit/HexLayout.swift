import CoreGraphics
import Foundation

struct HexLayout: Equatable {
    struct Insets: Equatable {
        var top: CGFloat
        var left: CGFloat
        var bottom: CGFloat
        var right: CGFloat

        static let board = Insets(top: 18, left: 18, bottom: 18, right: 18)
    }

    let hexSize: CGFloat
    let origin: CGPoint

    func hexToPixel(_ coord: HexCoord) -> CGPoint {
        let q = CGFloat(coord.q)
        let r = CGFloat(coord.r)
        let rootThree = CGFloat(3).squareRoot()
        let x = hexSize * rootThree * (q + r / 2)
        let y = -hexSize * 1.5 * r
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }

    func pixelToHex(_ point: CGPoint) -> HexCoord {
        let x = (point.x - origin.x) / hexSize
        let y = -(point.y - origin.y) / hexSize
        let rootThree = CGFloat(3).squareRoot()
        let q = rootThree / 3 * x - y / 3
        let r = 2 * y / 3
        return Self.roundAxial(q: q, r: r)
    }

    func polygonPoints(center: CGPoint) -> [CGPoint] {
        (0..<6).map { index in
            let angle = CGFloat.pi / 180 * CGFloat(30 + 60 * index)
            return CGPoint(
                x: center.x + hexSize * CGFloat(cos(Double(angle))),
                y: center.y + hexSize * CGFloat(sin(Double(angle)))
            )
        }
    }

    func edgePoints(center: CGPoint, direction: HexDirection) -> (CGPoint, CGPoint) {
        let points = polygonPoints(center: center)

        switch direction {
        case .east:
            return (points[5], points[0])
        case .northEast:
            return (points[0], points[1])
        case .northWest:
            return (points[1], points[2])
        case .west:
            return (points[2], points[3])
        case .southWest:
            return (points[3], points[4])
        case .southEast:
            return (points[4], points[5])
        }
    }

    static func fitted(mapWidth: Int, mapHeight: Int, in sceneSize: CGSize, insets: Insets = .board) -> HexLayout {
        let unitLayout = HexLayout(hexSize: 1, origin: .zero)
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for q in 0..<mapWidth {
            for r in 0..<mapHeight {
                let center = unitLayout.hexToPixel(HexCoord(q: q, r: r))
                for point in unitLayout.polygonPoints(center: center) {
                    minX = min(minX, point.x)
                    minY = min(minY, point.y)
                    maxX = max(maxX, point.x)
                    maxY = max(maxY, point.y)
                }
            }
        }

        let rawWidth = max(maxX - minX, 1)
        let rawHeight = max(maxY - minY, 1)
        let availableWidth = max(sceneSize.width - insets.left - insets.right, 1)
        let availableHeight = max(sceneSize.height - insets.top - insets.bottom, 1)
        let size = max(8, min(availableWidth / rawWidth, availableHeight / rawHeight))

        let fittedWidth = rawWidth * size
        let fittedHeight = rawHeight * size
        let origin = CGPoint(
            x: insets.left + (availableWidth - fittedWidth) / 2 - minX * size,
            y: insets.bottom + (availableHeight - fittedHeight) / 2 - minY * size
        )

        return HexLayout(hexSize: size, origin: origin)
    }

    /// v0.21: 固定 hexSize 布局，不塞满 scene。用于放大显示 + 拖动平移。
    /// hexSize 固定（默认 36，约 fitted 默认 8-12 的 3-4x），origin 居中地图边界。
    /// 超出 scene 的部分由 BoardScene 平移（任务 0.2）处理。
    static func fixed(mapWidth: Int, mapHeight: Int, hexSize: CGFloat = 36) -> HexLayout {
        let unitLayout = HexLayout(hexSize: 1, origin: .zero)
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude

        for q in 0..<mapWidth {
            for r in 0..<mapHeight {
                let center = unitLayout.hexToPixel(HexCoord(q: q, r: r))
                for point in unitLayout.polygonPoints(center: center) {
                    minX = min(minX, point.x)
                    minY = min(minY, point.y)
                }
            }
        }

        // origin 使地图左下角 hex 中心对齐到 (hexSize, hexSize) 内边距
        let origin = CGPoint(
            x: hexSize - minX * hexSize,
            y: hexSize - minY * hexSize
        )

        return HexLayout(hexSize: hexSize, origin: origin)
    }

    private static func roundAxial(q: CGFloat, r: CGFloat) -> HexCoord {
        let s = -q - r
        var roundedQ = q.rounded()
        var roundedR = r.rounded()
        let roundedS = s.rounded()

        let qDiff = abs(roundedQ - q)
        let rDiff = abs(roundedR - r)
        let sDiff = abs(roundedS - s)

        if qDiff > rDiff && qDiff > sDiff {
            roundedQ = -roundedR - roundedS
        } else if rDiff > sDiff {
            roundedR = -roundedQ - roundedS
        }

        return HexCoord(q: Int(roundedQ), r: Int(roundedR))
    }
}
