import SwiftUI

/// Thin non-modal strip above canvas. Shows recent scheduler / stale / activity events.
/// Click event → routes canvas. X → dismiss. Cap enforced by AppState.
struct AmbientStrip: View {
    @EnvironmentObject var appState: AppState
    @State private var expanded = false

    var body: some View {
        if appState.ambientEvents.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                collapsedRow
                if expanded {
                    Divider().overlay(DS.borderSoft)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(appState.ambientEvents) { e in
                                eventRow(e)
                                Divider().overlay(DS.borderSoft)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .background(DS.insetBG)
            .overlay(Rectangle().fill(DS.borderSoft).frame(height: 1), alignment: .bottom)
        }
    }

    private var collapsedRow: some View {
        HStack(spacing: 8) {
            if let top = appState.ambientEvents.first {
                Image(systemName: top.iconName).foregroundStyle(tint(for: top.kind)).font(.caption)
                Text(top.text).font(DS.Font.caption).foregroundStyle(DS.textPrimary).lineLimit(1)
                if appState.ambientEvents.count > 1 {
                    Text("+\(appState.ambientEvents.count - 1)")
                        .font(DS.Font.micro).foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DS.subtleFill))
                }
            }
            Spacer()
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
            }
            .buttonStyle(.borderless)
            if let top = appState.ambientEvents.first {
                Button { appState.dismissAmbient(top.id) } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, DS.space4).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let top = appState.ambientEvents.first, let target = top.target {
                appState.setArtifact(target)
            } else {
                expanded.toggle()
            }
        }
    }

    private func eventRow(_ e: AmbientEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: e.iconName).foregroundStyle(tint(for: e.kind)).font(.caption)
            Text(e.text).font(DS.Font.caption).foregroundStyle(DS.textPrimary).lineLimit(2)
            Spacer()
            Text(relative(e.at)).font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            Button { appState.dismissAmbient(e.id) } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.space4).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let t = e.target { appState.setArtifact(t) }
        }
    }

    private func tint(for k: AmbientEvent.Kind) -> Color {
        switch k {
        case .stale: return DS.warn
        case .idle: return DS.warn
        case .digest: return DS.accent
        case .activity: return DS.accent
        case .info: return DS.textSecondary
        case .error: return DS.danger
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
