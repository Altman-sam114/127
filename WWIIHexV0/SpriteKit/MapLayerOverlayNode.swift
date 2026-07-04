import SpriteKit

final class MapLayerOverlayNode: SKNode {
    init(
        state: GameState,
        layer: MapDisplayLayer,
        layout: HexLayout
    ) {
        super.init()
        zPosition = 11

        guard layer != .hex else {
            return
        }

        let calculator = MapLayerOverlayCalculator(state: state)
        if layer == .frontLine {
            addOpaqueBase(state: state, layout: layout)
            addFrontLineChains(calculator.frontLineChains(), layout: layout)
            addSegmentSeparators(calculator.frontLineSegments(), layout: layout)
            return
        }

        let buckets = calculator.buckets(layer: layer)
        let bucketIds = Array(Set(buckets.values.compactMap(\.bucketId))).sorted()
        let bucketPaletteIndexes = Dictionary(uniqueKeysWithValues: bucketIds.enumerated().map { ($0.element, $0.offset) })

        for tile in state.map.tiles.values {
            guard let bucket = buckets[tile.coord] else {
                continue
            }
            guard let bucketId = bucket.bucketId else {
                continue
            }

            let shape = SKShapeNode(path: Self.hexPath(layout: layout))
            shape.position = layout.hexToPixel(tile.coord)
            shape.fillColor = Self.color(
                for: bucketId,
                layer: layer,
                pressure: bucket.pressure,
                paletteIndex: bucketPaletteIndexes[bucketId],
                paletteCount: bucketIds.count
            )
            shape.strokeColor = Self.hexDividerColor(for: layer)
            shape.lineWidth = Self.hexDividerWidth(for: layer, layout: layout)
            shape.zPosition = 11
            addChild(shape)
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

    private static func color(
        for bucketId: String,
        layer: MapDisplayLayer,
        pressure: Double,
        paletteIndex: Int?,
        paletteCount: Int
    ) -> SKColor {
        let alpha: CGFloat
        switch layer {
        case .hex:
            alpha = 0
        case .province:
            alpha = 1
        case .initialTheater, .dynamicTheater:
            alpha = 1
        case .frontLine:
            alpha = 1
        case .deployment:
            alpha = 0.86
        }
        if layer == .deployment {
            return deploymentColor(for: bucketId).withAlphaComponent(alpha)
        }
        return paletteColor(
            layer: layer,
            paletteIndex: paletteIndex,
            paletteCount: paletteCount,
            fallback: bucketId
        ).withAlphaComponent(alpha)
    }

    private func addOpaqueBase(state: GameState, layout: HexLayout) {
        for tile in state.map.tiles.values {
            let shape = SKShapeNode(path: Self.hexPath(layout: layout))
            shape.position = layout.hexToPixel(tile.coord)
            shape.fillColor = SKColor(white: 0.12, alpha: 0.96)
            shape.strokeColor = .clear
            shape.zPosition = 11
            addChild(shape)
        }
    }

    private func addFrontLineChains(_ chains: [FrontLineOverlaySegment], layout: HexLayout) {
        for chain in chains {
            let points = chain.points.map { layout.hexToPixel($0) }
            guard let first = points.first else { continue }
            let path = CGMutablePath()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }

            let line = SKShapeNode(path: path)
            line.strokeColor = Self.frontLineColor(for: chain)
            line.lineWidth = Self.frontLineWidth(for: chain)
            line.lineCap = .round
            line.lineJoin = .round
            line.zPosition = 12
            addChild(line)

            if chain.opposingTheaterIds.count > 1 {
                addDashedOverlay(points: points, color: line.strokeColor, width: line.lineWidth)
            }
        }
    }

    private func addSegmentSeparators(_ segments: [FrontLineOverlaySegment], layout: HexLayout) {
        for segment in segments {
            guard let point = segment.points.first.map({ layout.hexToPixel($0) }) else {
                continue
            }
            addSegmentSeparator(at: point, color: Self.frontLineColor(for: segment), layout: layout)
        }
    }

    private func addDashedOverlay(points: [CGPoint], color: SKColor, width: CGFloat) {
        guard points.count >= 2 else { return }
        for pair in zip(points, points.dropFirst()) {
            addDashedOverlay(from: pair.0, to: pair.1, color: color, width: width)
        }
    }

    private func addDashedOverlay(from start: CGPoint, to end: CGPoint, color: SKColor, width: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let dash: CGFloat = 8
        let gap: CGFloat = 6
        var offset: CGFloat = 0

        while offset < length {
            let next = min(offset + dash, length)
            let startRatio = offset / length
            let endRatio = next / length
            let dashPath = CGMutablePath()
            dashPath.move(to: CGPoint(x: start.x + dx * startRatio, y: start.y + dy * startRatio))
            dashPath.addLine(to: CGPoint(x: start.x + dx * endRatio, y: start.y + dy * endRatio))
            let dashNode = SKShapeNode(path: dashPath)
            dashNode.strokeColor = color.withAlphaComponent(0.45)
            dashNode.lineWidth = width + 1
            dashNode.lineCap = .round
            dashNode.zPosition = 13
            addChild(dashNode)
            offset += dash + gap
        }
    }

    private func addSegmentSeparator(at point: CGPoint, color: SKColor, layout: HexLayout) {
        let radius = max(3, layout.hexSize * 0.12)
        let separator = SKShapeNode(circleOfRadius: radius)
        separator.position = point
        separator.fillColor = SKColor.black.withAlphaComponent(0.92)
        separator.strokeColor = color
        separator.lineWidth = max(1.5, layout.hexSize * 0.05)
        separator.zPosition = 14
        addChild(separator)
    }

    private static func frontLineColor(for segment: FrontLineOverlaySegment) -> SKColor {
        let hue = theaterHue(for: segment.theaterId)
        let pressureBoost = CGFloat(min(0.22, max(0, segment.pressure) * 0.22))
        let warningBoost: CGFloat = segment.type == .encirclement || segment.state == .collapsing ? 0.12 : 0
        let brightness: CGFloat = 0.64 + pressureBoost + warningBoost
        return SKColor(hue: hue, saturation: 0.90, brightness: min(1, brightness), alpha: 1.0)
    }

    private static func deploymentColor(for bucketId: String) -> SKColor {
        let parts = bucketId.split(separator: "_").map(String.init)
        guard let factionRaw = parts.first,
              let faction = Faction(rawValue: factionRaw),
              let role = UnitDeploymentRole(rawValue: parts.dropFirst().joined(separator: "_")) else {
            return SKColor(white: 0.8, alpha: 1)
        }
        return TerrainStyle.deploymentUnitColor(for: faction, role: role)
    }

    private static func theaterHue(for theaterId: TheaterId) -> CGFloat {
        let known: [String: CGFloat] = [
            "northWest": 0.57,
            "northEast": 0.31,
            "southWest": 0.08,
            "southEast": 0.78,
            "theater_1": 0.57,
            "theater_2": 0.31,
            "theater_3": 0.08,
            "theater_4": 0.78,
            "germany_front": 0.02,
            "germany_depth": 0.10,
            "germany_core": 0.14,
            "france_front": 0.58,
            "soviet_front": 0.34,
            "soviet_depth": 0.43
        ]
        if let hue = known[theaterId.rawValue] {
            return hue
        }
        let hash = stableHash(theaterId.rawValue)
        return CGFloat(hash % 360) / 360.0
    }

    private static func paletteColor(
        layer: MapDisplayLayer,
        paletteIndex: Int?,
        paletteCount: Int,
        fallback: String
    ) -> SKColor {
        let index = paletteIndex ?? (stableHash(fallback) % max(1, paletteCount))
        let palette = strategicPalette(for: layer)
        if paletteCount <= palette.count {
            return palette[index % palette.count]
        }

        let hue = CGFloat((index * 137) % 360) / 360.0
        return SKColor(hue: hue, saturation: 0.78, brightness: 0.94, alpha: 1)
    }

    private static func strategicPalette(for layer: MapDisplayLayer) -> [SKColor] {
        switch layer {
        case .province:
            return [
                SKColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1),
                SKColor(red: 0.18, green: 0.62, blue: 0.32, alpha: 1),
                SKColor(red: 0.16, green: 0.48, blue: 0.91, alpha: 1),
                SKColor(red: 0.88, green: 0.70, blue: 0.18, alpha: 1),
                SKColor(red: 0.56, green: 0.32, blue: 0.86, alpha: 1),
                SKColor(red: 0.10, green: 0.70, blue: 0.74, alpha: 1),
                SKColor(red: 0.92, green: 0.46, blue: 0.13, alpha: 1),
                SKColor(red: 0.78, green: 0.22, blue: 0.58, alpha: 1)
            ]
        case .initialTheater, .dynamicTheater:
            return [
                SKColor(red: 0.18, green: 0.42, blue: 0.88, alpha: 1),
                SKColor(red: 0.88, green: 0.32, blue: 0.23, alpha: 1),
                SKColor(red: 0.22, green: 0.68, blue: 0.34, alpha: 1),
                SKColor(red: 0.82, green: 0.66, blue: 0.18, alpha: 1),
                SKColor(red: 0.56, green: 0.31, blue: 0.84, alpha: 1),
                SKColor(red: 0.13, green: 0.68, blue: 0.72, alpha: 1)
            ]
        default:
            return [
                SKColor(red: 0.18, green: 0.42, blue: 0.88, alpha: 1),
                SKColor(red: 0.88, green: 0.32, blue: 0.23, alpha: 1),
                SKColor(red: 0.22, green: 0.68, blue: 0.34, alpha: 1),
                SKColor(red: 0.82, green: 0.66, blue: 0.18, alpha: 1)
            ]
        }
    }

    private static func hexDividerColor(for layer: MapDisplayLayer) -> SKColor {
        switch layer {
        case .province, .initialTheater, .dynamicTheater:
            return SKColor(white: 0.08, alpha: 0.42)
        case .deployment:
            return SKColor(white: 0.05, alpha: 0.30)
        default:
            return .clear
        }
    }

    private static func hexDividerWidth(for layer: MapDisplayLayer, layout: HexLayout) -> CGFloat {
        switch layer {
        case .province, .initialTheater, .dynamicTheater:
            return max(0.9, layout.hexSize * 0.025)
        case .deployment:
            return max(0.7, layout.hexSize * 0.018)
        default:
            return 0
        }
    }

    private static func stableHash(_ value: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return Int(hash)
    }

    private static func frontLineWidth(for segment: FrontLineOverlaySegment) -> CGFloat {
        if segment.type == .encirclement || segment.state == .collapsing {
            return 6
        }
        if segment.type == .breakthrough {
            return 5
        }
        return 3
    }
}
