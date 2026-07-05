import SwiftUI
import SpriteKit
#if os(macOS)
import UniformTypeIdentifiers
#endif

struct MapEditorView: View {
    @StateObject private var viewModel = MapEditorViewModel()
    private let editorFactions: [Faction] = [.blueForce, .redForce, .greenForce]

    var body: some View {
        NavigationSplitView {
            controlPanel
                .navigationSplitViewColumnWidth(min: 300, ideal: 340)
        } detail: {
            MapEditorSpriteView(viewModel: viewModel)
                .background(.black)
        }
        .frame(minWidth: 1280, minHeight: 780)
    }

    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("地图编辑器")
                    .font(.title2.bold())

                modePicker
                Divider()
                activeModePanel
                Divider()
                editSessionPanel
                Divider()
            dataPanel
                Divider()
                backgroundPanel
                Divider()
                infoPanel
                statusPanel
            }
            .padding(14)
        }
    }

    private var modePicker: some View {
        Picker("模式", selection: $viewModel.mode) {
            ForEach(MapEditorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.mode) { _, _ in
            viewModel.cancelEditing()
        }
    }

    @ViewBuilder
    private var activeModePanel: some View {
        switch viewModel.mode {
        case .hexPainter:
            hexPanel
        case .regionBuilder:
            regionPanel
        case .theaterAssignment:
            theaterPanel
        case .unitPlanner:
            unitPanel
        }
    }

    private var hexPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("地块模式")
                .font(.headline)
            Picker("地形", selection: $viewModel.selectedTerrain) {
                ForEach(paintableTerrains, id: \.self) { terrain in
                    Text(terrain.chineseName).tag(terrain)
                }
            }
            Toggle("道路", isOn: $viewModel.paintRoad)
            Toggle("补给站", isOn: $viewModel.paintSupply)
            Picker("补给阵营", selection: $viewModel.supplyFaction) {
                ForEach(editorFactions, id: \.self) { faction in
                    Text(faction.chineseName).tag(faction)
                }
            }
            Picker("控制方", selection: controllerBinding) {
                Text("中立").tag(Optional<Faction>.none)
                ForEach(editorFactions, id: \.self) { faction in
                    Text(faction.chineseName).tag(Optional(faction))
                }
            }
            HStack {
                Label(viewModel.hexTool.title, systemImage: viewModel.hexTool == .extend ? "plus.hexagon" : "paintbrush")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("扩展地块", systemImage: "plus.hexagon", action: viewModel.beginExtendingHexes)
            }
            Text("覆盖：修改已有地块。扩展：只能在已有地块相邻空位生成平原。删除：移除地块。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var regionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("区域模式")
                .font(.headline)
            TextField("区域名称", text: $viewModel.newRegionText)
            Button("准备新区域", systemImage: "square.and.pencil", action: viewModel.prepareNewRegion)
            Picker("当前区域", selection: regionBinding) {
                Text("未选择").tag(Optional<RegionId>.none)
                ForEach(viewModel.document.regions.values.sorted { $0.id.rawValue < $1.id.rawValue }) { region in
                    Text("\(region.name) · \(region.id.rawValue)").tag(Optional(region.id))
                }
            }
            Toggle("橡皮擦", isOn: $viewModel.eraseRegionMembership)
            Text("待加入地块：\(viewModel.pendingRegionHexes.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var theaterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("作战区模式")
                .font(.headline)
            TextField("作战区名称", text: $viewModel.newTheaterText)
            Button("准备新作战区", systemImage: "square.and.pencil", action: viewModel.prepareNewTheater)
            Picker("当前作战区", selection: theaterBinding) {
                Text("未选择").tag(Optional<TheaterId>.none)
                ForEach(viewModel.document.theaters.values.sorted { $0.id.rawValue < $1.id.rawValue }) { theater in
                    Text("\(theater.name) · \(theater.id.rawValue)").tag(Optional(theater.id))
                }
            }
            Text("待加入区域：\(viewModel.pendingTheaterRegions.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var unitPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("任务编组模式")
                .font(.headline)
            Picker("阵营", selection: $viewModel.selectedUnitFaction) {
                ForEach(editorFactions, id: \.self) { faction in
                    Text(faction.chineseName).tag(faction)
                }
            }
            Picker("模板", selection: $viewModel.selectedUnitTemplateId) {
                Text("机械化任务编组").tag("mechanized_task_force")
                Text("装甲任务编组").tag("armored_task_force")
                Text("侦察屏卫").tag("recon_screen")
                Text("火力分队").tag("fires_battery")
                Text("防空分队").tag("air_defense_detachment")
                Text("轻步兵小队").tag("light_infantry_team")
                Text("安全分队").tag("security_detachment")
                Text("工程分队").tag("engineer_detachment")
                Text("后勤分队").tag("logistics_element")
            }
            Stepper("兵力 \(viewModel.selectedUnitHP)", value: $viewModel.selectedUnitHP, in: 1...20)
            Picker("朝向", selection: $viewModel.selectedUnitFacing) {
                ForEach(HexDirection.ordered, id: \.self) { direction in
                    Text(direction.chineseName).tag(direction)
                }
            }
            TextField("部队名称", text: $viewModel.newUnitNameText)
            Toggle("橡皮擦", isOn: $viewModel.eraseUnits)
            Text("待部署：\(viewModel.pendingUnitHexes.count)，已部署：\(viewModel.document.initialUnits.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var editSessionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("编辑动作")
                .font(.headline)
            Text("当前状态：\(viewModel.editAction.title)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("添加", systemImage: "plus", action: viewModel.beginAdding)
                    .keyboardShortcut("n", modifiers: [])
                Button("删除", systemImage: "trash", action: viewModel.beginDeleting)
            }
            HStack {
                Button("完成", systemImage: "checkmark", action: viewModel.finishEditing)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("m", modifiers: [])
                Button("取消", systemImage: "xmark", action: viewModel.cancelEditing)
            }
            Text("右侧地图：左键点击/拖拽编辑，右键/中键/Option+左键拖拽平移，滚轮缩放。快捷键 N 添加，M 完成。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("游戏资源")
                .font(.headline)
            Button("读取默认游戏资源", action: viewModel.loadDefaultGameResources)
            Button("覆盖保存为游戏资源", action: viewModel.overwriteDefaultGameResources)
                .buttonStyle(.borderedProminent)
            Button("导出 JSON 到内存") {
                _ = viewModel.export()
            }
            Text(MapEditorGameResourceBridge.gameDataDirectory.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("底图")
                .font(.headline)
            HStack {
                Button("导入底图", systemImage: "photo", action: importBackgroundImage)
                Button("移除", systemImage: "trash", action: viewModel.clearBackgroundImage)
            }
            Slider(value: $viewModel.backgroundOpacity, in: 0...1) {
                Text("透明度")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("1")
            }
            Text("透明度 \(viewModel.backgroundOpacity, format: .number.precision(.fractionLength(2)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("缩放 \(viewModel.backgroundScale, format: .number.precision(.fractionLength(2)))", value: $viewModel.backgroundScale, in: 0.05...20, step: 0.05)
            HStack {
                TextField("X", value: $viewModel.backgroundOffsetX, format: .number)
                TextField("Y", value: $viewModel.backgroundOffsetY, format: .number)
            }
            .textFieldStyle(.roundedBorder)
            Button("应用底图参数", systemImage: "checkmark.circle", action: viewModel.updateBackgroundImageSettings)
            if let path = viewModel.document.backgroundImage?.filePath {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .onChange(of: viewModel.backgroundOpacity) { _, _ in viewModel.updateBackgroundImageSettings() }
        .onChange(of: viewModel.backgroundScale) { _, _ in viewModel.updateBackgroundImageSettings() }
        .onChange(of: viewModel.backgroundOffsetX) { _, _ in viewModel.updateBackgroundImageSettings() }
        .onChange(of: viewModel.backgroundOffsetY) { _, _ in viewModel.updateBackgroundImageSettings() }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("信息")
                .font(.headline)
            if let coord = viewModel.inspectedCoord,
               let hex = viewModel.document.hexes[coord] {
                Text("坐标：\(coord.mapEditorKey)")
                Text("地形：\(hex.terrain.chineseName)")
                Text("道路：\(hex.hasRoad ? "有" : "无")")
                if let regionId = hex.regionId {
                    Text("区域 ID：\(regionId.rawValue)")
                    TextField("区域名称", text: $viewModel.inspectedRegionName)
                    if let theaterId = viewModel.document.regionTheaterAssignments[regionId] {
                        Text("作战区 ID：\(theaterId.rawValue)")
                        TextField("作战区名称", text: $viewModel.inspectedTheaterName)
                    } else {
                        Text("作战区：未分配")
                            .foregroundStyle(.secondary)
                    }
                    Button("保存信息", systemImage: "square.and.arrow.down", action: viewModel.saveInspectedInfo)
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("区域：未分配")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("右键点击右侧地块查看信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = viewModel.lastStatusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.lastErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var paintableTerrains: [BaseTerrain] {
        [.plain, .city, .forest, .mountain, .hill]
    }

    private var controllerBinding: Binding<Faction?> {
        Binding(
            get: { viewModel.paintController },
            set: { viewModel.paintController = $0 }
        )
    }

    private var regionBinding: Binding<RegionId?> {
        Binding(
            get: { viewModel.selectedRegionId },
            set: { viewModel.selectedRegionId = $0 }
        )
    }

    private var theaterBinding: Binding<TheaterId?> {
        Binding(
            get: { viewModel.selectedTheaterId },
            set: { viewModel.selectedTheaterId = $0 }
        )
    }

    private func importBackgroundImage() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setBackgroundImage(path: url.path)
        }
        #endif
    }
}

private struct MapEditorSpriteView: View {
    @ObservedObject var viewModel: MapEditorViewModel
    @State private var scene = MapEditorCanvasScene(size: CGSize(width: 900, height: 700))

    var body: some View {
        #if os(macOS)
        MapEditorSKViewRepresentable(scene: scene, viewModel: viewModel)
            .onAppear {
                scene.configure(viewModel: viewModel)
            }
            .onChange(of: viewModel.redrawToken) { _, _ in
                scene.redraw()
            }
        #else
        SpriteView(scene: scene)
            .onAppear {
                scene.configure(viewModel: viewModel)
            }
            .onChange(of: viewModel.redrawToken) { _, _ in
                scene.redraw()
            }
        #endif
    }
}

#if os(macOS)
private struct MapEditorSKViewRepresentable: NSViewRepresentable {
    let scene: MapEditorCanvasScene
    @ObservedObject var viewModel: MapEditorViewModel

    func makeNSView(context: Context) -> MapEditorEventSKView {
        let view = MapEditorEventSKView()
        view.sceneRef = scene
        view.viewModel = viewModel
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ nsView: MapEditorEventSKView, context: Context) {
        nsView.sceneRef = scene
        nsView.viewModel = viewModel
        if nsView.scene !== scene {
            nsView.presentScene(scene)
        }
    }
}

private final class MapEditorEventSKView: SKView {
    weak var sceneRef: MapEditorCanvasScene?
    weak var viewModel: MapEditorViewModel?

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
        let scenePoint = sceneRef.scenePoint(fromViewPoint: viewPoint)
        if event.modifierFlags.contains(.shift) || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            sceneRef.panFromScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
        } else {
            sceneRef.zoomFromScroll(deltaY: event.scrollingDeltaY, anchor: scenePoint)
        }
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.charactersIgnoringModifiers,
           characters.count == 1,
           viewModel?.handleShortcut(characters) == true {
            return
        }
        super.keyDown(with: event)
    }
}
#endif

private extension BaseTerrain {
    var chineseName: String {
        switch self {
        case .plain:
            return "平原"
        case .forest:
            return "森林"
        case .mountain:
            return "山地"
        case .hill:
            return "丘陵"
        case .city:
            return "城市"
        case .fortress:
            return "要塞"
        }
    }
}

private extension Faction {
    var chineseName: String {
        switch self {
        case .germany:
            return "红方"
        case .allies:
            return "蓝方"
        case .blueForce:
            return "蓝方"
        case .redForce:
            return "红方"
        case .greenForce:
            return "绿方"
        case .neutral:
            return "中立"
        }
    }
}

private extension HexDirection {
    var chineseName: String {
        switch self {
        case .east:
            return "东"
        case .northEast:
            return "东北"
        case .northWest:
            return "西北"
        case .west:
            return "西"
        case .southWest:
            return "西南"
        case .southEast:
            return "东南"
        }
    }
}
