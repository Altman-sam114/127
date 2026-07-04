import SpriteKit

final class RegionOverlayNode: SKNode {
    init(region: RegionNode, layout: HexLayout, isSelected: Bool) {
        super.init()
        zPosition = 12

        for hex in region.displayHexes {
            let outline = SKShapeNode(path: Self.hexPath(layout: layout))
            outline.position = layout.hexToPixel(hex)
            outline.fillColor = .clear
            outline.strokeColor = isSelected
                ? TerrainStyle.selectedStroke
                : TerrainStyle.controllerColor(for: region.controller).withAlphaComponent(0.42)
            outline.lineWidth = isSelected ? max(2, layout.hexSize * 0.07) : max(1, layout.hexSize * 0.03)
            outline.zPosition = isSelected ? 13 : 12
            addChild(outline)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func hexPath(layout: HexLayout) -> CGPath {
        let points = layout.polygonPoints(center: .zero)
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
