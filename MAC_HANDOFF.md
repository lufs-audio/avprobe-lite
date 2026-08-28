# MAC_HANDOFF — ordered reconciliation runbook for a local agent on a MacBook (pi)

> ## STATUS: COMPLETE (2026-08-28, on `pi`, macOS 26.3.1 / arm64 / Swift 6.3.3 / SDK 26.5).
> `swift build` green, `swift test` green (15 tests), acceptance pass done on a real video,
> docs reconciled, README banner flipped. This runbook is now a record; the reconciliation
> details and verified API surfaces live in `AGENTS.md` (see "Mac-verified API surfaces").
> Keep the honest-unsupported + exit-floor invariants intact if anything is changed.

This project was written against the documented Apple APIs from doc-only knowledge, with
no Swift toolchain / no AVFoundation / no VideoToolbox available at authoring time. It is
**not** confirmed to compile. Your job is to reconcile it against the real SDK, fix any
compile errors, run it on a real video, and push. Follow the steps in order. **Do not**
close this issue claiming green until step 4 passes.

---

## Step 0 — Preconditions (do once)

- You are on a **MacBook (`pi`)** with:
  - Xcode Command Line Tools / a recent Swift toolchain (`swift --version` → Swift 5.9+,
    ideally 5.10 / 6.x). If you don't have it: `xcode-select --install`.
  - An **Apple-silicon Mac running macOS 15.4+** for the `VTFrameProcessor` path to light
    up. On older OS / Intel, `process` must report `supported:false` honestly — that's a
    *pass*, not a failure.
  - A test video to probe. No file? Generate one:
    `ffmpeg -f lavfi -i testsrc=duration=5:size=1280x720:rate=30 -pix_fmt yuv420p sample.mp4`
    (audio optional: `-f lavfi -i sine=frequency=440:duration=5 -c:a aac`).
- The proposed package lives at `/agent/workspace/avprobe/`. It is a separate new package
  under that path (the repo's `docs/specs/` contract is at
  `avprobe-lite/docs/specs/2026-08-28T0505Z_avf-probe/`). If you want it at the repo root
  instead, move it; the paths below assume `/agent/workspace/avprobe`.

## Step 1 — Open the package in Xcode

1. `open /agent/workspace/avprobe/Package.swift`
2. Wait for Swift Package Manager to resolve `swift-argument-parser` and create the Xcode
   scheme (Product menu, or the scheme popup shows "avprobe-lite").
3. Select the **avprobe-lite** executable scheme, **My Mac** destination.

## Step 2 — `swift build`

In a terminal from `/agent/workspace/avprobe`:

```sh
swift build
```

**Fix forward** — this is the whole point of the Mac pass. The most likely compile issues
(and where the code is written accordingly):

1. **`VTFrameProcessor` real API** (`Sources/avprobe-lite/ProcessPath.swift`). The unit
   deliberately references it only inside `#if canImport(VideoToolbox.VTFrameProcessor)` so
   older SDKs fall back to honest-unsupported. On macOS 15.4+ SDK the block must still
   compile — if the type's Swift name differs, adjust the canImport guard and wire the
   real effect/config API. Keep the honesty gate FIRST; never process then fake.
2. **`CMFormatDescriptionGetMediaSubType` return type** (`FormatProbe.swift`): verify it's
   `FourCharCode` in this SDK (it is); `mediaSubTypeString` calls `fourCCString` with it —
   type-check the `FourCharCode`→`OSStatus` bridging.
3. **`CMFormatDescriptionGetExtension` cast**: verify `ext as? NSNumber` / `as? String`
   compile for the PixelFormat and ColorPrimaries keys. If the SDK returns `CVImageBuffer` /
   CF types differently, adjust the casts.
4. **`AVAssetTrack` sync props** (`Streams.swift`): `.formatDescriptions` and `.timeRange`
   are read as synchronous properties. If Swift Concurrency flags them as unavailable
   without `load`, switch to `try await track.load(.timeRange, .formatDescriptions)`.
5. **`AVAssetReader` is not Sendable** (`Frames.swift`): compiled under default minimal
   strict-concurrency it's fine. If someone enabled `.swiftStrictConcurrency`, move reader
   setup to `@MainActor` / a dedicated executor (the file has a NOTE already).
6. **Exit-code design** (`CLI.swift`): with `@main AsyncParsableCommand`, ArgumentParser
   validates syntax and exits 64 (`EX_USAGE`) on unknown flags BEFORE `run()`. Our 0/2/5
   floor governs every contract-relevant path we control. If the spec demands malformed
   syntax → 2, replace `@main AsyncParsableCommand` with a hand-rolled `@main` doing
   `parseAsRoot` + `exit(ErrorOut.code(...))`.

Iterate `swift build` until it is clean. **Only proceed once it is.**

## Step 3 — `swift test`

```sh
swift test
```

The tests are pure-logic (envelope shape/determinism, capability honesty, superres before/
after, FourCC/frame-rate/DAR/bitrate helpers, CMTime seconds guard) and don't need a real
asset. They should pass once the build is green. If a capability-honesty test fails on
your box, fix the logic, not the assertion.

## Step 4 — Run it on a real video (the acceptance pass)

```sh
BIN=.build/debug/avprobe-lite

# 1. info — expect source metadata + envelope
$BIN info sample.mp4
# expect: {"status":"success","data":{"schemaVersion":1,"durationS":5.0,"playable":true,...}}

# 2. streams — expect per-track listing
$BIN streams sample.mp4

# 3. frames — expect sample PTS/dts/duration; PTS monotonically non-decreasing
$BIN frames sample.mp4 --count 30

# 4. process --check — capability-only, no asset decode
$BIN process --check
# On your Mac: either supported:true (macOS 15.4+, Apple silicon) or honest
# supported:false + reason + exit 0. Both are correct; never a fabricated result.

# 5. process --effect denoise sample.mp4 / superres / frc
$BIN process --effect superres sample.mp4

# 6. Exit-code + envelope spot checks
$BIN info /nonexistent.mp4 ; echo "exit=$?"      # expect message + exit 2
$BIN frames /not-a-video.mp4 ; echo "exit=$?"     # usage when no video track (exit 2)
$BIN process ; echo "exit=$?"                     # usage (needs FILE or --check) exit 2
$BIN --version                                    # 1.0.0
```

**Verify the honesty invariant explicitly**: on any asset/OS where `process` reports
`supported:false`, it MUST also carry a `reason` and `exit` 0. If you ever see a fabricated
"ran denoise" on an unsupported host, that's a blocking bug.

## Step 5 — Record what changed; push

1. Note every edit you made to make `swift build`/`swift test`/the acceptance pass green.
2. **Update `AGENTS.md`** — move any "reconciling-agent flags" that compiled fine into a
   short "verified on macOS" note.
3. **Update `CHANGELOG.md`** — add a `[1.0.1] (Mac-verified)` entry listing the fixes.
4. **Flip the UNVERIFIED disclaimer in `README.md`** to reference the verified build once
   step 2–4 are green.
5. Commit and push from `/agent/workspace/avprobe`.

## Reconciling-agent flags (things a doc-only pass could get wrong)

These are the highest-risk items to confirm on the real SDK. Flag them back to the
authoring agent if any fails:

1. **`VTFrameProcessor`'s concrete Swift API** — the *type* is real (macOS 15.4+/iOS 26+)
   but the effect/config initializer we imply (`.superResolution`, `.denoise`,
   `.frameRateConversion`) is our semantic naming. Wire it to the true symbol on the Mac.
2. **`isOperatingSystemAtLeast(macOS 15.4)` + `canImport(VideoToolbox.VTFrameProcessor)`**
   is the gate; confirm the canImport module path matches the SDK (it may need to be
   `VideoToolbox` alone with an `@available(macOS 15.4, *)` annotation instead).
3. **`CMFormatDescriptionGetExtension` key cast types** (see step 2.3).
4. **`VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)` → `Bool`** — confirmed by docs,
   verify against SDK.
5. **SAR** is currently honest `nil` (not publicly exposed). If the consumer needs a value,
   derive the ISO/IEC 13818-1 `pasp` box from the extension/dimensions on the Mac rather
   than hardcoding.

## What "done" looks like

- `swift build` **green on `pi`**.
- `swift test` green.
- `info`/`streams`/`frames` output real framework reads on a real file; `process --check`
  and `process --effect …` are honest (supported ✔ / unsupported + reason + exit 0 ✔).
- README disclaimer flipped, CHANGELOG updated, `AGENTS.md` notes reconciled, pushed.
