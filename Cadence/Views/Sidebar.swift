import SwiftUI

enum NavRoute: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case kanban = "Kanban"
    case tickets = "Tickets"
    case sprints = "Sprints"
    case projects = "Projects"
    case digest = "Digest"
    case graph = "Graph"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .kanban: return "rectangle.split.3x1"
        case .tickets: return "list.bullet.rectangle"
        case .sprints: return "flag"
        case .projects: return "folder"
        case .digest: return "text.badge.checkmark"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .settings: return "gearshape"
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var appState: AppState
    @Binding var route: NavRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 10) {
                LogoMark().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cadence").font(.system(size: 15, weight: .bold))
                    Text("v0.1").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, DS.space4)
            .padding(.top, DS.space5)
            .padding(.bottom, DS.space4)

            Divider().overlay(DS.border)

            // Nav sections
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Workspace")
                    navItem(.dashboard)
                    navItem(.kanban)
                    navItem(.tickets)
                    navItem(.sprints)
                    navItem(.projects)

                    sectionHeader("Daily")
                    navItem(.digest)
                    navItem(.graph)

                    sectionHeader("System")
                    navItem(.settings)
                }
                .padding(.vertical, DS.space3)
            }

            Spacer()

            // Sprint footer
            if let sprint = appState.currentSprint {
                Divider().overlay(DS.border)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        StatusDot(tint: sprint.daysLeft <= 3 ? DS.danger : DS.ok)
                        Text(sprint.name).font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    Text("\(sprint.daysLeft) days left · \(sprint.startDate) → \(sprint.endDate)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    ProgressView(value: sprintProgress(sprint))
                        .tint(sprint.daysLeft <= 3 ? DS.danger : DS.accent)
                        .frame(height: 4)
                }
                .padding(DS.space4)
            }
        }
        .frame(minWidth: 240, maxWidth: 240)
        .background(DS.sidebarBG)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.space4)
            .padding(.top, DS.space4)
            .padding(.bottom, DS.space2)
    }

    private func navItem(_ r: NavRoute) -> some View {
        let selected = route == r
        return Button {
            route = r
        } label: {
            HStack(spacing: 10) {
                Image(systemName: r.icon)
                    .frame(width: 18)
                    .foregroundStyle(selected ? DS.accent : .secondary)
                Text(r.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : .secondary)
                Spacer()
                if r == .kanban {
                    Text("\(appState.tickets.filter { $0.status != .done }.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DS.subtleFill))
                }
            }
            .padding(.horizontal, DS.space3)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? DS.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.space2)
    }

    private func sprintProgress(_ s: Sprint) -> Double {
        guard let start = s.startDateObj, let end = s.endDateObj, end > start else { return 0 }
        let total = end.timeIntervalSince(start)
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }
}

/// Small squircle logo mark rendered in-app (mirrors icon design).
struct LogoMark: View {
    var body: some View {
        Canvas { ctx, sz in
            let rect = CGRect(origin: .zero, size: sz)
            let path = Path(roundedRect: rect, cornerRadius: sz.width * 0.22)
            // bg gradient
            ctx.fill(path, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.31, green: 0.27, blue: 0.90),
                    Color(red: 0.12, green: 0.11, blue: 0.30),
                ]),
                startPoint: CGPoint(x: 0, y: sz.height),
                endPoint: CGPoint(x: sz.width, y: 0)
            ))
            // C stroke
            let center = CGPoint(x: sz.width * 0.44, y: sz.height * 0.5)
            let midR = sz.width * 0.26
            let gap = CGFloat.pi * 0.30
            var arc = Path()
            arc.addArc(center: center, radius: midR,
                       startAngle: .radians(gap), endAngle: .radians(2 * .pi - gap),
                       clockwise: false)
            ctx.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: sz.width * 0.115, lineCap: .round))
            // dot
            let dotR = sz.width * 0.062
            let dotC = CGPoint(x: center.x + midR + 1, y: center.y)
            ctx.fill(Path(ellipseIn: CGRect(x: dotC.x - dotR, y: dotC.y - dotR, width: dotR * 2, height: dotR * 2)),
                     with: .color(Color(red: 0.99, green: 0.65, blue: 0.20)))
        }
    }
}
