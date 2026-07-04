import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

final class MapEditorCanvasScene: SKScene {
    weak var viewModel: MapEditorViewModel?
    var layout = MapEditorHexLayout()
    private let editorCamera = SKCameraNode()
    private var paintedThisDrag: Set<HexCoord> = []
    private var lastPanViewPoint: CGPoint?
    private var rightMouseDownScenePoint: CGPoint?
    private var isPanning = false

    func configure(viewModel: MapEditorViewModel) {
        self.viewModel = viewModel
        isUserInteractionEnabled = true
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.12, green: 0.13, blue: 0.12, alpha: 1)
        if camera == nil {
            addChild(editorCamera)
            camera = editorCamera
        }
        redraw()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layout.origin = CGPoint(x: 54, y: -54)
        redraw()
    }

    func redraw() {
        children
            .filter { $0 !== editorCamera }
            .forEach { $0.removeFromParent() }
        if editorCamera.parent == nil {
            addChild(editorCamera)
            camera = editorCamera
        }
        guard let viewModel else { return }

        drawBackgroundImage(viewModel: viewModel)
        for hex in viewModel.document.sortedHexes {
            draw(hex, viewModel: viewModel)
        }
    }

    func zoomFromScroll(deltaY: CGFloat, anchor: CGPoint) {
        let multiplier: CGFloat = deltaY > 0 ? 0.92 : 1.08
        zoom(multiplier: multiplier, anchor: anchor)
    }

    func panFromScroll(deltaX: CGFloat, deltaY: CGFloat) {
        editorCamera.position.x += deltaX * editorCamera.xScale
        editorCamera.position.y -= deltaY * editorCamera.yScale
    }

    func scenePoint(fromViewPoint viewPoint: CGPoint) -> CGPoint {
        convertPoint(fromView: viewPoint)
    }

    private func drawBackgroundImage(viewModel: MapEditorViewModel) {
        guard let backgroundImage = viewModel.document.backgroundImage,
              let image = platformImage(contentsOfFile: backgroundImage.filePath) else {
            return
        }

        let texture = SKTexture(image: image)
        let node = SKSpriteNode(texture: texture)
        node.name = "底图"
        node.zPosition = -100
        node.alpha = CGFloat(max(0, min(1, backgroundImage.opacity)))
        node.setScale(CGFloat(max(0.05, min(20, backgroundImage.scale))))
        node.position = CGPoint(x: backgroundImage.positionX, y: backgroundImage.positionY)
        addChild(node)
    }

    private func draw(_ hex: MapEditorHex, viewModel: MapEditorViewModel) {
        let path = CGMutablePath()
        let corners = layout.corners(for: hex.coord)
        guard let first = corners.first else { return }
        path.move(to: first)
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.fillColor = fillColor(for: hex, viewModel: viewModel)
        node.strokeColor = strokeColor(for: hex, viewModel: viewModel)
        node.lineWidth = lineWidth(for: hex, viewModel: viewModel)
        addChild(node)

        if viewModel.mode == .hexPainter, hex.hasRoad {
            let road = SKShapeNode(circleOfRadius: 3)
            road.fillColor = SKColor(red: 0.88, green: 0.78, blue: 0.52, alpha: 1)
            road.strokeColor = .clear
            road.position = layout.center(for: hex.coord)
            addChild(road)
        }

        if viewModel.mode == .hexPainter, hex.isSupplySource {
            let supply = SKLabelNode(text: "补")
            supply.fontSize = 11
            supply.fontName = "Helvetica-Bold"
            supply.fontColor = .white
            supply.position = CGPoint(x: layout.center(for: hex.coord).x, y: layout.center(for: hex.coord).y - 5)
            addChild(supply)
        }

        if viewModel.mode == .unitPlanner,
           let unit = viewModel.document.initialUnits.first(where: { $0.coord == hex.coord }) {
            draw(unit, at: hex.coord)
        }

        if shouldDrawPendingMarker(for: hex, viewModel: viewModel) {
            drawPendingMarker(at: hex.coord, mode: viewModel.mode)
        }
    }

    private func draw(_ unit: MapEditorUnitDraft, at coord: HexCoord) {
        let center = layout.center(for: coord)
        let marker = SKShapeNode(rectOf: CGSize(width: 22, height: 14), cornerRadius: 2)
        marker.position = CGPoint(x: center.x, y: center.y + 11)
        marker.fillColor = TerrainStyle.unitFillColor(for: unit.faction)
        marker.strokeColor = TerrainStyle.unitStrokeColor(for: unit.faction)
        marker.lineWidth = 1
        addChild(marker)

        let label = SKLabelNode(text: unit.templateId.mapEditorUnitAbbreviation)
        label.fontSize = 7
        label.fontName = "Helvetica-Bold"
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = marker.position
        addChild(label)
    }

    private func drawPendingMarker(at coord: HexCoord, mode: MapEditorMode) {
        let marker = SKShapeNode(circleOfRadius: 6)
        marker.position = layout.center(for: coord)
        marker.fillColor = pendingColor(for: mode)
        marker.strokeColor = .white
        marker.lineWidth = 1
        addChild(marker)
    }

    private func fillColor(for hex: MapEditorHex, viewModel: MapEditorViewModel) -> SKColor {
        let baseGrid = SKColor(red: 0.28, green: 0.30, blue: 0.27, alpha: 1)
        switch viewModel.mode {
        case .hexPainter:
            let base = TerrainStyle.fillColor(for: hex.terrain)
            guard let controller = hex.controller else { return base }
            let overlay = TerrainStyle.controllerColor(for: controller)
            return base.mapEditorBlend(with: overlay, fraction: 0.26)
        case .regionBuilder:
            guard let regionId = hex.regionId else { return baseGrid }
            return regionColor(for: regionId).withAlphaComponent(0.78)
        case .theaterAssignment:
            guard let regionId = hex.regionId,
                  let theaterId = viewModel.document.regionTheaterAssignments[regionId] else {
                return baseGrid
            }
            return theaterColor(for: theaterId).withAlphaComponent(0.78)
        case .unitPlanner:
            return baseGrid
        }
    }

    private func strokeColor(for hex: MapEditorHex, viewModel: MapEditorViewModel) -> SKColor {
        if viewModel.mode == .regionBuilder, hex.regionId == viewModel.selectedRegionId {
            return .yellow
        }
        if viewModel.mode == .theaterAssignment,
           let regionId = hex.regionId,
           let theaterId = viewModel.document.regionTheaterAssignments[regionId],
           theaterId == viewModel.selectedTheaterId {
            return SKColor(red: 0.20, green: 0.78, blue: 1.0, alpha: 1)
        }
        return SKColor(red: 0.16, green: 0.18, blue: 0.16, alpha: 1)
    }

    private func lineWidth(for hex: MapEditorHex, viewModel: MapEditorViewModel) -> CGFloat {
        if viewModel.mode == .regionBuilder, hex.regionId == viewModel.selectedRegionId {
            return 2.8
        }
        if viewModel.mode == .theaterAssignment,
           let regionId = hex.regionId,
           let theaterId = viewModel.document.regionTheaterAssignments[regionId],
           theaterId == viewModel.selectedTheaterId {
            return 2.8
        }
        return 1
    }

    private func shouldDrawPendingMarker(for hex: MapEditorHex, viewModel: MapEditorViewModel) -> Bool {
        switch viewModel.mode {
        case .hexPainter:
            return false
        case .regionBuilder:
            return viewModel.pendingRegionHexes.contains(hex.coord)
        case .theaterAssignment:
            guard let regionId = hex.regionId else { return false }
            return viewModel.pendingTheaterRegions.contains(regionId)
        case .unitPlanner:
            return viewModel.pendingUnitHexes.contains(hex.coord)
        }
    }

    private func pendingColor(for mode: MapEditorMode) -> SKColor {
        switch mode {
        case .hexPainter:
            return .white
        case .regionBuilder:
            return SKColor(red: 1.0, green: 0.84, blue: 0.18, alpha: 0.92)
        case .theaterAssignment:
            return SKColor(red: 0.15, green: 0.82, blue: 1.0, alpha: 0.92)
        case .unitPlanner:
            return SKColor(red: 0.95, green: 0.25, blue: 0.22, alpha: 0.92)
        }
    }

    private func regionColor(for id: RegionId) -> SKColor {
        indexedColor(key: id.rawValue, palette: Self.regionPalette)
    }

    private func theaterColor(for id: TheaterId) -> SKColor {
        indexedColor(key: id.rawValue, palette: Self.theaterPalette)
    }

    private func indexedColor(key: String, palette: [SKColor]) -> SKColor {
        let hash = abs(key.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return palette[hash % palette.count]
    }

    private static let regionPalette: [SKColor] = [
        SKColor(red: 0.90, green: 0.34, blue: 0.31, alpha: 1),
        SKColor(red: 0.23, green: 0.62, blue: 0.90, alpha: 1),
        SKColor(red: 0.30, green: 0.74, blue: 0.45, alpha: 1),
        SKColor(red: 0.95, green: 0.70, blue: 0.25, alpha: 1),
        SKColor(red: 0.64, green: 0.48, blue: 0.86, alpha: 1),
        SKColor(red: 0.20, green: 0.72, blue: 0.68, alpha: 1),
        SKColor(red: 0.92, green: 0.46, blue: 0.70, alpha: 1),
        SKColor(red: 0.55, green: 0.66, blue: 0.25, alpha: 1)
    ]

    private static let theaterPalette: [SKColor] = [
        SKColor(red: 0.78, green: 0.18, blue: 0.18, alpha: 1),
        SKColor(red: 0.12, green: 0.36, blue: 0.76, alpha: 1),
        SKColor(red: 0.16, green: 0.56, blue: 0.24, alpha: 1),
        SKColor(red: 0.76, green: 0.48, blue: 0.10, alpha: 1),
        SKColor(red: 0.42, green: 0.24, blue: 0.70, alpha: 1),
        SKColor(red: 0.10, green: 0.54, blue: 0.52, alpha: 1),
        SKColor(red: 0.70, green: 0.20, blue: 0.48, alpha: 1),
        SKColor(red: 0.42, green: 0.52, blue: 0.12, alpha: 1)
    ]

    private func handle(_ point: CGPoint) {
        guard let viewModel else { return }
        let coord = layout.coord(at: point)
        guard !paintedThisDrag.contains(coord) else { return }
        paintedThisDrag.insert(coord)
        viewModel.applyPrimaryAction(at: coord)
        redraw()
    }

    private func pan(from previousViewPoint: CGPoint, to currentViewPoint: CGPoint) {
        editorCamera.position = MapEditorViewportMath.cameraPositionAfterPan(
            currentPosition: editorCamera.position,
            previousViewPoint: previousViewPoint,
            currentViewPoint: currentViewPoint,
            scale: editorCamera.xScale
        )
    }

    private func zoom(multiplier: CGFloat, anchor: CGPoint) {
        let oldScale = editorCamera.xScale
        let nextScale = max(0.18, min(6.0, oldScale * multiplier))
        editorCamera.position = MapEditorViewportMath.cameraPositionAfterZoom(
            currentPosition: editorCamera.position,
            anchor: anchor,
            oldScale: oldScale,
            newScale: nextScale
        )
        editorCamera.setScale(nextScale)
    }

    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        paintedThisDrag.removeAll()
        handle(touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        handle(touch.location(in: self))
    }
    #endif

    #if os(macOS)
    private func platformImage(contentsOfFile path: String) -> NSImage? {
        NSImage(contentsOfFile: path)
    }

    private func viewPoint(from event: NSEvent) -> CGPoint {
        guard let view else { return event.location(in: self) }
        return view.convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        paintedThisDrag.removeAll()
        isPanning = event.modifierFlags.contains(.option)
        lastPanViewPoint = viewPoint(from: event)
        if !isPanning {
            handle(event.location(in: self))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.location(in: self)
        let currentViewPoint = viewPoint(from: event)
        if isPanning, let lastPanViewPoint {
            pan(from: lastPanViewPoint, to: currentViewPoint)
            self.lastPanViewPoint = currentViewPoint
        } else {
            handle(point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        paintedThisDrag.removeAll()
        isPanning = false
        lastPanViewPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        isPanning = true
        lastPanViewPoint = viewPoint(from: event)
        rightMouseDownScenePoint = event.location(in: self)
    }

    override func rightMouseDragged(with event: NSEvent) {
        let currentViewPoint = viewPoint(from: event)
        if let lastPanViewPoint {
            pan(from: lastPanViewPoint, to: currentViewPoint)
        }
        self.lastPanViewPoint = currentViewPoint
    }

    override func rightMouseUp(with event: NSEvent) {
        if let viewModel,
           let rightMouseDownScenePoint,
           rightMouseDownScenePoint.mapEditorDistance(to: event.location(in: self)) < 7 {
            viewModel.inspect(at: layout.coord(at: event.location(in: self)))
        }
        isPanning = false
        lastPanViewPoint = nil
        rightMouseDownScenePoint = nil
    }

    override func otherMouseDown(with event: NSEvent) {
        isPanning = true
        lastPanViewPoint = viewPoint(from: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        let currentViewPoint = viewPoint(from: event)
        if let lastPanViewPoint {
            pan(from: lastPanViewPoint, to: currentViewPoint)
        }
        self.lastPanViewPoint = currentViewPoint
    }

    override func otherMouseUp(with event: NSEvent) {
        isPanning = false
        lastPanViewPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            editorCamera.position.x += event.scrollingDeltaY * editorCamera.xScale
        } else if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let multiplier: CGFloat = event.scrollingDeltaY > 0 ? 0.92 : 1.08
            zoom(multiplier: multiplier, anchor: event.location(in: self))
        } else {
            editorCamera.position.x += event.scrollingDeltaX * editorCamera.xScale
            editorCamera.position.y -= event.scrollingDeltaY * editorCamera.yScale
        }
    }

    override func magnify(with event: NSEvent) {
        let multiplier = max(0.5, min(1.5, 1 - event.magnification))
        zoom(multiplier: multiplier, anchor: event.location(in: self))
    }
    #endif

    #if os(iOS)
    private func platformImage(contentsOfFile path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }
    #endif
}

private extension CGPoint {
    func mapEditorDistance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

private extension SKColor {
    func mapEditorBlend(with color: SKColor, fraction: CGFloat) -> SKColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return SKColor(
            red: r1 * (1 - f) + r2 * f,
            green: g1 * (1 - f) + g2 * f,
            blue: b1 * (1 - f) + b2 * f,
            alpha: a1 * (1 - f) + a2 * f
        )
    }
}

private extension String {
    var mapEditorUnitAbbreviation: String {
        if localizedStandardContains("recon") {
            return "ISR"
        }
        if localizedStandardContains("fires") || localizedStandardContains("artillery") {
            return "FIR"
        }
        if localizedStandardContains("air_defense") {
            return "AD"
        }
        if localizedStandardContains("engineer") {
            return "ENG"
        }
        if localizedStandardContains("logistics") {
            return "LOG"
        }
        if localizedStandardContains("armor")
            || localizedStandardContains("armored")
            || localizedStandardContains("panzer")
            || localizedStandardContains("tank") {
            return "ARM"
        }
        if localizedStandardContains("mechanized") || localizedStandardContains("motorized") {
            return "MECH"
        }
        return "INF"
    }
}
