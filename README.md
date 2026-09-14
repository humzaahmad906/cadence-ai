# Cadence

Personal macOS app: a time-blocked day, and workflow automation built from blocks. Native SwiftUI,
a plain file-based store (no external DB), and the Claude CLI (subscription OAuth via keychain —
no API keys).

Three screens, and nothing else on the home surface:

| | | |
|---|---|---|
| **Workflows** `⌘1` | Node-based automations you assemble on a canvas and run as a DAG | [docs/WORKFLOWS.md](docs/WORKFLOWS.md) |
| **Day** `⌘2` | Today as a shape: ordered blocks sized by their real length, one timer at a time | [docs/DAY.md](docs/DAY.md) |
| **Log** `⌘3` | Everything that ran — workflow runs, day blocks, office arrivals, archived days | [docs/DAY.md](docs/DAY.md#the-log) |

Tickets still exist — workflows create them — but they live off the home surface, in
Settings → Archive. There is no board, no wizard, no digest.

## What it does
- **Day canvas.** Blocks you can reorder and resize, a live now-line, and a start/stop timer on
  each block. One clock at a time; totals show tracked-vs-planned. The day flips at **05:00**, not
  midnight, so working past midnight is still today.
- **Menu bar timer.** While a block is running, `⏱ Work · 12:30` sits in the menu bar — click to
  pause or jump to Day. It disappears when nothing is running.
- **Office arrival.** The first time each day you join your office network, a notification offers to
  open Day. Identified by the router's MAC address (macOS won't hand out the Wi-Fi name without
  Location access). Ignore it and it stays quiet until tomorrow.
- **Workflow builder.** Assemble automations on a canvas (agent / code / review / ticket blocks),
  wire them into a graph, run as a DAG, debug step by step.
- **Model picker.** Which Claude model the CLI runs, app-wide, with a free-text field so a model
  released after this build works by typing its id.
- Everything is stored as plain files on disk (survives quit/relaunch).

## Layout
```
~/cadence-ai/                      source repo
├── Cadence/                       Swift/SwiftUI sources (Models, Views, Services, Bridge)
├── Resources/                     app icons + ticket template
├── Scripts/build.sh, install-launchd.sh
├── project.yml                    xcodegen config
└── Cadence.xcodeproj/             generated (gitignored — `xcodegen generate`)

~/Library/Application Support/Cadence/     (runtime data)
├── days/<yyyy-MM-dd>.json         one file per day: blocks, tasks, timers
├── workflows/<ID>/                workflow.json + runs/<runID>.json
├── activity.jsonl                 the log — day events, one JSON object per line
├── network.json                   which network counts as the office
├── config.json                    claude binary, model, effort
├── issues/<ID>/                   issue.md + exploration notes (one folder per ticket)
├── repos.json                     indexed repos
└── attachments/<ticket_id>/       images / files
```

## Build
```
brew install xcodegen        # if missing
cd ~/cadence-ai
bash Scripts/build.sh        # xcodegen generate + build + install to ~/Applications/Cadence.app
```

`Cadence.xcodeproj` is generated and gitignored — never edit it by hand; add a source file and
`project.yml` picks it up on the next build.

## First run
1. **Settings → Claude model** — defaults to `claude-opus-5`. Change it or type any model id.
2. **Settings → Office network → "Use current network"** — captures the router you're on now.
   Nothing fires until you do this.
3. **Settings → "Open Cadence at login"** — the arrival check runs when the app starts, so it needs
   to be running. (`bash Scripts/install-launchd.sh` is the alternative: a launch agent that opens
   it at login and at 08:30 on weekdays.)

## Deps
- macOS 14+
- Xcode 15+ (Xcode 26 tested) + xcodegen
- Claude CLI at `/opt/homebrew/bin/claude` (uses your Claude subscription; no API keys)

## How data flows
1. **Day** is one JSON file per day under `days/`. Blocks carry their own clock; only the start
   instant is stored, so elapsed time stays right across a relaunch without writing every second.
2. At **05:00** the plan rolls over: block shape and anything parked in *Later* carry forward, the
   blocks' tasks are written into the log as an archive row, and the new day starts empty.
3. **Workflows** chain blocks on a canvas and run as a DAG; every run is saved under
   `workflows/<ID>/runs/`. The Log reads those directly — it doesn't keep a second copy.
4. The agent runs via `claude -p` with native Read/Grep/Glob/`Bash(git …)` tools scoped to your
   repos (`--add-dir`). No MCP server, no cloud DB, no API-key billing.
