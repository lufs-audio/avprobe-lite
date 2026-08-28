# avprobe-lite

A macOS-native Swift CLI that inspects media the way `ffprobe` does — but through
Apple's own frameworks (**AVFoundation**, **Core Media**, **VideoToolbox**) — emitting a
**versioned, deterministic JSON schema** for agent consumption, plus the one thing no
existing probe wraps: **`VTFrameProcessor`** (Apple's hardware-accelerated ML video
processing: denoise / super-resolution / frame-rate conversion).

Built and verified on **macOS 26.3.1, Apple-silicon (arm64), Swift 6.3.3** against the
Xcode `MacOSX26.5.sdk`. This is Daniel's first native Swift project, deliberately shaped
as Apple's own "fastest learning path": AVAsset → async-property → format-description
probe → `AVAssetReader` samples → `VTFrameProcessor` ML effects.

> **Status: Mac-verified.** `swift build` is green and `swift test` passes (15 tests) on
> this machine; `swift build` needs an Apple SDK 15.4+ for the full `VTFrameProcessor`
> gate to be live. See [MAC_HANDOFF.md](MAC_HANDOFF.md) for the reconciliation runbook.

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

**Determinism**: sorted keys, no ANSI, no wall-clock, no hostname/pid. The probe-y
subcommands (`info`/`streams`/`frames`) and `--check` produce identical bytes for the same
file & binary. Only `process --effect <frc|superres>` on the supported path reports a
measured `averageFrameTimeS` — a genuine wall-clock taken by the real ML transform, so it
varies run-to-run by design (a live benchmark, not an identity timestamp).

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

`VTFrameProcessor` is gated per effect behind a real availability + OS-version +
`isSupported` check. Each effect maps to its **own** configuration class with **its own
macOS floor** (hardened SDK facts, not our choosing):

| `--effect` | Real pipeline | macOS floor |
|---|---|---|
| `frc` | `VTFrameRateConversionConfiguration` (interpolation) | 15.4+ |
| `superres` | `VTSuperResolutionScalerConfiguration` (only scale factor 4 here) | 26.0+ |
| `denoise` | `VTTemporalNoiseFilterConfiguration` (needs high-bit-depth 4:2:2/4:4:4 source) | 26.0+ |

On a host where the ML pipeline is unavailable, or where the source can't be serviced
(e.g. 8-bit 4:2:0 `420f` for denoise, or the super-res model not yet downloaded),
`process --effect …` emits an honest reason and **exit 0** — a clean no-op is a success,
**never a fabricated result**:

```json
{"status":"success","data":{"effect":"denoise","supported":false,"os":"macOS 26.0","soc":"arm64","applied":"none","reason":"temporal noise filter does not accept source pixel format 420f (requires a high-bit-depth 4:2:2\/4:4:4 source)"}}
```

When support IS available it runs the **real** pipeline over a decoded frame and reports
measured `before`/`after`, naming the exact configuration class that ran (e.g.
`applied:"VTFrameRateConversionConfiguration"`, with measured `averageFrameTimeS`). A
supported-but-undeecodable asset is a contract error (exit 5) — we refuse to fake a
transform.

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
  ProcessPath.swift   # per-effect VTFrameProcessor gate + capability    (unit 04)
  FrameProcessorLive.swift  # decode + run the real ML effect            (unit 04)
  Models.swift        # versioned Codable schema                         (all units)
  Envelope.swift      # bplate JSON envelope                              (unit 05)
  AppError.swift      # error taxonomy + exit codes                       (unit 05)
Tests/avprobe-liteTests/   # schema/envelope/capability/helper assertions
docs/specs/2026-08-28T0505Z_avf-probe/  # the interface contract this implements
```

## Acceptance asset

`.acceptance/` holds a locally regenerated sample (see [MAC_HANDOFF.md](MAC_HANDOFF.md))
and is gitignored — never commit the generated `sample.mp4`.

## Ecosystem

This probe's JSON schema is the Apple-native front end for `smart-abr-ladder`, and is
wrapped as an agent-callable MCP surface by `avfoundation-mcp`. The envelope + exit-code
floor echo `workchain`'s verification doctrine and `bplate`. See the phase
`docs/specs/2026-08-28T0505Z_avf-probe/` for the full design rationale.
