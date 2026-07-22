import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paths").font(.system(size: 14, weight: .semibold))
                        row("Issues", CadencePaths.issuesDir.path)
                        row("Repos registry", CadencePaths.reposFile.path)
                        row("Attachments", CadencePaths.attachmentsDir.path)
                        row("Claude CLI", "/opt/homebrew/bin/claude")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schedule").font(.system(size: 14, weight: .semibold))
                        row("Morning brief", "09:00 daily")
                        row("Idle scan", "hourly (In Progress > 2 days)")
                        row("Deadline scan", "hourly (< 3 days + open P0/P1)")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard shortcuts").font(.system(size: 14, weight: .semibold))
                        row("Paste sprint", "⇧⌘V")
                        row("Copy digest", "⇧⌘D")
                    }
                }
            }
            .padding(DS.space6)
        }
        .background(DS.contentBG)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(v).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
