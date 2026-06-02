import Foundation
import Dispatch
import Alaya
import Vijna
import Manas
import Manovijna

/// `alayad` — the BIOID composition root.
///
/// This file is the *single* place in the repository where the four
/// peer layers (`Vijna`, `Manas`, `Manovijna`, `Alaya`) are referenced
/// by name. Every other module talks to neighbours through `BioidCore`
/// protocols only. Keeping the wiring isolated to the `@main` file is
/// the bootstrap exception: it is the price of layer independence.
///
/// Phase 0 wiring:
///   Sense       — `StdinLineSense` (one `text/plain` Stimulus per line)
///   Bias        — `IdentityManas` (MANAS bypass; explicit, not silent)
///   Substrate   — `FileBackedSubstrate` (NDJSON logs, durable)
///   Cognizer    — selected at boot via `BIOID_COGNIZER`:
///                   `echo` (default) → `EchoCognizer`
///                   `claude`         → `ClaudeCodeCognizer.default()`
///   KarmanGate  — `IdentityManas`
///   Effector    — `StdoutEffector`
///
/// The daemon runs until either:
/// - stdin reaches EOF (`Ctrl-D` from a tty), or
/// - it receives `SIGINT` (`Ctrl-C`) or `SIGTERM`.
///
/// Either path triggers a graceful shutdown: the sense's stream
/// finishes, the control loop exits at the next boundary, and the
/// substrate flushes and closes its log files.
@main
struct AlayaDaemon {

    static func main() async throws {
        let substrateDirectory = try defaultSubstrateDirectory()
        log("substrate at \(substrateDirectory.path)")

        let substrate = try FileBackedSubstrate(directory: substrateDirectory)
        let sense = StdinLineSense()
        let manas = IdentityManas()
        let cognizer: any Cognizer = try selectCognizer()
        let effector = StdoutEffector()

        let signalStream = installShutdownSignals()

        log("ready; reading text/plain lines from stdin")

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await runControlLoop(
                        sense: sense,
                        bias: manas,
                        substrate: substrate,
                        cognizer: cognizer,
                        karmanGate: manas,
                        effector: effector
                    )
                }

                group.addTask {
                    for await signal in signalStream {
                        log("received signal \(signal); shutting down")
                        await sense.shutdown()
                        break
                    }
                }

                try await group.next()
                group.cancelAll()
            }
        } catch {
            log("error: \(error)")
            do {
                try await substrate.close()
            } catch {
                log("close error: \(error)")
            }
            throw error
        }

        try await substrate.close()
        log("stopped")
    }

    /// Pick the cognizer backend based on `BIOID_COGNIZER`. Recognised
    /// values: `echo` (default) and `claude`. Unknown values throw to
    /// surface configuration mistakes loudly rather than silently
    /// falling back.
    private static func selectCognizer() throws -> any Cognizer {
        let raw = ProcessInfo.processInfo
            .environment["BIOID_COGNIZER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? "echo"

        switch raw {
        case "echo":
            log("cognizer=echo")
            return EchoCognizer()
        case "claude", "claudecode", "claude-code":
            log("cognizer=claude (model=sonnet, ephemeral session)")
            return ClaudeCodeCognizer.default()
        default:
            throw CognizerSelectionError.unknownBackend(raw)
        }
    }

    enum CognizerSelectionError: Error, CustomStringConvertible {
        case unknownBackend(String)

        var description: String {
            switch self {
            case .unknownBackend(let value):
                return "BIOID_COGNIZER=\(value) is not recognised. Use 'echo' or 'claude'."
            }
        }
    }

    private static func defaultSubstrateDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("bioid", isDirectory: true)
            .appendingPathComponent("alayad", isDirectory: true)
    }

    private static func installShutdownSignals() -> AsyncStream<Int32> {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        return AsyncStream<Int32> { continuation in
            let queue = DispatchQueue.global()
            let intSource = DispatchSource.makeSignalSource(
                signal: SIGINT,
                queue: queue
            )
            let termSource = DispatchSource.makeSignalSource(
                signal: SIGTERM,
                queue: queue
            )
            intSource.setEventHandler { continuation.yield(SIGINT) }
            termSource.setEventHandler { continuation.yield(SIGTERM) }
            intSource.resume()
            termSource.resume()

            continuation.onTermination = { _ in
                intSource.cancel()
                termSource.cancel()
            }
        }
    }

    private static func log(_ message: String) {
        let line = "alayad: \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
