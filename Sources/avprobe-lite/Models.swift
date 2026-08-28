//
// Models.swift
// avprobe-lite
//
// The versioned JSON schema types. This is the "stable, add-only" contract that
// agent consumers (e.g. smart-abr-ladder) parse deterministically.
//
// FIELD POLICY (add-only):
//   * Never rename or remove an emitted key.
//   * Never change the semantic/unit of an emitted key (durationS stays seconds).
//   * New capabilities are added as NEW optional keys; old consumers must keep parsing.
//   * schemaVersion is the only counter; bump it by 1 on any non-additive shape change
//     (effectively: on a breaking change — which is disallowed anyway).
//
// Some fields are nullable / omitted (never fabricated). A field the OS could not
// read is `nil` and is dropped by the JSON encoder's omitEmpty policy, rather than
// guessed. Components aggregate optional fragments into one model so the JSON is
// flat exactly as the consumer expects.
//

import Foundation
import CoreMedia
import CoreVideo

/// Version of the emitted JSON schema. Stable, add-only contract.
public enum Schema {
    public static let version = 1
}

// MARK: - Source model (top-level `data` for `info --json`)

public struct SourceModel: Codable {
    public var schemaVersion: Int
    public var durationS: Double
    public var playable: Bool
    public var video: VideoStream?
    public var audio: AudioStream?
}

public struct VideoStream: Codable {
    /// Human-readable codec family name (e.g. "h264"). Derivable from the FourCC.
    public var codec: String?
    /// Raw `CMFormatDescriptionGetMediaSubType` FourCC, as a string (e.g. "avc1", "hvc1").
    public var codecFourCC: String?
    public var width: Int?
    public var height: Int?
    /// Frame rate rational — the track's nominalFrameRate (or derimmed) numerator/denominator.
    public var fpsNum: Int?
    public var fpsDen: Int?
    public var sar: String?
    public var dar: String?
    public var pixFmt: String?
    /// HDR/color info described by the format description, when present.
    public var colorPrimaries: String?
    /// Estimated video bitrate in bits/second from the track (0 when unavailable).
    public var bitRateBPS: Int?
    /// Container time range of the track, in seconds.
    public var startS: Double?
    public var endS: Double?
}

public struct AudioStream: Codable {
    /// Human-readable codec family name (e.g. "aac").
    public var codec: String?
    /// Raw format-description subtype FourCC (e.g. "aac", "mp4a").
    public var codecFourCC: String?
    public var channels: Int?
    public var sampleRate: Double?
    /// Estimated audio bitrate in bits/second from the track.
    public var bitRateBPS: Int?
    public var startS: Double?
    public var endS: Double?
}

// MARK: - Streams / frames payloads

/// One stream descriptor entry as emitted by `streams --json`.
public struct StreamDescriptor: Codable {
    /// Stream ordinal in the asset (`i` across any media type).
    public var index: Int
    /// "video", "audio", or the raw `AVMediaCharacteristic`-derived label.
    public var type: String
    public var codec: String?
    public var codecFourCC: String?
    public var width: Int?
    public var height: Int?
    public var fpsNum: Int?
    public var fpsDen: Int?
    /// Container time range, seconds.
    public var startS: Double?
    public var endS: Double?
}

/// One decoded-sample entry as emitted by `frames --json`.
public struct FrameSample: Codable {
    /// Index of the video track this sample came from.
    public var trackIndex: Int
    /// Presentation time stamp, seconds (stable unit).
    public var pts: Double
    /// Decode time stamp, seconds. May equal `pts` for streams without B-frames.
    public var dts: Double?
    /// Sample duration, seconds.
    public var duration: Double
    /// Byte size of the sample buffer.
    public var sizeBytes: Int
}

// MARK: - process / capability payloads

public struct EffectCapability: Codable {
    /// "denoise", "superres", or "frc" — whichever this gate evaluated.
    public var effect: String
    /// Verified support on this device. NEVER fabricated; `false` carries a reason.
    public var supported: Bool
    /// Projected OS (e.g. "macOS 15.4") that gates this capability.
    public var os: String?
    /// SoC / hardware note, when the gate depends on silicon.
    public var soc: String?
    /// What actually ran: e.g. "none" when unsupported, "VTFrameProcessor.superResolution" when applied.
    public var applied: String
    /// Honest reason string for the unsupported path (and any no-op).
    public var reason: String?
    /// Before / after stats for the applied effect (present only when an effect ran).
    public var before: EffectStep?
    public var after: EffectStep?
}

public struct EffectStep: Codable {
    public var frameCount: Int
    public var width: Int?
    public var height: Int?
    public var averageFrameTimeS: Double?
}

// MARK: - Time helpers

enum CMTimeSeconds {
    /// Convert a CMTime to a whole number of seconds (double), guarding against
    /// invalid times. Used so sample timing stays a stable scalar in the JSON.
    static func seconds(_ t: CMTime) -> Double {
        guard t.isNumeric, t.timescale > 0 else { return 0 }
        return Double(t.value) / Double(t.timescale)
    }
}
