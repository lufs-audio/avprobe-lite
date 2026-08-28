//
// Frames.swift
// avprobe-lite
//
// Unit 03 — `frames` subcommand: read up to N decoded sample buffers off a video track
// via AVAssetReader + AVAssetReaderTrackOutput, reporting PTS/DTS/duration/size.
//
// Timing is reported as seconds (Double) derived from CMSampleBuffer timing — the stable
// unit the consumer expects, not raw CMTime structs.
//
// NOTE on concurrency: AVAssetReader is a synchronous (not Sendable) API. Swift 5.9's
// default "minimal" strict-concurrency mode tolerates calling it from an async context.
// If the package later enables `SwiftSetting.swiftStrictConcurrency`, the reader setup
// below should move to an `@MainActor` or a dedicated executor — see MAC_HANDOFF.
//

import Foundation
import AVFoundation
import CoreMedia

public enum FrameReader {

    /// How many samples to emit by default when `--count` is omitted.
    public static let defaultCount = 20

    /// Read up to `count` samples from the first video track of an asset.
    ///
    /// - Throws: `.usage` when the asset has no video track (named failure, never an
    ///   empty-success). `.contract` when the reader cannot be created or started.
    public static func read(_ asset: AVAsset, count: Int) async throws -> [FrameSample] {
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        guard let videoTrack else {
            throw AppError.usage("no video track found; `frames` requires a video stream")
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AppError.contract("could not create AVAssetReader: \(String(describing: error))")
        }

        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        if reader.canAdd(output) {
            reader.add(output)
        }
        if !reader.startReading() {
            throw AppError.contract("AVAssetReader failed to start (status \(reader.status.rawValue))")
        }

        var samples: [FrameSample] = []
        let capped = count > 0 ? min(count, 100_000) : 0

        while samples.count < capped {
            guard let buffer = output.copyNextSampleBuffer() else { break }
            let (pts, dts, duration, size) = timing(of: buffer)
            samples.append(FrameSample(
                trackIndex: Int(videoTrack.trackID),
                pts: pts,
                dts: dts,
                duration: duration,
                sizeBytes: size
            ))
        }

        return samples
    }

    // MARK: Timing

    /// Extract PTS (seconds), DTS (seconds), duration (seconds), and byte size.
    static func timing(of buffer: CMSampleBuffer) -> (Double, Double?, Double, Int) {
        let pts = CMTimeSeconds.seconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        let dtsCM = CMSampleBufferGetDecodeTimeStamp(buffer)
        let dts = dtsCM.isNumeric && dtsCM.timescale > 0
            ? Double(dtsCM.value) / Double(dtsCM.timescale)
            : nil
        let duration = CMTimeSeconds.seconds(CMSampleBufferGetDuration(buffer))
        let size = CMSampleBufferGetTotalSampleSize(buffer)
        return (pts, dts, duration, size)
    }
}
