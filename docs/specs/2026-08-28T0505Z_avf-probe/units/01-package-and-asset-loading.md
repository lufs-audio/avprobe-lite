# Unit 01 — package-and-asset-loading

## Objective

Stand up the Swift Package, define the versioned JSON schema types, and load an `AVAsset`
with typed async property loading.

## Context

- New Swift Package (`Package.swift`), executable target `avprobe-lite`.
- Apple: `AVFoundation` `AVAsset`, `AVAssetTrack`; the typed async-load pattern from
  WWDC22 "Create a more responsive media app" (see phase `SPEC.md`).
- First step of Apple's own "fastest learning path" — this unit is that path's opening.

## Acceptance criteria

- [ ] `swift build` succeeds on macOS with `swift-argument-parser` dependency.
- [ ] `AVAsset(url:)` opens local files; `try await asset.load(.duration, .tracks, .playable)`
      returns real values (not string-keyed KVC).
- [ ] Schema types defined (Codable): `SourceModel`, `VideoStream`, `AudioStream`,
      `SchemaVersion`. Add-only field policy documented.
- [ ] A minimal `info --json` emits duration + playlist-ability + track count as valid JSON.
- [ ] `--version` prints the schema version.

## Interface contract

The `SourceModel` Codable shape (stable field names):

```swift
struct SourceModel: Codable {
  var schemaVersion: Int
  var durationS: Double
  var playable: Bool
  var video: VideoStream?
  var audio: AudioStream?
}
```

## Boundaries — do NOT touch

- Units 02–05 (format-description probe, streams/samples, vtframeprocessor, cli).

## Output

- `Package.swift`, `Sources/avprobe-lite/` with the model + a minimal `info` path.
- `Tests/` asserting `info --json` parses to the schema and `--version` output.

## Verification

- `swift build` and `swift test` green on macOS.
