//
// AssetLoader.swift
// avprobe-lite
//
// Unit 01 — open an AVAsset and load its core properties with typed async loading
// (the WWDC22 "Create a more responsive media app" pattern). Never string-keyed KVC.
//
//   let asset = try await AssetLoader.open(url)
//   let source = try await AssetLoader.loadSource(asset)
//
// Uses `asset.load(.duration, .tracks, .playable)` — the typed async tuples API.
// `.playable` has a guard: files under some sandboxing rules can report an empty
// playability value; we treat an error there as "unknown, not false".
//

import Foundation
import AVFoundation

public struct AssetLoader {

    // MARK: Open

    /// Construct the asset from a local file URL. The file must exist and be readable;
    /// otherwise this is a usage error (exit 2), raised before we ever touch a schema.
    public static func open(url: URL) throws -> AVAsset {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.usage("input file does not exist: \(url.path)")
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw AppError.usage("input file is not readable: \(url.path)")
        }
        return AVAsset(url: url)
    }

    // MARK: Core async load

    /// Load duration, tracks, and playability in one typed async tuple load.
    /// Contract-level failure here means we cannot honor `info --json` → exit 5.
    public static func loadSource(_ asset: AVAsset) async throws -> SourceModel {
        let duration: CMTime
        let tracks: [AVAssetTrack]
        let playableAny: Bool?

        do {
            (duration, tracks, playableAny) = try await asset.load(.duration, .tracks, .playable)
        } catch {
            throw LoadError.contract("failed to load asset core properties", cause: error)
        }

        let durationS = duration.seconds
        let playable = playableAny ?? false

        var model = SourceModel(
            schemaVersion: Schema.version,
            durationS: durationS,
            playable: playable,
            video: nil,
            audio: nil
        )

        // Pull the first video and first audio tracks into the top-level model.
        // The `streams` subcommand is authoritative for the full per-track list.
        let videoTrack = tracks.first(where: { $0.hasMediaCharacteristics(.isVideoTrack) })
        let audioTrack = tracks.first(where: { $0.hasMediaCharacteristics(.isAudioTrack) })

        if let v = videoTrack {
            model.video = try await FormatProbe.probeVideo(track: v)
        }
        if let a = audioTrack {
            model.audio = try await FormatProbe.probeAudio(track: a)
        }

        return model
    }
}
