import SwiftUI

// MARK: - Accent mapping
// Colors come from DS, same split as BlockStyle.swift — no new hues.
extension DayAccent {
    var color: Color {
        switch self {
        case .amber:  return DS.warn
        case .purple: return DS.purple
        case .indigo: return DS.accent
        case .green:  return DS.ok
        }
    }
}

/// The day as a shape, not a list. Blocks are sized by their real length, a red
/// line tracks the actual time, and tasks go in each morning rather than the night before.
struct DayView: View {
    @EnvironmentObject var appState: AppState

    private let pxPerMinute: CGFloat = 1.5
    private let minBlockHeight: CGFloat = 84
    private let blockGap: CGFloat = DS.space2
    private let railWidth: CGFloat = 48

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space6) {
                header
                timeline
                addBlockButton
                footer
            }
            .padding(DS.space6)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
        .onChange(of: appState.day) { _, _ in appState.saveDay() }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .bottom, spacing: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space2) {
                Text(longDate).font(DS.Font.display)
                HStack(spacing: DS.space2) {
                    Text("Day starts")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                    DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: 78)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DS.space2) {
                Text(label(appState.day.plannedMinutes)).font(DS.Font.displayL)
                budgetChip
            }
        }
    }

    private var budgetChip: some View {
        let diff = appState.day.plannedMinutes - appState.day.targetMinutes
        let target = label(appState.day.targetMinutes)
        if diff == 0 {
            return Chip("matches your \(target) target", tint: DS.ok)
        } else if diff < 0 {
            return Chip("\(label(-diff)) short of \(target)", tint: DS.warn)
        } else {
            return Chip("\(label(diff)) over \(target)", tint: DS.danger)
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: appState.day.startMinutes / 60,
                                      minute: appState.day.startMinutes % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                appState.day.startMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
            }
        )
    }

    // MARK: timeline

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack(alignment: .topLeading) {
                VStack(spacing: blockGap) {
                    ForEach(appState.day.blocks) { block in
                        blockRow(block, now: context.date)
                    }
                }
                if let y = nowOffset(at: context.date) {
                    nowIndicator(at: context.date)
                        .frame(height: 18)
                        .offset(y: y - 9)
                }
            }
        }
    }

    private func blockRow(_ block: DayBlock, now: Date) -> some View {
        let idx = index(of: block) ?? 0
        let begins = appState.day.startOf(idx)
        let running = isRunning(block, now: now)

        return HStack(alignment: .top, spacing: DS.space3) {
            Text(clock(begins))
                .font(DS.Font.caption)
                .foregroundStyle(running ? block.accent.color : DS.textTertiary)
                .frame(width: railWidth, alignment: .trailing)
                .padding(.top, DS.space5)

            VStack(alignment: .leading, spacing: DS.space3) {
                titleRow(block, begins: begins)
                if !block.tasks.isEmpty { taskList(block) }
                InlineAdd(
                    placeholder: block.tasks.isEmpty ? "what goes in here?" : "and then…",
                    onCommit: { text in
                        guard let i = index(of: block) else { return }
                        appState.day.blocks[i].tasks.append(DayTask(text: text))
                    }
                )
            }
            .padding(DS.space5)
            .frame(maxWidth: .infinity, minHeight: height(block), alignment: .topLeading)
            .background(cardBackground(block, running: running))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                    .stroke(running ? block.accent.color.opacity(0.45) : DS.border, lineWidth: 1)
            )
            .cardShadow(block.done ? 0 : (running ? 2 : 1))
            .opacity(block.done ? 0.72 : 1)
        }
    }

    private func cardBackground(_ block: DayBlock, running: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                .fill(block.done ? DS.insetBG : DS.cardBG)
            if running {
                RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                    .fill(block.accent.color.opacity(0.07))
            }
            Rectangle().fill(block.accent.color).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
    }

    private func titleRow(_ block: DayBlock, begins: Int) -> some View {
        HStack(spacing: DS.space3) {
            Button {
                guard let i = index(of: block) else { return }
                appState.day.blocks[i].done.toggle()
            } label: {
                Image(systemName: block.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(block.accent.color)
            }
            .buttonStyle(.plain)
            .help(block.done ? "Mark unfinished" : "Mark finished")

            TextField("Block", text: nameBinding(block))
                .textFieldStyle(.plain)
                .font(DS.Font.headline)
                .foregroundStyle(block.accent.color)
                .strikethrough(block.done, color: block.accent.color.opacity(0.6))

            Text("\(clock(begins))–\(clock(begins + block.minutes))")
                .font(DS.Font.caption)
                .foregroundStyle(DS.textTertiary)
                .monospacedDigit()

            durationStepper(block)
            reorderButtons(block)

            Button {
                guard let i = index(of: block) else { return }
                appState.day.blocks.remove(at: i)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.textTertiary)
            .help("Remove block")
        }
    }

    private func durationStepper(_ block: DayBlock) -> some View {
        HStack(spacing: 3) {
            Button {
                guard let i = index(of: block) else { return }
                appState.day.blocks[i].minutes = max(15, block.minutes - 15)
            } label: { Image(systemName: "minus") }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: DS.radiusS).fill(DS.subtleFill))

            Text(label(block.minutes))
                .font(DS.Font.micro)
                .monospacedDigit()
                .foregroundStyle(block.accent.color)
                .frame(width: 44)
                .padding(.vertical, 3)
                .background(Capsule().fill(block.accent.color.opacity(0.14)))

            Button {
                guard let i = index(of: block) else { return }
                appState.day.blocks[i].minutes = min(480, block.minutes + 15)
            } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: DS.radiusS).fill(DS.subtleFill))
        }
        .foregroundStyle(DS.textSecondary)
    }

    private func reorderButtons(_ block: DayBlock) -> some View {
        let i = index(of: block) ?? 0
        return VStack(spacing: 1) {
            Button { move(block, by: -1) } label: {
                Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(i == 0)

            Button { move(block, by: 1) } label: {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(i >= appState.day.blocks.count - 1)
        }
        .foregroundStyle(DS.textTertiary)
        .help("Reorder — the order is yours")
    }

    private func taskList(_ block: DayBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(block.tasks) { task in
                HStack(spacing: DS.space2) {
                    Button {
                        guard let bi = index(of: block),
                              let ti = appState.day.blocks[bi].tasks.firstIndex(where: { $0.id == task.id })
                        else { return }
                        appState.day.blocks[bi].tasks[ti].done.toggle()
                    } label: {
                        Image(systemName: task.done ? "circle.inset.filled" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(task.done ? DS.textTertiary : DS.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Text(task.text)
                        .font(DS.Font.body)
                        .foregroundStyle(task.done ? DS.textTertiary : DS.textPrimary)
                        .strikethrough(task.done, color: DS.textTertiary)

                    Spacer()

                    Button {
                        guard let bi = index(of: block) else { return }
                        appState.day.blocks[bi].tasks.removeAll { $0.id == task.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: now line

    private func nowIndicator(at date: Date) -> some View {
        HStack(spacing: 0) {
            Text(clock(minutes(of: date)))
                .font(DS.Font.micro)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(DS.danger))
                .frame(width: railWidth, alignment: .trailing)

            Rectangle()
                .fill(DS.danger)
                .frame(height: 1.5)
                .padding(.leading, DS.space3)
        }
        .allowsHitTesting(false)
    }

    /// Blocks have a minimum height, so a short block is taller on screen than its
    /// duration. Walk the list to find where a clock time really sits.
    private func nowOffset(at date: Date) -> CGFloat? {
        let mins = minutes(of: date)
        let day = appState.day
        guard mins >= day.startMinutes, mins <= day.endMinutes, !day.blocks.isEmpty else { return nil }

        var y: CGFloat = 0
        var cursor = day.startMinutes
        for b in day.blocks {
            if mins <= cursor + b.minutes {
                return y + CGFloat(mins - cursor) / CGFloat(b.minutes) * height(b)
            }
            y += height(b) + blockGap
            cursor += b.minutes
        }
        return y
    }

    // MARK: add block

    private var addBlockButton: some View {
        Button {
            let next = DayAccent.allCases[appState.day.blocks.count % DayAccent.allCases.count]
            appState.day.blocks.append(DayBlock(name: "New block", minutes: 60, accent: next))
        } label: {
            Label("Add a block", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .padding(.leading, railWidth + DS.space3)
    }

    // MARK: footer

    private var footer: some View {
        HStack(alignment: .top, spacing: DS.space6) {
            Card {
                VStack(alignment: .leading, spacing: DS.space2) {
                    Text("Later").font(DS.Font.headline)
                    Text("Something lands mid-block? Park it here instead of switching.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.bottom, DS.space2)

                    if appState.day.later.isEmpty {
                        Text("Empty.").font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                    } else {
                        ForEach(appState.day.later) { item in
                            HStack(spacing: DS.space2) {
                                Text(item.text).font(DS.Font.body)
                                Spacer()
                                Button("move up") {
                                    guard !appState.day.blocks.isEmpty else { return }
                                    appState.day.blocks[0].tasks.append(DayTask(text: item.text))
                                    appState.day.later.removeAll { $0.id == item.id }
                                }
                                .buttonStyle(.plain)
                                .font(DS.Font.micro)
                                .foregroundStyle(DS.accent)

                                Button {
                                    appState.day.later.removeAll { $0.id == item.id }
                                } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(DS.textTertiary)
                            }
                            .padding(.vertical, 3)
                            Divider().overlay(DS.borderSoft)
                        }
                    }

                    InlineAdd(placeholder: "Renew the domain") { text in
                        appState.day.later.append(DayTask(text: text))
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: DS.space2) {
                    Text("Hours finished").font(DS.Font.headline)
                    Text("Only ticked blocks count. A full bar means you hit your target.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.bottom, DS.space2)
                    historyBars
                }
            }
        }
    }

    private var historyBars: some View {
        let days = appState.dayHistory.reversed().suffix(14)
        return Group {
            if days.isEmpty {
                Text("Nothing yet. Today is day one.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.textTertiary)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days), id: \.date) { d in
                        let ratio = d.targetMinutes > 0
                            ? min(1, Double(d.finishedMinutes) / Double(d.targetMinutes)) : 0
                        VStack(spacing: DS.space1) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: DS.radiusS)
                                    .fill(DS.insetBG)
                                    .frame(height: 44)
                                RoundedRectangle(cornerRadius: DS.radiusS)
                                    .fill(ratio >= 1 ? DS.ok : DS.accent)
                                    .frame(height: max(3, 44 * ratio))
                            }
                            Text(String(d.date.suffix(2)))
                                .font(.system(size: 9))
                                .foregroundStyle(DS.textTertiary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: 20)
                        .help("\(d.date) — \(label(d.finishedMinutes)) of \(label(d.targetMinutes))")
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func index(of block: DayBlock) -> Int? {
        appState.day.blocks.firstIndex { $0.id == block.id }
    }

    private func nameBinding(_ block: DayBlock) -> Binding<String> {
        Binding(
            get: { appState.day.blocks.first { $0.id == block.id }?.name ?? block.name },
            set: { v in
                if let i = index(of: block) { appState.day.blocks[i].name = v }
            }
        )
    }

    private func move(_ block: DayBlock, by delta: Int) {
        guard let i = index(of: block) else { return }
        let j = i + delta
        guard j >= 0, j < appState.day.blocks.count else { return }
        appState.day.blocks.swapAt(i, j)
    }

    private func height(_ block: DayBlock) -> CGFloat {
        max(minBlockHeight, CGFloat(block.minutes) * pxPerMinute)
    }

    private func isRunning(_ block: DayBlock, now: Date) -> Bool {
        guard !block.done, let i = index(of: block) else { return false }
        let mins = minutes(of: now)
        let begins = appState.day.startOf(i)
        return mins >= begins && mins < begins + block.minutes
    }

    private func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func clock(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }

    private func label(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h > 0 && r > 0 { return "\(h)h \(r)m" }
        if h > 0 { return "\(h)h" }
        return "\(r)m"
    }

    private var longDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }
}

// MARK: - Inline add field
// Own struct so each field keeps its own @State.
private struct InlineAdd: View {
    let placeholder: String
    let onCommit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(DS.Font.body)
            .padding(.top, DS.space2)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.borderSoft).frame(height: 1)
            }
            .onSubmit {
                let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty else { return }
                onCommit(v)
                text = ""
            }
    }
}
