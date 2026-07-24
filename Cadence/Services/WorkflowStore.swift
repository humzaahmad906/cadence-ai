import Foundation

/// File-based persistence for workflows + their runs. One folder per workflow under
/// AppSupport/workflows/<ID>/:
///   workflow.json        — the Workflow definition
///   runs/<runID>.json    — one WorkflowRun per execution
/// Pure filesystem, synchronous, atomic writes — mirrors IssueStore / RepoRegistry.
final class WorkflowStore {
    private let fm = FileManager.default

    // ISO-8601 dates so JSON stays human-readable and matches the rest of the app's on-disk style.
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func folder(_ id: String) -> URL {
        CadencePaths.workflowsDir.appendingPathComponent(id)
    }
    private func workflowFile(_ id: String) -> URL {
        folder(id).appendingPathComponent("workflow.json")
    }
    private func runsDir(_ id: String) -> URL {
        folder(id).appendingPathComponent("runs")
    }
    private func ensureFolder(_ id: String) throws {
        try fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
    }

    // MARK: workflows

    /// Scan workflows/*/workflow.json, newest-updated first.
    func list() -> [Workflow] {
        guard let dirs = try? fm.contentsOfDirectory(at: CadencePaths.workflowsDir,
                                                     includingPropertiesForKeys: nil) else { return [] }
        var out: [Workflow] = []
        for dir in dirs {
            let f = dir.appendingPathComponent("workflow.json")
            guard let data = try? Data(contentsOf: f),
                  let wf = try? Self.decoder.decode(Workflow.self, from: data) else { continue }
            out.append(wf)
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(_ id: String) -> Workflow? {
        guard let data = try? Data(contentsOf: workflowFile(id)),
              let wf = try? Self.decoder.decode(Workflow.self, from: data) else { return nil }
        return wf
    }

    func save(_ workflow: Workflow) throws {
        try ensureFolder(workflow.id)
        let data = try Self.encoder.encode(workflow)
        try data.write(to: workflowFile(workflow.id), options: .atomic)
    }

    func delete(_ id: String) throws {
        try fm.removeItem(at: folder(id))
    }

    // MARK: runs

    func runs(workflowId: String) -> [WorkflowRun] {
        guard let files = try? fm.contentsOfDirectory(at: runsDir(workflowId),
                                                      includingPropertiesForKeys: nil) else { return [] }
        var out: [WorkflowRun] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let run = try? Self.decoder.decode(WorkflowRun.self, from: data) else { continue }
            out.append(run)
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    func loadRun(workflowId: String, runId: String) -> WorkflowRun? {
        let url = runsDir(workflowId).appendingPathComponent("\(runId).json")
        guard let data = try? Data(contentsOf: url),
              let run = try? Self.decoder.decode(WorkflowRun.self, from: data) else { return nil }
        return run
    }

    /// Best-effort persistence of a run; called frequently as a run progresses.
    func saveRun(_ run: WorkflowRun) {
        try? fm.createDirectory(at: runsDir(run.workflowId), withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(run) else { return }
        try? data.write(to: runsDir(run.workflowId).appendingPathComponent("\(run.id).json"), options: .atomic)
    }
}
