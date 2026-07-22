import Foundation

/// A repo the user can tag onto a task. Replaces the Kuzu Repo index.
struct RepoNode: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var path: String
    var description: String = ""
    var headSha: String = ""
    var lastIndexed: String = ""
    var fileCount: Int = 0
}

/// Reads/writes AppSupport/repos.json — a flat list of repos. Branches come live from git.
final class RepoRegistry {
    private var url: URL { CadencePaths.reposFile }

    func list() -> [RepoNode] {
        guard let data = try? Data(contentsOf: url),
              let repos = try? JSONDecoder().decode([RepoNode].self, from: data) else { return [] }
        return repos
    }

    private func write(_ repos: [RepoNode]) {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Register a repo folder. id = lowercased folder name. fileCount from git so it isn't "stale".
    @discardableResult
    func add(name: String, path: String) -> RepoNode {
        var repos = list()
        let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let (head, count) = repoStats(clean)
        let node = RepoNode(id: id, name: name, path: clean,
                            headSha: head, lastIndexed: ISO8601DateFormatter().string(from: Date()),
                            fileCount: count)
        repos.removeAll { $0.id == id || $0.path == clean }
        repos.append(node)
        write(repos)
        return node
    }

    func remove(id: String) {
        write(list().filter { $0.id != id })
    }

    /// (current branch, all local branches) via git.
    func branches(repoPath: String) -> (current: String, branches: [String]) {
        let all = git(repoPath, ["branch", "--format=%(refname:short)"])
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let current = git(repoPath, ["rev-parse", "--abbrev-ref", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (current, all)
    }

    private func repoStats(_ path: String) -> (head: String, fileCount: Int) {
        let head = git(path, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let files = git(path, ["ls-files"]).split(separator: "\n").count
        // Ensure non-zero so the repo is selectable even for a fresh/empty repo.
        return (head, max(files, 1))
    }

    private func git(_ repoPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repoPath] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
