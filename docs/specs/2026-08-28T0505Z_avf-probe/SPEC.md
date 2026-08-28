# avprobe-lite — Native AVFoundation/VideoToolbox Probe

A macOS-native Swift CLI that inspects media the way ffprobe does — but through Apple's
own frameworks (AVFoundation, Core Media, VideoToolbox), emitting a versioned JSON schema
for agent consumption, plus the one thing no existing tool wraps: **VTFrameProcessor**
(Apple's hardware-accelerated ML video processing).

## Problem

The Apple Cloud Media Engineer JD (200678579-0836) lists, as a **minimum** (not
preferred) qualification, "Familiarity with Apple platform frameworks — Cocoa,
AVFoundation, or the iOS/macOS SDK." That is the single biggest named gap in Daniel's
profile — a flat zero against Apple's native stack.

The direct answer is not a resume line; it is a working artifact that proves the
frameworks are learned and used: a real, native Swift tool on AVFoundation/VideoToolbox.
fast-forward to the whitespace: several Swift AVFoundation probes already exist, but none
combine the two differentiators this project claims.

## What already exists (and why we're still here)

- `mself/avfprobe` — 2016, Objective-C, effectively dead; human-readable output, no JSON schema.
- `oscnord/FramePeek` — Swift CLI, does emit JSON; but no stable/versioned agent schema,
  no MCP surface, and no VTFrameProcessor path.
- `xocialize/media-bridge` — a Swift probing *library* (`MediaBridge.probe()`), not an
  ffprobe-style CLI contract.
- `SoundBlaster/ISOInspector` — a container parser (MP4/MOV), not an AVFoundation/VideoToolbox probe.
- `aagedal/SwiftExif` — Swift ffprobe alternative, but explicitly "no decoding, no AVFoundation."

So "Swift AVFoundation CLI that emits JSON" is not greenfield. The defensible position is:
**(1)** a maintained, versioned, agent-oriented JSON contract, and **(2)** the first
AVFoundation-démux + **VTFrameProcessor** probe — read Apple's ML media-processing path
(denoise, super-resolution, frame-rate conversion) that no prior tool wraps. That second
point is the "zing": it turns "I learned AVFoundation" into "I wrapped an API nobody
else has, on the very ML-media seam the JD asks about."

## Goals

1. Open any `AVAsset` and async-load its tracks, format descriptions, duration, codec
   FourCCs, resolution, frame rate, bitrate, HDR/color, audio channel/sample-rate.
2. Emit a **versioned JSON schema** (`schema_version`, stable field names, add-only) on
   `--json`, designed for another program/agent to consume deterministically.
3. Provide `info`, `streams`, and `frames` subcommands (metadata; per-track stream index;
   sample-level PTS/DTS via `AVAssetReader`).
4. Provide a **`process`** subcommand that runs a frame through `VTFrameProcessor`
   (denoise / super-res / framerate-conversion where the OS+SoC supports it), reporting
   capability + before/after without over-claiming what the device can do.
5. Honest capability reporting: use `VTIsHardwareDecodeSupported` / `VTFrameProcessor`
   availability checks and say "unsupported on this device" rather than fabricating.
6. Agent-ergonomic: `--json`, deterministic output, exit-code floor (0/2/5), bplate JSON
   envelope.

## Non-goals

- Not a decoder to disk or a player. This *probes*; it does not transcode or render.
- Not cross-platform. macOS-native by design (that's the point — the JD's Apple-platform
  gap).
- Not a reimplementation of ffprobe's full grammar. We expose what AVFoundation/Core Media/
  VideoToolbox natively provide; container-level gaps (e.g. MKV) are out of scope.
- Not yet certified (Workchain tier). This phase targets "working, honest, tested."

## Design approach

Swift Package (`Package.swift`), Swift Concurrency throughout:

- `AVAsset(url:)` + typed async property loading (the WWDC22-recommended pattern) for
  duration/tracks/playable.
- `AVAssetTrack.formatDescriptions` → `CMFormatDescription` for codec subtype FourCCs
  (`vide/avc1`, `soun/aac`, …), dimension, frame rate, estimated data rate.
- `AVAssetReader`/`AVAssetReaderTrackOutput` for sample-level PTS/DTS when `frames`/`streams`
  need it.
- `VTIsHardwareDecodeSupported` for honest decode-capability signals.
- `VTFrameProcessor` (macOS 15.4+ / iOS 26+) for the `process` subcommand's ML effects.
- `swift-argument-parser` for the CLI; codable `struct`s for the JSON schema.

The probe JSON schema is *deliberately* shaped to be consumable by `smart-abr-ladder`
(sibling repo) — so this is the Apple-native probe inside Daniel's own verification
ecosystem, not an orphan tool.

## Ecosystem references

- **`lufs-audio/smart-abr-ladder`** — consumes this tool's probe JSON schema as its
  Apple-native media-probe front end (shared contract).
- **`lufs-audio/avfoundation-mcp`** — the MCP server that wraps this probe (and more) as
  an agent-callable surface; sibling Swift project.
- **`lufs-audio/workchain`** — the verifier/provenance doctrine this tool's deterministic
  output and exit codes echo.
- **`lufs-audio/bplate`** — exit-code floor (0/2/5) and JSON envelope.
- **Apple frameworks** (the point): `AVFoundation` (av-foundation), `Core Media`,
  `Core Video`, `VideoToolbox`, and `VTFrameProcessor`
  (`developer.apple.com/documentation/videotoolbox/vtframeprocessor`); capability checks
  via `VTIsHardwareDecodeSupported`.
- **Prior art (differentiation targets):** `mself/avfprobe`, `oscnord/FramePeek`,
  `xocialize/media-bridge`, `SoundBlaster/ISOInspector`, `aagedal/SwiftExif`.

## Language

**Swift** — non-negotiable. This is the Apple-platform-framework gap-closer; it *must* be
native Swift on AVFoundation/VideoToolbox, not a Rust/Python wrapper around FFmpeg.

## Units

1. `01-package-and-asset-loading` — Swift Package, `AVAsset` typed async loading, schema types.
2. `02-format-description-probe` — codec FourCCs, dimension, framerate, bitrate, HDR/color.
3. `03-streams-and-samples` — `info`/`streams`/`frames` subcommands (AVAssetReader PTS/DTS).
4. `04-vtframeprocessor-path` — `process` subcommand + honest capability reporting.
5. `05-cli-envelope` — argument-parser CLI, `--json`, exit codes, envelope.

## Done criteria

- [ ] `avprobe-lite info/streams/frames --json <file>` emits the versioned schema, deterministic.
- [ ] Codec FourCCs, resolution, fps, bitrate, channels/sample-rate all populated from
      real framework reads (not hardcoded).
- [ ] `process --effect denoise` reports VTFrameProcessor capability honestly, including a
      clean "unsupported on this device" path.
- [ ] Exit-code floor (0/2/5) + bplate envelope; `--json` + `--version`.
- [ ] `swift build` + `swift test` green; tests assert schema stability + capability honesty.

## Extra context for the builder

This is Daniel's first native Swift project. The "fastest learning path" per Apple's own
docs is exactly the vertical slice this project is: load AVAsset → async-property →
preview → `AVAssetImageGenerator` thumbnails → `AVAssetReader`/Writer samples. This spec
is written so each unit is a step along that path, with the `VTFrameProcessor` unit as the
deliberate stretch at the end (it is the differentiator, not the foundation).
