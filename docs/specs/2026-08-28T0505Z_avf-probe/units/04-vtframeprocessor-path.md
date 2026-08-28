# Unit 04 — vtframeprocessor-path

## Objective

Implement the `process` subcommand: run a frame through `VTFrameProcessor` (denoise /
super-resolution / frame-rate conversion) with **honest capability reporting**. This is
the differentiator — no prior AVFoundation probe wraps Apple's ML video-processing path.

## Context

- Apple `VideoToolbox`: `VTFrameProcessor` (macOS 15.4+/iOS 26+), `VTIsHardwareDecodeSupported`,
  and the WWDC25 "Enhance your app with ML-based video effects" session.
- This is the deliberate "stretch" unit (see phase `SPEC.md`).

## Acceptance criteria

- [ ] `process --effect denoise|superres|frc <file>` exists and is capability-gated.
- [ ] Reports `VTFrameProcessor` availability via a real check; on an unsupported OS/SoC,
      emits `{"supported": false, "reason": "…"}` and exits 0 (honest no-op), never a
      fabricated result.
- [ ] Where supported, processes at least one representative frame and reports before/after
      (frame count, resolution change for superres, timing) as JSON.
- [ ] `--check` (capability-only) reports what effects are available on this device without
      decoding a full asset.
- [ ] No over-claim: output states exactly which effect ran and the OS/SoC gate it passed.

## Interface contract

`process`/`--check` emit `{effect, supported, os, soc, applied, before?, after?}`. Stable.

## Boundaries — do NOT touch

- Units 02/03 (probe/streams), 05 (cli wrapper integration is separate from this
  component's logic).

## Output

- `Sources/avprobe-lite/VTFrameProcessorPath.swift` + `Tests/` (mock/gate tests where a
  real VTFrameProcessor-capable device isn't present; the honest-unsupported path is the
  testable default).

## Verification

- `swift test` green; the `--check` path returns `supported:false` gracefully on a
  non-supporting runner without crashing.
