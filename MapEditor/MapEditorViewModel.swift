import Foundation
import Combine

final class MapEditorViewModel: ObservableObject {
    @Published var document: MapEditorDocument
    @Published var mode: MapEditorMode = .hexPainter
    @Published var editAction: MapEditorEditAction = .idle
    @Published var hexTool: MapEditorHexTool = .paint
    @Published var selectedTerrain: BaseTerrain = .plain
    @Published var paintRoad: Bool = false
    @Published var paintController: Faction? = nil
    @Published var paintSupply: Bool = false
    @Published var supplyFaction: Faction = .blueForce
    @Published var selectedRegionId: RegionId?
    @Published var selectedTheaterId: TheaterId?
    @Published var eraseRegionMembership: Bool = false
    @Published var selectedUnitTemplateId: String = "mechanized_task_force"
    @Published var selectedUnitFaction: Faction = .blueForce
    @Published var selectedUnitHP: Int = 10
    @Published var selectedUnitFacing: HexDirection = .east
    @Published var eraseUnits: Bool = false
    @Published var pendingRegionHexes: Set<HexCoord> = []
    @Published var pendingTheaterRegions: Set<RegionId> = []
    @Published var pendingUnitHexes: Set<HexCoord> = []
    @Published var redrawToken: Int = 0
    @Published var lastExportResult: MapEditorExportResult?
    @Published var lastErrorMessage: String?
    @Published var lastStatusMessage: String?
    @Published var inspectedCoord: HexCoord?
    @Published var inspectedRegionName: String = ""
    @Published var inspectedTheaterName: String = ""
    @Published var backgroundOpacity: Double = 0.45
    @Published var backgroundScale: Double = 1
    @Published var backgroundOffsetX: Double = 0
    @Published var backgroundOffsetY: Double = 0

    @Published var newRegionText: String = "新区域"
    @Published var newTheaterText: String = "新作战区"
    @Published var newUnitNameText: String = "任务编组"

    init(document: MapEditorDocument = .new(width: 8, height: 6)) {
        self.document = document
    }

    func newMap(width: Int, height: Int) {
        document = .new(width: width, height: height)
        selectedRegionId = nil
        selectedTheaterId = nil
        clearPendingSelection()
        markChanged()
    }

    func resize(width: Int, height: Int) {
        document.resize(width: width, height: height)
        markChanged()
    }

    func createRegion(idText: String? = nil) {
        let id: RegionId
        let name: String
        if let idText {
            let raw = idText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            id = RegionId(raw)
            name = raw
        } else {
            let nextIndex = nextRegionIndex()
            id = RegionId("region_\(nextIndex)")
            let rawName = newRegionText.trimmingCharacters(in: .whitespacesAndNewlines)
            name = rawName.isEmpty ? "区域 \(nextIndex)" : rawName
        }
        document.createRegion(id: id, name: name)
        selectedRegionId = id
        lastStatusMessage = "已创建区域：\(name)（\(id.rawValue)）。"
        markChanged()
    }

    func createTheater(idText: String? = nil) {
        let id: TheaterId
        let name: String
        if let idText {
            let raw = idText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            id = TheaterId(raw)
            name = raw
        } else {
            let nextIndex = nextTheaterIndex()
            id = TheaterId("theater_\(nextIndex)")
            let rawName = newTheaterText.trimmingCharacters(in: .whitespacesAndNewlines)
            name = rawName.isEmpty ? "作战区 \(nextIndex)" : rawName
        }
        document.createTheater(id: id, name: name)
        selectedTheaterId = id
        lastStatusMessage = "已创建作战区：\(name)（\(id.rawValue)）。"
        markChanged()
    }

    func prepareNewRegion() {
        selectedRegionId = nil
        pendingRegionHexes.removeAll()
        lastStatusMessage = "将创建新区域，ID 会自动递增。"
        markChanged()
    }

    func prepareNewTheater() {
        selectedTheaterId = nil
        pendingTheaterRegions.removeAll()
        lastStatusMessage = "将创建新作战区，ID 会自动递增。"
        markChanged()
    }

    func beginAdding() {
        if mode == .hexPainter {
            hexTool = .paint
        }
        editAction = .adding
        clearPendingSelection()
        ensureDraftExistsForCurrentMode()
        lastStatusMessage = "\(mode.title)添加中：在右侧地图点击或拖拽。"
        markChanged()
    }

    func beginExtendingHexes() {
        mode = .hexPainter
        hexTool = .extend
        editAction = .adding
        clearPendingSelection()
        lastStatusMessage = "扩展地块中：点击现有地块旁边的空位，默认生成平原。"
        markChanged()
    }

    func beginDeleting() {
        if mode == .hexPainter {
            hexTool = .paint
        }
        editAction = .deleting
        clearPendingSelection()
        lastStatusMessage = "\(mode.title)删除中：在右侧地图点击或拖拽。"
        markChanged()
    }

    func finishEditing() {
        switch mode {
        case .hexPainter:
            break
        case .regionBuilder:
            commitPendingRegion()
        case .theaterAssignment:
            commitPendingTheater()
        case .unitPlanner:
            commitPendingUnits()
        }
        hexTool = .paint
        editAction = .idle
        clearPendingSelection()
        lastStatusMessage = "\(mode.title)编辑已完成。"
        markChanged()
    }

    func cancelEditing() {
        hexTool = .paint
        editAction = .idle
        clearPendingSelection()
        lastStatusMessage = "已取消编辑。"
        markChanged()
    }

    func applyPrimaryAction(at coord: HexCoord) {
        guard editAction != .idle else { return }
        guard mode == .hexPainter || document.contains(coord) else { return }
        switch mode {
        case .hexPainter:
            editHex(at: coord)
        case .regionBuilder:
            stageRegionMembership(at: coord)
        case .theaterAssignment:
            stageTheaterAssignment(at: coord)
        case .unitPlanner:
            stageInitialUnit(at: coord)
        }
        markChanged()
    }

    func handleShortcut(_ key: String) -> Bool {
        switch key.lowercased() {
        case "n":
            beginAdding()
            return true
        case "m":
            finishEditing()
            return true
        default:
            return false
        }
    }

    func inspect(at coord: HexCoord) {
        inspectedCoord = coord
        guard let hex = document.hexes[coord] else {
            inspectedRegionName = ""
            inspectedTheaterName = ""
            lastStatusMessage = "坐标 \(coord.mapEditorKey) 没有地块。"
            markChanged()
            return
        }

        if let regionId = hex.regionId, let region = document.regions[regionId] {
            inspectedRegionName = region.name
            if let theaterId = document.regionTheaterAssignments[regionId],
               let theater = document.theaters[theaterId] {
                inspectedTheaterName = theater.name
            } else {
                inspectedTheaterName = ""
            }
        } else {
            inspectedRegionName = ""
            inspectedTheaterName = ""
        }
        lastStatusMessage = "已选中：\(coord.mapEditorKey)。"
        markChanged()
    }

    func saveInspectedInfo() {
        guard let inspectedCoord,
              let hex = document.hexes[inspectedCoord],
              let regionId = hex.regionId else {
            lastStatusMessage = "当前选中地块没有区域信息可保存。"
            markChanged()
            return
        }

        let regionName = inspectedRegionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !regionName.isEmpty, var region = document.regions[regionId] {
            region.name = regionName
            document.regions[regionId] = region
        }

        let theaterName = inspectedTheaterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !theaterName.isEmpty,
           let theaterId = document.regionTheaterAssignments[regionId],
           var theater = document.theaters[theaterId] {
            theater.name = theaterName
            document.theaters[theaterId] = theater
        }

        lastStatusMessage = "已保存选中信息。"
        markChanged()
    }

    func setBackgroundImage(path: String) {
        document.backgroundImage = MapEditorBackgroundImage(
            filePath: path,
            opacity: backgroundOpacity,
            scale: backgroundScale,
            positionX: backgroundOffsetX,
            positionY: backgroundOffsetY
        )
        lastStatusMessage = "已导入底图：\(URL(fileURLWithPath: path).lastPathComponent)。"
        markChanged()
    }

    func clearBackgroundImage() {
        document.backgroundImage = nil
        lastStatusMessage = "已移除底图。"
        markChanged()
    }

    func updateBackgroundImageSettings() {
        guard var backgroundImage = document.backgroundImage else { return }
        backgroundImage.opacity = max(0, min(1, backgroundOpacity))
        backgroundImage.scale = max(0.05, min(20, backgroundScale))
        backgroundImage.positionX = backgroundOffsetX
        backgroundImage.positionY = backgroundOffsetY
        document.backgroundImage = backgroundImage
        markChanged()
    }

    func moveBackgroundBy(deltaX: Double, deltaY: Double) {
        backgroundOffsetX += deltaX
        backgroundOffsetY += deltaY
        updateBackgroundImageSettings()
    }

    func saveDocument(to url: URL) {
        do {
            try MapEditorStorage.save(document, to: url)
            lastErrorMessage = nil
            lastStatusMessage = "已保存 \(url.lastPathComponent)。"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func loadDocument(from url: URL) {
        do {
            document = try MapEditorStorage.load(from: url)
            syncBackgroundControlsFromDocument()
            lastErrorMessage = nil
            lastStatusMessage = "已读取 \(url.lastPathComponent)。"
            markChanged()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func loadDefaultGameResources() {
        do {
            document = try MapEditorGameResourceBridge.loadDefaultDocument()
            selectedRegionId = document.regions.keys.sorted { $0.rawValue < $1.rawValue }.first
            selectedTheaterId = document.theaters.keys.sorted { $0.rawValue < $1.rawValue }.first
            syncBackgroundControlsFromDocument()
            lastErrorMessage = nil
            lastStatusMessage = "已读取默认游戏资源。"
            markChanged()
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    func overwriteDefaultGameResources() {
        do {
            let result = try MapEditorGameResourceBridge.overwriteDefaultGameResources(document: document)
            lastExportResult = result
            lastErrorMessage = nil
            lastStatusMessage = "已覆盖 \(result.scenarioFileName).json 和 \(result.regionFileName).json。"
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    @discardableResult
    func export() -> MapEditorExportResult? {
        do {
            let result = try MapEditorExporter.export(document: document)
            lastExportResult = result
            lastErrorMessage = nil
            lastStatusMessage = "已在内存中导出 JSON。"
            return result
        } catch {
            lastErrorMessage = String(describing: error)
            return nil
        }
    }

    @discardableResult
    func export(to directory: URL) -> MapEditorExportResult? {
        guard let result = export() else { return nil }
        do {
            try MapEditorExporter.write(result, to: directory)
            lastErrorMessage = nil
            lastStatusMessage = "已导出 JSON 到 \(directory.path)。"
            return result
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func editHex(at coord: HexCoord) {
        if editAction == .deleting {
            document.deleteHex(at: coord)
            return
        }
        if hexTool == .extend {
            if document.addHex(at: coord, terrain: .plain) {
                lastStatusMessage = "已扩展地块：\(coord.mapEditorKey)。"
            } else if !document.contains(coord) {
                lastStatusMessage = "扩展失败：新地块必须贴着已有地块。"
            }
            return
        }
        guard var hex = document.hexes[coord] else { return }
        hex.terrain = selectedTerrain
        hex.hasRoad = paintRoad
        hex.controller = paintController
        hex.isSupplySource = paintSupply
        hex.supplyFaction = paintSupply ? supplyFaction : nil
        if selectedTerrain == .city, hex.cityName == nil {
            hex.cityName = "City \(coord.q),\(coord.r)"
        } else if selectedTerrain != .city {
            hex.cityName = nil
        }
        document.setHex(hex)
    }

    private func stageRegionMembership(at coord: HexCoord) {
        if editAction == .deleting || eraseRegionMembership {
            document.assign(coord, to: nil)
            return
        }
        pendingRegionHexes.insert(coord)
    }

    private func stageTheaterAssignment(at coord: HexCoord) {
        guard let regionId = document.hexes[coord]?.regionId else {
            return
        }
        if editAction == .deleting {
            document.assign(regionId: regionId, to: nil)
            return
        }
        pendingTheaterRegions.insert(regionId)
    }

    private func stageInitialUnit(at coord: HexCoord) {
        if editAction == .deleting || eraseUnits {
            document.initialUnits.removeAll { $0.coord == coord }
            return
        }
        pendingUnitHexes.insert(coord)
    }

    private func commitPendingRegion() {
        ensureDraftExistsForCurrentMode()
        guard let selectedRegionId else { return }
        for coord in pendingRegionHexes {
            document.assign(coord, to: selectedRegionId)
        }
    }

    private func commitPendingTheater() {
        ensureDraftExistsForCurrentMode()
        guard let selectedTheaterId else { return }
        for regionId in pendingTheaterRegions {
            document.assign(regionId: regionId, to: selectedTheaterId)
        }
    }

    private func commitPendingUnits() {
        for coord in pendingUnitHexes.sortedByMapOrder() {
            stampUnit(at: coord)
        }
    }

    private func stampUnit(at coord: HexCoord) {
        document.initialUnits.removeAll { $0.coord == coord }
        let nextIndex = document.initialUnits.count + 1
        let factionPrefix: String
        switch selectedUnitFaction.alignment {
        case .red:
            factionPrefix = "red"
        case .blue:
            factionPrefix = "blue"
        case .green:
            factionPrefix = "green"
        case .neutral:
            factionPrefix = "neutral"
        }
        let id = "\(factionPrefix)_editor_\(nextIndex)"
        document.initialUnits.append(
            MapEditorUnitDraft(
                id: id,
                name: "\(newUnitNameText) \(nextIndex)",
                faction: selectedUnitFaction,
                templateId: selectedUnitTemplateId,
                coord: coord,
                facing: selectedUnitFacing,
                hp: selectedUnitHP
            )
        )
    }

    private func ensureDraftExistsForCurrentMode() {
        switch mode {
        case .hexPainter, .unitPlanner:
            break
        case .regionBuilder:
            if selectedRegionId == nil {
                createRegion()
            }
        case .theaterAssignment:
            if selectedTheaterId == nil {
                createTheater()
            }
        }
    }

    private func clearPendingSelection() {
        pendingRegionHexes.removeAll()
        pendingTheaterRegions.removeAll()
        pendingUnitHexes.removeAll()
    }

    private func markChanged() {
        redrawToken += 1
    }

    private func syncBackgroundControlsFromDocument() {
        guard let backgroundImage = document.backgroundImage else {
            backgroundOpacity = 0.45
            backgroundScale = 1
            backgroundOffsetX = 0
            backgroundOffsetY = 0
            return
        }
        backgroundOpacity = backgroundImage.opacity
        backgroundScale = backgroundImage.scale
        backgroundOffsetX = backgroundImage.positionX
        backgroundOffsetY = backgroundImage.positionY
    }

    private func nextRegionIndex() -> Int {
        nextNumericSuffix(
            used: document.regions.keys.map(\.rawValue),
            prefix: "region_"
        )
    }

    private func nextTheaterIndex() -> Int {
        nextNumericSuffix(
            used: document.theaters.keys.map(\.rawValue),
            prefix: "theater_"
        )
    }

    private func nextNumericSuffix(used: [String], prefix: String) -> Int {
        let usedIndices = Set(used.compactMap { raw -> Int? in
            guard raw.hasPrefix(prefix) else { return nil }
            return Int(raw.dropFirst(prefix.count))
        })
        var candidate = 1
        while usedIndices.contains(candidate) {
            candidate += 1
        }
        return candidate
    }
}

private extension Set where Element == HexCoord {
    func sortedByMapOrder() -> [HexCoord] {
        sorted { lhs, rhs in
            lhs.r == rhs.r ? lhs.q < rhs.q : lhs.r < rhs.r
        }
    }
}
