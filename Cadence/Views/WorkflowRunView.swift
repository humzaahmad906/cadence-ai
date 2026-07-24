import SwiftUI
import AppKit

/// Live progress for one workflow run: per-block status, captured output, and the
/// approve/edit/reject controls for a paused `manualReview` block.
struct WorkflowRunView: View {
    @EnvironmentObject var appState: AppState
    let runId: String

    @State private var reviewText: String = ""

    private var run: WorkflowRun? {
        guard let r = appState.activeRun, r.id == runId else { return nil }
        return r
    }

    var body: some View {
        Group {
            if let run = run {
                content(run)
            } else {
                notFound
            }
        }
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.circle").font(.system(size: 30)).foregroundStyle(DS.textTertiary)
            Text("This run is no longer active").foregroundStyle(DS.textSecondary)
            Button { appState.setArtifact(.workflows) } label: {
                Label("Back to workflows", systemImage: "flowchart")
            }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ run: WorkflowRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                header(run)
                ForEach(Array(run.blocks.enumerated()), id: \.element.id) { idx, block in
                    blockCard(run: run, index: idx, block: block)
                }
            }
            .padding(DS.space6)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
    }

    private func header(_ run: WorkflowRun) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.workflowName).font(DS.Font.displayL)
                HStack(spacing: 8) {
                    statusChip(for: run.status)
                    Text("\(run.blocks.filter { $0.status == .done }.count)/\(run.blocks.count) blocks done")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            }
            Spacer()
            if appState.agentRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(appState.agentCurrentTool.map { "Running · \($0)" } ?? "Running…")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            }
            Button { appState.setArtifact(.workflows) } label: {
                Label("Workflows", systemImage: "flowchart")
            }.buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private func blockCard(run: WorkflowRun, index: Int, block: BlockRunState) -> some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space2) {
                HStack(spacing: DS.space2) {
                    statusIcon(block.status)
                    Text("\(index + 1). \(block.title)").font(DS.Font.headline)
                    Chip(block.kind.label, tint: DS.purple, filled: false)
                    Spacer()
                    Text(block.status.rawValue).font(DS.Font.micro).foregroundStyle(DS.textTertiary)
                }
                if let err = block.error, !err.isEmpty {
                    Text(err).font(DS.Font.caption).foregroundStyle(DS.danger)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if block.status == .awaitingReview {
                    reviewControls(block)
                } else if !block.output.isEmpty {
                    ScrollView {
                        OutputContent(text: block.output, prose: isProse(block.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 320)
                    .padding(DS.space2)
                    .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                }
            }
        }
    }

    @ViewBuilder
    private func reviewControls(_ block: BlockRunState) -> some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            if !block.title.isEmpty {
                Text("Review — edit if needed, then approve to continue.")
                    .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            }
            TextEditor(text: $reviewText)
                .font(DS.Font.mono)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 200)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.border, lineWidth: 1))
            HStack {
                Button(role: .destructive) {
                    Task { await appState.resumeReview(approve: false, editedOutput: nil) }
                } label: { Label("Reject", systemImage: "xmark") }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button {
                    Task { await appState.resumeReview(approve: true, editedOutput: reviewText) }
                } label: { Label("Approve & continue", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .onAppear { reviewText = block.output }
    }

    /// Markdown-ish blocks read better in a proportional font; JSON-shaped output stays monospaced.
    private func isProse(_ kind: WorkflowBlockKind) -> Bool {
        switch kind {
        case .agentPrompt, .createTickets, .code: return false
        case .input, .manualReview, .summarize, .createDescription, .createSolution, .viewer, .docQA, .repoReport: return true
        }
    }

    // MARK: status chrome

    @ViewBuilder
    private func statusIcon(_ status: BlockRunStatus) -> some View {
        switch status {
        case .pending:        Image(systemName: "circle").foregroundStyle(DS.textTertiary)
        case .running:        ProgressView().controlSize(.small)
        case .awaitingReview: Image(systemName: "hand.raised.fill").foregroundStyle(DS.warn)
        case .done:           Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.ok)
        case .failed:         Image(systemName: "xmark.octagon.fill").foregroundStyle(DS.danger)
        case .skipped:        Image(systemName: "minus.circle").foregroundStyle(DS.textTertiary)
        }
    }

    private func statusChip(for status: RunStatus) -> some View {
        let tint: Color
        switch status {
        case .pending:        tint = DS.textTertiary
        case .running:        tint = DS.accent
        case .awaitingReview: tint = DS.warn
        case .done:           tint = DS.ok
        case .failed:         tint = DS.danger
        }
        return Chip(status.rawValue, tint: tint)
    }
}

/// Renders a block's textual output — but if the text is just a path to an existing image file,
/// shows the image instead. This is the code-block → viewer visualization path: a script prints an
/// image path and a downstream viewer (or this run view) renders it.
struct OutputContent: View {
    let text: String
    var prose: Bool = false

    var body: some View {
        if let image = Self.image(fromPath: text) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: DS.radius))
        } else {
            Text(text)
                .font(prose ? DS.Font.body : DS.Font.mono)
                .textSelection(.enabled)
        }
    }

    /// An NSImage if `text` is a lone path to an existing image file, else nil.
    static func image(fromPath text: String) -> NSImage? {
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path.count < 2048, !path.contains("\n") else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }
}
