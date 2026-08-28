//
// CLI.swift
// avprobe-lite
//
// Unit 05 — the full avprobe-lite CLI with swift-argument-parser. Each subcommand
// resolves its own FILE/count/effect, runs the relevant unit logic, wraps the result in
// the bplate JSON envelope, and enforces the exit-code floor (0/2/5).
//
// Exit-code floor (from the spec):
//   * 0 — success (including an honest, capability-gated unsupported `process` no-op)
//   * 2 — usage / missing input (missing or unreadable file, `frames` on a no-video
//         asset, `process` without FILE or --check)
//   * 5 — contract (asset cannot be opened / core properties cannot be loaded, or a
//         promised schema field is unproducible)
//
// Design note on exit codes: we hand-roll the `@main` entrypoint (rather than letting
// `@main AsyncParsableCommand` synthesize one) so that ArgumentParser's parse-time
// errors (unknown flags, bad subcommand, missing required args — which would otherwise
// exit 64 / EX_USAGE before our run() ever sees them) are mapped down to OUR usage floor
// of 2. The per-command `run()` bodies already enforce the rest of the 0/2/5 floor via
// `Outcome.emit()` + `exit()`. `--help` / `--version` still exit 0 via ArgumentParser's
// public `exit(withError:)` (its own exit code for CleanExit is 0).
//
// `--json` is accepted for interface compatibility but this build emits JSON
// unconditionally (that is the tool's purpose). Output is deterministic: sorted keys,
// no ANSI, no wall-clock, no hostname/pid.
//

import Foundation
import Darwin
import ArgumentParser
import AVFoundation

// Hand-rolled entrypoint: parse once, dispatch, and map ArgumentParser's parse-time
// errors to our usage floor (2) instead of EX_USAGE (64). Help/version stay at 0.
@main
enum AVProbeLiteMain {
    static func main() async {
        do {
            var command = try AVProbeLite.parseAsRoot(Array(CommandLine.arguments.dropFirst()))
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            // Built-in help (`--help`) / version (`--version`) are CleanExit: exit 0.
            if AVProbeLite.exitCode(for: error).rawValue == 0 {
                AVProbeLite.exit(withError: error)
            }
            // Real parse/validation/syntax error → our usage floor 2 (not EX_USAGE 64).
            fputs(Envelope.error(code: 2, message: parseErrorMessage(error)) + "\n", stderr)
            Darwin.exit(2)
        }
    }

    // Re-formats an ArgumentParser parse error into a short, deterministic human string.
    // `String(describing:)` embeds the cause (e.g. `unknownOption(...long("bogus"))`); we
    // strip the internal wrapper noise and keep just the failing option/argument name.
    private static func parseErrorMessage(_ error: Error) -> String {
        let raw = String(describing: error)
        guard let r = raw.range(of: "parserError: ") else { return raw }
        let p = String(raw[r.upperBound...])
            .replacingOccurrences(of: "ArgumentParser.ParserError.", with: "")
        let cleaned = String(p.split(separator: "(").first ?? "")
        switch cleaned {
        case "unknownOption": return "unknown option"
        case "unexpectedExtraValues": return "unexpected argument"
        case "missingValueForOption": return "missing value for option"
        default: return cleaned
        }
    }
}

struct AVProbeLite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "avprobe-lite",
        abstract: "Probe media via Apple's AVFoundation / Core Media / VideoToolbox, "
            + "emitting a versioned JSON schema for agent consumption.",
        version: "1.0.0",
        subcommands: [Info.self, Streams.self, Frames.self, Process.self]
    )

    // No subcommand given → print help and exit with the usage floor (2).
    func run() throws {
        fputs(AVProbeLite.helpMessage(), stderr)
        Darwin.exit(2)
    }

    // MARK: - info

    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Emit source metadata (duration, playable, first video/audio track).")
        @Argument(help: "Path to a media file.") var file: String
        @Flag(name: .long, help: "Accepted for interface-compat; output is always JSON.") var json = false

        @MainActor
        func run() async throws {
            await Outcome.run(
                status: "info",
                body: { try await probeInfo(file: file) }
            ).emit()
        }
    }

    // MARK: - streams

    struct Streams: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List every track with index, type, codec, time range.")
        @Argument(help: "Path to a media file.") var file: String
        @Flag(name: .long, help: "Accepted for interface-compat; output is always JSON.") var json = false

        @MainActor
        func run() async throws {
            await Outcome.run(
                status: "streams",
                body: { try await probeStreams(file: file) }
            ).emit()
        }
    }

    // MARK: - frames

    struct Frames: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Read up to N sample buffers and report PTS/DTS/duration.")
        @Argument(help: "Path to a media file.") var file: String
        @Option(name: .long, help: "Number of samples to read (default \(FrameReader.defaultCount)).") var count: Int?
        @Flag(name: .long, help: "Accepted for interface-compat; output is always JSON.") var json = false

        @MainActor
        func run() async throws {
            await Outcome.run(
                status: "frames",
                body: { try await probeFrames(file: file, count: count) }
            ).emit()
        }
    }

    // MARK: - process

    struct Process: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a media frame through VTFrameProcessor (ML effect) or check capability.")
        @Argument(help: "Path to a media file (optional for --check).") var file: String?
        @Flag(name: .long, help: "Capability-only: no asset decode.") var check = false
        @Option(name: .long, help: "ML effect: denoise | superres | frc.") var effect: ProcessPath.Effect?
        @Flag(name: .long, help: "Accepted for interface-compat; output is always JSON.") var json = false

        @MainActor
        func run() async throws {
            if check {
                let capability = await ProcessPath.check(effect: effect ?? .frc)
                print(Envelope.success(capability))
                return
            }
            guard let file else {
                throw AppError.usage("process requires a FILE, or pass --check for capability-only")
            }
            await Outcome.run(
                status: "process",
                body: { try await probeProcess(file: file, effect: effect ?? .denoise) }
            ).emit()
        }
    }

    // MARK: - probe bodies

    private static func probeInfo(file: String) async throws -> SourceModel {
        let asset = try AssetLoader.open(url: URL(fileURLWithPath: file))
        return try await AssetLoader.loadSource(asset)
    }

    private static func probeStreams(file: String) async throws -> [StreamDescriptor] {
        let asset = try AssetLoader.open(url: URL(fileURLWithPath: file))
        return try await StreamLister.enumerate(asset)
    }

    private static func probeFrames(file: String, count: Int?) async throws -> [FrameSample] {
        let asset = try AssetLoader.open(url: URL(fileURLWithPath: file))
        return try await FrameReader.read(asset, count: count ?? FrameReader.defaultCount)
    }

    private static func probeProcess(file: String, effect: ProcessPath.Effect) async throws -> EffectCapability {
        let asset = try AssetLoader.open(url: URL(fileURLWithPath: file))
        return try await ProcessPath.run(asset: asset, effect: effect)
    }
}

// MARK: - Envelope + exit-code enforcement

/// Runs an async probe body, catches AppError / generic errors, prints the right
/// envelope, and exits with the 0/2/5 code. `.emit()` never returns on the error path.
enum Outcome {
    static func run<T: Encodable>(
        status: String,
        body: @escaping () async throws -> T
    ) async -> Outcome.Box<T> {
        do {
            let value = try await body()
            return Box(value: value, error: nil)
        } catch {
            return Box(value: nil, error: error)
        }
    }
}

extension Outcome {
    struct Box<T> {
        var value: T?
        var error: Error?
    }
}

extension Outcome.Box where T: Encodable {
    /// Print the success envelope, or translate the error → envelope + `exit(code)`.
    func emit() {
        if let error {
            let code = ErrorOut.code(for: error)
            fputs(Envelope.error(code: code, message: ErrorOut.message(for: error)), stderr)
            exit(code)
        }
        if let value {
            print(Envelope.success(value))
            return
        }
        // Neither value nor error — internal invariant violation; treat as contract.
        let code = Int32(5)
        fputs(Envelope.error(code: code, message: "internal: no result produced"), stderr)
        exit(code)
    }
}

/// Map a thrown error to the 0/2/5 exit code. AppError is authoritative; anything else
/// (SDError, reader failure, decode failure) is a contract=5 envelope.
enum ErrorOut {
    static func code(for error: Error) -> Int32 {
        guard let app = error as? AppError else { return 5 }
        return app.exitCode
    }

    static func message(for error: Error) -> String {
        guard let app = error as? AppError else { return String(describing: error) }
        return app.localizedDescription
    }
}
