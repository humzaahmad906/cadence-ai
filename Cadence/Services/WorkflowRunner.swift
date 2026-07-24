import Foundation

/// Executes a workflow's blocks in order, threading each block's output into the next block's
/// input. The engine is block-kind agnostic: it asks `WorkflowBlockRegistry` for a handler and
/// runs it. Progress is published by mutating `appState.activeRun` (which views observe) and the
/// run is persisted after every state change. A handler that `awaitsUserAfterRun` (manualReview)
/// pauses the run until `resumeReview` is called.
@MainActor
final class WorkflowRunner {
    unowned let appState: AppState
    private var workflow: Workflow?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: entry points

    /// Build a fresh run for `workflow` and execute from the first block. `initialInput` seeds the
    /// first block's input (e.g. a task title or sprint description). When `navigate` is true the
    /// canvas jumps to the live run view; the digest path passes `false` to stay put.
    func start(workflow: Workflow, initialInput: String = "", navigate: Bool = true) async {
        self.workflow = workflow
        let run = WorkflowRun(workflow: workflow)
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        if navigate { appState.setArtifact(.workflowRun(id: run.id)) }
        await runFrom(0, initialInput: initialInput)
    }

    /// Resume a run paused on a block that awaits the user. On approve, the (optionally edited)
    /// output is carried forward; on reject the run is marked failed.
    func resumeReview(approve: Bool, editedOutput: String?) async {
        guard var run = appState.activeRun, workflow != nil else { return }
        let i = run.currentIndex
        guard i < run.blocks.count, run.blocks[i].status == .awaitingReview else { return }

        if !approve {
            run.blocks[i].status = .skipped
            run.blocks[i].finishedAt = Date()
            run.status = .failed
            run.updatedAt = Date()
            appState.activeRun = run
            appState.workflowStore.saveRun(run)
            appState.addAmbient(AmbientEvent(kind: .info, text: "Workflow run rejected at review.", at: Date(), target: nil))
            return
        }

        if let edited = editedOutput { run.blocks[i].output = edited }
        run.blocks[i].status = .done
        run.blocks[i].finishedAt = Date()
        run.updatedAt = Date()
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        await runFrom(i + 1)
    }

    // MARK: engine

    private func runFrom(_ index: Int, initialInput: String = "") async {
        guard let wf = workflow, var run = appState.activeRun else { return }
        run.status = .running
        run.updatedAt = Date()
        appState.activeRun = run

        var input = index > 0 && index - 1 < run.blocks.count ? run.blocks[index - 1].output : initialInput
        var i = index

        while i < wf.blocks.count {
            let block = wf.blocks[i]
            run.currentIndex = i
            run.blocks[i].status = .running
            run.blocks[i].startedAt = Date()
            run.updatedAt = Date()
            appState.activeRun = run

            let handler = WorkflowBlockRegistry.handler(for: block.kind)
            do {
                let output = try await handler.run(block, context: BlockRunContext(appState: appState, workflow: wf, input: input))
                run.blocks[i].output = output
                run.blocks[i].finishedAt = Date()

                if handler.awaitsUserAfterRun {
                    run.blocks[i].status = .awaitingReview
                    run.status = .awaitingReview
                    run.updatedAt = Date()
                    appState.activeRun = run
                    appState.workflowStore.saveRun(run)
                    return
                }

                run.blocks[i].status = .done
                run.updatedAt = Date()
                appState.activeRun = run
                appState.workflowStore.saveRun(run)
                input = output
            } catch {
                run.blocks[i].status = .failed
                run.blocks[i].error = error.localizedDescription
                run.blocks[i].finishedAt = Date()
                run.status = .failed
                run.updatedAt = Date()
                appState.activeRun = run
                appState.workflowStore.saveRun(run)
                appState.addAmbient(AmbientEvent(kind: .error,
                                                 text: "Workflow '\(wf.name)' failed at '\(block.title)': \(error.localizedDescription)",
                                                 at: Date(), target: nil))
                return
            }
            i += 1
        }

        run.status = .done
        run.updatedAt = Date()
        appState.activeRun = run
        appState.workflowStore.saveRun(run)
        appState.addAmbient(AmbientEvent(kind: .info, text: "Workflow '\(wf.name)' finished.", at: Date(), target: nil))
    }
}
