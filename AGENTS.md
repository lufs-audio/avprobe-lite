# AGENTS.md — guidance for agents working in this repo

## Context

`avprobe-lite` is a macOS-native Swift CLI probing via AVFoundation / Core Media /
VideoToolbox, emitting a versioned JSON contract for agent consumers
(`smart-abr-ladder`, `avfoundation-mcp`). The interface contract lives in
`docs/specs/2026-08-28T0505Z_avf-probe/` — **the spec is the source of truth for the
schema; the implementation must stay faithful to it.** Read `SPEC.md` + `units/01..05`
before changing behavior.

## Hard rules

1. **Never fabricate a framework read.** A field the OS can't produce is `nil`/omitted,
   never guessed. The `process` path (VTFrameProcessor) is the test: on an unsupported
   host it MUST emit `{"supported":false,"reason":"…"}` and exit 0 — a clean no-op is a
   success. Nobody gets to claim an effect ran.
2. **Schema is add-only.** Never rename/remove a key or change a unit (`durationS` stays
   seconds). New capability ⇒ new optional key + `schemaVersion` unchanged (it only
   bumps on a non-additive, i.e. forbidden, change).
3. **Exit-code floor: 0/2/5.** 0 success (incl. honest-unsupported no-op), 2 usage/missing
   input, 5 contract (promised field unproducible / asset unopenable). Every subcommand's
   error path goes through `Envelope.error` + the floor.
4. **Deterministic output.** Sorted keys, no ANSI, no wall-clock, no hostname/pid.
5. **Swift Concurrency.** Prefer typed async `asset.load(...)`; never string-keyed KVC.
   AVAssetReader is synchronous — keep it off the async hot path and note Sendable
   implications (see below).

## Adding a field / subcommand

1. Extend the model structurally in `Models.swift` (optional field → synthesized Codable
   omits it when nil). Update the matching `*Tests.swift` assertion. Update the spec's
   interface-contract snippet to match (spec is the living contract).
2. Keep exit codes and envelope intact.

## Known build/compile notes (from the Mac pass)

- The package builds only on macOS (AVFoundation/VideoToolbox) and needs the **macOS SDK
  15.4+** for the `VTFrameProcessor` availability block (verified on SDK 26.5).
- `ProcessPath.gate(effect:)` uses `#if canImport(VideoToolbox.VTFrameProcessor)` — on older
  SDKs it compiles to the honest unsupported path. Do not "simplify" this into a hard
  citation that breaks older SDKs.
- With Swift's default "minimal" strict-concurrency, the synchronous `AVAssetReader`
  calls in `Frames.swift` / `FrameProcessorLive.swift` compile fine. If someone enables
  `.swiftStrictConcurrency`, reader setup must move to `@MainActor` / an executor.
- **The CLI is a hand-rolled `@main`** (`AVProbeLiteMain`): it calls
  `AVProbeLite.parseAsRoot` then maps ArgumentParser **parse errors to our usage floor (2)**
  (ArgumentParser's native `EX_USAGE` is 64), while `--help`/`--version` still exit 0 via
  `AVProbeLite.exit(withError:)`. Keep that mapping; a plain `@main AsyncParsableCommand`
  would silently leak 64 as a 4th exit code.
- The real ML effects live in `FrameProcessorLive.swift`, each keyed off a distinct config
  class with its own OS floor. Do not merge them back into a single coarse gate.

## Mac-verified API surfaces (PROVEN by the 2026-08-28 build; no longer flags)

The following were reconciled against the real SDK during the Mac pass and are now
confirmed to compile and behave correctly. Treat these as settled facts:

- **VTFrameProcessor effect/config API** — `VTFrameRateConversionConfiguration` (interpolate,
  macOS 15.4+), `VTTemporalNoiseFilterConfiguration` (denoise, macOS 26.0+, rejects 8-bit
  4:2:0 `420f`), `VTSuperResolutionScalerConfiguration` (macOS 26.0+, **only scale factor 4**
  on this Mac, and needs the ML model downloaded — check its `status`). `.isSupported` is a
  live `Bool` class property per config. Use `VTFrameProcessorFrame(buffer:presentationTimeStamp:)`
  to wrap `CVPixelBuffer`s.
- **`CMFormatDescriptionGetMediaSubType`/`GetExtension`** — return `FourCharCode` /
  `CFTypeRef?` as originally written. `kCMFormatDescriptionExtension_PixelFormat` does
  **NOT** exist in this SDK → `pixelFormatString` stays honest raw FourCC only.
- **`AVAssetTrack.timeRange` / `formatDescriptions`** — synchronous property access;
  the Streams path reads them directly without async load.
- **`VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)`** — returns `Bool` (confirmed).
- **Audio** — `CMAudioFormatDescriptionGetStreamBasicDescription(fd).pointee` for sample
  rate / channels; channel layout via `CMAudioFormatDescriptionGetChannelLayout(fd, sizeOut:)`
  (no `mNumberChannels`). `AVAsset(url:)` is deprecated → `AVURLAsset(url:)`;
  `asset.load(.isPlayable)` returns `Bool` (not optional); media characteristic constants
  are `.visual` / `.audible` (no `.isVideoTrack` / `.isAudioTrack`).

See `MAC_HANDOFF.md` for the ordered reconciliation runbook.
