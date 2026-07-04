import SwiftUI

@main
struct MapEditorMacApp: App {
    var body: some Scene {
        WindowGroup {
            MapEditorView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
