//
// AppError.swift
// avprobe-lite
//
// The error taxonomy and the bplate exit-code floor.
//
//   * 0 — success (including an honest, capability-gated unsupported `process`
//          path: a clean no-op is a success, not a failure).
//   * 2 — usage / missing input (bad subcommand shape, missing or unreadable file).
//   * 5 — contract (a promised schema field could not be produced, or the asset
//          could not be opened at all — i.e. we can't honor the `info --json`
//          contract).
//
// Anything else (decode failure, reader failure) maps to contract=5 because the
// caller asked for a deterministic schema and we cannot deliver it. We never
// silently drop a failed read into a success envelope.
//

import Foundation
import AVFoundation

public enum AppError: Error, LocalizedError {
    /// Missing/invalid input path or a subcommand shape we can't interpret. → exit 2.
    case usage(String)
    /// The asset could not be opened or a promised schema field is unproducible. → exit 5.
    case contract(String)

    public var exitCode: Int32 {
        switch self {
        case .usage: return 2
        case .contract: return 5
        }
    }

    public var errorDescription: String? {
        switch self {
        case .usage(let msg): return msg
        case .contract(let msg): return msg
        }
    }
}

// MARK: - AVFoundation-friendly mapping

enum LoadError {
    /// Wrap an async AVAsset `load` failure into a contract error with the cause name.
    static func contract(_ message: String, cause: Error?) -> AppError {
        let detail = cause.map { ": \(String(describing: $0))" } ?? ""
        return .contract("\(message)\(detail)")
    }
}
