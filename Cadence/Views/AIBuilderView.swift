import SwiftUI

/// The "AI workflow builder" modal. Describe an automation in plain language and let Cadence
/// assemble + wire the blocks, or start from one of the built-in `Workflow.templates()`.
///
/// Self-contained: renders its own dimmed scrim + centered card. The host presents it over the
/// app content and provides `onClose` to dismiss.
struct AIBuilderView: View {
    @EnvironmentObject var appState: AppState
    var onClose: () -> Void

    @State private var prompt: String = ""
    @State private var busy = false
    @FocusState private var promptFocused: Bool

    private let templates = Workflow.templates()

    private let placeholder = "e.g. When I paste a sprint, split it into tickets, ground each in the repo, let me approve, then create Linear issues…"

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !busy { onClose() } }

            card
                .onExitCommand { if !busy { onClose() } }
        }
        .onAppear { promptFocused = true }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            bodyContent
            Divider().overlay(DS.border)
            footer
        }
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: DS.radiusXL, style: .continuous).fill(DS.cardBG))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXL, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .cardShadow(3)
    }

    // MARK: Header (gradient)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("✦ AI workflow builder")
                .font(DS.Font.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text("Describe the automation in plain language. Cadence assembles the blocks and wires them up.")
                .font(DS.Font.body)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.space5)
        .background(DS.accentGradient)
    }

    // MARK: Body (prompt + templates)

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            promptEditor

            Text("Or start from a template")
                .font(DS.Font.callout)
                .foregroundStyle(DS.textTertiary)

            VStack(spacing: DS.space2) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    TemplateRow(
                        workflow: template,
                        tint: index.isMultiple(of: 2) ? DS.purple : DS.accent
                    ) {
                        appState.createWorkflow(from: template)
                        onClose()
                    }
                }
            }
            .disabled(busy)
        }
        .padding(DS.space5)
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .fill(DS.insetBG)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                        .stroke(DS.border, lineWidth: 1)
                )

            if prompt.isEmpty {
                Text(placeholder)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $prompt)
                .font(DS.Font.body)
                .foregroundStyle(DS.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($promptFocused)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
        }
        .frame(height: 104)
        .disabled(busy)
    }

    // MARK: Footer (status + actions)

    private var footer: some View {
        HStack(spacing: DS.space3) {
            Text(busy ? "Generating your workflow…" : "Cadence will place and connect the blocks for you.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DS.space3)

            Button("Cancel") { onClose() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy)

            Button(action: generate) {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Generating…")
                    } else {
                        Text("✦ Generate")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmedPrompt.isEmpty)
        }
        .padding(DS.space5)
    }

    // MARK: Actions

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generate() {
        guard !busy, !trimmedPrompt.isEmpty else { return }
        busy = true
        promptFocused = false
        Task {
            await appState.createWorkflowFromAI(prompt: prompt)
            onClose()
        }
    }
}

// MARK: - Template row

/// A single "start from a template" row: tinted glyph + name + summary + trailing arrow.
private struct TemplateRow: View {
    let workflow: Workflow
    let tint: Color
    let onSelect: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.space3) {
                RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: workflow.blocks.first?.kind.icon ?? "square.stack.3d.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.name)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if !workflow.summary.isEmpty {
                        Text(workflow.summary)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: DS.space2)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hover ? DS.accent : DS.textTertiary)
            }
            .padding(.horizontal, DS.space3)
            .padding(.vertical, DS.space3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .fill(hover ? DS.subtleFill : DS.cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .stroke(hover ? DS.accent.opacity(0.45) : DS.border, lineWidth: 1)
        )
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
