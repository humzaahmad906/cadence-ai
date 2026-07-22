# Cadence — Application Flow (chat-first)

How Cadence should *work* as a single conversational surface. The eight routes go away as places you navigate to; they become things the agent surfaces inside one flow. All the machinery in `FUNCTIONALITY.md` stays — Kuzu graph, MCP agent, propose/approve, stale detection, digest, dedupe — but it runs in the background and appears only when a step needs it.

> Scope: this is the *flow*, not a UI/CSS spec. It answers "what happens, in what order, and where does it show up."

---

## 0. The reframe (one paragraph)

Today Cadence is a dashboard with a chat pane bolted on: eight routes you click between, each showing a slice of the same graph. That's the clutter. Flip it. Cadence becomes **one conversation** with an **adaptive canvas** beside it. You talk (or dump, or dictate); the agent reasons over the graph *and reads repo files on the fly*; whatever it produces — a ticket draft, the board, a risk summary, a sub-graph — renders on the canvas for you to read and edit; nothing is written until you approve it. Kanban, dashboard, graph explorer, and digest stop being destinations and become **views the canvas can take** when the moment calls for them.

---

## 1. Layout model — decision

**Chosen: Chat + adaptive canvas.** (You asked R&D to decide; here's the call and why.)

A persistent conversation rail on the left drives everything. To its right, a single canvas renders the one artifact relevant to the current step — a ticket draft, the kanban board, a sprint-status card, a focused sub-graph, the digest. The canvas is where structured work is *read and edited*; the chat is where intent and reasoning live.

Why this over the alternatives:

| Option | Verdict | Reason |
|---|---|---|
| **Chat only** (everything as inline messages) | Rejected | Recreates the clutter as an infinite scroll. Editing a ticket's Linear headings inside a chat bubble is painful, and yesterday's board scrolls out of reach. |
| **Chat + collapsible panels** | Rejected | Keeps the eight-route baggage, just hidden. You'd still be managing panels instead of a flow. |
| **Chat + adaptive canvas** | **Chosen** | The 2026 consensus shape (ChatGPT Canvas, Claude Artifacts, Notion AI, Lovable). One conversation, one focused work surface that morphs to the task. Chat stays present but the canvas holds the structured thing. Ideal for exactly your case: iterative creation + editing of structured objects (tickets) with approve-in-place. |

The canvas is *singular and adaptive* — not a grid of panels. At any moment it's showing one thing, chosen by the conversation. Back/forward (⌘[ / ⌘]) walks the canvas history, so the graph-node trail you already have keeps working.

---

## 2. Screen anatomy — three zones

1. **Conversation rail (left, persistent).** The primary input. Text + speech-to-text (your existing `SFSpeechRecognizer`). This *is* the command palette — natural language replaces ⌘K. Multi-conversation dropdown stays (each sprint problem is a thread). Live under the composer: the **step ribbon** — a compact "planning → reading files → drafting → waiting for you" progress line replacing today's raw tool-call spinner.
2. **Adaptive canvas (center/right, dominant).** Renders the current artifact. Takes one of a small set of *views* (see §5). Editable in place where it matters (ticket drafts). This is where kanban, sprint status, graph, and digest now live — summoned, not navigated to.
3. **Ambient strip (thin, top or bottom).** Where background services speak up: "3 files moved since you linked them," "digest draft ready," "TICK-14 idle 2 days." Non-modal, dismissible, click to pull the detail onto the canvas. This absorbs the dashboard's stale-links card, the scheduler notifications, and the recent-activity feed.

---

## 3. The core loop

Every interaction follows the same rhythm — this is the whole app in six beats:

1. **Intent.** You say/type/dump something ("plan this sprint," "where do I stand," "what touches the worker pool," "add a ticket for the OOM fix").
2. **Plan.** The agent decides what to do and shows it in the step ribbon. Multi-step work gets a visible plan; trivial reads don't.
3. **Reason.** ReAct loop over MCP: lists tickets, queries the graph, `find_files`/`find_symbols`, **and reads file contents on the fly** (not just the index) when it needs to understand code. Each step streams into the ribbon.
4. **Render.** The result lands on the canvas in the right view — a draft, a board, a status card, a sub-graph.
5. **Gate (only for writes).** If the agent wants to change the graph, the canvas shows an editable proposal and pauses. Reads never gate; writes always do (§4).
6. **Commit + settle.** You approve (optionally after editing); `AgentDispatcher` writes to Kuzu; the canvas and ambient strip update. Failures show inline as `✗ … — <error>`, successes as `✓ …`, exactly as today.

Memory: the last N turns still ride along on every `claude -p` call, so the thread stays coherent even though the CLI is stateless.

---

## 4. Signature flow A — dump → repo-aware ticket drafts → approve

This is the flow you most want. It's the reason for the redesign.

**You:** paste or dictate a raw dump — "this sprint: fix the NCCL crash on mac, add retry to the uploader, the graph explorer is slow with >500 nodes, and we need auth on the helper socket" — then name the repos it should think with: "use ai-on-prem and cadence."

**Agent, in the step ribbon, visibly:**
1. **Scopes the repos.** Confirms `ai-on-prem` and `cadence` are indexed; if stale or missing, offers to (re)index first (that's its own approve-gated action).
2. **Splits the dump** into candidate work items — here, four.
3. **Reasons per item, reading files on the fly.** For "NCCL crash on mac" it `find_symbols`/`find_files` for nccl/backend, **opens the actual files** to see how the backend is selected, checks existing `Doctrine` nodes (finds your "fall back to gloo" lesson), checks existing `Functionality` nodes so it reuses "Distributed Backend Selection" instead of inventing a duplicate.
4. **Drafts each ticket in full Linear shape** — title, priority, estimate, labels, `## Description / ## Results / ## Blockers / ## Verification`, plus proposed links: `link_ticket_file` to the real files it read (with a note on each), `link_ticket_functionality`, and a `BLOCKS` edge if it inferred a dependency.

**Canvas:** renders the drafts as a **review stack** — one editable ticket card per item. Each card shows the delta clearly: what will be created, which files it links, why (the evidence it read). Every field is editable in place. Additive links pre-checked; anything destructive unchecked and red.

**Gate:** nothing is written yet. You read a draft, fix the estimate, delete a wrong file link, tweak the description, then **Approve** (⌘⏎). Approve commits *that ticket* as one unit; the stack advances to the next. You can approve all, approve some, or reject and redirect ("no, split the uploader one into two").

Key point that honors your rule: **the ticket, with your Linear headings and description, is always previewed and editable before it's added.** The agent does the heavy thinking (reading repos, drafting, linking); you stay the gate.

---

## 5. Signature flow B — "where do I stand?" (understanding the sprint)

You said understanding the sprint is the weaker half. Today that's spread across Dashboard + Sprints + Kanban + the stale-links card. In the new flow it's **one intent** that composes them onto the canvas.

**You:** "where do I stand?" (or it's the default canvas view on launch).

**Canvas renders a single sprint-status view**, assembled from the graph:
- Days left + progress (from `currentSprint`), tinted at ≤5d / ≤3d.
- The five KPIs (open, done, blocked, urgent-open) as a compact header.
- **Risk first**, not buried: blocked tickets, P0/P1 open, idle >2 days, and stale file links (`linked_git_sha ≠ File.git_sha`) — the things that actually threaten the sprint, surfaced together with the offending IDs.
- A **"what to do next"** line the agent computes, not just raw counts ("TICK-14 is your only P0 open and it's blocked on TICK-9 — unblock that first").

From here, natural follow-ups keep the canvas morphing: "show the board" → canvas becomes the **kanban view** (drag-drop still writes a `StatusChange`); "why is TICK-14 blocked?" → canvas becomes a **focused sub-graph** around that ticket; "what changed since yesterday?" → recent-activity timeline. You never navigate to a route; you ask, and the canvas takes the right shape.

---

## 6. Intent → surface map (the eight routes, dissolved)

Every current route survives as a *capability*, reachable by intent instead of a nav click:

| Today's route | Becomes | Triggered by |
|---|---|---|
| Dashboard | Sprint-status canvas view (§5) + ambient strip | "where do I stand," launch default |
| Sprints | Folded into sprint-status view | same as above |
| Kanban | Canvas board view (drag-drop intact) | "show the board," "move TICK-9 to review" |
| Tickets table | Canvas list view (filter/search) | "list open P1s," "find the uploader ticket" |
| Projects | A filter facet on the list view, not a place | "show ai-on-prem tickets" |
| Graph explorer | Canvas sub-graph view, focused on a node on demand | "what touches the worker pool," "expand TICK-14" |
| Digest | Background auto-draft → approve-to-copy card in ambient strip | 1:45 PM auto, or "draft my standup" |
| Settings | A command that prints the runtime table onto canvas | "show settings/paths" |
| Command palette (⌘K) | The chat composer itself | just type |

Nothing is lost. The surface area shrinks to *one canvas that adapts*, which is the decluttering you asked for.

---

## 7. The approval model (kept, sharpened)

You want to approve everything that gets added. Correct instinct — the R&D backs "propose-then-commit, gate before the side effect." The failure mode to avoid is **approval fatigue**: if the agent asks about six micro-actions per ticket, you stop reading and rubber-stamp. So keep approve-everything but change the *grain*:

- **Approve meaningful units, not micro-actions.** One ticket draft (with its fields + links) = one approval, not six checkboxes for add_ticket / link_file / link_functionality / comment. Related edges ride with their ticket.
- **Show the delta, not the mechanism.** Each proposal states plainly what changes and cites the evidence the agent read (file paths, symbol names, existing IDs). No fabricated claims — same rule the critique agent already follows.
- **Edit-in-place before commit** (Review-or-Correct). You can change any field on the draft; you're approving the corrected version, not just yes/no.
- **Gate strictly before the write.** MCP stays read-only; all writes go through `AgentDispatcher`. Approval is recorded *before* the Kuzu mutation, never after.
- **Destructive stays loud.** `delete_ticket` and priority downgrades render red and unchecked, as today.

Net: you still approve every write, but each approval is high-signal and worth reading.

---

## 8. What runs in the background (silent unless it matters)

These never occupy a route; they work quietly and speak only through the ambient strip:

- **Indexer.** `index_repo` / `reindex_repo` run on request or on a schedule; on completion, if files moved git_sha, the strip notes affected tickets.
- **Stale detection.** Continuous check of `TICKET_TOUCHES_FILE` edges; surfaces as a strip notice + inside sprint-status risk.
- **Scheduler.** 09:00 brief, 13:45 digest draft, 14:00 copy, hourly idle/deadline scans — all become ambient strip events, not notifications you manage. (launchd path stays for when the app is closed.)
- **Dedupe.** Functionality fuzzy-match runs invisibly at dispatch; you only see the result (reused vs. new) on the draft.
- **Digest composition.** Auto-drafts in the background; appears as an "approve to copy" card, honoring the approve-everything rule even for the Slack paste.

---

## 9. Design principles (so it stays decluttered)

1. **One conversation, one canvas.** Never more than one primary work surface at a time. If you're tempted to add a panel, make it a canvas view instead.
2. **Progressive disclosure.** First view shows essentials (the draft, the risk, the delta); detail (full attribute tables, edge counts, tool traces) lives behind expanders. Don't show 50 fields when 5 matter.
3. **Intent over navigation.** Anything you used to click to, you now ask for. The composer is the only entry point.
4. **Read-first, write-gated.** The agent reads freely (graph + live file contents); every write pauses for you.
5. **Ambient, not interruptive.** Background services inform; they don't block or nag.
6. **Evidence or it didn't happen.** Every proposed change cites the ID/path/file it's based on. No fabrication.

---

## 10. Open questions for you

Answer these and I can turn this into a build-ordered spec:

1. **Launch default** — should the canvas open on the sprint-status view (§5), or on the last conversation you had?
2. **Canvas persistence** — when you switch conversations, should the canvas follow the thread, or stay on whatever you last looked at?
3. **Batch approve** — for a multi-ticket dump, do you want per-ticket approval (safer, more clicks) or an "approve all, I'll spot-check" option with easy undo?
4. **Auto-reindex** — when you name repos in a dump, should stale repos reindex automatically (still gated) or only when you ask?
5. **Kanban drag** — keep drag-drop as a canvas view, or is moving tickets by chat command enough that the board is read-only?
6. **Digest** — still a core daily thing you want, or is it clutter now that standups may not need it?
