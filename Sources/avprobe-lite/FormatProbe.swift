//
// FormatProbe.swift
// avprobe-lite
//
// Unit 02 — populate codec, dimensions, frame rate, bitrate, color/HDR, and audio
// properties from real AVAssetTrack / CMFormatDescription reads. No hardcoded guesses.
//
// Everything here is derived from framework reads; anything the OS can't surface is
// `nil` and omitted from the JSON (honest) rather than fabricated.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

public enum FormatProbe {

    // MARK: Video

    /// Probe the first video format description of a track. Only the first description
    /// is used (a track's formatDescriptions can carry multiple for e.g. multi-view;
    /// the primary/codec is index 0).
    public static func probeVideo(track: AVAssetTrack) async -> VideoStream {
        // Load the format descriptions plus the numeric track properties in one call.
        let formatDescriptions: [CMFormatDescription]
        let frameRate: Float
        let estBitRate: Float
        let naturalSize: CGSize
        let timeRange: CMTimeRange

        do {
            (formatDescriptions, frameRate, estBitRate, naturalSize, timeRange) =
                try await track.load(
                    .formatDescriptions, .nominalFrameRate, .estimatedDataRate,
                    .naturalSize, .timeRange)
        } catch {
            // Honest: unknown is not fabricated. Return an empty-but-valid VideoStream
            // carrying the type, rather than inventing codec/resolution.
            return VideoStream(codec: nil, codecFourCC: nil, width: nil, height: nil,
                               fpsNum: nil, fpsDen: nil, sar: nil, dar: nil,
                               pixFmt: nil, colorPrimaries: nil,
                               bitRateBPS: nil, startS: nil, endS: nil)
        }

        guard let fd = formatDescriptions.first else {
            return VideoStream(codec: nil, codecFourCC: nil, width: nil, height: nil,
                               fpsNum: nil, fpsDen: nil, sar: nil, dar: nil,
                               pixFmt: nil, colorPrimaries: nil,
                               bitRateBPS: nominalBits(estBitRate),
                               startS: timeStart(timeRange), endS: timeEnd(timeRange))
        }

        let fourCC = mediaSubTypeString(fd)
        let dims = CMVideoFormatDescriptionGetDimensions(fd)

        // Frame rate as a stable rational. nominalFrameRate is a Float (e.g. 29.97);
        // scale by 1000 and return (num/den) for a deterministic representation.
        let (fpsNum, fpsDen) = fractionFromFloat(frameRate)

        let dar = darString(naturalSize: naturalSize)
        // SAR is not directly exposed via the public CMFormatDescription API on Core
        // Media; deriving it requires digging into private pasp boxes. We prefer an
        // honest `nil` over guessing "1:1". (See MAC_HANDOFF — candidate for refinement.)
        let sar: String? = nil

        return VideoStream(
            codec: codecFamily(fourCC),
            codecFourCC: fourCC,
            width: Int(dims.width),
            height: Int(dims.height),
            fpsNum: fpsNum,
            fpsDen: fpsDen,
            sar: sar,
            dar: dar,
            pixFmt: pixelFormatString(fourCC),
            colorPrimaries: colorPrimariesString(fd),
            bitRateBPS: nominalBits(estBitRate),
            startS: timeStart(timeRange),
            endS: timeEnd(timeRange)
        )
    }

    // MARK: Audio

    public static func probeAudio(track: AVAssetTrack) async -> AudioStream {
        let formatDescriptions: [CMFormatDescription]
        let estBitRate: Float
        let timeRange: CMTimeRange

        do {
            (formatDescriptions, estBitRate, timeRange) =
                try await track.load(.formatDescriptions, .estimatedDataRate, .timeRange)
        } catch {
            return AudioStream(codec: nil, codecFourCC: nil, channels: nil,
                               sampleRate: nil, bitRateBPS: nil, startS: nil, endS: nil)
        }

        guard let fd = formatDescriptions.first else {
            return AudioStream(codec: nil, codecFourCC: nil, channels: nil,
                               sampleRate: nil, bitRateBPS: nominalBits(estBitRate),
                               startS: timeStart(timeRange), endS: timeEnd(timeRange))
        }

        let fourCC = mediaSubTypeString(fd)
        // AudioStreamBasicDescription is the reliable channel + sample-rate source.
        // (CoreMedia's AudioChannelLayout pointer has no numeric member in the
        // current SDK; the ASBD's mChannelsPerFrame governs.)
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)
        let channelCount = asbd.map { Int($0.pointee.mChannelsPerFrame) }
        let sampleRate = asbd.map { Double($0.pointee.mSampleRate) }

        return AudioStream(
            codec: codecFamily(fourCC),
            codecFourCC: fourCC,
            channels: (channelCount ?? 0) > 0 ? channelCount : nil,
            sampleRate: (sampleRate ?? 0) > 0 ? sampleRate : nil,
            bitRateBPS: nominalBits(estBitRate),
            startS: timeStart(timeRange),
            endS: timeEnd(timeRange)
        )
    }

    // MARK: Shared helpers

    /// Nominal bitrate in bits/sec; 0 (unknown) maps to nil so we never emit a fabricated
    /// numeric success—the JSON just omits the field.
    static func nominalBits(_ est: Float) -> Int? {
        let v = Int(est.rounded())
        return v > 0 ? v : nil
    }

    static func timeStart(_ range: CMTimeRange) -> Double? {
        guard range.isValid, range.start.isNumeric else { return nil }
        return CMTimeSeconds.seconds(range.start)
    }

    static func timeEnd(_ range: CMTimeRange) -> Double? {
        guard range.isValid, range.end.isValid, range.end.isNumeric else { return nil }
        return CMTimeSeconds.seconds(range.end)
    }

    /// Reduce a float to (num, den) with a fixed scale for determinism.
    static func fractionFromFloat(_ value: Float) -> (Int?, Int?) {
        guard value.isFinite, value > 0 else { return (nil, nil) }
        let scale = 1000
        let num = Int((Double(value) * Double(scale)).rounded())
        return (num, scale)
    }

    /// Display-aspect-ratio string "W:H" reduced, from naturalSize. Honest: only set when
    /// naturalSize is non-empty and finite.
    static func darString(naturalSize: CGSize) -> String? {
        guard naturalSize != .zero,
              naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.height > 0 else { return nil }
        let reduced = Self.reduceFraction(Int(naturalSize.width), Int(naturalSize.height))
        return "\(reduced.0):\(reduced.1)"
    }

    static func reduceFraction(_ n: Int, _ d: Int) -> (Int, Int) {
        let gcd = Self.gcd(abs(n), abs(d))
        guard gcd > 0 else { return (n, d) }
        return (n / gcd, d / gcd)
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    // MARK: FourCC / extension decoding

    /// `CMFormatDescriptionGetMediaSubType` FourCC as a lossless 4-char string.
    static func mediaSubTypeString(_ fd: CMFormatDescription) -> String? {
        let cc = CMFormatDescriptionGetMediaSubType(fd)
        guard cc != 0 else { return nil }
        return fourCCString(cc)
    }

    static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        // Blank padding byte → omit it (e.g. 'jpeg' prints as "jpeg", not "jpeg\0").
        let printable = bytes.filter { $0 >= 0x20 && $0 < 0x7F }
        return String(decoding: printable, as: UTF8.self)
    }

    /// Human/ffprobe-style codec family name for a FourCC. Falls back to the raw FourCC.
    static func codecFamily(_ fourCC: String?) -> String? {
        guard let f = fourCC else { return nil }
        let u = f.lowercased()
        // Video
        if ["avc1", "avc3", "h264", "x264", "davc"].contains(u) { return "h264" }
        if ["hevc", "hev1", "hvc1", "dvh1", "dhe1"].contains(u) { return "hevc" }
        if u.hasPrefix("ap"), ["ap4h", "apch", "apcn", "apco", "apcs", "apcx", "aprh", "aprn"].contains(u) { return "prores" }
        if ["mp4v", "xvid", "divx", "fmp4"].contains(u) { return "mpeg4video" }
        if ["h263", "s263"].contains(u) { return "h263" }
        if ["vp09", "vp08", "vp8", "vp9"].contains(u) { return u.contains("vp9") || u.contains("09") ? "vp9" : "vp8" }
        if ["av01", "av1"].contains(u) { return "av1" }
        // Audio
        if ["aac", "mp4a", "aach", "aacl"].contains(u) { return "aac" }
        if ["ac-3", "ac3"].contains(u) { return "ac3" }
        if ["ec-3", "eac3"].contains(u) { return "eac3" }
        if ["alac"].contains(u) { return "alac" }
        if ["lpcm", "sowt", "twos", "fl32", "fl64", "in24", "in32"].contains(u) { return "pcm" }
        if ["mp3", ".mp3"].contains(u) { return "mp3" }
        if ["opus", "op01", "opus"].contains(u) { return "opus" }
        return f
    }

    /// Pixel format FourCC for RAW/uncompressed sources only.
    ///
    /// The modern CoreMedia SDK has no public "PixelFormat" format-description
    /// extension key. For a compressed source the decoded pixel format is not knowable
    /// without opening a decoder, so we never guess one. We only report a field for
    /// uncompressed/raw codec types whose FourCC is itself a CoreVideo pixel format
    /// (e.g. `420f`, `2vuy`, `BGRA`) — an honest read, never a fabricated one.
    static func pixelFormatString(_ fourCC: String?) -> String? {
        guard let f = fourCC else { return nil }
        let u = f.uppercased()
        // Uncompressed/raw codec types that also name a CoreVideo pixel format.
        // Everything else (avc1, hvc1, mp4a, …) is compressed → nil (omitted).
        let raw = [
            "420V", "420F", "422Y", "422V", "422F", "444V", "444F",
            "2VUY", "YV12", "NV12", "BGRA", "ARGB", "RGBA", "ABGR",
            "Y420", "Y422", "YUVS",
            "R10K", "R408", "V210", "V308", "V408",
        ]
        guard raw.contains(u) else { return nil }
        return u
    }

    /// Color primaries from the `ColorPrimaries` extension key (e.g. "ITU_R_709_2").
    static func colorPrimariesString(_ fd: CMFormatDescription) -> String? {
        let ext = CMFormatDescriptionGetExtension(
            fd, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries as CFString)
        return ext as? String
    }
}
