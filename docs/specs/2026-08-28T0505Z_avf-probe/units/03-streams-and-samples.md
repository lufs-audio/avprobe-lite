# Unit 03 — streams-and-samples

## Objective

Implement `streams` and `frames` subcommands: per-track stream index, and sample-level
PTS/DTS via `AVAssetReader`.

## Context

- Builds on Units 01–02. Apple: `AVAssetReader` + `AVAssetReaderTrackOutput`,
  `CMSampleBuffer` timing (`CMSampleBufferGetPresentationTimeStamp`).
- This is the "read samples" step of Apple's learning path.

## Acceptance criteria

- [ ] `streams --json` lists each track with its index, type, codec, and time range.
- [ ] `frames --count N --json` reads up to N sample buffers and reports PTS/DTS/duration
      per packet, deterministic.
- [ ] Sample timing is reported in a stable unit (seconds, double), not raw CMTime objects.
- [ ] `frames` on a stream it cannot read (e.g. no video track) fails with a named usage
      error, not an empty-success.

## Interface contract

`streams` emits `[{index, type, codec, startS, endS}]`; `frames` emits
`[{pts, dts, duration, sizeBytes}]`. Stable, add-only.

## Boundaries — do NOT touch

- Units 02 (format probe), 04 (vtframeprocessor), 05 (cli).

## Output

- `Sources/avprobe-lite/Streams.swift`, `Frames.swift` + `Tests/`.

## Verification

- `swift test` green; a test asserts `frames` PTS is monotonically non-decreasing on a
      known fixture.
