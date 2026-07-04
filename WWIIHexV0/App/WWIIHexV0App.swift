import SwiftUI

@main
struct WWIIHexV0App: App {
    @StateObject private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootGameView(container: container)
        }
    }
}
