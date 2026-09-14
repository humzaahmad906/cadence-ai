# Cadence — Functional Overview

What each part of Cadence *does*. No UI/CSS talk — just the mechanics.

Companion docs: [DAY.md](DAY.md) (day canvas, timers, log, office arrival, model settings) and
[WORKFLOWS.md](WORKFLOWS.md) (the node builder and DAG engine).

---

## What Cadence is (in one paragraph)

A personal macOS app with two jobs: shape the working day into timed blocks, and run
block-based automations against your repos through the Claude CLI. Everything lives as plain files
on disk. No external DB, no MCP server, no API-key billing — the agent runs via `claude -p` with
native Read/Grep/Glob/`Bash(git …)` tools scoped by `--add-dir`. Data survives quit/relaunch.

## What Cadence is *not*

- Not a team tool. Single user, local files, no sync, no auth.
- Not a Linear/Jira replacement. Tickets exist because workflows produce them; there's no board,
  no sprint view, no assignment flow.
- Not an autonomous agent. Every workflow run is something you started.

---

## The surface

Three destinations in the header, and nothing else:

| Canvas | Shortcut | View | Does |
|---|---|---|---|
| **Workflows** | `⌘1` | `WorkflowsListView` | Library of workflows. Home. New from template, new blank, or describe one and let Claude assemble it. |
| **Day** | `⌘2` | `DayView` | Today as sized blocks with a now-line and a per-block timer. |
| **Log** | `⌘3` | `ActivityView` | Every workflow run, day block, rollover and office arrival, newest first. |

Click-through destinations (not in the header): `workflowBuilder`, `workflowRun`, `ticketsList`,
`ticketDetail`, `settings`.

`CanvasArtifact` (`Models/CanvasArtifact.swift`) is the whole router — one enum, one canvas at a
time, with back/forward (`⌘[` / `⌘]`) kept in `AppState.artifactBack/Forward`.

### Ticket archive

Workflows still create tickets (`createTickets` block → `IssueStore` → `issues/<ID>/issue.md`), and
`viewer` blocks can display one. They're reachable from **Settings → Archive** and from the Log's
toolbar — deliberately off the home surface. `TicketsListView` and `TicketDetailView` are all that
remain of the old ticket UI.

---

## Core models

Persisted as files. Everything else is a view onto them.

| Model | File | Represents |
|---|---|---|
| **DayPlan / DayBlock / DayTask** | `days/<yyyy-MM-dd>.json` | The day's shape, its blocks, their timers |
| **Workflow / WorkflowBlock** | `workflows/<ID>/workflow.json` | An automation graph |
| **WorkflowRun / BlockRunState** | `workflows/<ID>/runs/<runID>.json` | One execution, per-block input/output/status |
| **ActivityEvent** | `activity.jsonl` | A line in the log |
| **OfficeNetwork** | `network.json` | Which network counts as the office |
| **ClaudeSettings** | `config.json` | CLI binary, model, effort |
| **Ticket** | `issues/<ID>/issue.md` | Unit of work produced by a workflow |

Paths are centralised in `Services/CadencePaths.swift`. Every store writes atomically.

---

## Day

See [DAY.md](DAY.md) for the full picture. In short:

- Blocks sized by real duration, reorderable, resizable in 15-minute steps.
- **The timer lives on the block.** One clock at a time; starting a second banks the first. A block
  with no tasks times just the same.
- **The day flips at 05:00**, not midnight.
- At the flip, block tasks are archived into the log and the blocks start empty; shape and *Later*
  carry forward.
- A running timer shows in the menu bar as `⏱ Work · 12:30`.

---

## Workflows

See [WORKFLOWS.md](WORKFLOWS.md). Blocks are wired on a canvas and executed as a DAG by
`WorkflowRunner`, one block at a time, with `manualReview` blocks pausing for approval. Every state
change is persisted to the run file, so the Log and the run view read the same bytes.

`AIBuilderView` takes a plain-language description and asks Claude to assemble and wire the blocks;
`Workflow.templates()` supplies the ready-made ones.

Per-block debug (`DebugPanelView`) runs a single block with a given input and shows its raw
input/output without touching the run history.

---

## The log

`ActivityLog.feed(store:)` merges two sources at read time:

1. Every `WorkflowRun` on disk, via `WorkflowStore.allRuns()` — folded into rows by
   `ActivityEvent.init(run:)`. Runs are **not** copied into the log; they're already files.
2. `activity.jsonl` — day-block starts, rollovers, archived days, office arrivals. JSON Lines, so
   an append is a single write with no read-modify-write race.

Rows with a destination navigate; rows without one (an archived day) expand in place.

---

## Scheduler + notifications

`Services/Scheduler.swift`. One 60-second tick, three jobs:

1. **Rollover** — if `day.date` no longer matches `DayPlan.key(for: now)`, reload and log it.
2. **Block start** — announce a block within 5 minutes of it beginning, once, guarded by
   `DayPlan.notified` on disk.
3. **Network** — re-read the current network fingerprint and fire the office arrival if it's new
   today.

Notifications carry a `cadence://` URL in `userInfo`; `NotificationRouter` (a
`UNUserNotificationCenterDelegate`) turns a tap into a canvas route. `cadence://day` and
`cadence://log` are the two routes.

Notification authorization is requested **before** the scheduler starts — the office check runs
immediately on start, and a notification posted before the prompt is answered is silently dropped.

---

## Claude bridge

`Bridge/ClaudeBridge.swift` — an actor wrapping the `claude` CLI.

| Method | Shape |
|---|---|
| `promptAgent` | `claude -p … --output-format json`, Read/Grep/Glob + read-only `git` tools |
| `promptAgentJSONStreaming` | `--output-format stream-json`, emits tool-use names as they arrive |
| `prompt` | Plain single-turn, no tools |

`--add-dir` grants read access to the scoped repo paths. Model and effort resolve in one place
(`modelArgs`): per-call value, else the app default from `config.json`, else whatever the CLI is
configured to use.

---

## Repos

`Services/RepoRegistry.swift` → `repos.json`. Workflows are tagged with repos and a branch per
repo; those paths become the agent's `--add-dir` scope. `AppState.loadBranches` reads the branch
list with `git`.

---

## Persistence

| Store | Writes |
|---|---|
| `DayStore` | `days/<key>.json`, atomic. `today()` returns `(plan, rolledFrom)`. |
| `WorkflowStore` | `workflow.json` + `runs/<id>.json`, atomic. `allRuns()` scans all workflows. |
| `ActivityLog` | Appends one JSON object per line to `activity.jsonl`. Best-effort — logging must never break what it's logging. |
| `IssueStore` | `issues/<ID>/issue.md` + exploration notes. |
| `RepoRegistry` | `repos.json`. |

**Codable gotcha:** Swift's synthesized `Decodable` ignores default values — a missing key throws
even when the property has one. `DayBlock` and `WorkflowBlockConfig` both decode leniently for this
reason. Add a field to a persisted type and you must extend its decoder too.

---

## Typical day

1. Log in at the office. Cadence is already running (login item); the arrival notification opens
   Day.
2. Fill in the morning's blocks, hit ▶ on whichever one you're actually starting.
3. Run a workflow or two. They land in the Log as they finish.
4. Work past midnight if it goes that way — still the same day until 05:00.
5. Next morning the blocks are empty again; yesterday's contents are a row in the Log.
