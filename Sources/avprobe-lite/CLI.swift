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
// Design note on exit codes: with `@main AsyncParsableCommand`, ArgumentParser's
// generated entry catches errors escaping `run()` and exits with its OWN code (64 for
// usage, 1 otherwise) — which would defeat the 0/2/5 floor. So we enforce the floor
// inside each run(): every error is caught, printed as the error envelope, and the
// process exits with exactly 2 or 5 via `exit()`. Success exits 0 naturally by returning
// from the AsyncParsableCommand main.
//
// `--json` is accepted for interface compatibility but this build emits JSON
// unconditionally (that is the tool's purpose). Output is deterministic: sorted keys,
// no ANSI, no wall-clock, no hostname/pid.
//
// NOTE for the Mac pass: ArgumentParser validates positional/flag syntax and calls
// `exit(withError:)` itself BEFORE run() if e.g. an unknown flag is passed. That path
// yields ArgumentParser's EX_USAGE (64). If you want malformed syntax mapped to 2 as
// well, replace `@main AsyncParsableCommand` with a hand-rolled `@main` calling
// `parseAsRoot` + `exit(ErrorOut.code(...))` — see MAC_HANDOFF, reconciling-agent flags.
//

import Foundation
import Darwin
import ArgumentParser
import AVFoundation

@main
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
        exit(2)
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
                let capability = await ProcessPath.check()
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
