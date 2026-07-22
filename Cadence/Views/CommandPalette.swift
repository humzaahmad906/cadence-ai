import SwiftUI

struct CommandPalette: View {
    @EnvironmentObject var appState: AppState
    @Binding var isOpen: Bool
    @Binding var route: NavRoute
    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Jump to ticket, run action…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { runFirst() }
                Text("ESC").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.subtleFill))
            }
            .padding(DS.space4)
            Divider().overlay(DS.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        if !section.items.isEmpty {
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DS.space4)
                                .padding(.top, DS.space3)
                                .padding(.bottom, 4)
                            ForEach(section.items) { item in
                                Button { run(item) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.icon).foregroundStyle(DS.accent).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.title).font(.system(size: 13))
                                            if let sub = item.subtitle {
                                                Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if let hint = item.hint {
                                            Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, DS.space4)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 640)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.cardBG)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        )
        .onAppear { focused = true }
    }

    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let icon: String
        let hint: String?
        let run: () -> Void
    }
    struct Section { let title: String; let items: [Item] }

    private var sections: [Section] {
        let q = query.lowercased()

        let nav = NavRoute.allCases.compactMap { r -> Item? in
            let title = "Go to \(r.rawValue)"
            if !q.isEmpty && !title.lowercased().contains(q) && !r.rawValue.lowercased().contains(q) { return nil }
            return Item(title: title, subtitle: nil, icon: r.icon, hint: nil) {
                route = r
                isOpen = false
            }
        }

        let actions: [Item] = [
            Item(title: "Paste Sprint…", subtitle: nil, icon: "doc.on.clipboard", hint: "⇧⌘V") {
                appState.showPasteSprint = true; isOpen = false
            },
            Item(title: "Generate Digest", subtitle: nil, icon: "text.badge.checkmark", hint: nil) {
                Task { await appState.generateDigestDraft() }; isOpen = false
            },
            Item(title: "Copy Digest to Clipboard", subtitle: nil, icon: "doc.on.doc", hint: "⇧⌘D") {
                Task { await appState.copyDigestNow() }; isOpen = false
            },
            Item(title: "Refresh", subtitle: nil, icon: "arrow.clockwise", hint: nil) {
                Task { await appState.refresh() }; isOpen = false
            },
        ].filter { q.isEmpty || $0.title.lowercased().contains(q) }

        let ticketItems = appState.tickets
            .filter { q.isEmpty || $0.id.lowercased().contains(q) || $0.title.lowercased().contains(q) }
            .prefix(20)
            .map { t in
                Item(title: t.title, subtitle: "\(t.id) · \(t.status.rawValue)", icon: "ticket", hint: t.priority.rawValue) {
                    appState.selectedTicketId = t.id
                    isOpen = false
                }
            }

        return [
            Section(title: "Navigate", items: nav),
            Section(title: "Actions", items: actions),
            Section(title: "Tickets", items: Array(ticketItems)),
        ]
    }

    private func run(_ item: Item) { item.run() }
    private func runFirst() {
        for s in sections { if let f = s.items.first { f.run(); return } }
    }
}
