import Foundation

actor ClaudeBridge {
    let binary: String
    init(binary: String = "/opt/homebrew/bin/claude") { self.binary = binary }

    /// Agent mode: `claude -p goal --output-format json`. Native Read/Grep/Glob/Bash(git) only.
    func promptAgent(userMessage: String, systemPrompt: String, timeout: TimeInterval = 300) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = [
            "-p", userMessage,
            "--append-system-prompt", systemPrompt,
            "--output-format", "json",
            "--allowedTools", "Read", "Grep", "Glob",
                              "Bash(git log:*)", "Bash(git show:*)", "Bash(git blame:*)", "Bash(git rev-parse:*)",
            "--permission-mode", "bypassPermissions",
            "--dangerously-skip-permissions",
        ]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline { p.terminate(); throw ClaudeError.timeout }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if p.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? "unknown"
            throw ClaudeError.nonZero(status: p.terminationStatus, stderr: msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.badJSON(String(data: data, encoding: .utf8) ?? "")
        }
        if let isErr = json["is_error"] as? Bool, isErr {
            throw ClaudeError.nonZero(status: -1, stderr: (json["result"] as? String) ?? "unknown agent error")
        }
        return (json["result"] as? String) ?? ""
    }

    /// Agent + JSON: prompts Claude with MCP tools, expects the final message to be JSON
    /// (either {"kind":"reply","text":...} or {"kind":"propose","reply":"...","actions":[...]}).
    func promptAgentJSON(userMessage: String, systemPrompt: String, timeout: TimeInterval = 300) async throws -> Any {
        let raw = try await promptAgent(userMessage: userMessage, systemPrompt: systemPrompt, timeout: timeout)
        let cleaned = Self.extractJSON(from: raw)
        guard let data = cleaned.data(using: .utf8) else { throw ClaudeError.badJSON(raw) }
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw ClaudeError.badJSON(raw) }
    }

    /// Streaming variant. Emits tool_use names via onToolUse as they arrive; returns final JSON body.
    /// `addDirs` grants the agent read access to repo paths + the issues folder so its native
    /// Read/Grep/Glob/Bash tools can explore code and existing issue files.
    func promptAgentJSONStreaming(
        userMessage: String,
        systemPrompt: String,
        onToolUse: @escaping @Sendable (String) async -> Void,
        addDirs: [String] = [],
        timeout: TimeInterval = 300
    ) async throws -> Any {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        var args: [String] = [
            "-p", userMessage,
            "--append-system-prompt", systemPrompt,
            "--output-format", "stream-json",
            "--verbose",
        ]
        for d in addDirs {
            args.append(contentsOf: ["--add-dir", d])
        }
        args.append("--allowedTools")
        args.append(contentsOf: [
            "Read", "Grep", "Glob",
            "Bash(git log:*)", "Bash(git show:*)", "Bash(git blame:*)",
            "Bash(git rev-parse:*)", "Bash(git diff:*)", "Bash(git status:*)",
        ])
        args.append(contentsOf: [
            "--permission-mode", "bypassPermissions",
            "--dangerously-skip-permissions",
        ])
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()

        var finalResult: String?
        var buffer = ""
        let handle = out.fileHandleForReading
        let deadline = Date().addingTimeInterval(timeout)

        while p.isRunning || !buffer.isEmpty {
            if Date() > deadline { p.terminate(); throw ClaudeError.timeout }
            let data = handle.availableData
            if data.isEmpty {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if !p.isRunning { break }
                continue
            }
            if let s = String(data: data, encoding: .utf8) {
                buffer += s
            }
            while let nl = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<nl])
                buffer.removeSubrange(...nl)
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                guard let evtData = line.data(using: .utf8),
                      let evt = try? JSONSerialization.jsonObject(with: evtData) as? [String: Any] else { continue }
                let type = evt["type"] as? String ?? ""
                if type == "assistant", let message = evt["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    for part in content {
                        if (part["type"] as? String) == "tool_use", let name = part["name"] as? String {
                            let clean = name.replacingOccurrences(of: "mcp__cadence__", with: "")
                            await onToolUse(clean)
                        }
                    }
                } else if type == "result" {
                    finalResult = evt["result"] as? String
                    if let isErr = evt["is_error"] as? Bool, isErr {
                        throw ClaudeError.nonZero(status: -1, stderr: finalResult ?? "agent error")
                    }
                }
            }
        }

        _ = err.fileHandleForReading.readDataToEndOfFile()
        guard let raw = finalResult else {
            throw ClaudeError.badJSON("no result event received")
        }
        let cleaned = Self.extractJSON(from: raw)
        guard let data = cleaned.data(using: .utf8) else { throw ClaudeError.badJSON(raw) }
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw ClaudeError.badJSON(raw) }
    }

    /// Plain single-turn (no MCP). Kept for digest polishing + intake parsing.
    func prompt(_ text: String, timeout: TimeInterval = 120) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["-p", text]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline { p.terminate(); throw ClaudeError.timeout }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if p.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? "unknown"
            throw ClaudeError.nonZero(status: p.terminationStatus, stderr: msg)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Prompt with structured JSON output. Instructs claude to return only JSON.
    func promptJSON(_ text: String, timeout: TimeInterval = 120) async throws -> Any {
        let framed = """
        Return ONLY valid JSON. No prose, no code fences, no explanation.

        \(text)
        """
        let raw = try await prompt(framed, timeout: timeout)
        let cleaned = Self.extractJSON(from: raw)
        guard let data = cleaned.data(using: .utf8) else { throw ClaudeError.badJSON(raw) }
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw ClaudeError.badJSON(raw) }
    }

    static func extractJSON(from s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // strip ```json ... ``` or ``` ... ``` fences
        if t.hasPrefix("```") {
            if let start = t.range(of: "\n"), let end = t.range(of: "```", options: .backwards) {
                t = String(t[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // if there's prose before the JSON, take from first { or [ to matching last } or ]
        if !t.hasPrefix("{") && !t.hasPrefix("[") {
            if let firstBrace = t.firstIndex(where: { $0 == "{" || $0 == "[" }) {
                let opener = t[firstBrace]
                let closer: Character = (opener == "{") ? "}" : "]"
                if let lastBrace = t.lastIndex(of: closer) {
                    t = String(t[firstBrace...lastBrace])
                }
            }
        }
        return t
    }
}

enum ClaudeError: Error, LocalizedError {
    case timeout
    case nonZero(status: Int32, stderr: String)
    case badJSON(String)
    var errorDescription: String? {
        switch self {
        case .timeout: return "Claude CLI timed out"
        case .nonZero(let s, let m): return "Claude CLI exit \(s): \(m)"
        case .badJSON(let s): return "Claude returned non-JSON:\n\(s.prefix(500))"
        }
    }
}
