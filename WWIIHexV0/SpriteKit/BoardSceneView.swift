import SpriteKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
struct BoardSceneView: NSViewRepresentable {
    let renderState: BoardRenderState
    let onHexTapped: (HexCoord) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHexTapped: onHexTapped)
    }

    func makeNSView(context: Context) -> BoardEventSKView {
        let view = BoardEventSKView()
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        view.backgroundColor = SKColor(red: 0.16, green: 0.20, blue: 0.18, alpha: 1)

        let scene = BoardScene(size: CGSize(width: 1400, height: 900))
        context.coordinator.scene = scene
        view.sceneRef = scene
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ nsView: BoardEventSKView, context: Context) {
        context.coordinator.onHexTapped = onHexTapped

        if context.coordinator.scene == nil {
            let scene = BoardScene(size: nsView.bounds.size == .zero ? CGSize(width: 1400, height: 900) : nsView.bounds.size)
            context.coordinator.scene = scene
            nsView.sceneRef = scene
            nsView.presentScene(scene)
        }

        let coordinator = context.coordinator
        coordinator.scene?.configure(with: renderState) { coord in
            coordinator.onHexTapped(coord)
        }
    }

    final class Coordinator {
        var scene: BoardScene?
        var onHexTapped: (HexCoord) -> Void

        init(onHexTapped: @escaping (HexCoord) -> Void) {
            self.onHexTapped = onHexTapped
        }
    }
}

final class BoardEventSKView: SKView {
    weak var sceneRef: BoardScene?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let sceneRef else {
            super.scrollWheel(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let scenePoint = sceneRef.convertPoint(fromView: viewPoint)
        sceneRef.handleScrollWheel(event, anchor: scenePoint)
    }

    override func magnify(with event: NSEvent) {
        guard let sceneRef else {
            super.magnify(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let scenePoint = sceneRef.convertPoint(fromView: viewPoint)
        sceneRef.handleMagnify(event, anchor: scenePoint)
    }
}
#else
struct BoardSceneView: UIViewRepresentable {
    let renderState: BoardRenderState
    let onHexTapped: (HexCoord) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHexTapped: onHexTapped)
    }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.backgroundColor = SKColor(red: 0.16, green: 0.20, blue: 0.18, alpha: 1)

        // v0.21: 放大 scene 容纳大 hex（hexSize=36），给平移余量
        let scene = BoardScene(size: CGSize(width: 1400, height: 900))
        context.coordinator.scene = scene
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        context.coordinator.onHexTapped = onHexTapped

        if context.coordinator.scene == nil {
            let scene = BoardScene(size: uiView.bounds.size == .zero ? CGSize(width: 1400, height: 900) : uiView.bounds.size)
            context.coordinator.scene = scene
            uiView.presentScene(scene)
        }

        let coordinator = context.coordinator
        coordinator.scene?.configure(with: renderState) { coord in
            coordinator.onHexTapped(coord)
        }
    }

    final class Coordinator {
        var scene: BoardScene?
        var onHexTapped: (HexCoord) -> Void

        init(onHexTapped: @escaping (HexCoord) -> Void) {
            self.onHexTapped = onHexTapped
        }
    }
}
#endif
