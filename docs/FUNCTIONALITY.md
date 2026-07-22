# Cadence — Functional Overview

What each part of Cadence *does*. No UI/CSS talk. Just the mechanics behind every panel and feature.

---

## 1. What Cadence is (in one paragraph)

A personal sprint dashboard for a single dev on a 2-week Linear-style cadence. Every ticket, code change, and finding lives in one Kuzu graph on disk. An MCP-driven Claude ReAct agent reads that graph to help you plan, expand tickets, index repos, and draft daily standup updates — always with human preview/approve before mutations. Data survives quit/relaunch. No external cloud DB, no API-key billing (uses your Claude subscription CLI).

---

## 2. Core concepts (the nouns)

These are the node types stored in Kuzu. Everything else in the app is a view onto them.

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

## 3. The chat pane (`AgentChatView`) — the primary surface

Persistent 400px column on the left side of the window. Always visible. Not a modal.

### What it does
- Multi-conversation. Header dropdown lists every conversation with relative "updated" time; you can delete conversations from there, or start a new one with the `+` button. First user message auto-becomes the conversation title.
- Speech-to-text mic (SFSpeechRecognizer + AVAudioEngine). Tap mic → transcript streams into the input field live. First tap prompts macOS permission for mic + speech recognition.
- **Every user message goes through the ReAct agent flow (not one-shot):**
  1. Cadence builds a system prompt naming every available MCP tool and every action kind the agent can propose.
  2. Cadence invokes `claude -p <user-msg> --mcp-config Helpers/mcp_config.json --output-format stream-json --allowedTools mcp__cadence__*` — passing your Claude Max/Pro OAuth token via keychain; no API-key billing.
  3. Claude runs a ReAct loop: `thought → tool_use → observe → thought → …` for up to N turns. It can call any exposed MCP tool: `list_tickets`, `get_ticket`, `find_files`, `find_symbols`, `read_file_head`, `graph_around`, `find_functionality`, etc.
  4. Cadence parses stream-json events in real time — every `tool_use` fires an update in the live status bar under the header showing which tool is running now, total call count, elapsed time. This is the streaming spinner.
  5. Claude's final message must be JSON: either `{"kind":"reply","text":"…"}` (info answer) or `{"kind":"propose","reply":"…","actions":[…]}` (mutation proposal).
- **Preview panel.** When Claude proposes actions, the pane grows a proposal panel (max 320px tall) between conversation and composer. Every action is a checkbox row with a plain-English summary. Additive actions are pre-selected; destructive actions (only `delete_ticket` today) start unchecked and are tinted red. Bottom row: `Reject` and `Apply N` (gradient primary button, ⌘⏎ shortcut). Apply routes each action through `AgentDispatcher` which performs the graph write and refreshes app state; failures produce `✗ <summary> — <error>` in chat, successes produce `✓ <summary>`.
- Persistent history: chat is saved to `chats.json` after every append (capped at last 500 entries per conversation). Loaded in `AppState.init()`.
- Full conversation history is passed to Claude on every turn (last 20 turns as `CONVERSATION SO FAR`) so it has memory across turns even though `claude -p` is stateless.

### Actions the agent can propose (the mutation vocabulary)
Grouped, all previewed and approved:

**Tickets:**
- `add_ticket {id, title, priority, status, estimate, assignee, labels[], project, sprint, description}`
- `update_ticket {id, fields}`
- `move_ticket {id, to_status}`
- `reprioritize {id, to_priority, reason}`
- `add_comment {ticket_id, body}`
- `add_project`, `add_sprint`, `delete_ticket` (destructive)

**Code graph:**
- `index_repo {path, name?, excludes?}` — indexer walks `git ls-files`, hashes files, extracts symbols
- `reindex_repo {repo_id}` — re-runs indexer, flags files whose git_sha advanced
- `link_ticket_repo`, `link_ticket_file {ticket_id, file_query, note}` — file_query is resolved via `find_files` at dispatch time
- `add_doctrine {title, content, confidence, source, tags, repo_id?, file_id?, ticket_id?}`

**Functionality graph (canonical concept namespace):**
- `add_functionality {name, description}` — description is required rich markdown (`## Purpose`, `## Key files`, `## Constraints`, `## Related concepts`)
- `update_functionality {name, new_name?, description?}` — enrich existing thin descriptions
- `link_ticket_functionality {ticket_id, functionality_name, note}` — dispatcher fuzzy-matches existing (case-insensitive CONTAINS) before creating, kills duplicates
- `link_file_functionality {file_query, functionality_name}` — resolves both sides
- `link_functionalities {from_name, to_name, kind, note}` — `kind ∈ {depends_on, part_of, related_to}` for hierarchy + dependency graph

---

## 4. Dashboard

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

## 5. Kanban

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

## 6. Tickets (table view)

Row-per-ticket table:
- Filter pills top: All / per status.
- Search box top-right: matches title, id, or assignee (case-insensitive).
- Columns: ID (mono), Title, Status (dot + label), Priority chip, Est (hours), Assignee, Updated (short date).
- Row hover shades. Click → opens ticket detail sheet.
- Sort: priority rank ascending, then status alphabetical.

---

## 7. Sprints

Single card view of the current sprint:
- Status dot (red if ≤3d left).
- Progress bar computed from `elapsed / total` between `start_date` and `end_date`.
- Stat tiles: Total tickets, Done, In Progress, Blocked (has blockers text), P0/P1 open.
- Empty state instructs `⇧⌘V` to paste a new sprint.

---

## 8. Projects

Groups all tickets by their `project` field (`—` for un-projected). Each group is a card with:
- Folder icon + project key.
- Ticket count.
- Status dots: Done / In Progress / Backlog counts inline.

Reads from `Ticket.project` in memory (populated by the paste-sprint intake or agent's `add_ticket`).

---

## 9. Digest

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

## 10. Graph explorer (`GraphExplorerView` + `ForceGraphCanvas`)

Three-column route for exploring the knowledge graph directly.

- **Left index (260px).** Lists every Repo, Ticket, Doctrine in the DB. Click row → focus that node.
- **Center canvas.** Force-directed physics graph:
  - Focus node at center (pinned, large, glowing).
  - 1-hop neighbors radiate outward (Repo → File edges, Ticket → File edges, Ticket → Functionality edges, Functionality → Functionality edges, etc.).
  - Physics loop @ 40 FPS: Coulomb-like repulsion between all node pairs (`k_rep = 22000, F = k/d²`), Hookean spring attraction along edges (rest length 130), 0.008× center gravity, 0.86 damping. Cooling factor drops to 0.6 after 200 iterations so layout settles.
  - **Drag a node** → pins it (📌 badge). Position freezes; physics keeps flowing around it.
  - **Double-click a node** → unpins.
  - **Drag empty background** → pan.
  - **Pinch / scroll** → zoom (0.3× to 3×). Zoom controls bottom-right also expose +/−/reset.
  - **Filter chips** top: colored per node type. Click a chip to hide that type; empty selection = show all.
  - **Click a neighbor** → re-centers on it and pushes onto nav history so ⌘[ backs out.
- **Right detail panel (320px).**
  - Node type chip, label, id.
  - For Ticket nodes: two buttons — `Open detail` (reopens ticket sheet) and `Expand w/ context` (fires an agent prompt to expand the ticket via MCP).
  - Attribute table: every field of the node from Kuzu.
  - Edge counts: `EDGE_NAME:direction → N`, so you can see e.g. `TICKET_WORKS_ON:in → 12` = 12 tickets touch this functionality.

Colors are shared with the `.typeColor` map: Ticket=indigo, File=green, Repo=amber, Doctrine=purple, Functionality=violet, Symbol=grey.

---

## 11. Ticket detail (sheet modal)

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

## 12. Settings

Read-only display of the runtime environment:
- Paths: Kuzu DB, attachments dir, digest archive dir, kuzu_helper.py, claude CLI.
- Schedule: 09:00 morning brief, 13:45 digest draft, 14:00 auto-clipboard, hourly idle scan, hourly deadline scan.
- Keyboard shortcuts: ⇧⌘V paste sprint, ⇧⌘D copy digest, ⌘K palette, ⌘[/⌘] back/forward.

---

## 13. Command palette (⌘K)

Overlay with three sections:
- **Navigate.** One entry per route (Dashboard / Kanban / Tickets / Sprints / Projects / Digest / Graph / Settings).
- **Actions.** Paste Sprint, Generate Digest, Copy Digest, Refresh.
- **Tickets.** Up to 20 filtered by title/id.

Filter box on top. Enter runs first match. ESC or backdrop-click closes. Global ⌘K binding via a hidden `NSViewRepresentable` that intercepts the key equivalent.

---

## 14. Back/Forward navigation

Top bar chevrons + ⌘[ / ⌘]. AppState maintains `navBack` and `navForward` stacks of `NavHistoryEntry(routeRaw, focusedType?, focusedId?)`. Every route change and every focus change pushes an entry and clears forward. Back pops back and pushes onto forward. Graph-navigation trails (click through node → node → node) are fully rewindable.

---

## 15. Paste Sprint intake (`PasteSprintView`)

⇧⌘V or the toolbar button opens a modal:
- Sprint name (auto: `Sprint N` where N = week/2 + 1).
- Start / end date (auto: current ISO Monday + 13 days).
- Project name + key.
- Big textarea: paste raw sprint tasks in any format (markdown, JSON, plain list, Linear export).
- **Parse with Claude** button: sends non-agent `claude -p` prompt asking to output a JSON array of tickets with all fields. Preview table shows parsed tickets.
- **Commit N tickets** button: creates `Sprint` + `Project` nodes if provided, then for each parsed ticket calls `bridge.addTicket()` which inserts `Ticket` node + `BELONGS_TO` and `IN_SPRINT` edges.

---

## 16. Scheduler + notifications

`Scheduler` runs an in-app `Timer` every 60s while the app is alive:
- **09:00** — `morningBrief`. Refreshes state, computes top-3 open tickets by priority, posts a system notification with sprint days-left in the title.
- **13:45** — `draftPing`. Runs `generateDigestDraft()` (see §9) and posts "Digest draft ready" notif so you can pre-review.
- **14:00** — `copyDigestNow`. Puts today's draft on the clipboard + notif.
- **Hourly idle scan** — queries `bridge.idleTickets(status: "In Progress", days: 2)`, notifies for each result. Also checks current sprint: if `daysLeft ≤ 3` and there are any open P0/P1 tickets, posts an escalation notif with the top 5.

`Scheduler.handle(url:)` catches `cadence://digest`, `cadence://copy`, `cadence://brief` URL-scheme triggers. These are used by an optional `launchd` agent (installed via `Scripts/install-launchd.sh`) so the scheduled fires still happen when the app is closed at those times.

Notifications go through `Notifier` which uses `UNUserNotificationCenter`. First launch prompts macOS permission.

---

## 17. Kuzu graph storage (`Helpers/kuzu_helper.py`)

Long-running Python subprocess owned by the Swift `KuzuBridge`. On startup it:
1. Opens `~/Library/Application Support/Cadence/graph.kuzu` with a `kuzu.Database`.
2. Runs `CREATE NODE TABLE IF NOT EXISTS …` / `CREATE REL TABLE IF NOT EXISTS …` for every schema entity. Additive — never destructive.
3. Starts a **Unix socket server** at `~/Library/Application Support/Cadence/helper.sock` on a background thread, guarded by a threading lock that serializes with the stdin protocol.
4. Reads newline-delimited JSON commands on stdin, executes them against Kuzu inside the same lock, writes JSON responses. This is what the Swift app uses.

Ops it exposes (`handle(op, args)`):
- CRUD: `add_project`, `add_sprint`, `add_ticket`, `update_ticket`, `move_ticket`, `reprioritize`, `add_comment`, `add_attachment`.
- Queries: `list_tickets`, `get_ticket`, `status_changes_since`, `idle_tickets`, `current_sprint`, `ticket_history`.
- Repo: `add_repo`, `index_repo` (walks git, hashes files, extracts symbols via language-specific regex), `list_repos`, `repo_files`, `find_files`.
- Links: `link_ticket_repo`, `link_ticket_file`, `ticket_linked`, `stale_ticket_links`.
- Doctrines: `add_doctrine`, `list_doctrines`.
- Graph traversal: `graph_around(type, id)` — returns focus node + 1-hop neighbors (capped 40 per edge kind) + totals.
- Symbols: `find_symbols`, `list_symbols_for_file`.
- Functionalities: `add_functionality`, `update_functionality`, `find_functionality` (case-insensitive fuzzy), `list_functionalities`, `link_ticket_functionality`, `link_file_functionality`, `link_symbol_functionality`, `link_functionalities`, `get_functionality` (returns node + every incoming/outgoing edge).

**Stale detection.** When you link a ticket to a file, we snapshot `File.git_sha` into the edge as `linked_git_sha`. `stale_ticket_links` returns every edge where the current `File.git_sha` differs. Dashboard surfaces these; ticket detail's Linked tab renders per-file warnings.

---

## 18. Symbol extraction (during `index_repo`)

Regex-based, language-aware (Python, Swift, TypeScript/JS, Go, Rust). For each supported file:
- Python: `def`, `async def`, `class`.
- Swift: `func`, `class`, `struct`, `enum`, `protocol`, `extension`, `actor` (with visibility modifiers).
- TS/JS: `function`, `class`, `interface`, `type`.
- Go: `func`, `type … struct`, `type … interface`.
- Rust: `fn`, `struct`, `enum`, `trait`.

Every match becomes a `Symbol` node + a `DEFINED_IN` edge to the parent File. Symbols persist through file renames only if you reindex (they are keyed by `(file_id, name, line)` — file rename gives a new `file_id`).

---

## 19. Claude bridge (`ClaudeBridge`)

Wraps three modes of `claude -p` invocation:

1. **`prompt(text)`** — plain single-turn. Used by digest polishing and paste-sprint parsing. No tools.
2. **`promptAgent(userMessage, systemPrompt)`** — MCP agent mode. Flags: `--mcp-config`, `--output-format json`, `--allowedTools mcp__cadence__*`, `--permission-mode bypassPermissions --dangerously-skip-permissions`. Returns final `result` string.
3. **`promptAgentJSONStreaming(userMessage, systemPrompt, onToolUse)`** — same as (2) but `--output-format stream-json`. Parses newline-delimited events, extracts `tool_use` from `assistant` events, invokes `onToolUse(name)` for each. Returns final JSON body. Powers the live status bar.

All three shell out to `/opt/homebrew/bin/claude` which authenticates via OAuth token in your macOS keychain (`Claude Code-credentials`). Uses your Max/Pro subscription usage cap. No `ANTHROPIC_API_KEY` env, no API billing.

---

## 20. MCP server (`Helpers/cadence_mcp.py`)

Spawned by `claude` when agent mode runs. Read-only. Talks to `kuzu_helper.py` via the Unix socket (`helper.sock`). Exposes these tools to Claude:

- `list_tickets`, `get_ticket`, `ticket_linked`, `ticket_history`
- `list_repos`, `repo_files`, `find_files`, `read_file_head`
- `graph_around`, `list_doctrines`
- `current_sprint`, `stale_ticket_links`
- `find_symbols`, `list_symbols_for_file`
- `list_functionalities`, `find_functionality`, `get_functionality`

Why read-only: writes always go through Swift's `AgentDispatcher` so the propose/approve invariant is never bypassed. Claude can research iteratively but must return proposed mutations as the final message.

---

## 21. Persistence

Everything survives quit + relaunch:
- **`~/Library/Application Support/Cadence/graph.kuzu`** — the full graph (all node/edge state).
- **`chats.json`** — conversations, migrating old `chat.json` if found. Written after every chat append.
- **`ui_state.json`** — last selected route + digest draft. Restored in `AppState.init()`.
- **`attachments/<ticket_id>/`** — ticket file attachments.
- **`digests/`** — archived Slack drafts (per day).
- **`helper.sock`** — recreated every launch by kuzu_helper.

---

## 22. Fuzzy-match / dedupe (why Functionality nodes stay canonical)

Every functionality-related agent action goes through the dispatcher's dedupe step:
1. `bridge.findFunctionality(query: name, limit: 3)` — case-insensitive CONTAINS match on `name` and `description`.
2. If a match exists → reuse its id.
3. Only if no match → create a new Functionality with the provided name.

This is why proposing `link_ticket_functionality "worker pool"` won't create a duplicate when "Worker Pool" or "worker-pool" already exists. Same pattern for `link_file_functionality` and `link_functionalities`.

---

## 23. Critique agent

Dashboard `Run Critique` opens a fresh chat and fires a specialized system prompt telling Claude to:
1. Enumerate every ticket via `list_tickets` + `get_ticket`; flag missing fields (verification, results, estimate, linked files) and status-idle >7 days.
2. Enumerate repos via `list_repos`; flag repos with zero incoming `TICKET_TOUCHES_REPO` edges.
3. Enumerate doctrines; flag stale (>60 days since update).
4. Call `stale_ticket_links` — every result is a code-moved-since-link warning.
5. Verify P0/P1 open tickets have file links.
6. Cross-check ticket descriptions for concepts (OOM, worker, cache, etc.) that lack a matching doctrine.

Final reply is structured markdown: Summary / Blockers / Under-specified / Stale knowledge / Coverage gaps / **Suggested new tickets (Linear-paste code blocks, one per ticket)** / Next 3 actions. Every claim must cite a ticket ID or file path retrieved via MCP.

---

## 24. Linear ticket export

Two paths:
- **Per-ticket:** `Copy as Linear` button in ticket detail (see §11). Formats one ticket → clipboard → paste into Linear's issue create.
- **Bulk (via critique):** critique output includes one Linear-paste-ready code block per proposed new ticket. Copy each block, paste into Linear separately (no bulk-CSV yet).

---

## 25. Speech recognition

`SpeechRecognizer` uses `SFSpeechRecognizer` (`en-US`) + `AVAudioEngine`. Mic button in chat pane toggles listening. Live partial transcripts flow into the input field via `onChange(of: speech.transcript)`. First tap prompts two macOS permissions: microphone + speech recognition. Auto-stops on message send.

---

## 26. What Cadence is *not*

- Not multi-user. Single-dev, single-machine. No sync, no server, no auth. Everything is local files.
- Not a Linear replacement — it feeds you Linear-paste output so you can push your day's changes into Linear (or wherever your team tracks).
- Not sandboxed. Reads/writes on disk freely: home dir, indexed repos, attachments. Unsigned/ad-hoc-signed personal build.
- Not API-billed. Uses your Claude Max/Pro subscription via `claude` CLI OAuth. Cost fields in stream-json output are informational, not billed.
- Not real-time collaborative. Sockets are local (Unix domain), no network exposure.

---

## 27. Typical daily loop

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
