import SpriteKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

final class BoardScene: SKScene {
    private var renderState: BoardRenderState?
    private var layout: HexLayout?
    private var onHexTapped: ((HexCoord) -> Void)?
    // v0.21: camera 平移
    private var boardCamera: SKCameraNode?
    private var lastDragViewPosition: CGPoint?
    private var lastDragScenePosition: CGPoint?
    private var totalDragDistance: CGFloat = 0
    private let tapThreshold: CGFloat = 8

    override init(size: CGSize) {
        super.init(size: size)
        // v0.21: resizeFill 让 scene 跟 SKView 同尺寸；hex 大小由 HexLayout.fixed 决定（不塞满），
        // 超出 view 的 hex 画在 scene 外，由平移（任务 0.2）暴露。
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.16, green: 0.20, blue: 0.18, alpha: 1.0)
        setupCamera()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.16, green: 0.20, blue: 0.18, alpha: 1.0)
        setupCamera()
    }

    private func setupCamera() {
        let camera = SKCameraNode()
        self.camera = camera
        addChild(camera)
        self.boardCamera = camera
    }

    func configure(with renderState: BoardRenderState, onHexTapped: @escaping (HexCoord) -> Void) {
        self.renderState = renderState
        self.onHexTapped = onHexTapped
        redraw()
    }

    override func didMove(to view: SKView) {
        redraw()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        redraw()
    }

    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        lastDragViewPosition = touch.location(in: view)
        totalDragDistance = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let view,
              let prev = lastDragViewPosition,
              let camera = boardCamera else {
            return
        }
        let current = touch.location(in: view)
        let delta = CGPoint(x: current.x - prev.x, y: current.y - prev.y)
        totalDragDistance += hypot(delta.x, delta.y)
        // 拖动方向反转（手指右移 → 内容右移 → camera 左移）
        camera.position.x -= delta.x
        camera.position.y += delta.y
        clampCamera()
        lastDragViewPosition = current
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            lastDragViewPosition = nil
        }
        // 累计拖动超阈值视为平移，不当 tap
        guard totalDragDistance < tapThreshold,
              let touch = touches.first,
              let layout,
              let state = renderState?.gameState else {
            return
        }

        let point = touch.location(in: self)
        let coord = layout.pixelToHex(point)
        guard state.map.contains(coord) else {
            return
        }

        onHexTapped?(coord)
    }
    #endif

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        lastDragScenePosition = event.location(in: self)
        totalDragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let prev = lastDragScenePosition,
              let camera = boardCamera else {
            return
        }
        let current = event.location(in: self)
        let delta = CGPoint(x: current.x - prev.x, y: current.y - prev.y)
        totalDragDistance += hypot(delta.x, delta.y)
        camera.position.x -= delta.x
        camera.position.y -= delta.y
        clampCamera()
        lastDragScenePosition = current
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            lastDragScenePosition = nil
        }
        guard totalDragDistance < tapThreshold,
              let layout,
              let state = renderState?.gameState else {
            return
        }

        let point = event.location(in: self)
        let coord = layout.pixelToHex(point)
        guard state.map.contains(coord) else {
            return
        }

        onHexTapped?(coord)
    }

    func handleScrollWheel(_ event: NSEvent, anchor: CGPoint) {
        guard let camera = boardCamera else { return }

        if event.modifierFlags.contains(.shift) || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            camera.position.x += event.scrollingDeltaX * camera.xScale
            camera.position.y -= event.scrollingDeltaY * camera.yScale
            clampCamera()
            return
        }

        let multiplier: CGFloat = event.scrollingDeltaY > 0 ? 0.92 : 1.08
        zoomCamera(multiplier: multiplier, anchor: anchor)
    }

    func handleMagnify(_ event: NSEvent, anchor: CGPoint) {
        let multiplier = max(0.5, min(1.5, 1 - event.magnification))
        zoomCamera(multiplier: multiplier, anchor: anchor)
    }
    #endif

    /// 限制 camera 在地图边界内，避免拖空。
    private func clampCamera() {
        guard let layout, let state = renderState?.gameState else { return }
        let mapWidth = state.map.width
        let mapHeight = state.map.height
        // 地图四角像素（fixed layout 下）
        let corners: [CGPoint] = [
            layout.hexToPixel(HexCoord(q: 0, r: 0)),
            layout.hexToPixel(HexCoord(q: mapWidth - 1, r: 0)),
            layout.hexToPixel(HexCoord(q: 0, r: mapHeight - 1)),
            layout.hexToPixel(HexCoord(q: mapWidth - 1, r: mapHeight - 1))
        ]
        let minX = corners.map(\.x).min() ?? 0
        let maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let maxY = corners.map(\.y).max() ?? 0
        let margin = layout.hexSize
        if let camera = boardCamera {
            camera.position.x = min(max(camera.position.x, minX - margin), maxX + margin)
            camera.position.y = min(max(camera.position.y, minY - margin), maxY + margin)
        }
    }

    private func zoomCamera(multiplier: CGFloat, anchor: CGPoint) {
        guard let camera = boardCamera else { return }
        let oldScale = camera.xScale
        let nextScale = max(0.45, min(2.4, oldScale * multiplier))
        guard nextScale != oldScale else { return }

        let ratio = nextScale / oldScale
        camera.position = CGPoint(
            x: anchor.x + (camera.position.x - anchor.x) * ratio,
            y: anchor.y + (camera.position.y - anchor.y) * ratio
        )
        camera.setScale(nextScale)
        clampCamera()
    }

    private func redraw() {
        // v0.21: 保 camera，只清内容节点
        let cameraRef = boardCamera
        removeAllChildren()
        if let cameraRef {
            addChild(cameraRef)
            self.camera = cameraRef
            self.boardCamera = cameraRef
        }

        guard let renderState else {
            drawEmptyState()
            return
        }

        let state = renderState.gameState
        // v0.21: 固定大 hexSize（~36），不再 fitted 塞满 scene。超出靠平移（任务 0.2）。
        let layout = HexLayout.fixed(mapWidth: state.map.width, mapHeight: state.map.height)
        self.layout = layout

        drawTiles(renderState: renderState, layout: layout)
        drawLayerOverlay(renderState: renderState, layout: layout)
        drawRegionOverlays(renderState: renderState, layout: layout)
        drawRoads(map: state.map, layout: layout)
        drawRivers(map: state.map, layout: layout)
        drawModernC2Overlays(renderState: renderState, layout: layout)
        drawPlannedOperations(renderState: renderState, layout: layout)
        drawUnits(renderState: renderState, layout: layout)
    }

    private func drawTiles(renderState: BoardRenderState, layout: HexLayout) {
        let state = renderState.gameState
        let supplyByCoord = Dictionary(uniqueKeysWithValues: state.map.supplySources.compactMap { source in
            state.map.controllingFaction(for: source).map { (source.coord, $0) }
        })
        let adapter = renderState.displayAdapter

        for tile in state.map.tiles.values.sorted(by: tileSort) {
            guard let displayState = adapter.hexDisplayState(for: tile.coord, viewerFaction: renderState.viewerFaction) else {
                continue
            }

            let node = HexNode(
                displayState: displayState,
                layout: layout,
                supplySourceFaction: supplyByCoord[tile.coord],
                isSelected: renderState.selectedHex == tile.coord,
                isMoveHighlighted: renderState.movementHighlights.contains(tile.coord),
                isAttackHighlighted: renderState.attackHighlights.contains(tile.coord)
            )
            addChild(node)
        }
    }

    private func drawRoads(map: MapState, layout: HexLayout) {
        let directions: [HexDirection] = [.east, .southEast, .southWest]

        for tile in map.tiles.values where tile.hasRoad {
            for direction in directions {
                let nextCoord = tile.coord.neighbor(in: direction)
                guard let nextTile = map.tile(at: nextCoord),
                      nextTile.hasRoad else {
                    continue
                }

                let start = layout.hexToPixel(tile.coord)
                let end = layout.hexToPixel(nextCoord)
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)

                let road = SKShapeNode(path: path)
                road.strokeColor = TerrainStyle.roadStroke
                road.lineWidth = max(2, layout.hexSize * 0.08)
                road.lineCap = .round
                road.zPosition = 15
                addChild(road)
            }
        }
    }

    private func drawRegionOverlays(renderState: BoardRenderState, layout: HexLayout) {
        guard renderState.mapDisplayLayer == .hex else {
            return
        }

        for region in renderState.gameState.map.regions.values {
            let node = RegionOverlayNode(
                region: region,
                layout: layout,
                isSelected: renderState.selectedRegionId == region.id
            )
            addChild(node)
        }
    }

    private func drawLayerOverlay(renderState: BoardRenderState, layout: HexLayout) {
        let node = MapLayerOverlayNode(
            state: renderState.gameState,
            layer: renderState.mapDisplayLayer,
            layout: layout
        )
        addChild(node)
    }

    private func drawRivers(map: MapState, layout: HexLayout) {
        for tile in map.tiles.values {
            let center = layout.hexToPixel(tile.coord)
            for direction in HexDirection.ordered where tile.riverEdges.contains(direction) {
                let edge = layout.edgePoints(center: center, direction: direction)
                let path = CGMutablePath()
                path.move(to: edge.0)
                path.addLine(to: edge.1)

                let river = SKShapeNode(path: path)
                river.strokeColor = TerrainStyle.riverStroke
                river.lineWidth = max(3, layout.hexSize * 0.10)
                river.lineCap = .round
                river.zPosition = 18
                addChild(river)
            }
        }
    }

    private func drawModernC2Overlays(renderState: BoardRenderState, layout: HexLayout) {
        guard renderState.modernC2OverlayEnabled,
              renderState.mapDisplayLayer != .frontLine else {
            return
        }

        drawSensorCoverage(renderState: renderState, layout: layout)
        drawEWEffects(renderState: renderState, layout: layout)
        drawFireSupportResults(renderState: renderState, layout: layout)
        drawContacts(renderState: renderState, layout: layout)
    }

    private func drawSensorCoverage(renderState: BoardRenderState, layout: HexLayout) {
        let side = renderState.viewerFaction.alignment
        let coverages = renderState.gameState.operationalAwareness.sensorCoverage.filter {
            $0.side == side && renderState.gameState.map.contains($0.coord)
        }

        for coverage in coverages {
            let center = layout.hexToPixel(coverage.coord)
            let overlay = SKShapeNode(path: modernHexPath(center: center, layout: layout, inset: 0.16))
            let alpha = min(0.22, 0.06 + CGFloat(coverage.quality) * 0.018)
            overlay.fillColor = modernSensorColor.withAlphaComponent(alpha)
            overlay.strokeColor = coverage.jammed
                ? modernEWColor.withAlphaComponent(0.42)
                : modernSensorColor.withAlphaComponent(0.18)
            overlay.lineWidth = coverage.jammed ? 2 : 1
            overlay.zPosition = 21
            addChild(overlay)
        }
    }

    private func drawEWEffects(renderState: BoardRenderState, layout: HexLayout) {
        for effect in renderState.gameState.operationalAwareness.ewEffects {
            for coord in effect.area where renderState.gameState.map.contains(coord) {
                let center = layout.hexToPixel(coord)
                let marker = SKShapeNode(path: modernHexPath(center: center, layout: layout, inset: 0.04))
                marker.fillColor = modernEWColor.withAlphaComponent(0.10)
                marker.strokeColor = modernEWColor.withAlphaComponent(0.58)
                marker.lineWidth = max(1.5, layout.hexSize * 0.04)
                marker.zPosition = 22
                addChild(marker)
            }
        }
    }

    private func drawFireSupportResults(renderState: BoardRenderState, layout: HexLayout) {
        let results = renderState.gameState.fireSupportState.lastMissionResults.suffix(6)
        for result in results where result.side == renderState.viewerFaction.alignment {
            guard let center = fireResultPoint(for: result, state: renderState.gameState, layout: layout) else {
                continue
            }

            let radius = max(8, layout.hexSize * 0.22)
            let marker = SKShapeNode(circleOfRadius: radius)
            marker.position = center
            marker.fillColor = fireResultColor(for: result.status).withAlphaComponent(0.16)
            marker.strokeColor = fireResultColor(for: result.status).withAlphaComponent(0.86)
            marker.lineWidth = max(2, layout.hexSize * 0.06)
            marker.zPosition = 31
            addChild(marker)

            let label = SKLabelNode(text: result.status == .failed ? "!" : "F")
            label.fontName = "AvenirNext-Bold"
            label.fontSize = max(8, layout.hexSize * 0.18)
            label.fontColor = SKColor(white: 1, alpha: 0.94)
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = center
            label.zPosition = 32
            addChild(label)
        }
    }

    private func drawContacts(renderState: BoardRenderState, layout: HexLayout) {
        let contacts = renderState.gameState.operationalAwareness.visibleContacts(for: renderState.viewerFaction)
        for contact in contacts where renderState.gameState.map.contains(contact.lastKnownCoord) {
            let center = layout.hexToPixel(contact.lastKnownCoord)
            let radius = contact.confidence == .confirmed ? layout.hexSize * 0.18 : layout.hexSize * 0.15
            let marker = SKShapeNode(circleOfRadius: max(6, radius))
            marker.position = CGPoint(x: center.x, y: center.y + layout.hexSize * 0.42)
            marker.fillColor = contactColor(for: contact.confidence).withAlphaComponent(0.78)
            marker.strokeColor = SKColor(white: 1, alpha: 0.84)
            marker.lineWidth = contact.confidence >= .high ? 2 : 1
            marker.zPosition = 42
            addChild(marker)

            let label = SKLabelNode(text: contactLabel(for: contact))
            label.fontName = "AvenirNext-Bold"
            label.fontSize = max(7, layout.hexSize * 0.16)
            label.fontColor = SKColor(white: 0.98, alpha: 1)
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = marker.position
            label.zPosition = 43
            addChild(label)
        }
    }

    private func fireResultPoint(for result: FireMissionResult, state: GameState, layout: HexLayout) -> CGPoint? {
        switch result.target {
        case .contact(let id):
            guard let contact = state.operationalAwareness.contacts[id] else {
                return nil
            }
            return layout.hexToPixel(contact.lastKnownCoord)
        case .hex(let coord):
            guard state.map.contains(coord) else {
                return nil
            }
            return layout.hexToPixel(coord)
        case .region(let regionId):
            guard let coord = state.map.representativeHex(for: regionId) else {
                return nil
            }
            return layout.hexToPixel(coord)
        }
    }

    private func contactLabel(for contact: ContactTrack) -> String {
        switch contact.estimatedType {
        case .armor:
            return "A"
        case .infantry:
            return "I"
        case .artillery:
            return "F"
        case .airDefense:
            return "AD"
        case .logistics:
            return "L"
        case .unknown:
            return contact.confidence >= .high ? "?" : "?"
        }
    }

    private func contactColor(for confidence: ContactConfidence) -> SKColor {
        switch confidence {
        case .low:
            return SKColor(red: 0.72, green: 0.76, blue: 0.78, alpha: 1)
        case .medium:
            return SKColor(red: 0.95, green: 0.66, blue: 0.22, alpha: 1)
        case .high:
            return SKColor(red: 0.96, green: 0.42, blue: 0.20, alpha: 1)
        case .confirmed:
            return SKColor(red: 0.86, green: 0.16, blue: 0.16, alpha: 1)
        }
    }

    private func fireResultColor(for status: FireMissionOutcomeStatus) -> SKColor {
        switch status {
        case .success:
            return SKColor(red: 0.95, green: 0.44, blue: 0.16, alpha: 1)
        case .degraded:
            return SKColor(red: 0.96, green: 0.70, blue: 0.26, alpha: 1)
        case .failed:
            return SKColor(red: 0.62, green: 0.28, blue: 0.84, alpha: 1)
        case .suppressed:
            return SKColor(red: 0.20, green: 0.64, blue: 0.84, alpha: 1)
        }
    }

    private func modernHexPath(center: CGPoint, layout: HexLayout, inset: CGFloat) -> CGPath {
        let points = layout.polygonPoints(center: center).map { point in
            CGPoint(
                x: center.x + (point.x - center.x) * (1 - inset),
                y: center.y + (point.y - center.y) * (1 - inset)
            )
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func drawPlannedOperations(renderState: BoardRenderState, layout: HexLayout) {
        guard renderState.mapDisplayLayer != .frontLine else {
            return
        }

        let operations = renderState.gameState.playerCommandState.plannedOperations.filter {
            $0.turn == renderState.gameState.turn && $0.faction == renderState.viewerFaction
        }
        guard !operations.isEmpty else {
            return
        }

        for operation in operations {
            guard let sourcePoint = operationPoint(
                regionId: operation.sourceRegionId,
                zoneId: operation.zoneId,
                state: renderState.gameState,
                layout: layout
            ) else {
                continue
            }

            if let targetRegionId = operation.targetRegionId,
               let targetPoint = operationPoint(
                regionId: targetRegionId,
                zoneId: operation.zoneId,
                state: renderState.gameState,
                layout: layout
               ) {
                drawOperationArrow(
                    from: sourcePoint,
                    to: targetPoint,
                    type: operation.directiveType
                )
            } else {
                drawOperationHoldMarker(at: sourcePoint)
            }
        }
    }

    private func operationPoint(
        regionId: RegionId?,
        zoneId: FrontZoneId,
        state: GameState,
        layout: HexLayout
    ) -> CGPoint? {
        if let regionId,
           let hex = state.map.representativeHex(for: regionId) {
            return layout.hexToPixel(hex)
        }

        guard let zone = state.warDeploymentState.frontZones[zoneId] else {
            return nil
        }
        let hqRegionId = zone.generalAssignment?.hqRegionId ?? zone.regionIds.first
        guard let hqRegionId,
              let hex = state.map.representativeHex(for: hqRegionId) else {
            return nil
        }
        return layout.hexToPixel(hex)
    }

    private func drawOperationArrow(from start: CGPoint, to end: CGPoint, type: DirectiveType) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let line = SKShapeNode(path: path)
        line.strokeColor = operationColor(for: type)
        line.lineWidth = 4
        line.lineCap = .round
        line.zPosition = 26
        addChild(line)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 14
        let spread: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - cos(angle - spread) * arrowLength,
            y: end.y - sin(angle - spread) * arrowLength
        )
        let right = CGPoint(
            x: end.x - cos(angle + spread) * arrowLength,
            y: end.y - sin(angle + spread) * arrowLength
        )
        let headPath = CGMutablePath()
        headPath.move(to: end)
        headPath.addLine(to: left)
        headPath.move(to: end)
        headPath.addLine(to: right)

        let head = SKShapeNode(path: headPath)
        head.strokeColor = operationColor(for: type)
        head.lineWidth = 4
        head.lineCap = .round
        head.zPosition = 27
        addChild(head)
    }

    private func drawOperationHoldMarker(at point: CGPoint) {
        let marker = SKShapeNode(circleOfRadius: 18)
        marker.position = point
        marker.strokeColor = operationColor(for: .defend)
        marker.fillColor = operationColor(for: .defend).withAlphaComponent(0.16)
        marker.lineWidth = 4
        marker.zPosition = 26
        addChild(marker)
    }

    private func operationColor(for type: DirectiveType) -> SKColor {
        switch type {
        case .attack:
            return SKColor(red: 0.95, green: 0.32, blue: 0.20, alpha: 0.85)
        case .defend:
            return SKColor(red: 0.18, green: 0.64, blue: 0.38, alpha: 0.85)
        }
    }

    private var modernSensorColor: SKColor {
        SKColor(red: 0.20, green: 0.66, blue: 0.82, alpha: 1)
    }

    private var modernEWColor: SKColor {
        SKColor(red: 0.62, green: 0.28, blue: 0.84, alpha: 1)
    }

    private func drawUnits(renderState: BoardRenderState, layout: HexLayout) {
        guard renderState.mapDisplayLayer != .frontLine else {
            return
        }
        let adapter = renderState.displayAdapter
        let placements = adapter.unitPlacements(viewerFaction: renderState.viewerFaction)
        let deploymentManager = WarDeploymentManager()

        let orderedDivisions = renderState.gameState.divisions
            .map { division in
                (division: division, displayHex: adapter.unitDisplayHex(for: division) ?? division.coord)
            }
            .sorted { lhs, rhs in
                let lhsHex = lhs.displayHex
                let rhsHex = rhs.displayHex
                if lhsHex.r == rhsHex.r {
                    return lhsHex.q < rhsHex.q
                }
                return lhsHex.r < rhsHex.r
            }

        for item in orderedDivisions {
            let division = item.division
            guard let placement = placements[division.id] else {
                continue
            }

            let node = UnitNode(
                division: division,
                layout: layout,
                placement: placement,
                isSelected: renderState.selectedUnitId == division.id,
                isPlayerManaged: renderState.gameState.playerCommandState.micromanagedDivisionIds.contains(division.id),
                fillColorOverride: deploymentColorOverride(
                    for: division,
                    renderState: renderState,
                    deploymentManager: deploymentManager
                )
            )
            addChild(node)
        }
    }

    private func deploymentColorOverride(
        for division: Division,
        renderState: BoardRenderState,
        deploymentManager: WarDeploymentManager
    ) -> SKColor? {
        guard renderState.mapDisplayLayer == .deployment else {
            return nil
        }
        let role = deploymentManager.deploymentRole(
            for: division,
            in: renderState.gameState.map,
            state: renderState.gameState.warDeploymentState
        )
        return TerrainStyle.deploymentUnitColor(for: division.faction, role: role)
    }

    private func drawEmptyState() {
        let field = SKShapeNode(
            rectOf: CGSize(width: max(size.width - 48, 120), height: max(size.height - 48, 120)),
            cornerRadius: 8
        )
        field.fillColor = SKColor(red: 0.24, green: 0.30, blue: 0.22, alpha: 1.0)
        field.strokeColor = SKColor(red: 0.55, green: 0.60, blue: 0.48, alpha: 1.0)
        field.lineWidth = 2
        field.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(field)

        let title = SKLabelNode(text: "Modern Command Board")
        title.fontName = "AvenirNext-DemiBold"
        title.fontSize = 24
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
        addChild(title)
    }

    private func tileSort(_ lhs: HexTile, _ rhs: HexTile) -> Bool {
        if lhs.coord.r == rhs.coord.r {
            return lhs.coord.q < rhs.coord.q
        }
        return lhs.coord.r < rhs.coord.r
    }
}
