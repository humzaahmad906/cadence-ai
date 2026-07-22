import SwiftUI

struct IconRail: View {
    @EnvironmentObject var appState: AppState
    @Binding var route: NavRoute

    var body: some View {
        VStack(spacing: 0) {
            LogoMark().frame(width: 34, height: 34).padding(.top, DS.space4)
            VStack(spacing: 4) {
                ForEach(NavRoute.allCases) { r in
                    railItem(r)
                }
            }
            .padding(.top, DS.space4)
            Spacer()
            if let s = appState.currentSprint {
                VStack(spacing: 2) {
                    StatusDot(tint: s.daysLeft <= 3 ? DS.danger : DS.ok)
                    Text("\(s.daysLeft)d")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, DS.space4)
                .help("\(s.name) · \(s.daysLeft) days left")
            }
        }
        .frame(width: 60)
        .background(DS.sidebarBG)
        .overlay(Rectangle().fill(DS.border).frame(width: 1), alignment: .trailing)
    }

    private func railItem(_ r: NavRoute) -> some View {
        let selected = route == r
        return Button {
            route = r
        } label: {
            VStack(spacing: 4) {
                Image(systemName: r.icon)
                    .font(.system(size: 18, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.accent : DS.textTertiary)
                Text(r.rawValue.prefix(4))
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.textTertiary)
            }
            .frame(width: 52, height: 48)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(selected ? DS.accentSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(r.rawValue)
    }
}
