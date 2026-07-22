import SwiftUI
import UniformTypeIdentifiers

struct TicketDetailView: View {
    @EnvironmentObject var appState: AppState
    @State var ticket: Ticket
    @State private var newCommentBody: String = ""
    @State private var pendingAttachments: [URL] = []
    @State private var comments: [IssueStore.Comment] = []
    @State private var tab: Tab = .fields

    enum Tab: String, CaseIterable { case fields = "Fields", comments = "Comments" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PriorityChip(priority: ticket.priority)
                Text(ticket.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.copyLinearTicket(ticket)
                } label: {
                    Label("Copy as Linear", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy this ticket formatted for Linear paste (Title/Priority/Description/Verification)")
                Button("Save") { Task { await appState.saveTicket(ticket) } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            TextField("Title", text: $ticket.title).font(.title2).textFieldStyle(.plain).padding(.horizontal)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                switch tab {
                case .fields: fieldsSection
                case .comments: commentsSection
                }
            }
        }
        .onAppear { comments = appState.store.comments(ticket.id) }
        .onChange(of: ticket.id) { _, _ in comments = appState.store.comments(ticket.id) }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Priority", selection: $ticket.priority) {
                    ForEach(Priority.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 160)
                HStack { Text("Estimate"); TextField("h", value: $ticket.estimate, format: .number).frame(width: 60) }
                TextField("Assignee", text: $ticket.assignee).frame(width: 180)
                Spacer()
            }
            LabeledSection(title: "Description", text: $ticket.description)
            LabeledSection(title: "Results", text: $ticket.results)
            LabeledSection(title: "Blockers", text: $ticket.blockers, tint: .orange)
            LabeledSection(title: "Verification", text: $ticket.verification)
            LabeledSection(title: "Notes (private, not in digest)", text: $ticket.notes)
            LabeledSection(title: "Time Log", text: $ticket.timeLog, monospaced: true)
            if !ticket.labels.isEmpty {
                HStack {
                    Text("Labels:").foregroundStyle(.secondary)
                    ForEach(ticket.labels, id: \.self) { Text($0).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Color.gray.opacity(0.15)).cornerRadius(4) }
                }
            }
        }
        .padding()
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New comment").font(.headline)
            TextEditor(text: $newCommentBody).frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            HStack {
                Button("Attach files…") { pickAttachments() }
                if !pendingAttachments.isEmpty {
                    Text("\(pendingAttachments.count) file(s) queued").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Post") {
                    let body = newCommentBody
                    let atts = pendingAttachments
                    Task {
                        await appState.addComment(ticketId: ticket.id, body: body, attachments: atts)
                        newCommentBody = ""
                        pendingAttachments = []
                        comments = appState.store.comments(ticket.id)
                    }
                }
                .disabled(newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            Divider()
            if comments.isEmpty {
                Text("No comments yet.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(comments.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.author).font(.caption).bold()
                            Spacer()
                            Text(c.created).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(c.body)
                    }
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        .padding()
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            pendingAttachments.append(contentsOf: panel.urls)
        }
    }
}

struct LabeledSection: View {
    let title: String
    @Binding var text: String
    var tint: Color = .primary
    var monospaced: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(tint)
            TextEditor(text: $text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .frame(minHeight: 60)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
        }
    }
}
