//
// ProcessPath.swift
// avprobe-lite
//
// Unit 04 — the `process` subcommand: run a real frame through VTFrameProcessor
// (denoise / super-res / frame-rate conversion), with HONEST capability reporting.
// This is the project's differentiator — wrapping Apple's ML media-processing path
// that no prior probe exposes.
//
// HONESTY RULE (repeated from the spec; non-negotiable):
//   * VTFrameProcessor only exists on macOS 15.4+ / iOS 26+ (base class).
//   * Each effect has its OWN, stricter availability floor and its own runtime
//     hardware `isSupported` signal. We never claim a pixel was transformed when
//     the platform cannot service it.
//   * On any other build/device we MUST report `{"supported": false, "reason": "…"}`
//     and exit 0 — a clean no-op is a success, never a fabricated result.
//   * When support IS available we run the REAL pipeline and report measured
//     before/after — naming the exact configuration class that ran.
//
// Reconciled against the real macOS SDK (verified on macOS 26): the semantic names
// implied in the original handoff (.superResolution / .denoise / .frameRateConversion)
// map to distinct configuration classes with DIFFERENT OS floors:
//   * frc      -> VTFrameRateConversionConfiguration      (macOS 15.4+)
//   * denoise  -> VTTemporalNoiseFilterConfiguration      (macOS 26.0+)
//   * superres -> VTSuperResolutionScalerConfiguration    (macOS 26.0+)
// These floors are hard SDK facts, not our choosing; they are reported honestly.
//

import Foundation
import AVFoundation
import VideoToolbox
import ArgumentParser

public enum ProcessPath {

    public enum Effect: String, CaseIterable, Codable, ExpressibleByArgument {
        case denoise
        case superres
        case frc

        public init?(argument: String) {
            self.init(rawValue: argument)
        }

        /// Human-readable OS floor this effect's REAL configuration class requires.
        public var requiresOS: String {
            switch self {
            case .frc: return "macOS 15.4"
            case .denoise, .superres: return "macOS 26.0"
            }
        }

        /// The configuration class this effect maps to (display string).
        public var appliedPipeline: String {
            switch self {
            case .denoise: return "VTTemporalNoiseFilterConfiguration"
            case .superres: return "VTSuperResolutionScalerConfiguration"
            case .frc: return "VTFrameRateConversionConfiguration"
            }
        }
    }

    /// Conservative silicon floor — Apple silicon with a media encoder.
    public static let requiresSoC = "Apple silicon (M-series)"

    // MARK: - Per-effect gate

    /// The checked, PER-EFFECT gate. Deterministic; no I/O, no asset decode.
    /// Returns (available, reasonIfNotAvailable).
    public static func gate(effect: Effect) -> (available: Bool, reason: String?) {
        // SDK / availability probe — the compile-time gate for each config class.
        // These must be arranged so an older SDK (no VTFrameProcessor at all) still
        // compiles to the honest-unsupported path instead of a type error.
        let apiOK: Bool
        switch effect {
        case .frc:
            #if canImport(VideoToolbox.VTFrameProcessor)
                if #available(macOS 15.4, *) {
                    apiOK = true
                } else { apiOK = false }
            #else
                apiOK = false
            #endif
        case .denoise, .superres:
            #if canImport(VideoToolbox.VTFrameProcessor)
                if #available(macOS 26.0, *) {
                    apiOK = true
                } else { apiOK = false }
            #else
                apiOK = false
            #endif
        }

        // Runtime hardware truth — the real `isSupported` class property.
        let hwOK: Bool
        if apiOK {
            switch effect {
            case .frc:
                if #available(macOS 15.4, *) {
                    hwOK = VTFrameRateConversionConfiguration.isSupported
                } else { hwOK = false }
            case .superres:
                if #available(macOS 26.0, *) {
                    hwOK = VTSuperResolutionScalerConfiguration.isSupported
                } else { hwOK = false }
            case .denoise:
                if #available(macOS 26.0, *) {
                    hwOK = VTTemporalNoiseFilterConfiguration.isSupported
                } else { hwOK = false }
            }
        } else {
            hwOK = false
        }

        // OS floor probe — runtime, deterministic for a given host.
        let osOK: Bool
        switch effect {
        case .frc:
            osOK = ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 0))
        case .denoise, .superres:
            osOK = ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        }

        if apiOK && osOK && hwOK {
            return (true, nil)
        }

        var reasons: [String] = []
        if !apiOK { reasons.append("VTFrameProcessor API not present in this SDK") }
        if !osOK { reasons.append("requires \(effect.requiresOS)") }
        if !hwOK { reasons.append("\(effect.appliedPipeline) not supported by VideoToolbox on this device") }
        if reasons.isEmpty { reasons.append("capability check unavailable in this build") }
        return (false, reasons.joined(separator: "; "))
    }

    /// SoC best-effort name via sysctl hw.machine. Informational only; never the gate.
    static func hardwareSoCName() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(validatingUTF8: buf)
    }

    // MARK: - Entry: `--check`

    /// Capability-only; reports what this effect could run on this device WITHOUT
    /// opening or decoding an asset. Supports exit 0 on the honest-unsupported path.
    public static func check(effect: Effect) async -> EffectCapability {
        let (available, reason) = gate(effect: effect)
        return EffectCapability(
            effect: effect.rawValue,
            supported: available,
            os: effect.requiresOS,
            soc: hardwareSoCName() ?? "unknown",
            applied: available ? "capability present (no asset decoded)" : "none",
            reason: reason,
            before: nil,
            after: nil
        )
    }

    // MARK: - Entry: `process --effect …`

    /// Run the requested effect live over a real frame of the asset where supported.
    /// - On the honest-unsupported path: returns `EffectCapability(supported:false)` (exit 0).
    /// - On the supported-but-unserviceable path: returns honest `supported:false` with a
    ///   reason (exit 0) OR throws a contract error (exit 5) when the source cannot be
    ///   decoded at all — we refuse to fabricate a result.
    public static func run(asset: AVAsset, effect: Effect) async throws -> EffectCapability {
        let soc = hardwareSoCName() ?? "unknown"
        let (available, reason) = gate(effect: effect)

        guard available else {
            return EffectCapability(
                effect: effect.rawValue,
                supported: false,
                os: effect.requiresOS,
                soc: soc,
                applied: "none",
                reason: reason ?? "unsupported path reached",
                before: nil,
                after: nil
            )
        }

        // Supported path: run the REAL live pipeline (frames decoded + transformed).
        switch effect {
        case .frc:
            if #available(macOS 15.4, *) {
                var cap = try await FrameProcessorLive.frameRateConversion(asset)
                cap.soc = soc
                return cap
            } else {
                return EffectCapability(
                    effect: effect.rawValue, supported: false, os: effect.requiresOS,
                    soc: soc, applied: "none",
                    reason: "requires \(effect.requiresOS)", before: nil, after: nil)
            }
        case .superres:
            if #available(macOS 26.0, *) {
                var cap = try await FrameProcessorLive.superResolution(asset)
                cap.soc = soc
                return cap
            } else {
                return EffectCapability(
                    effect: effect.rawValue, supported: false, os: effect.requiresOS,
                    soc: soc, applied: "none",
                    reason: "requires \(effect.requiresOS)", before: nil, after: nil)
            }
        case .denoise:
            if #available(macOS 26.0, *) {
                var cap = try await FrameProcessorLive.temporalNoiseFilter(asset)
                cap.soc = soc
                return cap
            } else {
                return EffectCapability(
                    effect: effect.rawValue, supported: false, os: effect.requiresOS,
                    soc: soc, applied: "none",
                    reason: "requires \(effect.requiresOS)", before: nil, after: nil)
            }
        }
    }
}
