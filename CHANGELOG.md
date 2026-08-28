# CHANGELOG

## [1.0.0] — Unverified (pre-Mac-pass)

Authoring milestone. Authored without an Apple SDK present; **not yet confirmed to
compile**. Do not report "compiles-green" until `swift build` passes on macOS (see
`MAC_HANDOFF.md`).

### Added
- **Swift Package** (`Package.swift`, tools 5.9, macOS 13 platform floor) + executable
  target `avprobe-lite` depending on `swift-argument-parser`.
- **Schema types** (`Models.swift`, `Schema.version = 1`): `SourceModel`, `VideoStream`,
  `AudioStream`, `StreamDescriptor`, `FrameSample`, `EffectCapability`, `EffectStep`.
  Stable, add-only field policy.
- **Asset loading** (`AssetLoader.swift`): `AVAsset(url:)` + typed async
  `load(.duration, .tracks, .playable)` (WWDC22 pattern); file-exists/readable usage
  checks.
- **Format probe** (`FormatProbe.swift`): codec FourCC via
  `CMFormatDescriptionGetMediaSubType`, dimensions, frame-rate num/den, DAR (natural
  size), pixel format + color primaries via format-description extensions, audio
  channels/sample-rate from the audio format description + ASBD, estimated bitrate. SAR
  intentionally `nil` (not publicly exposed — see README/MAC_HANDOFF).
- **Streams** (`StreamLister` in `Streams.swift`): per-track `index/type/codec/timeRange`
  listing; `frames` on a no-video asset throws `.usage` (exit 2), never empty-success.
- **Frames** (`FrameReader` in `Frames.swift`): `AVAssetReader` +
  `AVAssetReaderTrackOutput` reading up to N samples; PTS/DTS/duration as seconds (Double)
  + `sizeBytes`.
- **VTFrameProcessor path** (`ProcessPath.swift`): honest capability gate combining SDK
  availability (`#if canImport`), OS floor (`isOperatingSystemAtLeast(macOS 15.4)`), and
  `VTIsHardwareDecodeSupported`. `check()` = no-decode capability; `run(effect:)` =
  measured before/after. Unsupported → `supported:false` + reason, exit 0. Supported but
  unserviceable → contract error (exit 5), refusing a fabricated result.
- **CLI + envelope** (`CLI.swift`, `Envelope.swift`, `AppError.swift`): subcommands
  `info/streams/frames/process`, `--check`, `--json`, `--version`; bplate envelope
  (`success`/`error`), sorted deterministic keys; exit-code floor 0/2/5 enforced via
  `exit()` in the error path.
- **Tests** (`Tests/avprobe-liteTests/`): envelope shape + determinism; capability honesty
  (unsupported carries a reason; supported names the applied pipeline); superres before/
  after doubling; FourCC/frame-rate/DAR/bitrate helpers; CMTime seconds guard.
- **Docs**: `README.md`, `AGENTS.md`, this `CHANGELOG.md`, `MAC_HANDOFF.md`.

### Open items for the Mac pass
- Confirm the exact `VTFrameProcessor` initializer/effect API against the real SDK 15.4+
  and wire the real `process` body (currently an honest gate + measured before/after, not
  a live pixel transform).
- Confirm SAR: derive from the ISO/IEC 13818-1 pasp box if we want more than `nil`
  (currently honest `nil`).
- Decide malformed-syntax exit code: ArgumentParser currently exits 64 on unknown flags
  before our `run()`; map to 2 via a hand-rolled `@main` if the floor must cover syntax.
