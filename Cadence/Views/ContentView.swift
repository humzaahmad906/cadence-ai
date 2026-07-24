import SwiftUI

/// New shape: persistent chat rail (left) + adaptive canvas (right).
/// No route enum — canvas artifact drives what appears on the right.
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                AgentChatView()
                    .frame(width: 420)
                    .overlay(Rectangle().fill(DS.border).frame(width: 1), alignment: .trailing)
                CanvasHost()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .sheet(isPresented: $appState.showPasteSprint) { PasteSprintView() }
    }
}
