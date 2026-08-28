# CHANGELOG

## [1.0.1] — Mac-verified (2026-08-28)

Phase 1 reconciliation: builds green on macOS 26.3.1 (arm64, Swift 6.3.3, SDK 26.5),
`swift test` passes (15 tests), the **real** `VTFrameProcessor` pipeline runs live, and the
exit-code floor 0/2/5 including malformed syntax is enforced. Schema stayed add-only;
`schemaVersion` unchanged (1).

### Changed (reconciled against the real SDK; no schema shape change)
- **Live ML pipeline** (`FrameProcessorLive.swift`): `process --effect frc` runs a genuine
  `VTFrameRateConversionConfiguration` interpolate (2 source frames → 1) and reports
  measured `before/after` + `averageFrameTimeS`. `superres` runs
  `VTSuperResolutionScalerConfiguration` (scale factor 4) where the model is downloaded;
  `denoise` runs `VTTemporalNoiseFilterConfiguration` only for high-bit-depth
  4:2:2/4:4:4 sources. Unserviceable sources emit an honest `supported:false` + reason,
  exit 0.
- **Per-effect gates** (`ProcessPath.swift`): each effect now has its own OS floor (`frc`
  = 15.4+, `denoise`/`superres` = 26.0+) and maps to its own configuration class
  (`appliedPipeline`). Replaces the single coarse `macOS 15.4` gate and the static
  before/after "doubling" guess the pre-Mac design implied.
- **Malformed-syntax → exit 2** (`CLI.swift`): hand-rolled `@main` calling
  `AVProbeLite.parseAsRoot`; ArgumentParser parse errors are remapped from its native
  `EX_USAGE` (64) down to **our** usage floor. `--help`/`--version` still exit 0.
- **SDK drift fixes**: `AVURLAsset(url:)` (non-deprecated), `asset.load(.isPlayable)` →
  `Bool`, `.visual`/`.audible` characteristic constants, `CMAudioFormatDescriptionGetStreamBasicDescription(...).pointee`, audio channel-layout via
  `GetAudioChannelLayout(_:sizeOut:)`, `pixelFormatString` honest raw FourCC only
  (`kCMFormatDescriptionExtension_PixelFormat` absent). Affects `AssetLoader.swift`,
  `FormatProbe.swift`, `Streams.swift`.
- **Tests** rewritten to the per-effect gating API (`CapabilityTests.swift`); `EnvelopeTests`
  and `FormatProbeTests` fixed for SDK/toolchain (`import CoreMedia`, homogeneous envelope
  payload, correct FourCC expectation `mpg4`).

### Added
- `FrameProcessorLive.swift` — decode PixelBuffers via `AVAssetReader`, live effect runners.
- `.gitignore` — excludes `.build/`, `Package.resolved`, generated `.acceptance/`, `.DS_Store`.

### Removed
- README "UNVERIFIED build" banner (replaced with "Mac-verified").
- Static `applyEffectMapping` effect-mapping API (replaced by live pipeline + per-effect gate).

---

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
- ~~Confirm the exact `VTFrameProcessor` initializer/effect API against the real SDK 15.4+
  and wire the real `process` body~~ — done in [1.0.1] (live `FrameProcessorLive`).
- ~~Confirm SAR~~ — SAR stays honest `nil` (the `pasp` box isn't surfaced through the
  current format-description read; not blocking).
- ~~Decide malformed-syntax exit code~~ — done in [1.0.1] (hand-rolled `@main` maps
  ArgumentParser `EX_USAGE` → 2).
