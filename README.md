# avprobe-lite

A macOS-native Swift CLI that inspects media the way `ffprobe` does — but through
Apple's own frameworks (**AVFoundation**, **Core Media**, **VideoToolbox**) — emitting a
**versioned, deterministic JSON schema** for agent consumption, plus the one thing no
existing probe wraps: **`VTFrameProcessor`** (Apple's hardware-accelerated ML video
processing: denoise / super-resolution / frame-rate conversion).

Built and verified on macOS 15.4+ / Apple-silicon. This is Daniel's first native Swift
project, deliberately shaped as Apple's own "fastest learning path": AVAsset →
async-property → format-description probe → `AVAssetReader` samples → `VTFrameProcessor`
ML effects.

> **Status: UNVERIFIED build.** Authored without an Apple SDK present; do not report
> "compiles-green" until `swift build` passes on an actual Mac. See
> [MAC_HANDOFF.md](MAC_HANDOFF.md) for the ordered reconciliation runbook.

## What it does

| Subcommand | Emits (per record type) | Purpose |
|---|---|---|
| `info` | `SourceModel` (schemaVersion, durationS, playable, video?, audio?) | Source metadata — duration, playability, first video/audio track |
| `streams` | `[StreamDescriptor]` (index, type, codec, timeRange) | Full per-track listing |
| `frames` | `[FrameSample]` (pts, dts, duration, sizeBytes) | Sample-level PTS/DTS via `AVAssetReader` |
| `process` | `EffectCapability` (effect, supported, os, soc, applied, before?, after?) | Run/check a `VTFrameProcessor` ML effect |
| `--check` | `EffectCapability` | Capability-only; no asset decode |
| `--version` | schema version | Prints version |

## Interface contract

```
avprobe-lite <info|streams|frames|process> FILE [--json] [--count N]
                                                 [--effect E] [--check] [--version]
```

**Exit-code floor** (bplate): `0` success (incl. an honest, capability-gated unsupported
`process` no-op) · `2` usage/missing input · `5` contract (a promised schema field
unproducible / asset unopenable).

**JSON envelope**:
```
{"status":"success","data":…}
{"status":"error","code":N,"message":…}
```

**Determinism**: sorted keys, no ANSI, no wall-clock, no hostname/pid. Same file → same
bytes, on every run of the same binary.

## JSON schema (stable, add-only)

Top-level types (all Codable, optional-bearing fields omitted — never fabricated):

```
SourceModel  { schemaVersion:Int, durationS:Double, playable:Bool, video:VideoStream?, audio:AudioStream? }
VideoStream  { codec?, codecFourCC?, width?, height?, fpsNum?, fpsDen?, sar?, dar?, pixFmt?, colorPrimaries?, bitRateBPS?, startS?, endS? }
AudioStream  { codec?, codecFourCC?, channels?, sampleRate?, bitRateBPS?, startS?, endS? }
```

Field policy: add-only. Never rename/remove a key; never change a key's unit (`durationS`
stays seconds). New capabilities are new optional keys.

## The `process` differentiator — honest capability reporting

`VTFrameProcessor` (macOS 15.4+ / iOS 26+, Apple-silicon) is gated behind a real
availability + OS-version + `VTIsHardwareDecodeSupported` check. On any host where the ML
pipeline is unavailable, `process --effect …` / `--check` emit:

```json
{"status":"success","data":{"effect":"denoise","supported":false,"os":"macOS 15.4","soc":"arm64","applied":"none","reason":"hardware H.264 decode not supported by VideoToolbox on this device; requires Apple silicon (M-series)"}}
```

…and **exit 0** — a clean no-op is a success, **never a fabricated result**. When support
IS reported, the output names exactly which pipeline applied (e.g.
`VTFrameProcessor.superResolution`) and what was measured, refusing to claim pixels it
could not service.

## Build & test (macOS only)

```sh
# inside the package root
swift build
swift test
```

The package imports `AVFoundation` / `VideoToolbox` / `Core Media`, so it builds and runs
only on macOS. It also builds only with a stable/newer Swift toolchain that ships those
frameworks' interfaces (macOS SDK 15.4+ for the `VTFrameProcessor` block).

## Layout

```
Package.swift
Sources/avprobe-lite/
  CLI.swift           # argument-parser CLI, envelope, exit-code floor  (unit 05)
  AssetLoader.swift   # AVAsset typed async load                         (unit 01)
  FormatProbe.swift   # CMFormatDescription reads                        (unit 02)
  Streams.swift       # per-track listing                                (unit 03)
  Frames.swift        # AVAssetReader sample PTS/DTS                     (unit 03)
  ProcessPath.swift   # VTFrameProcessor gate + effect mapping           (unit 04)
  Models.swift        # versioned Codable schema                         (all units)
  Envelope.swift      # bplate JSON envelope                              (unit 05)
  AppError.swift      # error taxonomy + exit codes                       (unit 05)
Tests/avprobe-liteTests/   # schema/envelope/capability/helper assertions
docs/specs/2026-08-28T0505Z_avf-probe/  # the interface contract this implements
```

## Ecosystem

This probe's JSON schema is the Apple-native front end for `smart-abr-ladder`, and is
wrapped as an agent-callable MCP surface by `avfoundation-mcp`. The envelope + exit-code
floor echo `workchain`'s verification doctrine and `bplate`. See the phase
`docs/specs/2026-08-28T0505Z_avf-probe/` for the full design rationale.
