import SwiftUI

/// Full-width adaptive canvas. The header picks the artifact; the canvas renders it.
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            CanvasHost()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.contentBG)

            if let err = appState.bootstrapError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.danger)
                    Text(err).font(DS.Font.caption).lineLimit(2)
                    Spacer()
                    Button("Retry") { Task { await appState.bootstrap() } }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, DS.space4).padding(.vertical, DS.space2)
                .background(DS.danger.opacity(0.15))
            }
        }
    }
}
