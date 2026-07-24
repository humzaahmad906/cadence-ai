import SwiftUI

/// Full-width adaptive canvas. The canvas artifact drives what appears; no route enum.
/// (The left chat rail was removed; AgentChatView.swift is kept but unused.)
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
        .sheet(isPresented: $appState.showPasteSprint) { PasteSprintView() }
        .sheet(isPresented: $appState.showDigestPreview) { DigestView() }
    }
}
