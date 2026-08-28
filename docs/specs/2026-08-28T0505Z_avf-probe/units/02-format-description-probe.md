# Unit 02 — format-description-probe

## Objective

Populate codec, dimension, frame rate, bitrate, HDR/color, and audio properties from
real `CMFormatDescription` / track reads — the core "what is this file" probe.

## Context

- Builds on Unit 01's `AVAsset`/`AVAssetTrack` loading.
- Apple: `AVAssetTrack.formatDescriptions` → `CMFormatDescription`,
  `AVAssetTrack.nominalFrameRate`, `estimatedDataRate`, `naturalSize`/`preferredTransform`,
  `CMVideoFormatDescriptionGetH264ParameterSetAtIndex`-style FourCC via
  `CMFormatDescriptionGetMediaSubType`.
- See phase `SPEC.md` for the FFmpeg-parity motivation (codec `vide/avc1`, `soun/aac`).

## Acceptance criteria

- [ ] Extract video codec FourCC (`CMFormatDescriptionGetMediaSubType`), width/height,
      frame rate (num/den), SAR/DAR, pixel format, color/HDR primaries where present.
- [ ] Extract audio codec, channel layout/count, sample rate.
- [ ] Emit per-stream fields into `VideoStream`/`AudioStream`, all from framework reads —
      no hardcoded guesses.
- [ ] A container the frameworks can't read (e.g. unsupported codec) reports honestly
      (`unsupported`), never fabricated metadata.
- [ ] Deterministic: same file → identical JSON.

## Interface contract

Fills `VideoStream`/`AudioStream` with: `codec`, `codecFourCC`, `width`, `height`,
`fpsNum`, `fpsDen`, `sar`, `dar`, `pixFmt`, `colorPrimaries`, `channels`, `sampleRate`.
Stable, add-only.

## Boundaries — do NOT touch

- Units 01 (already landed), 03 (streams/samples), 04 (vtframeprocessor), 05 (cli).

## Output

- `Sources/avprobe-lite/FormatProbe.swift` + `Tests/` with a fixture asserting real
  FourCC/resolution values for a known test asset (generated once, cached).

## Verification

- `swift test` green; a test reads a known H.264/AAC fixture and asserts codec `avc1`/`aac`.
