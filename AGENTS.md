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
  15.4+** for the `VTFrameProcessor` availability block.
- `ProcessPath.gate()` uses `#if canImport(VideoToolbox.VTFrameProcessor)` — on older SDKs
  it compiles to the honest unsupported path. Do not "simplify" this into a hard citation
  that breaks older SDKs.
- With Swift's default "minimal" strict-concurrency, the synchronous `AVAssetReader`
  calls in `Frames.swift` compile fine. If someone enables
  `.swiftStrictConcurrency`, reader setup must move to `@MainActor` / an executor.
- The CLI uses `@main AsyncParsableCommand`. ArgumentParser validates syntax and calls
  `exit(withError:)` FIRST for unknown flags (EX_USAGE 64) before our `run()`. If you want
  malformed-syntax mapped to 2, switch to a hand-rolled `@main` + `parseAsRoot` + `exit()`.

## Reconciling-agent flags (hardest-to-verify without a Mac)

Confirmed beyond doubt by reading Apple docs, but NOT compile-checked here — flag any that
fail the Mac `swift build`:

- The exact Swift signature of `VTFrameProcessor`'s effect/config API (the spec cites the
  type; the concrete pipeline names below are ours, semantically loaded). The `process`
  path may need its real initializer on the Mac instead of the conservative gate.
- Whether `CMFormatDescriptionGetMediaSubType`/`GetExtension` return `FourCharCode` /
  `CFTypeRef?` exactly as written against the current SDK.
- `AVAssetTrack.timeRange` / `formatDescriptions` synchronous property access vs needing
  async `load` — both are valid; the Streams path reads them directly.
- Whether `VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)` returns `Bool` (it does).

See `MAC_HANDOFF.md` for the ordered reconciliation runbook.
