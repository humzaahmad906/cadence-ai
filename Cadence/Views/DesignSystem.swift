import SwiftUI
import AppKit

// MARK: - Design System
// Cadence — "Clean light + airy" redesign.
//
// Drop-in replacement for the previous DesignSystem.swift. Every symbol the app
// already references (DS.accent, DS.sidebarBG, DS.contentBG, DS.cardBG, DS.border,
// DS.subtleFill, DS.accentSoft, DS.ok, DS.warn, DS.danger, DS.space1…6, DS.radius,
// DS.radiusL, and the Chip / StatusDot / Card / HoverRow components) is preserved,
// so the whole app re-themes with no other edits required.
//
// New, optional additions are marked "NEW" — adopt them for extra polish.

enum DS {

    // MARK: Palette — light-first, dark-aware
    // Light mode is the primary target: a soft off-white canvas with pure-white
    // cards floating on gentle shadows. Dark mode is kept clean as a fallback.

    /// Primary brand accent — a friendly indigo that reads well on white.
    static let accent = Color.dynamic(
        light: 0x4C5BF0,      // indigo
        dark:  0x7480FF)

    /// Low-opacity accent wash for selected states / tinted fills.
    static let accentSoft = accent.opacity(0.12)

    /// NEW — secondary accent used for the accent gradient's far stop.
    static let accent2 = Color.dynamic(light: 0x7A6CF0, dark: 0x9B8CFF)

    /// App canvas (behind everything). Airy, slightly cool off-white.
    static let contentBG = Color.dynamic(
        light: 0xF6F7F9,
        dark:  0x0F1116)

    /// Cards / elevated surfaces. Pure white in light mode for crisp separation.
    static let cardBG = Color.dynamic(
        light: 0xFFFFFF,
        dark:  0x191C23)

    /// Rails, sidebars, kanban columns — a step cooler/greyer than cards.
    static let sidebarBG = Color.dynamic(
        light: 0xEEF1F6,
        dark:  0x14161C)

    /// NEW — a very light "sunken" surface for insets / grouped panels.
    static let insetBG = Color.dynamic(light: 0xF0F2F6, dark: 0x121419)

    /// Hairline borders.
    static let border = Color.dynamic(
        light: 0x0A0C10, lightAlpha: 0.08,
        dark:  0xFFFFFF, darkAlpha: 0.09)

    /// NEW — even softer border for nested elements.
    static let borderSoft = Color.dynamic(
        light: 0x0A0C10, lightAlpha: 0.05,
        dark:  0xFFFFFF, darkAlpha: 0.06)

    /// Subtle fill for hover states / quiet chips.
    static let subtleFill = Color.dynamic(
        light: 0x0A0C10, lightAlpha: 0.04,
        dark:  0xFFFFFF, darkAlpha: 0.05)

    // MARK: Semantic colors (tuned for contrast on white)
    static let ok     = Color.dynamic(light: 0x15A34A, dark: 0x35C877)   // green
    static let warn   = Color.dynamic(light: 0xD9820A, dark: 0xF5A524)   // amber
    static let danger = Color.dynamic(light: 0xDC2B3E, dark: 0xF25563)   // red

    /// NEW — standardized purple (previously ad-hoc `.purple` for doctrines / agent).
    static let purple = Color.dynamic(light: 0x7C56E8, dark: 0x9E82FF)

    // MARK: Text (use these instead of raw .primary/.secondary for consistency)
    static let textPrimary   = Color.dynamic(light: 0x141821, dark: 0xF2F4F8)   // NEW
    static let textSecondary = Color.dynamic(light: 0x5B6472, dark: 0x9AA3B2)   // NEW
    static let textTertiary  = Color.dynamic(light: 0x8A93A3, dark: 0x6C7482)   // NEW

    // MARK: Spacing (unchanged 4-pt scale, plus airier steps)
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space7: CGFloat = 32   // NEW — section gaps
    static let space8: CGFloat = 40   // NEW — page gutters

    // MARK: Radii (softer, more generous)
    static let radiusS: CGFloat = 6    // NEW — chips, small controls
    static let radius:  CGFloat = 10   // was 8 — default control/card corner
    static let radiusL: CGFloat = 14   // was 12 — cards / panels
    static let radiusXL: CGFloat = 20  // NEW — hero / modal surfaces

    // MARK: Elevation (soft, diffuse shadows — the heart of the "airy" feel)
    static let shadowColor = Color.dynamic(
        light: 0x1B2A4A, lightAlpha: 0.10,
        dark:  0x000000, darkAlpha: 0.45)

    // MARK: Gradient — for primary buttons / hero banners
    static let accentGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    // MARK: Type scale (SF, tuned weights) — NEW, optional
    enum Font {
        static let displayL = SwiftUI.Font.system(size: 28, weight: .bold)
        static let display  = SwiftUI.Font.system(size: 22, weight: .bold)
        static let title    = SwiftUI.Font.system(size: 18, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body     = SwiftUI.Font.system(size: 13, weight: .regular)
        static let callout  = SwiftUI.Font.system(size: 12, weight: .medium)
        static let caption  = SwiftUI.Font.system(size: 11, weight: .regular)
        static let micro    = SwiftUI.Font.system(size: 10, weight: .medium)
        static let mono      = SwiftUI.Font.system(size: 11, design: .monospaced)
    }
}

// MARK: - Color helper (light/dark from hex)
extension Color {
    /// Build a dynamic (appearance-aware) color from hex ints, with optional alpha.
    static func dynamic(light: UInt32, lightAlpha: Double = 1,
                        dark: UInt32,  darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha)
                          : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255.0,
            green:   Double((hex >> 8)  & 0xFF) / 255.0,
            blue:    Double(hex & 0xFF) / 255.0,
            alpha:   alpha)
    }
}

// MARK: - Elevation modifier (NEW)
extension View {
    /// Soft, diffuse card shadow. Tune `level` 1…3 for higher surfaces.
    func cardShadow(_ level: Int = 1) -> some View {
        let (radius, y): (CGFloat, CGFloat) = {
            switch level {
            case 2:  return (18, 6)
            case 3:  return (30, 12)
            default: return (10, 3)
            }
        }()
        return self.shadow(color: DS.shadowColor, radius: radius, x: 0, y: y)
    }
}

// MARK: - Chip
struct Chip: View {
    let text: String
    let tint: Color
    let filled: Bool
    init(_ text: String, tint: Color, filled: Bool = true) {
        self.text = text; self.tint = tint; self.filled = filled
    }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(filled ? 0.14 : 0))
            )
            .overlay(
                Capsule().stroke(tint.opacity(filled ? 0 : 0.35), lineWidth: 1)
            )
    }
}

// MARK: - Status dot
struct StatusDot: View {
    let tint: Color
    var glow: Bool = false   // NEW — soft halo for "live" states
    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .shadow(color: glow ? tint.opacity(0.5) : .clear, radius: glow ? 4 : 0)
    }
}

// MARK: - Card container
// White surface, generous corners, hairline border, soft shadow.
struct Card<Content: View>: View {
    var padding: CGFloat
    var elevation: Int
    let content: () -> Content
    init(padding: CGFloat = DS.space5, elevation: Int = 1,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.elevation = elevation
        self.content = content
    }
    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                    .fill(DS.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
            .cardShadow(elevation)
    }
}

// MARK: - Hover-highlight row
struct HoverRow<Content: View>: View {
    let content: () -> Content
    @State private var hover = false
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .padding(.horizontal, DS.space4)
            .padding(.vertical, DS.space3)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(hover ? DS.subtleFill : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

// MARK: - Button styles (NEW, optional)

/// Filled gradient primary action. Use `.buttonStyle(PrimaryButtonStyle())`.
struct PrimaryButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(DS.accentGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(Color.white.opacity(hover ? 0.10 : 0))
            )
            .shadow(color: DS.accent.opacity(0.35), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Quiet secondary action — hairline border, subtle hover fill.
struct SecondaryButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(hover ? DS.subtleFill : DS.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .stroke(DS.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - Wrapping row layout
// Moved here from DraftReviewStackView when that view was removed; the workflow list and
// builder still lay out their tag rows with it.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var w: CGFloat = 0, h: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if w + s.width > maxW {
                h += rowH + spacing
                w = 0; rowH = 0
            }
            w += s.width + spacing
            rowH = max(rowH, s.height)
        }
        h += rowH
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Priority chip
// Moved here from TicketCard when the board was removed; the ticket archive still uses it.
struct PriorityChip: View {
    let priority: Priority
    var body: some View {
        Chip(priority.rawValue, tint: tint)
    }
    private var tint: Color {
        switch priority {
        case .p0: return DS.danger
        case .p1: return DS.warn
        case .p2: return .yellow
        case .p3: return DS.accent
        case .p4: return .gray
        }
    }
}
