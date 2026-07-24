import SwiftUI

/// Prompt for a run's initial input (a task title, sprint description, focus, …) shown before
/// starting a workflow whose first block consumes input. Mirrors the app's other lightweight
/// sheets (see PasteSprintView). The entered text is passed to the run as its seed input.
struct WorkflowStartInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workflowName: String
    let onStart: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Run \(workflowName)").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Text("Starting input — e.g. the task title or sprint description. This seeds the first block.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            HStack {
                Spacer()
                Button("Run") {
                    let value = text
                    dismiss()
                    onStart(value)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 560, height: 340)
    }
}
