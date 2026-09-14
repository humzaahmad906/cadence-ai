import Foundation

// MARK: - Day
// A single day's shape: ordered blocks of time, each holding tasks added that morning.
// Pure Foundation, Codable, one file per day on disk — mirrors Ticket / Workflow.

/// Which DS accent a block wears. Maps to a Color in DayView (same split as BlockStyle.swift).
enum DayAccent: String, Codable, CaseIterable, Identifiable {
    case amber, purple, indigo, green
    var id: String { rawValue }
}

/// A checklist line inside a block. Optional — a block can be timed with nothing listed in it.
struct DayTask: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var text: String
    var done: Bool = false
}

/// A stretch of the day. The block is what you time — tasks inside it are a checklist, and a
/// block with an empty list times just as well as a full one.
struct DayBlock: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var minutes: Int
    var accent: DayAccent
    var done: Bool = false
    var tasks: [DayTask] = []
    /// Time banked from previous runs of this block's timer.
    var secondsSpent: Int = 0
    /// Non-nil while the timer runs. Only the start instant is stored, so elapsed time stays
    /// correct across a relaunch without writing to disk every second.
    var startedAt: Date?

    var isTiming: Bool { startedAt != nil }

    /// Banked time plus the current run.
    func elapsed(at now: Date = Date()) -> Int {
        guard let startedAt else { return secondsSpent }
        return secondsSpent + max(0, Int(now.timeIntervalSince(startedAt)))
    }

    /// hh:mm:ss once past an hour, mm:ss before that.
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Decoded leniently, in an extension so the memberwise init survives. A synthesized decoder
/// throws on a missing key even when the property has a default, so a day file written before
/// the timer existed would fail to load and take the day's plan with it.
extension DayBlock {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 60
        accent = (try? c.decode(DayAccent.self, forKey: .accent)) ?? .indigo
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        tasks = (try? c.decode([DayTask].self, forKey: .tasks)) ?? []
        secondsSpent = (try? c.decode(Int.self, forKey: .secondsSpent)) ?? 0
        startedAt = try? c.decode(Date.self, forKey: .startedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, minutes, accent, done, tasks, secondsSpent, startedAt
    }
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

    /// The plan flips at 05:00, not midnight. Work past midnight and you're still on the same
    /// day's blocks — which is how the evening actually feels, and it stops a timer running at
    /// 01:00 from being treated as left over from yesterday.
    static let rolloverMinutes = 5 * 60

    /// Shifting the clock back by the rollover offset before formatting makes every existing
    /// call site boundary-aware without having to thread the rule through each one.
    static func key(for date: Date) -> String {
        keyFormatter.string(from: date.addingTimeInterval(-Double(rolloverMinutes) * 60))
    }

    /// The instant the logical day containing `date` ends — the next 05:00 strictly after it.
    static func boundary(after date: Date) -> Date {
        let cal = Calendar.current
        let h = rolloverMinutes / 60, m = rolloverMinutes % 60
        if let sameDay = cal.date(bySettingHour: h, minute: m, second: 0, of: date), sameDay > date {
            return sameDay
        }
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: date),
              let next = cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow) else { return date }
        return next
    }

    // MARK: derived

    var plannedMinutes: Int { blocks.reduce(0) { $0 + $1.minutes } }
    /// Seconds actually tracked today, across every block.
    func trackedSeconds(at now: Date = Date()) -> Int {
        blocks.reduce(0) { $0 + $1.elapsed(at: now) }
    }
    var finishedMinutes: Int { blocks.reduce(0) { $0 + ($1.done ? $1.minutes : 0) } }
    var endMinutes: Int { startMinutes + plannedMinutes }

    /// Noon on this plan's own date — a stable instant inside the day, used to work out when
    /// the day ended without having to re-parse the key against the current clock.
    var endOfDay: Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date).map { $0.addingTimeInterval(12 * 3600) } ?? Date()
    }

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

    // MARK: timers
    //
    // Blocks are worked in whatever order suits the day — the block you time doesn't have to be
    // the one the clock is sitting in, and the ones above it don't have to be finished. What the
    // day enforces is one timer at a time: starting a block banks whatever was running, so the
    // totals add up to time actually spent rather than several clocks racing each other.

    var runningBlockId: String? { blocks.first { $0.isTiming }?.id }
    var runningBlock: DayBlock? { blocks.first { $0.isTiming } }

    /// Start this block's timer, stopping whatever was running. Hitting it again stops it, so
    /// one button does both.
    mutating func toggleTimer(blockId: String, now: Date = Date()) {
        let wasRunning = runningBlockId == blockId
        stopAllTimers(at: now)
        guard !wasRunning, let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        blocks[i].startedAt = now
        blocks[i].done = false          // timing something means it isn't finished
    }

    /// Bank every running timer and clear it.
    mutating func stopAllTimers(at now: Date = Date()) {
        for i in blocks.indices {
            guard let started = blocks[i].startedAt else { continue }
            blocks[i].secondsSpent += max(0, Int(now.timeIntervalSince(started)))
            blocks[i].startedAt = nil
        }
    }

    /// Finishing a block stops its clock; un-finishing leaves it stopped.
    mutating func setDone(blockId: String, _ done: Bool, now: Date = Date()) {
        if done, runningBlockId == blockId { stopAllTimers(at: now) }
        guard let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        blocks[i].done = done
    }

    /// A timer left running when the app closed keeps counting off the wall clock. If it was
    /// started on an earlier day, stop it where that day ended rather than billing every hour
    /// since. A timer started at 23:00 and forgotten is billed to 05:00, not to now.
    mutating func reconcileTimers(now: Date = Date()) {
        let today = Self.key(for: now)
        for i in blocks.indices {
            guard let started = blocks[i].startedAt, Self.key(for: started) != today else { continue }
            let ended = Self.boundary(after: started)
            blocks[i].secondsSpent += max(0, Int(ended.timeIntervalSince(started)))
            blocks[i].startedAt = nil
        }
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
                         accent: $0.accent, done: false, tasks: [],
                         secondsSpent: 0, startedAt: nil)
            },
            later: later.map { DayTask(id: $0.id, text: $0.text, done: false) },
            notified: []
        )
    }
}
