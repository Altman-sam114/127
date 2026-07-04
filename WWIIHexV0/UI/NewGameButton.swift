import SwiftUI

struct NewGameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("NEW GAME", systemImage: "arrow.counterclockwise")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .buttonStyle(.bordered)
    }
}
