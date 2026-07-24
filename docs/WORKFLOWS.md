# Workflows — node-based flow builder

Cadence workflows are **automations you assemble on a canvas**: blocks are nodes, and you wire a
node's **output port** to another's **input port**. A workflow is a directed graph (DAG); the engine
runs the blocks in topological order, passing each block's output along the edges to the next
block's named inputs. Everything is file-based and synchronous, in the same style as `IssueStore` /
`RepoRegistry`.

You build in **Build** mode and run/inspect in **Debug** mode; an **AI builder** can assemble a whole
graph from a plain-language prompt.

## Where things live

| Concern | File |
| --- | --- |
| Model — `Workflow`, `WorkflowBlock`, `WorkflowBlockConfig`, `WorkflowEdge`, `WorkflowRun`, `BlockRunState`, block kinds, templates | `Cadence/Models/Workflow.swift` |
| Block presentation — `BlockCategory`, `WorkflowBlockKind.category/accent/tag/subtitle` | `Cadence/Views/BlockStyle.swift` |
| Block handlers + registry (`WorkflowBlockHandler`, `WorkflowBlockRegistry`, `AgentBlockKit`) | `Cadence/Services/WorkflowBlocks.swift` |
| Code execution (subprocess, streamed, cancelable) | `Cadence/Services/CodeRunner.swift` |
| Persistence (workflows + runs) | `Cadence/Services/WorkflowStore.swift` |
| **DAG engine** (topo order, input gathering, cycle detection, resume/re-run) | `Cadence/Services/WorkflowRunner.swift` |
| Shell (top bar, rails, right-panel states, run gating) | `Cadence/Views/WorkflowBuilderView.swift` |
| Canvas (grid, nodes, ports, bezier edges, pan/zoom, status, context menu) | `Cadence/Views/WorkflowCanvasView.swift` |
| Block palette · Debug panel · AI builder · Markdown render · Trackpad | `Cadence/Views/{BlockPaletteView,DebugPanelView,AIBuilderView,MarkdownText,TrackpadGestures}.swift` |
| Library + run history | `Cadence/Views/WorkflowsListView.swift` |
| Wiring / state (`workflows`, `activeRun`, run/AI/debug/history methods) | `Cadence/AppState.swift` |

## The graph model

- **`Workflow`** = `{ name, summary, blocks: [WorkflowBlock], edges: [WorkflowEdge], repoIds }`.
- **`WorkflowBlock`** = `{ id, kind, title, config }`. `config` also carries the node's canvas
  position (`x`,`y`) and its **named ports** (`inputPorts`, `outputPorts` — empty ⇒ a single default
  `input`/`output`).
- **`WorkflowEdge`** = `{ from, to, fromPort, toPort }` — a directed, port-to-port connection.
- Codable models use **tolerant decoders**, so adding fields never breaks a `workflow.json` written
  by an older build.

### Block kinds

| Kind | Category | Role |
| --- | --- | --- |
| `input` | Trigger | Seeds the run with typed text (prompted at run time if empty). |
| `agentPrompt` | AI | Runs the Claude agent over scoped repos; template reads `{{input}}`, `{{repos}}`, `{{port}}`. |
| `createDescription` / `createSolution` | AI | Reuse the wizard's description / solution agents verbatim. |
| `docQA` / `repoReport` | AI | Agent presets: answer about a doc / summarize git activity. |
| `summarize` | AI | Fold running output into markdown (optionally the daily digest). |
| `createTickets` | Action | Parse JSON `{"tickets":[…]}` and save each as a ticket. |
| `code` | Action | Run a **Python** script (Generate / Validate / Run) — see below. |
| `viewer` | Action | Read-only render of a doc / ticket / repo summary / previous output. |
| `manualReview` | Gate | Pause the run for approve / edit / reject. |

Category drives the node's accent (from the app DS: Trigger→indigo, AI→purple, Action→green,
Gate→amber) and shape (data-ish kinds render as a parallelogram, the rest as rounded rects).

### Ports, edges & data flow

- Add named ports to any block in the inspector's **Ports** section. Agent blocks with several
  inputs read each by name (`{{spec}}`, `{{repoData}}`, …).
- **Multiple outputs = JSON**: a block that declares >1 output port emits a JSON object keyed by
  those names; a downstream edge with `fromPort: "x"` plucks `x` out of it.
- **Code blocks**: a single input arrives as raw stdin; multiple named inputs arrive as a JSON
  object on stdin. Multiple outputs = print JSON.
- **Fan-in** to one port concatenates; **fan-out** is just several edges from one output.
- A workflow with no edges falls back to a **linear chain** over block order, so older workflows
  still run.

## The engine (`WorkflowRunner`)

- **Topological order** (Kahn) of the edges; a **cycle** fails the run up front.
- For each node it gathers inputs from incoming edges into `[port: value]`, resolving each source's
  output by `fromPort`, then runs the handler with `BlockRunContext.input` (primary) + `.inputs`.
- **Input gating**: pressing Run scans for `input` blocks with empty text; a sheet collects them and
  the run is blocked until they're filled.
- `manualReview` **pauses** (`awaitingReview`); approve/edit/reject resumes from the next node.
- **Re-run from a node** resets that node + everything after it in topo order and resumes — the retry
  path for a failed block.
- Progress is published on `appState.activeRun` and persisted after every state change.

## On disk

```
~/Library/Application Support/Cadence/workflows/
└── <workflowID>/
    ├── workflow.json          # definition (blocks, edges, positions, ports)
    └── runs/
        └── <runID>.json       # one WorkflowRun per execution — per-block status, input, output, timings
```

## Using it

1. Open **Workflows** → **New from template** / **Blank** (or **AI builder** to generate a graph from a
   prompt) → opens the builder.
2. **Build** mode: add blocks from the left palette; drag nodes to arrange; click an **output port**
   then an **input port** to wire an edge (hover an edge for its × to delete). Click a node to
   configure it in the right inspector (model, effort, repo access, ports, and kind-specific
   settings). Trackpad: **pinch to zoom**, **two-finger scroll to pan**; or use the zoom cluster.
3. **Run** (top bar): fills any empty inputs, then executes. Nodes light up — spinner while running,
   **green ✓ when done**, red ✗ on failure, amber ✋ when paused for review.
4. **Debug** mode: the right panel shows the live run — an I/O card (input/output JSON) + a run log
   with per-block timings, plus approve/reject when a review block pauses.
5. **Right-click a node** for **Configure**, **View output** (renders markdown / images), or
   **Re-run from here**.
6. **History**: each card in the Workflows list has a **History** menu of past runs; open one to
   inspect its per-block outputs.

### The `code` block

A deterministic Python step (not an agent): `Services/CodeRunner.swift` runs it as a subprocess.

- **Generate** — the agent writes the script from your intent + input/output description.
- **Validate** — the agent checks the pasted code against that contract (no execution).
- **Run** — executes once on the sample stdin, streaming output, cancelable.
- One configurable interpreter (default `python3`; an absolute path runs a venv directly). No
  package manager — a missing import fails the block with the real error. If the script prints an
  image-file path, a downstream `viewer` renders the image.

## Adding a new block kind

Still a small, localized change:
1. **Model** — add a case to `WorkflowBlockKind` (label/icon/blurb) and any config fields (with a
   line in `WorkflowBlockConfig`'s tolerant decoder). Map it to a `BlockCategory` in `BlockStyle.swift`.
2. **Handler** — add a `WorkflowBlockHandler` + one line in `WorkflowBlockRegistry.handler(for:)`.
   Agent-backed kinds call `AgentBlockKit.runAgent(...)`; set `awaitsUserAfterRun = true` to pause.
3. **Builder UI** — add a config editor case in `WorkflowBuilderView`'s `BlockEditor`.

The engine, canvas, palette, and persistence are kind-agnostic — they need no changes.
