# Cadence

Personal macOS app for 2-week sprint tracking + workflow automation. Native SwiftUI, a plain
file-based store (no external DB), and the Claude CLI (subscription OAuth via keychain — no API keys).

## What it does
- Kanban board (Backlog / Todo / In Progress / In Review / Done), drag-drop.
- Paste sprint tasks in any format → Claude splits them into tickets, grounded in your indexed repos.
- Per-ticket wizard: a grounded description → an implementation plan, with human review.
- Node-based **workflow builder** — assemble automations on a canvas (agent / code / review / ticket
  blocks), wire them into a graph, run as a DAG, and debug step-by-step. See
  [docs/WORKFLOWS.md](docs/WORKFLOWS.md).
- Auto daily-standup draft; scheduled notifications.
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
├── issues/<ID>/                   issue.md + exploration notes (one folder per ticket)
├── repos.json                     indexed repos
├── workflows/<ID>/                workflow.json + runs/<runID>.json
├── attachments/<ticket_id>/       images / files
├── digests/                       archived standup drafts
└── config.json
```

## Build
```
brew install xcodegen        # if missing
cd ~/cadence-ai
bash Scripts/build.sh        # xcodegen generate + build + install to ~/Applications/Cadence.app
```

## Set up scheduler (optional — the app also schedules while running)
```
bash Scripts/install-launchd.sh
```

## Deps
- macOS 14+
- Xcode 15+ (Xcode 26 tested) + xcodegen
- Claude CLI at `/opt/homebrew/bin/claude` (uses your Claude subscription; no API keys)

## How data flows
1. Paste a sprint → Claude splits it into tickets, each grounded in your indexed repos → saved as
   `issues/<ID>/issue.md`.
2. The per-ticket wizard writes a grounded description, then an implementation plan — each a Claude
   agent with Read/Grep/Glob/`git` access to the scoped repos — with human review before saving.
3. Workflows chain blocks on a canvas and run as a DAG; every run is saved under `workflows/<ID>/runs/`.
4. Standup digest: recent ticket activity → Claude polish → draft to clipboard + notification.

The agent runs via `claude -p` with native Read/Grep/Glob/`Bash(git …)` tools scoped to your repos
(`--add-dir`). No MCP server, no cloud DB, no API-key billing.

## Ticket template sections
Standard: title, id, description, status, priority (P0–P4), estimate, assignee, labels, project,
sprint. Added: results, blockers, verification, notes (private), time log, comments.
