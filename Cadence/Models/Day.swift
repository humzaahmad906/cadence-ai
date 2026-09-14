import Foundation

// MARK: - Day
// A single day's shape: ordered blocks of time, each holding tasks added that morning.
// Pure Foundation, Codable, one file per day on disk — mirrors Ticket / Workflow.

/// Which DS accent a block wears. Maps to a Color in DayView (same split as BlockStyle.swift).
enum DayAccent: String, Codable, CaseIterable, Identifiable {
    case amber, purple, indigo, green
    var id: String { rawValue }
}

struct DayTask: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var done: Bool = false
}

struct DayBlock: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var minutes: Int
    var accent: DayAccent
    var done: Bool = false
    var tasks: [DayTask] = []
}

struct DayPlan: Codable, Hashable {
    /// yyyy-MM-dd, local time.
    var date: String
    /// Minutes from midnight the day starts at.
    var startMinutes: Int = 9 * 60
    /// What you're aiming to actually finish.
    var targetMinutes: Int = 360
    var blocks: [DayBlock] = []
    /// Parked items. Survives rollover.
    var later: [DayTask] = []
    /// Block ids already announced today, so the scheduler never repeats itself.
    var notified: [String] = []

    // MARK: date key

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { keyFormatter.string(from: date) }

    // MARK: derived

    var plannedMinutes: Int { blocks.reduce(0) { $0 + $1.minutes } }
    var finishedMinutes: Int { blocks.reduce(0) { $0 + ($1.done ? $1.minutes : 0) } }
    var endMinutes: Int { startMinutes + plannedMinutes }

    /// Clock time (minutes from midnight) that block `index` begins at.
    func startOf(_ index: Int) -> Int {
        guard index > 0 else { return startMinutes }
        return startMinutes + blocks.prefix(index).reduce(0) { $0 + $1.minutes }
    }

    /// Index of the block containing `minutesFromMidnight`, if the day is running.
    func blockIndex(at minutesFromMidnight: Int) -> Int? {
        var cursor = startMinutes
        for (i, b) in blocks.enumerated() {
            if minutesFromMidnight >= cursor && minutesFromMidnight < cursor + b.minutes { return i }
            cursor += b.minutes
        }
        return nil
    }

    // MARK: lifecycle

    /// First run. Four blocks, amber first because that's the one that stalls the morning.
    static func seed(date: String) -> DayPlan {
        DayPlan(
            date: date,
            blocks: [
                DayBlock(name: "Boring tasks",       minutes: 60,  accent: .amber),
                DayBlock(name: "Applied ML Academy", minutes: 60,  accent: .purple),
                DayBlock(name: "Work",               minutes: 120, accent: .indigo),
                DayBlock(name: "CV and skills",      minutes: 60,  accent: .green)
            ]
        )
    }

    /// Next day: keep the shape you settled on and anything parked, drop yesterday's contents.
    func rolledOver(to newDate: String) -> DayPlan {
        DayPlan(
            date: newDate,
            startMinutes: startMinutes,
            targetMinutes: targetMinutes,
            blocks: blocks.map {
                DayBlock(id: UUID().uuidString, name: $0.name, minutes: $0.minutes,
                         accent: $0.accent, done: false, tasks: [])
            },
            later: later,
            notified: []
        )
    }
}
