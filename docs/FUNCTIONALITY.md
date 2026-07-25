# Cadence — Functional Overview

What each part of Cadence *does*. No UI/CSS talk. Just the mechanics behind every panel and feature.

> **Architecture note (current).** Cadence no longer uses a Kuzu graph DB, the `Helpers/` Python
> subprocess, or an MCP server — those were removed. State is plain files on disk: `IssueStore`
> (`issues/<ID>/*.md`), `RepoRegistry` (`repos.json`), workflows under `workflows/<ID>/`, config in
> `config.json` — see `Services/CadencePaths.swift`. The Claude agent runs via the `claude -p` CLI
> with native Read/Grep/Glob/`Bash(git …)` tools scoped by `--add-dir` (no MCP). The UI is
> canvas-driven (the chat rail was removed) and workflows are node-based (see `WORKFLOWS.md`).
> Sections below that say "Kuzu"/"MCP"/"Helpers" describe the superseded internals; the behaviour
> they describe (tickets, review/approve, digest) is largely unchanged.

---

## What Cadence is (in one paragraph)

A personal sprint dashboard for a single dev on a 2-week Linear-style cadence. Every ticket, exploration, and finding lives as plain files on disk. A Claude agent (via the `claude -p` CLI, with native Read/Grep/Glob/`git` tools scoped to your repos) helps you plan, expand tickets, index repos, and draft daily standup updates — always with human preview/approve before mutations. Data survives quit/relaunch. No external cloud DB, no API-key billing (uses your Claude subscription CLI).

---

## Core concepts (the nouns)

These are the core models, persisted as files on disk. Everything else in the app is a view onto them.

| Node | Represents | Key fields |
|---|---|---|
| **Ticket** | Unit of work | id, title, description, status, priority (P0–P4), estimate, assignee, labels, results, blockers, verification, notes, time_log |
| **Sprint** | 2-week window | id (`sprint_YYYY-MM-DD`), name, start_date, end_date |
| **Project** | Namespace for tickets | id, name, key, description |
| **Comment** | Threaded note on a ticket | id, body, author, created |
| **Attachment** | File attached to a ticket/comment | id, path (in AppSupport), mime |
| **StatusChange** | Kanban move event (audit log) | from_status, to_status, at |
| **PriorityChange** | Priority mutation (audit log) | from_priority, to_priority, reason, at |
| **DailyUpdate** | 2pm Slack digest artifact | date, yesterday, today, blockers |
| **Repo** | An indexed local git repo | id, name, path, head_sha, last_indexed, file_count |
| **File** | A tracked file inside a Repo | path, language, content_hash, git_sha, last_commit_date, loc, indexed_at |
| **Symbol** | Extracted function/class/struct | name, kind, line, language |
| **Doctrine** | Persistent finding / lesson | title, content, confidence, source, tags |
| **Functionality** | Coherent feature/capability | id, name, description (rich markdown), created, updated |

Edges (relationships) connect these:

- `BELONGS_TO` Ticket → Project
- `IN_SPRINT` Ticket → Sprint
- `HAS_COMMENT` Ticket → Comment
- `HAS_ATTACHMENT_T` Ticket → Attachment, `HAS_ATTACHMENT_C` Comment → Attachment
- `BLOCKS` Ticket → Ticket
- `TRANSITIONED` Ticket → StatusChange, `REPRIORITIZED` Ticket → PriorityChange (audit trails)
- `MENTIONED_IN` Ticket → DailyUpdate
- `HAS_FILE` Repo → File
- `DEFINED_IN` Symbol → File
- `TICKET_TOUCHES_REPO` Ticket → Repo (with `linked_at`, `linked_head_sha` snapshot)
- `TICKET_TOUCHES_FILE` Ticket → File (with `linked_at`, `linked_git_sha`, `note` — stale detection uses this)
- `TICKET_ABOUT_DOCTRINE` Ticket → Doctrine
- `DOCTRINE_ABOUT_FILE` Doctrine → File, `DOCTRINE_ABOUT_REPO` Doctrine → Repo
- `FILE_IMPLEMENTS` File → Functionality
- `SYMBOL_IMPLEMENTS` Symbol → Functionality
- `TICKET_WORKS_ON` Ticket → Functionality (with `linked_at`, `note`)
- `FUNCTIONALITY_DOCUMENTED_BY` Functionality → Doctrine
- `FUNCTIONALITY_DEPENDS_ON` Functionality → Functionality (with `note`)
- `FUNCTIONALITY_PART_OF` Functionality → Functionality (hierarchy)
- `FUNCTIONALITY_RELATED_TO` Functionality → Functionality (with `note`, weak association)

Everything the app can do reduces to reading and writing these nodes/edges.

---

## Dashboard

The default landing route.

- **Critique banner (top).** Gradient CTA that spawns a fresh conversation titled `Critique · <timestamp>` and auto-fires the workspace critique goal. That goal is a specialized system prompt instructing Claude to use MCP tools to inspect every ticket, repo, doctrine, and stale link, then output structured markdown with sections: Summary, Blockers, Under-specified tickets, Stale knowledge, Coverage gaps, Suggested new tickets (in Linear-paste code blocks), Next 3 actions. Every claim must cite an ID/path retrieved via MCP (no fabrication).
- **KPI tiles (5).**
  - Open: tickets whose status ≠ Done.
  - Done (sprint): tickets whose status = Done.
  - Blocked: tickets whose `blockers` field is non-empty.
  - Urgent (P0/P1) open: tickets with P0 or P1 that aren't Done.
  - Days left: derived from `currentSprint.endDate`. Tint changes at ≤5d (amber) and ≤3d (red).
- **Stale-links warning.** If any `TICKET_TOUCHES_FILE` edge has `linked_git_sha ≠ File.git_sha`, dashboard shows the top 5 affected tickets with the SHA delta. Means the code has moved since the link was made — re-verify.
- **Today's digest card.** Inline preview + regenerate button. Same digest that auto-copies to clipboard at 2 PM.
- **Recent activity card.** Reads `StatusChange` nodes from the last 48h and renders as a timeline.
- **Repos card.** All indexed repos with file count + head SHA.
- **Doctrines card.** All doctrines with confidence chip + updated date.
- **Urgent open card.** P0/P1 open tickets sorted by priority. Click row → opens ticket detail sheet.

---

## Kanban

- Five columns: Backlog, Todo, In Progress, In Review, Done. Column header shows a colored status dot + count badge.
- Cards sorted by priority within column (P0 top). Card content: priority chip, blocker warning if applicable, ticket ID, title, labels (up to 3), estimate in hours, assignee.
- Drag-drop between columns. Every drop:
  1. Calls `bridge.moveTicket(id, from, to)`.
  2. Helper writes a new `StatusChange` node + `TRANSITIONED` edge (so history is preserved).
  3. Helper updates `Ticket.status` and `Ticket.updated`.
  4. `AppState.refresh()` reloads tickets.
- Column drop-zone highlights accent color while a card hovers.
- Card hover: subtle accent glow + shadow lift. Click card → opens **ticket detail sheet**.

---

## Tickets (table view)

Row-per-ticket table:
- Filter pills top: All / per status.
- Search box top-right: matches title, id, or assignee (case-insensitive).
- Columns: ID (mono), Title, Status (dot + label), Priority chip, Est (hours), Assignee, Updated (short date).
- Row hover shades. Click → opens ticket detail sheet.
- Sort: priority rank ascending, then status alphabetical.

---

## Sprints

Single card view of the current sprint:
- Status dot (red if ≤3d left).
- Progress bar computed from `elapsed / total` between `start_date` and `end_date`.
- Stat tiles: Total tickets, Done, In Progress, Blocked (has blockers text), P0/P1 open.
- Empty state instructs `⇧⌘V` to paste a new sprint.

---

## Projects

Groups all tickets by their `project` field (`—` for un-projected). Each group is a card with:
- Folder icon + project key.
- Ticket count.
- Status dots: Done / In Progress / Backlog counts inline.

Reads from `Ticket.project` in memory (populated by the paste-sprint intake or agent's `add_ticket`).

---

## Digest

Full-page editor for today's daily-standup Slack draft.
- Header actions: Regenerate, Copy to Clipboard.
- Draft is auto-generated at 1:45 PM (see Scheduler), then auto-copied at 2:00 PM.
- Persisted in `ui_state.json` across restarts so it survives quit.
- **How the draft is built** (in `DigestService`):
  1. Query `bridge.statusChangesSince(startOfYesterday)` — every kanban move in the last 24h.
  2. Split into **yesterday** and **today** buckets by timestamp.
  3. `doneYesterday` = transitions to Done in the yesterday bucket.
  4. `doingToday` = current In Progress + Todo, top 5 by priority.
  5. Compose raw markdown-ish text with `*Yesterday*` and `*Today*` sections.
  6. Call plain (non-agent) `claude -p` with the raw text, asking Claude to polish into ≤12 bullets. Fallback: raw text if polish fails.
- 2 PM auto-copy: `AppState.copyDigestNow()` writes to `NSPasteboard.general` and posts a "Digest copied" system notification.

---

## Ticket detail (sheet modal)

Opens over the app when you click a ticket anywhere.

Header row: priority chip, ID, `Expand graph` button, `Copy as Linear` button, `Save` button.

Four tabs:

### 11.1 Fields
- Priority picker, estimate, assignee.
- Description (`TextEditor`).
- **Suggest linked files** button (top): saves ticket, then dispatches a chat prompt that includes the ticket description + up to 600 indexed file paths and asks Claude to propose `link_ticket_file` actions with `note` on each. Answers appear as a proposal panel in the chat pane.
- Sections: Description, Results, Blockers (tinted orange), Verification, Notes (private — excluded from Slack digest), Time Log (monospaced), Labels chips.

### 11.2 Linked
Reads `bridge.ticketLinked(id)` and renders:
- **Repos.** Row per linked repo: green dot if head SHA matches snapshot, amber `HEAD moved` chip if repo advanced past `linked_head_sha`. Click row → focuses that Repo in the Graph explorer.
- **Files.** Row per linked file: language chip, file's current git_sha vs `linked_git_sha`. If they differ → red `File moved: linked abc1234 → current def5678` badge. Note (if agent attached one) + last commit date. Click row → focuses File in Graph.
- **Doctrines.** Row per linked doctrine: confidence chip, title, content preview, source. Click → focuses Doctrine in Graph.

### 11.3 Comments
- Comment composer with `Attach files…` (multi-select NSOpenPanel).
- Attachments are copied into `~/Library/Application Support/Cadence/attachments/<ticket_id>/<timestamp>_<filename>`. Their absolute path is stored in `Attachment.path` and linked via `HAS_ATTACHMENT_C`.
- Existing comments list, author + created date + body.

### 11.4 History
Reads `bridge.ticketHistory(id)`:
- All `StatusChange` events: `from → to · at`.
- All `PriorityChange` events: `from → to · reason · at`.

### Ticket → Linear export
`Copy as Linear` button formats:
```
Title: …
Priority: Urgent | High | Medium | Low
Estimate: N
Assignee: …
Labels: …

Description:
…

## Results / ## Blockers / ## Verification / ## Notes
```
Priority mapping: P0→Urgent, P1→High, P2/P3→Medium, P4→Low. Placed on clipboard; toast says "Paste into Linear."

### Ticket "Expand graph" button
Sends specialized prompt into chat:
1. `get_ticket` — read full text.
2. `list_functionalities` + `find_functionality` on plausible concepts — must reuse existing before creating.
3. `find_files` + `find_symbols` for keywords.
4. `read_file_head` on top 2–3 candidates to verify.
5. Propose:
   - `add_functionality` for NEW concepts (rich `## Purpose / Key files / Constraints / Related concepts` markdown required).
   - `update_functionality` on any thin (<100 char) existing description.
   - `link_ticket_functionality` (multiple — a ticket can work on N functionalities).
   - `link_file_functionality`, `link_ticket_file`.
   - `link_functionalities` (depends_on / part_of / related_to) when hierarchy or dependency is evident.
Capped at 15 actions, precision over recall. All actions land in the proposal panel for approve.

---

## Settings

Read-only display of the runtime environment:
- Paths: app-support data dir (issues, repos.json, workflows, attachments, digests), claude CLI.
- Schedule: 09:00 morning brief, 13:45 digest draft, 14:00 auto-clipboard, hourly idle scan, hourly deadline scan.
- Keyboard shortcuts: ⇧⌘V paste sprint, ⇧⌘D copy digest, ⌘K palette, ⌘[/⌘] back/forward.

---

## Back/Forward navigation

Top bar chevrons + ⌘[ / ⌘]. AppState maintains `navBack` and `navForward` stacks of `NavHistoryEntry(routeRaw, focusedType?, focusedId?)`. Every route change and every focus change pushes an entry and clears forward. Back pops back and pushes onto forward. Graph-navigation trails (click through node → node → node) are fully rewindable.

---

## Paste Sprint intake (`PasteSprintView`)

⇧⌘V or the toolbar button opens a modal:
- Sprint name (auto: `Sprint N` where N = week/2 + 1).
- Start / end date (auto: current ISO Monday + 13 days).
- Project name + key.
- Big textarea: paste raw sprint tasks in any format (markdown, JSON, plain list, Linear export).
- **Parse with Claude** button: sends non-agent `claude -p` prompt asking to output a JSON array of tickets with all fields. Preview table shows parsed tickets.
- **Commit N tickets** button: creates `Sprint` + `Project` nodes if provided, then for each parsed ticket calls `bridge.addTicket()` which inserts `Ticket` node + `BELONGS_TO` and `IN_SPRINT` edges.

---

## Scheduler + notifications

`Scheduler` runs an in-app `Timer` every 60s while the app is alive:
- **09:00** — `morningBrief`. Refreshes state, computes top-3 open tickets by priority, posts a system notification with sprint days-left in the title.
- **13:45** — `draftPing`. Runs `generateDigestDraft()` (see §9) and posts "Digest draft ready" notif so you can pre-review.
- **14:00** — `copyDigestNow`. Puts today's draft on the clipboard + notif.
- **Hourly idle scan** — queries `bridge.idleTickets(status: "In Progress", days: 2)`, notifies for each result. Also checks current sprint: if `daysLeft ≤ 3` and there are any open P0/P1 tickets, posts an escalation notif with the top 5.

`Scheduler.handle(url:)` catches `cadence://digest`, `cadence://copy`, `cadence://brief` URL-scheme triggers. These are used by an optional `launchd` agent (installed via `Scripts/install-launchd.sh`) so the scheduled fires still happen when the app is closed at those times.

Notifications go through `Notifier` which uses `UNUserNotificationCenter`. First launch prompts macOS permission.

---

## Symbol extraction (during `index_repo`)

Regex-based, language-aware (Python, Swift, TypeScript/JS, Go, Rust). For each supported file:
- Python: `def`, `async def`, `class`.
- Swift: `func`, `class`, `struct`, `enum`, `protocol`, `extension`, `actor` (with visibility modifiers).
- TS/JS: `function`, `class`, `interface`, `type`.
- Go: `func`, `type … struct`, `type … interface`.
- Rust: `fn`, `struct`, `enum`, `trait`.

Every match becomes a `Symbol` node + a `DEFINED_IN` edge to the parent File. Symbols persist through file renames only if you reindex (they are keyed by `(file_id, name, line)` — file rename gives a new `file_id`).

---

## Claude bridge (`ClaudeBridge`)

Wraps three modes of `claude -p` invocation:

1. **`prompt(text)`** — plain single-turn. Used by digest polishing and paste-sprint parsing. No tools.
2. **`promptAgent(userMessage, systemPrompt)`** — MCP agent mode. Flags: `--mcp-config`, `--output-format json`, `--allowedTools mcp__cadence__*`, `--permission-mode bypassPermissions --dangerously-skip-permissions`. Returns final `result` string.
3. **`promptAgentJSONStreaming(userMessage, systemPrompt, onToolUse)`** — same as (2) but `--output-format stream-json`. Parses newline-delimited events, extracts `tool_use` from `assistant` events, invokes `onToolUse(name)` for each. Returns final JSON body. Powers the live status bar.

All three shell out to `/opt/homebrew/bin/claude` which authenticates via OAuth token in your macOS keychain (`Claude Code-credentials`). Uses your Max/Pro subscription usage cap. No `ANTHROPIC_API_KEY` env, no API billing.

---

## Persistence

Everything survives quit + relaunch, as plain files under `~/Library/Application Support/Cadence/`:
- **`issues/<ID>/`** — one folder per ticket (`issue.md` + exploration notes).
- **`repos.json`** — indexed repos.
- **`workflows/<ID>/`** — workflow definitions + `runs/<runID>.json`.
- **`config.json`** — settings.
- **`chats.json`** — conversations, migrating old `chat.json` if found. Written after every chat append.
- **`ui_state.json`** — last selected route + digest draft. Restored in `AppState.init()`.
- **`attachments/<ticket_id>/`** — ticket file attachments.
- **`digests/`** — archived Slack drafts (per day).

---

## Fuzzy-match / dedupe (why Functionality nodes stay canonical)

Every functionality-related agent action goes through the dispatcher's dedupe step:
1. `bridge.findFunctionality(query: name, limit: 3)` — case-insensitive CONTAINS match on `name` and `description`.
2. If a match exists → reuse its id.
3. Only if no match → create a new Functionality with the provided name.

This is why proposing `link_ticket_functionality "worker pool"` won't create a duplicate when "Worker Pool" or "worker-pool" already exists. Same pattern for `link_file_functionality` and `link_functionalities`.

---

## Critique agent

Dashboard `Run Critique` opens a fresh chat and fires a specialized system prompt telling Claude to:
1. Enumerate every ticket via `list_tickets` + `get_ticket`; flag missing fields (verification, results, estimate, linked files) and status-idle >7 days.
2. Enumerate repos via `list_repos`; flag repos with zero incoming `TICKET_TOUCHES_REPO` edges.
3. Enumerate doctrines; flag stale (>60 days since update).
4. Call `stale_ticket_links` — every result is a code-moved-since-link warning.
5. Verify P0/P1 open tickets have file links.
6. Cross-check ticket descriptions for concepts (OOM, worker, cache, etc.) that lack a matching doctrine.

Final reply is structured markdown: Summary / Blockers / Under-specified / Stale knowledge / Coverage gaps / **Suggested new tickets (Linear-paste code blocks, one per ticket)** / Next 3 actions. Every claim must cite a ticket ID or file path retrieved via MCP.

---

## Linear ticket export

Two paths:
- **Per-ticket:** `Copy as Linear` button in ticket detail (see §11). Formats one ticket → clipboard → paste into Linear's issue create.
- **Bulk (via critique):** critique output includes one Linear-paste-ready code block per proposed new ticket. Copy each block, paste into Linear separately (no bulk-CSV yet).

---

## Speech recognition

`SpeechRecognizer` uses `SFSpeechRecognizer` (`en-US`) + `AVAudioEngine`. Mic button in chat pane toggles listening. Live partial transcripts flow into the input field via `onChange(of: speech.transcript)`. First tap prompts two macOS permissions: microphone + speech recognition. Auto-stops on message send.

---

## What Cadence is *not*

- Not multi-user. Single-dev, single-machine. No sync, no server, no auth. Everything is local files.
- Not a Linear replacement — it feeds you Linear-paste output so you can push your day's changes into Linear (or wherever your team tracks).
- Not sandboxed. Reads/writes on disk freely: home dir, indexed repos, attachments. Unsigned/ad-hoc-signed personal build.
- Not API-billed. Uses your Claude Max/Pro subscription via `claude` CLI OAuth. Cost fields in stream-json output are informational, not billed.
- Not real-time collaborative. Sockets are local (Unix domain), no network exposure.

---

## Typical daily loop

1. **09:00** — Morning brief notif fires; app shows top-3 open tickets + days-left.
2. Move cards on kanban as work progresses. Every move logs a `StatusChange`.
3. Something new lands? Chat: `"add ticket X, link to file Y, comment: Z"` → preview → apply.
4. Refactor moves code? Chat: `"reindex ai-on-prem"` → Cadence runs `index_repo`, flags files that shifted git_sha; dashboard stale-links card lights up if any ticket referenced those files.
5. Learned something? Chat: `"save doctrine: NCCL crashes with mps backend on Mac — always fall back to gloo"` → agent proposes `add_doctrine`, links to related repo/file.
6. **13:45** — Digest draft notif fires. Review in Dashboard or Digest route.
7. **14:00** — Auto-clipboard fires. ⌘V into Slack.
8. New sprint arriving? `⇧⌘V` → paste manager's ticket dump → parse → commit. Cadence handles Sprint + Project + Tickets.
9. Weekly: Dashboard → **Run Critique** → workspace review + Linear-ready new tickets.

That's the entire loop, end to end.
