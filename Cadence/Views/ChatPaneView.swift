import SwiftUI

struct ChatPaneView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speech = SpeechRecognizer()
    @State private var input: String = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cadence Assistant").font(.title3.bold()).padding(.horizontal)
            Text("Reprioritize, ask questions, or dictate with the mic.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.chatLog) { e in
                            HStack(alignment: .top) {
                                Text(e.role.uppercased()).font(.caption2.bold())
                                    .foregroundStyle(e.role == "you" ? .blue : .purple)
                                    .frame(width: 40, alignment: .leading)
                                Text(e.text)
                            }
                            .padding(.horizontal)
                            .id(e.id)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: appState.chatLog.count) { _, _ in
                    if let last = appState.chatLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            if let err = speech.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await speech.toggle() }
                } label: {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(speech.isListening ? .red : .primary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(speech.isListening ? "Stop listening" : "Dictate")

                TextField("Type or dictate…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await send() } }

                Button(busy ? "…" : "Send") { Task { await send() } }
                    .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            if speech.isListening {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8).opacity(0.7)
                    Text("Listening… \(speech.transcript.isEmpty ? "(say something)" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
        .onChange(of: speech.transcript) { _, new in
            if !new.isEmpty { input = new }
        }
        .onAppear { Task { await speech.requestAuth() } }
        .onDisappear { speech.stop() }
    }

    private func send() async {
        let msg = input.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        input = ""
        speech.stop()
        busy = true
        defer { busy = false }
        appState.chatLog.append(ChatEntry(role: "you", text: msg, at: Date()))

        let ticketSnapshot = appState.tickets.map { t in
            "\(t.id) [\(t.priority.rawValue)] \(t.status.rawValue): \(t.title)"
        }.joined(separator: "\n")

        let prompt = """
        You are the Cadence assistant. Current sprint tickets:

        \(ticketSnapshot)

        User said: \(msg)

        If the user asks to reprioritize, output JSON in this form ONLY:
        {"kind":"reprioritize","changes":[{"id":"TICKET-ID","to_priority":"P0","reason":"..."}]}

        If the user asks something else, output:
        {"kind":"reply","text":"..."}
        """
        do {
            let obj = try await appState.claude.promptJSON(prompt, timeout: 60)
            guard let d = obj as? [String: Any] else {
                appState.chatLog.append(ChatEntry(role: "claude", text: "Bad response.", at: Date()))
                return
            }
            let kind = d["kind"] as? String ?? "reply"
            if kind == "reprioritize", let changes = d["changes"] as? [[String: Any]] {
                var report: [String] = []
                for c in changes {
                    guard let id = c["id"] as? String, let to = c["to_priority"] as? String,
                          let ticket = appState.tickets.first(where: { $0.id == id }),
                          let target = Priority(rawValue: to) else { continue }
                    let reason = c["reason"] as? String ?? ""
                    await appState.reprioritize(ticket, to: target, reason: reason)
                    report.append("• \(id) → \(to) (\(reason))")
                }
                appState.chatLog.append(ChatEntry(role: "claude", text: report.isEmpty ? "No changes applied." : report.joined(separator: "\n"), at: Date()))
            } else {
                appState.chatLog.append(ChatEntry(role: "claude", text: d["text"] as? String ?? "(empty)", at: Date()))
            }
        } catch {
            appState.chatLog.append(ChatEntry(role: "claude", text: "Error: \(error.localizedDescription)", at: Date()))
        }
    }
}
