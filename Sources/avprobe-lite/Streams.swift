//
// Streams.swift
// avprobe-lite
//
// Unit 03 — `streams` subcommand: a per-track listing (index, type, codec, time range).
// This is the authoritative full-track view; `info` only surfaces the first video/audio.
//

import Foundation
import AVFoundation
import CoreMedia

public enum StreamLister {

    /// Enumerate every track in the asset and describe it as a StreamDescriptor.
    public static func enumerate(_ asset: AVAsset) async throws -> [StreamDescriptor] {
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw LoadError.contract("failed to enumerate tracks", cause: error)
        }
        let tracks = videoTracks + audioTracks

        // Deterministic ordering: consolidated video-first, then audio, then by trackID.
        let sorted = tracks.sorted { a, b in
            let va = a.mediaType == .video ? 0 : 1
            let vb = b.mediaType == .video ? 0 : 1
            if va != vb { return va < vb }
            return a.trackID < b.trackID
        }

        var descriptors: [StreamDescriptor] = []
        for (index, track) in sorted.enumerated() {
            // Load format descriptions + time range, tolerating individual-track failure
            // (an unreadable track still yields a typed entry, just with nil codec).
            var fd: CMFormatDescription?
            var timeRange = CMTimeRange.invalid
            if let (fds, tr) = try? await track.load(.formatDescriptions, .timeRange) {
                fd = fds.first
                if tr.isValid { timeRange = tr }
            }

            var descriptor = StreamDescriptor(
                index: index,
                type: trackType(track),
                codec: nil, codecFourCC: nil,
                width: nil, height: nil,
                fpsNum: nil, fpsDen: nil,
                startS: nil, endS: nil
            )

            if let fd {
                let fourCC = FormatProbe.mediaSubTypeString(fd)
                descriptor.codec = FormatProbe.codecFamily(fourCC)
                descriptor.codecFourCC = fourCC
                if track.mediaType == .video {
                    // Asynchronous load for numeric props used by streams listing.
                    if let loaded = await loadVideoFacts(track) {
                        descriptor.width = loaded.0
                        descriptor.height = loaded.1
                        descriptor.fpsNum = loaded.2
                        descriptor.fpsDen = loaded.3
                    }
                }
            }

            if timeRange.isValid {
                descriptor.startS = FormatProbe.timeStart(timeRange)
                descriptor.endS = FormatProbe.timeEnd(timeRange)
            }

            descriptors.append(descriptor)
        }
        return descriptors
    }

    /// Pull width/height/fps asynchronously for a video track. Returns nil on any failure.
    private static func loadVideoFacts(_ track: AVAssetTrack) async -> (Int, Int, Int?, Int?)? {
        do {
            let (naturalSize, frameRate) = try await track.load(.naturalSize, .nominalFrameRate)
            let ratio = FormatProbe.fractionFromFloat(frameRate)
            return (
                Int(naturalSize.width), Int(naturalSize.height),
                ratio.0, ratio.1
            )
        } catch {
            return nil
        }
    }

    static func trackType(_ track: AVAssetTrack) -> String {
        if track.mediaType == .video { return "video" }
        if track.mediaType == .audio { return "audio" }
        return track.mediaType.rawValue
    }
}
