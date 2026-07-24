import Foundation

/// Runs a code block's script as a subprocess, off the main actor, streaming stdout as it arrives.
/// Python-first, but any interpreter path works. The app is unsandboxed and the user authors/OKs
/// the code, matching the `bypassPermissions` posture the agent already runs under.
///
/// stdin  = the previous block's output (or the sample input for a standalone Run)
/// stdout = this block's output (carried into the next block)
/// A non-zero exit is surfaced to the caller, which fails the block.
actor CodeRunner {
    static let shared = CodeRunner()

    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Write `code` to a temp file, run `<interpreter> <file>`, feed `stdin`, and stream stdout via
    /// `onOutput`. Honors task cancellation (terminates the process) and a wall-clock `timeout`.
    func run(interpreter: String,
             code: String,
             stdin: String,
             workingDirectory: String?,
             timeout: TimeInterval = 300,
             onOutput: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> Result {

        let interp = interpreter.trimmingCharacters(in: .whitespaces).isEmpty ? "python3" : interpreter

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-code-\(UUID().uuidString).py")
        try (code.data(using: .utf8) ?? Data()).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let p = Process()
        // Absolute interpreter path runs directly; a bare name goes through /usr/bin/env so it
        // resolves on PATH (a GUI app's PATH is minimal, but system python3 lives in /usr/bin).
        if interp.hasPrefix("/") {
            p.executableURL = URL(fileURLWithPath: interp)
            p.arguments = [scriptURL.path]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [interp, scriptURL.path]
        }
        if let wd = workingDirectory, !wd.isEmpty {
            p.currentDirectoryURL = URL(fileURLWithPath: wd)
        }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = inPipe

        try p.run()

        // Feed stdin, then close so scripts that read to EOF proceed.
        if let data = stdin.data(using: .utf8), !data.isEmpty {
            try? inPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inPipe.fileHandleForWriting.close()

        var stdoutBuffer = ""
        let handle = outPipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(timeout)

        while p.isRunning {
            if Task.isCancelled { p.terminate(); throw CancellationError() }
            if Date() > deadline { p.terminate(); throw CodeRunError.timeout }
            let data = handle.availableData
            if data.isEmpty {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            if let s = String(data: data, encoding: .utf8) {
                stdoutBuffer += s
                await onOutput(s)
            }
        }
        // Drain anything buffered after exit.
        let rest = handle.readDataToEndOfFile()
        if !rest.isEmpty, let s = String(data: rest, encoding: .utf8) {
            stdoutBuffer += s
            await onOutput(s)
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return Result(stdout: stdoutBuffer, stderr: stderr, exitCode: p.terminationStatus)
    }
}

enum CodeRunError: Error, LocalizedError {
    case timeout
    case nonZero(exit: Int32, stderr: String)
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Code block timed out"
        case .nonZero(let exit, let stderr):
            return "Script exited \(exit):\n\(stderr.isEmpty ? "(no stderr)" : String(stderr.prefix(1000)))"
        }
    }
}
