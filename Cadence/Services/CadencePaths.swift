import Foundation

enum CadencePaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Cadence")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var attachmentsDir: URL {
        let dir = appSupport.appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var configFile: URL { appSupport.appendingPathComponent("config.json") }
    /// One folder per issue: issues/<ID>/{issue.md, exploration.md, solution-exploration.md}.
    static var issuesDir: URL {
        let dir = appSupport.appendingPathComponent("issues")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    /// Repo registry (replaces the Kuzu repo index).
    static var reposFile: URL { appSupport.appendingPathComponent("repos.json") }
    /// One folder per workflow: workflows/<ID>/{workflow.json, runs/<runID>.json}.
    static var workflowsDir: URL {
        let dir = appSupport.appendingPathComponent("workflows")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var digestArchiveDir: URL {
        let dir = appSupport.appendingPathComponent("digests")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum AttachmentStore {
    /// Copy file into AppSupport/attachments/<ticketId>/ and return absolute path.
    static func persist(url: URL, ticketId: String) -> String {
        let dest = CadencePaths.attachmentsDir.appendingPathComponent(ticketId)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let name = "\(ISO8601DateFormatter().string(from: Date()))_\(url.lastPathComponent)"
        let target = dest.appendingPathComponent(name)
        try? FileManager.default.copyItem(at: url, to: target)
        return target.path
    }
}
