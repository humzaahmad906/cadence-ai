# Day, timers, and the log

The Day canvas, the block timer, the menu bar item, the office-arrival notification, and the
activity log. Source: `Models/Day.swift`, `Services/DayStore.swift`, `Views/DayView.swift`,
`Views/TimerMenuBar.swift`, `Services/NetworkWatch.swift`, `Services/ActivityLog.swift`,
`Views/ActivityView.swift`.

---

## The day as a shape

A `DayPlan` is one JSON file per day at `days/<yyyy-MM-dd>.json`. It holds ordered `DayBlock`s, a
start time, a target, and a *Later* list.

Blocks are drawn at their real length (1.5px per minute, floor of 84px), so a 3-hour block is
visibly three times a 1-hour one. A red now-line tracks the actual clock across them.

| Field | Meaning |
|---|---|
| `startMinutes` | Minutes from midnight the day begins at. Default 09:00. |
| `targetMinutes` | What you're aiming to actually finish. Default 6h. |
| `blocks` | Ordered. Reorder with the chevrons, resize with −/+ in 15-minute steps (15 min–8 h). |
| `later` | Parked items. Survives rollover. |
| `notified` | Block ids already announced, so the scheduler never repeats itself. |

Tasks inside a block are a plain checklist. They're optional — **a block with nothing listed times
exactly like a full one.**

---

## The timer

**The timer lives on the block, not the task.** One ▶ per block header, next to the duration
stepper.

- Start any block, in any order. It does not have to be the block the now-line is sitting in, and
  the blocks above it do not have to be finished.
- **One clock at a time.** Starting a second block banks the first automatically. Several timers
  racing each other would make the totals fiction, so the model doesn't allow it.
- Ticking a block done stops its clock. Starting a done block un-ticks it.
- Elapsed shows live beside the button in the block's accent, then stays in grey once stopped —
  turning accent if you ran past the length you gave the block.

Only `startedAt` (the start instant) and `secondsSpent` (banked time) are stored. Elapsed is
computed, so a relaunch doesn't lose the running count and nothing writes to disk every second.

```swift
func elapsed(at now: Date) -> Int {
    guard let startedAt else { return secondsSpent }
    return secondsSpent + max(0, Int(now.timeIntervalSince(startedAt)))
}
```

### Menu bar

While a block runs, `⏱ Work · 12:30` appears in the menu bar. Click it for the block name, its
running total, **Pause**, and **Open Day**. With nothing running the menu instead lists
**Start <block>** for each block, so you can restart without opening the window.

It is only inserted while something is timing — no idle icon parked up there all day. The
per-second redraw comes from `SecondTicker`, started and stopped by `AppState.day.didSet`, so no
timer spins when there's nothing to count. It runs on `.common` runloop mode so the count keeps
moving while a menu is open or a window is being dragged.

---

## When the day flips: 05:00

**The plan rolls over at 05:00, not midnight.** Work past midnight and you're still on the same
day's blocks.

`DayPlan.key(for:)` shifts the clock back by `rolloverMinutes` before formatting, which makes every
call site boundary-aware without threading the rule through each one:

```swift
static let rolloverMinutes = 5 * 60
static func key(for date: Date) -> String {
    keyFormatter.string(from: date.addingTimeInterval(-Double(rolloverMinutes) * 60))
}
```

| Wall clock | Logical day |
|---|---|
| Mon 22:00 | Monday |
| Tue 01:00 | **Monday** |
| Tue 04:59 | **Monday** |
| Tue 05:00 | Tuesday |

A consequence worth knowing: a timer still running at 01:00 is *not* treated as left over from
yesterday, because it isn't. One genuinely forgotten — started 23:00, app reopened next afternoon —
is billed to the 05:00 boundary (6h), not to the moment you reopened the app. That number is
visible in the archive row, so an obviously wrong figure is at least an obvious one.

### What rollover does

- Block **shape** carries forward: name, length, accent. Clocks reset to zero.
- ***Later*** carries forward.
- Block **tasks are archived to the log, then dropped.** No judgement about which counted as
  finished — the row records what was there and how long the block ran. One row per block that had
  tasks or tracked time:

  > **Work — 2:15:00**
  > ✓ ship the patch   · rip out kanban   · office wifi watcher

- The new day starts with empty blocks.

`DayStore.today()` returns `(plan, rolledFrom)` — the caller needs that second value to archive the
old day before it's gone, since the rollover is the only moment it still exists.

---

## The log

`Views/ActivityView.swift`. Reverse-chronological, grouped by day (Today / Yesterday / weekday),
with **All · Runs · Day** filters.

Two sources, merged at read time:

1. **Workflow runs** — read straight from `workflows/<ID>/runs/*.json` via
   `WorkflowStore.allRuns()`. Not copied into the log; the runs are already on disk.
2. **`activity.jsonl`** — the events with no other home: block starts, day rollovers, archived
   days, office arrivals. JSON Lines, so appending is one write with no read-modify-write race and
   a truncated tail costs one event instead of the file.

Rows that point somewhere navigate there (a run row opens the run). Rows that don't — an archived
day describes blocks that no longer exist — **expand in place on click** instead, with selectable
text.

---

## Office arrival

`Services/NetworkWatch.swift`. The first time each day you join the office network, a notification
offers to open Day.

**Why the gateway MAC.** The SSID would be the obvious identifier, but macOS 14 gates it behind
Location authorization — `ipconfig getsummary en0` returns `SSID : <redacted>` without it. Three
MACs are in play and only one is useful:

| MAC | Usable |
|---|---|
| Your Mac's Wi-Fi MAC | ❌ Same on every network — identifies the laptop, not the place |
| Router BSSID | ❌ Location-gated, same as the SSID |
| **Default gateway MAC** (`route -n get default` → `arp -n <gw>`) | ✅ Unique per router, no permission, survives roaming between APs in one building |

If the ARP entry isn't populated yet it falls back to `<interface>/<gateway-ip>` — weaker, but not
a false negative; the next tick self-heals it.

Detection: `NWPathMonitor` fires on path change → 2s settle (the path flips before the route table
does) → re-read → compare. The 60s scheduler tick is the backstop.

**Fires once per day.** `lastAnnounced` (a `yyyy-MM-dd`) is written to `network.json` the moment it
fires, before you've done anything — so ignoring it, dismissing it, reconnecting at lunch, or
logging out and back in all stay quiet until tomorrow.

### It only works while the app is running

The scheduler lives in-process. Settings → **"Open Cadence at login"** registers the app with
`SMAppService.mainApp`, which is what makes "logged in at the office" produce a notification.
`Scripts/install-launchd.sh` is the alternative — a launch agent with `RunAtLoad` plus 08:30 on
weekdays.

Note the ordering in `CadenceApp`: notification authorization is requested **before**
`scheduler.start()`. The office check runs the instant the scheduler starts, and a notification
posted before the permission prompt is answered is dropped without a trace.

---

## Block-start notifications

On the 60s tick, a block that has just begun is announced once — name plus up to three of its
tasks. The guard (`DayPlan.notified`) lives on disk, so a relaunch won't re-announce.

Firing uses a 5-minute window from the block's start rather than an exact minute match: a short
sleep won't swallow the alert, and opening the app mid-afternoon won't produce a burst of stale
ones. Tapping one opens Day, via the `cadence://day` URL in the notification's `userInfo` and
`NotificationRouter`.

---

## Gotcha: Codable defaults

Swift's **synthesized `Decodable` ignores default values** — `var secondsSpent: Int = 0` still
throws `keyNotFound` when the key is absent. A day file written before the timer fields existed
would fail to load and take the day's plan with it.

`DayBlock` therefore decodes leniently, in an **extension** so the memberwise initialiser survives
(declaring `init(from:)` in the struct body would suppress it):

```swift
extension DayBlock {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ...
        secondsSpent = (try? c.decode(Int.self, forKey: .secondsSpent)) ?? 0
        startedAt = try? c.decode(Date.self, forKey: .startedAt)
    }
}
```

Add a field to a persisted day type and you must extend that decoder too.

---

## Claude model settings

`Services/ClaudeSettings.swift`, persisted to `config.json`, edited in Settings.

`ClaudeBridge` resolves in one place — per-call value beats app default beats the CLI's own:

```swift
private func resolve(model: String, effort: String) -> (model: String, effort: String) {
    (model.isEmpty ? defaultModel : model, effort.isEmpty ? defaultEffort : effort)
}
```

A workflow block that names its own model still wins. Default is `claude-opus-5`.

`ModelCatalog.known` is a convenience list, **not a gate** — Settings also takes a typed id, passed
to `claude --model` verbatim, so a model released after this build works by typing its id. The
CLI's own aliases (`opus`, `sonnet`, `haiku`) work the same way.
