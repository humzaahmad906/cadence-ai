# Cadence

Personal macOS dashboard for 2-week sprint tracking. Native SwiftUI + Kuzu graph DB + Claude CLI (subscription auth, no API keys).

## What it does
- Kanban board (Backlog / Todo / In Progress / In Review / Done), drag-drop
- Paste sprint tasks in any format, Claude parses into tickets
- Ticket template: description, results, blockers, verification, notes, time log, comments (with image/file attachments)
- Priority rerank via drag OR natural-language chat ("PXLV-12 is top now")
- Auto daily-standup draft from kanban movements — preview 1:45pm, clipboard 2:00pm
- Notifs: 9am brief, 1:45pm draft-ready, idle >2d in In Progress, sprint <3d + open P0/P1
- Graph DB with full history: status transitions, priority changes, comments, attachments

## Layout
```
~/cadence-ai/                      source repo
├── Cadence/                       Swift/SwiftUI sources
├── Helpers/                          kuzu_helper.py + .venv
├── Resources/ticket_template.md
├── Scripts/build.sh, install-launchd.sh
├── project.yml                       xcodegen
└── Cadence.xcodeproj/             generated

~/Library/Application Support/Cadence/
├── graph.kuzu/                       DB
├── attachments/<ticket_id>/          images/files
└── digests/                          archived Slack drafts
```

## Build
```
brew install xcodegen        # if missing
cd ~/cadence-ai
bash Scripts/build.sh        # installs to ~/Applications/Cadence.app
```

## Set up scheduler (optional — app already schedules while running)
```
bash Scripts/install-launchd.sh
```

## Deps
- macOS 14+
- Xcode 15+ (Xcode 26 tested)
- Python 3.13 in Helpers/.venv (kuzu wheel)
- Claude CLI at /opt/homebrew/bin/claude (uses your subscription)

## Data flow
1. Paste sprint → Claude parses raw → JSON tickets → Kuzu commits `Ticket`, `Sprint`, `BELONGS_TO`, `IN_SPRINT` nodes/edges.
2. Every kanban move creates `StatusChange` node + `TRANSITIONED` edge.
3. Priority change (drag or chat) creates `PriorityChange` node + `REPRIORITIZED` edge.
4. Comments create `Comment` nodes with optional `Attachment` children. Attachments copied into AppSupport.
5. At 13:45 → query `StatusChange` in last 24h → Claude polish → draft ready.
6. At 14:00 → copy to clipboard + notif.

## Ticket template sections
Standard: title, id, description, status, priority (P0–P4), estimate, assignee, labels, project, sprint.
Added: results, blockers, verification, notes (private), time log, comments.
