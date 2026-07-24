# Workflows — composable, block-based automations

Cadence started with one hardcoded pipeline (kickoff → split → wizard). Workflows
generalize that idea: a **workflow** is an ordered list of reusable **blocks**, where each
block's output feeds the next block's input. Everything is file-based and synchronous, in
the same style as `IssueStore` / `RepoRegistry`.

## Where things live

| Concern | File |
| --- | --- |
| Models (`Workflow`, `WorkflowBlock`, `WorkflowBlockConfig`, `WorkflowRun`, `ViewerTarget`, templates) | `Cadence/Models/Workflow.swift` |
| Block handlers + registry (`WorkflowBlockHandler`, `WorkflowBlockRegistry`, `AgentBlockKit`, all handlers) | `Cadence/Services/WorkflowBlocks.swift` |
| Persistence (CRUD + runs) | `Cadence/Services/WorkflowStore.swift` |
| Path helper (`workflowsDir`) | `Cadence/Services/CadencePaths.swift` |
| Engine (kind-agnostic loop) | `Cadence/Services/WorkflowRunner.swift` |
| Shared wizard agents (`descriptionAgent`, `solutionAgent`) | `Cadence/AppState.swift` |
| Canvas routing | `Cadence/Models/CanvasArtifact.swift` (`.workflows`, `.workflowBuilder(id:)`, `.workflowRun(id:)`) + `Cadence/Views/CanvasHost.swift` |
| UI | `Cadence/Views/WorkflowsListView.swift`, `WorkflowBuilderView.swift`, `WorkflowRunView.swift` |
| Wiring / state | `Cadence/AppState.swift` (`workflowStore`, `runner`, `workflows`, `activeRun`, and the create/save/run/resumeReview/delete methods) |

## Architecture: pluggable blocks

Blocks are **extensible**. The engine (`WorkflowRunner`) never switches over block kinds — it asks
`WorkflowBlockRegistry` for a `WorkflowBlockHandler` and runs it:

```swift
@MainActor protocol WorkflowBlockHandler {
    var awaitsUserAfterRun: Bool { get }   // default false; true = pause for the user (manualReview)
    func run(_ block: WorkflowBlock, context: BlockRunContext) async throws -> String
}
```

`BlockRunContext` carries the `appState`, the `workflow`, and the previous block's `input`. A handler
returns the string that becomes the next block's input.

Several kinds are deliberately **thin presets of the generic agent block**. `AgentBlockKit.runAgent`
centralizes the `ClaudeBridge.promptAgentJSONStreaming` call (with `--add-dir` repo + issues scoping,
tool-status streaming, and the optional `{"output": …}` envelope). `agentPrompt`, `docQA`, and
`repoReport` all route through it with different preset system prompts. `createDescription` /
`createSolution` reuse the wizard's `AppState.descriptionAgent` / `solutionAgent` **verbatim**, so the
wizard and workflows can never drift apart.

## On disk

```
~/Library/Application Support/Cadence/workflows/
└── <workflowID>/
    ├── workflow.json          # the Workflow definition
    └── runs/
        └── <runID>.json       # one WorkflowRun per execution
```

JSON is pretty-printed with ISO-8601 dates.

## Block kinds

Generic building blocks:

| Kind | What it does | Key config |
| --- | --- | --- |
| `agentPrompt` | Runs the Claude agent over the workflow's scoped repos (`--add-dir`) plus the issues folder, capturing its output. | `systemPrompt`, `promptTemplate`, `expectJSON` |
| `createTickets` | Parses the previous block's JSON (`{"tickets":[…]}`, also tolerates `tasks`/`drafts`) and saves each as a ticket via `AgentDispatcher`/`IssueStore`. IDs follow the wizard's `PREFIX-N` scheme. | `defaultPriority`, `defaultStatus` |
| `manualReview` | Pauses the run (`awaitingReview`) and hands the incoming payload to the user to approve, edit, or reject. | `reviewInstructions` |
| `summarize` | Folds the running output into markdown via `ClaudeBridge.prompt`. Optionally persists the result as the daily digest. | `heading`, `promptTemplate`, `persistAsDigest` |

Wizard-reuse blocks (share the wizard's agents exactly):

| Kind | What it does | Key config |
| --- | --- | --- |
| `createDescription` | Wizard description writer: turns the incoming task title into a grounded `# title` + description. | — |
| `createSolution` | Wizard solution designer: turns the incoming description into an implementation plan (appends a `## Solution`). | — |

Display + inspection blocks:

| Kind | What it does | Key config |
| --- | --- | --- |
| `viewer` | Read-only render of a target — `previousOutput`, a `ticket`, a `repoSummary`, or a `doc` file. Never mutates. | `viewerTarget`, `ticketId`, `docPath` |
| `docQA` | Agent preset: answers a question about the incoming doc (and/or a doc path) with repo access, citing sources. | `question`, `docPath` |
| `repoReport` | Agent preset: summarizes repo activity (commits, branches, churn) via `git log/show/diff/blame`. | `sinceRef` |

Prompt templates support two placeholders: `{{input}}` (previous block's output) and
`{{repos}}` (a description of the scoped repos).

`agentPrompt` always speaks JSON on the wire. When `expectJSON` is false the agent is asked
for a `{"output": "..."}` envelope and only the string is carried forward; when true the raw
JSON is passed on verbatim (so a following `createTickets` block can consume it).

## Adding a new block kind

It's a small, localized change in three places:

1. **Model** — add a `case` to `WorkflowBlockKind` (Models/Workflow.swift) and fill in its
   `label` / `icon` / `blurb`. Add any config fields to `WorkflowBlockConfig`.
2. **Handler** — add a `struct MyHandler: WorkflowBlockHandler` in `Services/WorkflowBlocks.swift`
   and one line in `WorkflowBlockRegistry.handler(for:)`. If it's an agent, call
   `AgentBlockKit.runAgent(...)` with your preset prompt. Set `awaitsUserAfterRun = true` if it
   should pause for the user.
3. **Builder UI** — add a `case` to the config editor `switch` in `WorkflowBuilderView`.

The engine, list/run views, and persistence need no changes — they're kind-agnostic.

## Built-in templates

Seeded on first launch (and offered under **New from template**):

- **Sprint Kickoff** — `agentPrompt` (split a sprint description into atomic tasks) →
  `manualReview` → `createTickets`. A composed re-imagining of the built-in kickoff→split→wizard
  pipeline; it complements, and does not replace, the dedicated wizard flow.
- **Task Spec (Description → Solution)** — `createDescription` → `createSolution` →
  `manualReview`. Showcases the wizard-reuse chain: a task title becomes a grounded description,
  which feeds the solution designer, then pauses for review.
- **Daily Digest** — `agentPrompt` (review recent ticket activity) → `summarize`
  (`persistAsDigest = true`). This replaces the old digest stub: `AppState.generateDigestDraft()`
  now runs this workflow, and the summarize block persists through `AppState.persistDigest`, so
  the Digest canvas and `⌘⇧D` / `cadence://digest` all produce a real digest.
- **Bug Triage** — `agentPrompt` (scan a repo for bugs) → `createTickets`.
- **Repo Report** — a single `repoReport` block summarizing recent repo activity via git.

## Using it

1. Open **Workflows** from the canvas header button.
2. **New from template** (or **Blank workflow**) to create one → opens the builder.
3. In the builder: edit name/summary, toggle scoped repos, add/reorder/delete blocks, and edit
   each block's config. **Save**, or **Save & run**.
4. **Run** streams live per-block progress in the run view. When a `manualReview` block is
   reached the run pauses; edit the payload if needed and **Approve & continue** (or **Reject**).

## Engine notes

- `WorkflowRunner` is `@MainActor`; it mutates `AppState.activeRun` after every state change and
  persists the run via `WorkflowStore.saveRun`, so views update reactively.
- A failed block marks the run `failed` and surfaces an ambient error event.
- Agent blocks reuse `AppState.agentStart/agentToolCalled/agentStop`, so the existing streaming
  tool-call status UI works during workflow runs.
