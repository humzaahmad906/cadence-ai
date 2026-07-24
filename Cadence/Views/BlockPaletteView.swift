import SwiftUI

// MARK: - BlockPaletteView
// Left-rail "BLOCKS" palette for the workflow builder (mockup: 01-build.png).
//
// Renders `WorkflowBlockKind.allCases` grouped by `BlockCategory` — one uppercase
// section label per non-empty category, then a bordered, tappable row per kind:
// a soft-tinted glyph square + label/subtitle + a trailing plus. Tapping anywhere
// on a row (including the plus) calls `onAdd(kind)`.
//
// Styling uses only DesignSystem (DS) tokens. The view is a plain content column;
// the parent rail supplies the ~250pt frame and any scrolling (the rail also holds
// the WORKFLOWS list above this, so scrolling belongs to the shared parent).

struct BlockPaletteView: View {
    var onAdd: (WorkflowBlockKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            header

            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: DS.space2) {
                    Text(sectionTitle(section.category))
                        .font(DS.Font.micro.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.leading, 2)

                    ForEach(section.kinds) { kind in
                        PaletteRow(kind: kind, onAdd: onAdd)
                    }
                }
            }
        }
        .padding(.horizontal, DS.space4)
        .padding(.vertical, DS.space3)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BLOCKS")
                .font(DS.Font.micro.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(DS.textTertiary)
            Text("Click to add to the canvas.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: Grouping

    private struct PaletteSection: Identifiable {
        let category: BlockCategory
        let kinds: [WorkflowBlockKind]
        var id: String { category.rawValue }
    }

    /// Non-empty categories in `BlockCategory` declaration order; kinds keep
    /// `WorkflowBlockKind` declaration order within each group.
    private var sections: [PaletteSection] {
        BlockCategory.allCases.compactMap { category in
            let kinds = WorkflowBlockKind.allCases.filter { $0.category == category }
            return kinds.isEmpty ? nil : PaletteSection(category: category, kinds: kinds)
        }
    }

    private func sectionTitle(_ category: BlockCategory) -> String {
        switch category {
        case .trigger: return "TRIGGERS"
        case .ai:      return "AI"
        case .action:  return "ACTIONS"
        case .gate:    return "GATE"
        }
    }
}

// MARK: - Row

private struct PaletteRow: View {
    let kind: WorkflowBlockKind
    let onAdd: (WorkflowBlockKind) -> Void
    @State private var hover = false

    var body: some View {
        // The whole row is the tap target, so clicking the row or the trailing
        // plus both add the block.
        Button {
            onAdd(kind)
        } label: {
            HStack(spacing: DS.space3) {
                glyph
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(kind.subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.space2)
                plusGlyph
            }
            .padding(.horizontal, DS.space3)
            .padding(.vertical, DS.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(hover ? DS.subtleFill : DS.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .stroke(hover ? kind.accent.opacity(0.55) : DS.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help("Add \(kind.label) to the canvas")
    }

    // 26pt soft-tinted glyph square in the kind's accent.
    private var glyph: some View {
        RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
            .fill(kind.accent.opacity(0.14))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(kind.accent)
            )
    }

    // Trailing add affordance; tints with the accent on hover.
    private var plusGlyph: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(hover ? kind.accent : DS.textTertiary)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                    .fill(hover ? kind.accent.opacity(0.12) : Color.clear)
            )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        BlockPaletteView { _ in }
    }
    .frame(width: 250, height: 640)
    .background(DS.sidebarBG)
}
