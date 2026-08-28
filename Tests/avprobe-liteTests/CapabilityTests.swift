//
// CapabilityTests.swift
// avprobe-liteTests
//
// Unit 04 — VTFrameProcessor capability honesty. The whole point: on ANY machine where
// the ML pipeline is unavailable, we report `supported:false` with a reason and exit 0 —
// never a fabricated result. This test asserts the honest-unsupported contract holds
// regardless of the host, and that when support IS reported it names the applied pipeline
// (so a claim is always attributable, never silent).
//
// The pre-Mac design guessed before/after dimensions (e.g. superres "doubling" 1920→3840
// without touching a pixel). That static fantasy is gone: capability now comes from the
// REAL live pipeline (measured frames) or an honest `supported:false`. These tests pin the
// per-effect gate + capability invariants that replace it.
//

import XCTest
@testable import avprobe_lite

final class CapabilityTests: XCTestCase {

    func testEveryEffectHasAnHonestGate() {
        // gate() is deterministic and self-consistent: an unavailable effect must give a reason;
        // an available one must give none. We never report "available without any reason".
        for effect in ProcessPath.Effect.allCases {
            let (available, reason) = ProcessPath.gate(effect: effect)
            if available {
                XCTAssertNil(reason, "available effect \(effect) must not carry a reason")
            } else {
                XCTAssertNotNil(reason, "unavailable effect \(effect) must carry an honest reason")
            }
        }
    }

    func testEffectMetadataIsCompletePerEffect() {
        // Every effect names the real config class it would run and its own OS floor.
        for effect in ProcessPath.Effect.allCases {
            XCTAssertFalse(effect.appliedPipeline.isEmpty, "effect \(effect) must name a pipeline")
            XCTAssertFalse(effect.requiresOS.isEmpty, "effect \(effect) must state an OS floor")
        }
        XCTAssertEqual(ProcessPath.Effect.frc.appliedPipeline, "VTFrameRateConversionConfiguration")
        XCTAssertEqual(ProcessPath.Effect.denoise.appliedPipeline, "VTTemporalNoiseFilterConfiguration")
        XCTAssertEqual(ProcessPath.Effect.superres.appliedPipeline, "VTSuperResolutionScalerConfiguration")
    }

    func testCheckReturnsAWellFormedCapabilityPerEffect() async {
        for effect in ProcessPath.Effect.allCases {
            let cap = await ProcessPath.check(effect: effect)
            XCTAssertEqual(cap.effect, effect.rawValue)
            XCTAssertEqual(cap.os, effect.requiresOS)
            // Honesty invariant: unsupported ⇒ reason; supported ⇒ no reason.
            if cap.supported {
                XCTAssertNil(cap.reason, "supported \(effect) must not carry a reason")
                XCTAssertEqual(cap.applied, "capability present (no asset decoded)")
            } else {
                XCTAssertNotNil(cap.reason, "unsupported \(effect) must carry an honest reason")
                XCTAssertEqual(cap.applied, "none")
            }
            // --check never decodes → no before/after measurements.
            XCTAssertNil(cap.before)
            XCTAssertNil(cap.after)
        }
    }

    func testCheckNeverClaimsATransformWithoutRunningIt() async {
        // The capability gate only says what COULD run; it must never populate before/after
        // dimensions as if a transform already happened.
        for effect in ProcessPath.Effect.allCases {
            let cap = await ProcessPath.check(effect: effect)
            XCTAssertNil(cap.before?.width, "check() must not fabricate a measured 'before' width")
            XCTAssertNil(cap.after?.width, "check() must not fabricate a measured 'after' width")
        }
    }

    func testEffectRawValuesAreStableContractStrings() {
        // These strings are part of the versioned JSON contract — the CLI/user matched on
        // them. Changing them is a breaking (≠ add-only) schema change.
        let raws = ProcessPath.Effect.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(raws, ["denoise", "frc", "superres"])
    }

    func testHardwareSoCIsNeverTheGate() async {
        // SoC name is informational (free text); even if it's nil we still have a coherent,
        // honest capability with a reason on the unsupported path.
        for effect in ProcessPath.Effect.allCases {
            let cap = await ProcessPath.check(effect: effect)
            if let soc = cap.soc {
                XCTAssertFalse(soc.isEmpty)
            } // nil soc is acceptable — never a gate
        }
    }
}
