import Foundation

/// Executes a workflow as a DAG: blocks run in topological order of the edges, and each block's
/// inputs are gathered from its incoming edges (port → value). A block with several output ports
/// emits a JSON object whose keys are those ports; a downstream edge picks a key. The engine is
/// block-kind agnostic — it asks `WorkflowBlockRegistry` for a handler. Progress is published by
/// mutating `appState.activeRun` (observed by views) and persisted after every state change. A
/// handler that `awaitsUserAfterRun` (manualReview) pauses until `resumeReview`.
///
/// If a workflow has no edges, a linear chain over its block order is assumed, so older/edge-less
/// workflows still run sensibly.
@MainActor
final class WorkflowRunner {
    unowned let appState: AppState
    private var workflow: Workflow?
    private var order: [UUID] = []      // topological order of block ids
    private var orderIndex = 0          // position in `order` of the currently-running / paused node

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: entry points

    func start(workflow: Workflow, navigate: Bool = true) async {
        self.workflow = workflow
        guard let ord = topoOrder(workflow) else {
            var run = WorkflowRun(workflow: workflow)
            run.status = .failed
            appState.activeRun = run
            appState.workflowStore.saveRun(run)
            appState.addAmbient(AmbientEvent(kind: .error, text: "Workflow has a cycle — can't run.", at: Date(), target: nil))
            if navigate { appState.setArtifact(.workflowRun(id: run.id)) }
            return
        }
        order = ord
        orderIndex = 0
        let run = WorkflowRun(workflow: workflow)
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        if navigate { appState.setArtifact(.workflowRun(id: run.id)) }
        await execute(startAt: 0)
    }

    /// Retry: reset a block and everything after it in topological order, then resume from it.
    func rerun(workflow: Workflow, from blockId: UUID) async {
        self.workflow = workflow
        guard let ord = topoOrder(workflow) else { return }
        order = ord
        guard var run = appState.activeRun, let pos = order.firstIndex(of: blockId) else { return }
        let resetIds = Set(order[pos...])
        for j in run.blocks.indices where resetIds.contains(run.blocks[j].id) {
            run.blocks[j].status = .pending
            run.blocks[j].output = ""
            run.blocks[j].input = ""
            run.blocks[j].error = nil
            run.blocks[j].startedAt = nil
            run.blocks[j].finishedAt = nil
        }
        run.status = .running
        run.updatedAt = Date()
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        await execute(startAt: pos)
    }

    /// Resume a run paused on a review block. Approve carries the (optionally edited) output forward.
    func resumeReview(approve: Bool, editedOutput: String?) async {
        guard var run = appState.activeRun, workflow != nil,
              let ri = run.blocks.firstIndex(where: { $0.status == .awaitingReview }) else { return }
        if !approve {
            run.blocks[ri].status = .skipped
            run.blocks[ri].finishedAt = Date()
            run.status = .failed
            run.updatedAt = Date()
            appState.activeRun = run
            appState.workflowStore.saveRun(run)
            appState.addAmbient(AmbientEvent(kind: .info, text: "Workflow run rejected at review.", at: Date(), target: nil))
            return
        }
        if let edited = editedOutput { run.blocks[ri].output = edited }
        run.blocks[ri].status = .done
        run.blocks[ri].finishedAt = Date()
        run.updatedAt = Date()
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        await execute(startAt: orderIndex + 1)
    }

    // MARK: engine

    private func execute(startAt: Int) async {
        guard let wf = workflow, var run = appState.activeRun else { return }
        run.status = .running
        run.updatedAt = Date()
        appState.activeRun = run

        var idx = startAt
        while idx < order.count {
            let nodeId = order[idx]
            orderIndex = idx
            guard let block = wf.blocks.first(where: { $0.id == nodeId }),
                  let ri = run.blocks.firstIndex(where: { $0.id == nodeId }) else { idx += 1; continue }

            let inputs = gatherInputs(nodeId, wf: wf, run: run)
            let primary = primaryInput(block, inputs)

            run.currentIndex = ri
            run.blocks[ri].status = .running
            run.blocks[ri].input = primary
            run.blocks[ri].startedAt = Date()
            run.updatedAt = Date()
            appState.activeRun = run

            let handler = WorkflowBlockRegistry.handler(for: block.kind)
            do {
                let output = try await handler.run(block, context: BlockRunContext(
                    appState: appState, workflow: wf, input: primary, inputs: inputs))
                run.blocks[ri].output = output
                run.blocks[ri].finishedAt = Date()

                if handler.awaitsUserAfterRun {
                    run.blocks[ri].status = .awaitingReview
                    run.status = .awaitingReview
                    run.updatedAt = Date()
                    appState.activeRun = run
                    appState.workflowStore.saveRun(run)
                    return
                }
                run.blocks[ri].status = .done
                run.updatedAt = Date()
                appState.activeRun = run
                appState.workflowStore.saveRun(run)
            } catch {
                run.blocks[ri].status = .failed
                run.blocks[ri].error = error.localizedDescription
                run.blocks[ri].finishedAt = Date()
                run.status = .failed
                run.updatedAt = Date()
                appState.activeRun = run
                appState.workflowStore.saveRun(run)
                appState.addAmbient(AmbientEvent(kind: .error,
                    text: "Workflow '\(wf.name)' failed at '\(block.title)': \(error.localizedDescription)",
                    at: Date(), target: nil))
                return
            }
            idx += 1
        }

        run.status = .done
        run.updatedAt = Date()
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        appState.addAmbient(AmbientEvent(kind: .info, text: "Workflow '\(wf.name)' finished.", at: Date(), target: nil))
    }

    // MARK: graph helpers

    /// Edges to run by: explicit edges, or a linear chain over block order when none are wired.
    private func effectiveEdges(_ wf: Workflow) -> [WorkflowEdge] {
        if !wf.edges.isEmpty { return wf.edges }
        let ids = wf.blocks.map { $0.id }
        return (0..<max(0, ids.count - 1)).map { WorkflowEdge(from: ids[$0], to: ids[$0 + 1]) }
    }

    /// Kahn topological sort; nil if the graph has a cycle.
    private func topoOrder(_ wf: Workflow) -> [UUID]? {
        let ids = wf.blocks.map { $0.id }
        let idSet = Set(ids)
        var indeg = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        var adj: [UUID: [UUID]] = [:]
        for e in effectiveEdges(wf) where idSet.contains(e.from) && idSet.contains(e.to) {
            adj[e.from, default: []].append(e.to)
            indeg[e.to, default: 0] += 1
        }
        var queue = ids.filter { indeg[$0] == 0 }   // block order → stable
        var order: [UUID] = []
        while !queue.isEmpty {
            let n = queue.removeFirst()
            order.append(n)
            for m in adj[n, default: []] {
                indeg[m, default: 0] -= 1
                if indeg[m] == 0 { queue.append(m) }
            }
        }
        return order.count == ids.count ? order : nil
    }

    /// Gather a node's named inputs from its incoming edges (fan-in to one port is concatenated).
    private func gatherInputs(_ nodeId: UUID, wf: Workflow, run: WorkflowRun) -> [String: String] {
        guard let block = wf.blocks.first(where: { $0.id == nodeId }) else { return [:] }
        var inputs: [String: String] = [:]
        for e in effectiveEdges(wf) where e.to == nodeId {
            guard let srcBlock = wf.blocks.first(where: { $0.id == e.from }),
                  let srcRun = run.blocks.first(where: { $0.id == e.from }) else { continue }
            let value = resolveOutput(srcRun.output, port: e.fromPort, sourceBlock: srcBlock)
            let key = e.toPort.isEmpty ? (block.inputPorts.first ?? "input") : e.toPort
            if let existing = inputs[key], !existing.isEmpty {
                inputs[key] = existing + "\n" + value
            } else {
                inputs[key] = value
            }
        }
        return inputs
    }

    /// The value for a specific output port. Single/default output → the whole string; otherwise the
    /// source is expected to emit a JSON object and we pluck `port` out of it.
    private func resolveOutput(_ output: String, port: String, sourceBlock: WorkflowBlock) -> String {
        let ports = sourceBlock.outputPorts
        guard ports.count > 1, !port.isEmpty else { return output }
        if let data = ClaudeBridge.extractJSON(from: output).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = obj[port] {
            if let s = v as? String { return s }
            if JSONSerialization.isValidJSONObject(v),
               let d = try? JSONSerialization.data(withJSONObject: v),
               let s = String(data: d, encoding: .utf8) { return s }
            return "\(v)"
        }
        return output
    }

    private func primaryInput(_ block: WorkflowBlock, _ inputs: [String: String]) -> String {
        if let first = block.inputPorts.first, let v = inputs[first] { return v }
        return inputs.values.first ?? ""
    }
}
