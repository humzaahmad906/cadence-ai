import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        let grouped = Dictionary(grouping: appState.tickets) { $0.project ?? "—" }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.space3) {
                if grouped.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No tickets yet").font(.system(size: 14, weight: .semibold))
                            Text("Paste sprint tasks to populate.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(grouped.keys.sorted(), id: \.self) { key in
                    let list = grouped[key] ?? []
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(DS.accent)
                                Text(key).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(list.count) tickets").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                pStat("Done", list.filter { $0.status == .done }.count, DS.ok)
                                pStat("In Progress", list.filter { $0.status == .inProgress }.count, DS.warn)
                                pStat("Backlog", list.filter { $0.status == .backlog }.count, .gray)
                            }
                        }
                    }
                }
            }
            .padding(DS.space6)
        }
        .background(DS.contentBG)
    }

    private func pStat(_ label: String, _ n: Int, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            StatusDot(tint: tint)
            Text("\(label) · \(n)").font(.system(size: 11))
        }
    }
}
