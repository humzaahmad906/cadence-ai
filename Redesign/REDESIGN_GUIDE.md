# Cadence — "Clean Light + Airy" Redesign

A drop-in visual refresh. The whole app is themed through the `DS` enum and four
shared components (`Card`, `Chip`, `StatusDot`, `HoverRow`), so **step 1 alone
re-themes every screen**. Steps 2–5 are optional polish for the highest-impact
surfaces.

---

## Step 1 — Replace the design system (required, does 80% of the work)

Overwrite `Cadence/Views/DesignSystem.swift` with the new `DesignSystem.swift`.

It keeps **every** symbol the codebase already uses — `DS.accent`, `DS.accentSoft`,
`DS.sidebarBG`, `DS.contentBG`, `DS.cardBG`, `DS.border`, `DS.subtleFill`,
`DS.ok/warn/danger`, `DS.space1…6`, `DS.radius`, `DS.radiusL`, and the
`Chip / StatusDot / Card / HoverRow` views — so nothing else needs to change to compile.

### What changed
- **Light-first palette.** Soft off-white canvas (`contentBG` `#F6F7F9`), pure-white
  floating cards (`cardBG`), cooler grey rails/columns (`sidebarBG`). Dark mode is
  retained and tuned, but light is the star.
- **New accent.** Friendly indigo `#4C5BF0` (was Docker blue `#2496ED`), plus a
  gradient (`DS.accentGradient`) for primary actions.
- **Softer geometry.** Card corner radius `14`, controls `10`; continuous (squircle) corners.
- **Real elevation.** Diffuse, low-opacity shadows via `.cardShadow(level)` — this is
  what makes light mode feel airy instead of flat.
- **`Card` is now roomier** (default padding `20`) and shadowed automatically.

### New tokens you can adopt (all optional)
| Token | Use |
|---|---|
| `DS.accentGradient` | fill for primary buttons / hero banners |
| `DS.purple` | standardized purple (replaces ad-hoc `.purple`) |
| `DS.textPrimary/Secondary/Tertiary` | consistent text colors |
| `DS.insetBG`, `DS.borderSoft` | sunken panels, nested borders |
| `DS.radiusS / radiusXL`, `DS.space7 / space8` | small chips / hero surfaces / airy gutters |
| `DS.Font.*` | type scale (`.display`, `.title`, `.headline`, `.body`, `.caption`, `.mono`) |
| `.cardShadow(1…3)` | soft elevation on any view |
| `PrimaryButtonStyle()`, `SecondaryButtonStyle()` | polished buttons |

---

## Step 2 — Primary buttons (nice payoff, tiny change)

Swap `.borderedProminent` + `.tint(DS.accent)` for the gradient style.

**`DashboardView.swift` → `critiqueBanner`:**
```swift
Button { appState.requestCritique() } label: {
    Label("Run Critique", systemImage: "sparkles")
}
.buttonStyle(PrimaryButtonStyle())          // was: .buttonStyle(.borderedProminent).tint(DS.accent)
```

**`AgentChatView.swift` → `proposalPanel` "Apply" button:** same swap
(`.buttonStyle(PrimaryButtonStyle())`), and give "Reject" `.buttonStyle(SecondaryButtonStyle())`.

---

## Step 3 — Icon rail (`IconRail.swift`)

Make the selected item use a soft accent pill with a matching-color glyph, and give
the rail a hairline it earns on a light canvas.

```swift
private func railItem(_ r: NavRoute) -> some View {
    let selected = route == r
    return Button { route = r } label: {
        VStack(spacing: 3) {
            Image(systemName: r.icon)
                .font(.system(size: 16, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.accent : DS.textTertiary)
            Text(r.rawValue.prefix(4))
                .font(.system(size: 9, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.textPrimary : DS.textTertiary)
        }
        .frame(width: 52, height: 46)
        .background(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .fill(selected ? DS.accentSoft : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .help(r.rawValue)
}
```
The rail background stays `DS.sidebarBG`; the new lighter value + shadowed content
does the rest.

---

## Step 4 — Chat bubbles (`AgentChatView.swift` → `chatBubble`)

Give "you" a filled accent bubble and "Cadence" a clean white card. Airy, high-contrast.

```swift
private func chatBubble(_ e: ChatEntry) -> some View {
    let mine = e.role == "you"
    return HStack(alignment: .top, spacing: DS.space3) {
        if mine { Spacer(minLength: 40) }
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            Text(mine ? "You" : "Cadence")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(mine ? DS.accent : DS.purple)
            Text(e.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .foregroundStyle(mine ? .white : DS.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                        .fill(mine ? AnyShapeStyle(DS.accentGradient)
                                   : AnyShapeStyle(DS.cardBG))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                        .stroke(mine ? Color.clear : DS.border, lineWidth: 1)
                )
                .cardShadow(mine ? 2 : 1)
                .frame(maxWidth: 480, alignment: mine ? .trailing : .leading)
        }
        if !mine { Spacer(minLength: 40) }
    }
    .padding(.horizontal, DS.space4)
}
```

---

## Step 5 — KPI tiles (`DashboardView.swift` → `kpi`)

Bigger number, rounded-square icon chip (softer than a circle on white):

```swift
private func kpi(_ label: String, value: String, tint: Color, icon: String) -> some View {
    Card {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(DS.Font.display)
                Text(label).font(.system(size: 11)).foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
    }
}
```

---

## Optional global niceties
- **Text colors:** search-replace `.foregroundStyle(.secondary)` → `.foregroundStyle(DS.textSecondary)`
  for a slightly warmer, more deliberate grey. Safe to skip.
- **Window chrome:** for a fully modern feel, set the main window to
  `.containerBackground(DS.contentBG, for: .window)` (macOS 14+) or use a
  `.hiddenTitleBar` window style in `CadenceApp.swift`.
- **Kanban columns** already inherit the new lighter `sidebarBG`; bump their corner
  to `DS.radiusL` (already used) — no change needed.

## Notes
- All colors are appearance-aware (light/dark) via `Color.dynamic(...)`, so dark mode
  keeps working automatically.
- No symbols were removed or renamed — the project compiles after Step 1 with zero
  other edits. Steps 2–5 are additive.
