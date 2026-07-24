import SwiftUI

/// The daily standup digest, produced by the built-in "Daily Digest" workflow.
/// Generating runs the workflow (agentPrompt → summarize); the summarize block persists
/// the result via AppState.persistDigest, which this view renders.
struct DigestSectionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header
                if appState.digestDraft.isEmpty {
                    empty
                } else {
                    Card {
                        Text(appState.digestDraft)
                            .font(DS.Font.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(DS.space6)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Digest").font(DS.Font.displayL)
                Text("Auto-drafted standup update built from recent ticket activity.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary)
            }
            Spacer()
            if appState.agentRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(appState.agentCurrentTool.map { "Drafting · \($0)" } ?? "Drafting…")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            } else {
                if !appState.digestDraft.isEmpty {
                    Button { Task { await appState.copyDigestNow() } } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }.buttonStyle(SecondaryButtonStyle())
                }
                Button { Task { await appState.generateDigestDraft() } } label: {
                    Label(appState.digestDraft.isEmpty ? "Generate" : "Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appState.agentRunning)
            }
        }
    }

    private var empty: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark").font(.system(size: 28)).foregroundStyle(DS.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No digest yet").font(DS.Font.headline)
                    Text("Generate one to review your ticket activity as a Slack-ready standup.")
                        .font(DS.Font.body).foregroundStyle(DS.textSecondary)
                }
                Spacer()
            }
        }
    }
}
