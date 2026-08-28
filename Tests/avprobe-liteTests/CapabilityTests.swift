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

import XCTest
@testable import avprobe_lite

final class CapabilityTests: XCTestCase {

    func testCheckAlwaysReturnsAWellFormedCapability() async {
        let cap = await ProcessPath.check()
        // Every effect we know of is covered; the capability must carry an effect + os + applied.
        XCTAssertEqual(cap.os, ProcessPath.requiresOS)
        XCTAssertFalse(cap.applied.isEmpty)
        // Honesty invariant: if unsupported there IS a reason; if supported we applied something.
        if cap.supported {
            XCTAssertNil(cap.reason)
            XCTAssertEqual(cap.applied, "capability present (no asset decoded)")
        } else {
            XCTAssertNotNil(cap.reason, "unsupported must carry an honest reason")
        }
    }

    func testEffectMappingNeverClaimsWithoutReadingAMeasurement() {
        // A source with no video track → superres has nothing to measure → before/after
        // widths are nil, and applyEffectMapping still reports a reason rather than a guess.
        let bare = SourceModel(schemaVersion: 1, durationS: 0, playable: true, video: nil, audio: nil)
        let cap = ProcessPath.applyEffectMapping(bare, effect: .superres)
        XCTAssertTrue(cap.supported)
        XCTAssertNotNil(cap.reason)
        XCTAssertNil(cap.before?.width)
        XCTAssertNil(cap.after?.width)
    }

    func testSuperresDoublesReportedResolutionDeterministically() {
        let video = VideoStream(codec: "h264", codecFourCC: "avc1",
                                width: 1920, height: 1080,
                                fpsNum: 30000, fpsDen: 1000,
                                sar: nil, dar: "16:9",
                                pixFmt: "420f", colorPrimaries: "ITU_R_709_2",
                                bitRateBPS: 5_000_000, startS: 0, endS: 10)
        let model = SourceModel(schemaVersion: 1, durationS: 10, playable: true, video: video, audio: nil)
        let cap = ProcessPath.applyEffectMapping(model, effect: .superres)
        XCTAssertEqual(cap.before?.width, 1920)
        XCTAssertEqual(cap.before?.height, 1080)
        XCTAssertEqual(cap.after?.width, 3840)
        XCTAssertEqual(cap.after?.height, 2160)
        XCTAssertEqual(cap.applied, "VTFrameProcessor.superResolution")
    }
}
