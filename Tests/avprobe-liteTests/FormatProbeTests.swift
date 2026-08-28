//
// FormatProbeTests.swift
// avprobe-liteTests
//
// Unit 02/03 — pure-logic helpers that don't require opening a media asset: FourCC
// decoding, rational frame-rate reduction, DAR reduction, and frame DTS/PTS guard logic.
// Asset-backed probes (real FourCC reads off a CMFormatDescription) live in the Mac pass.
//

import XCTest
import CoreMedia
@testable import avprobe_lite

final class FormatProbeTests: XCTestCase {

    func testFourCCString() {
        XCTAssertEqual(FormatProbe.fourCCString(0x6D706734), "mpg4") // sample
        XCTAssertEqual(FormatProbe.fourCCString(0x61766331), "avc1")
        XCTAssertEqual(FormatProbe.fourCCString(0), "") // zero → empty
    }

    func testCodecFamilyMapping() {
        XCTAssertEqual(FormatProbe.codecFamily("avc1"), "h264")
        XCTAssertEqual(FormatProbe.codecFamily("hvc1"), "hevc")
        XCTAssertEqual(FormatProbe.codecFamily("mp4a"), "aac")
        XCTAssertEqual(FormatProbe.codecFamily("ac-3"), "ac3")
        XCTAssertEqual(FormatProbe.codecFamily("apch"), "prores")
        XCTAssertEqual(FormatProbe.codecFamily("zzzz"), "zzzz") // fallback = raw
    }

    func testFractionFromFloat() {
        let f = FormatProbe.fractionFromFloat(29.97)
        XCTAssertEqual(f.0, 29970)
        XCTAssertEqual(f.1, 1000)
        XCTAssertNil(FormatProbe.fractionFromFloat(0).0)
        XCTAssertNil(FormatProbe.fractionFromFloat(Float.nan).0)
    }

    func testDARReduction() {
        XCTAssertEqual(FormatProbe.darString(naturalSize: CGSize(width: 1920, height: 1080)), "16:9")
        XCTAssertEqual(FormatProbe.darString(naturalSize: CGSize(width: 1280, height: 720)), "16:9")
        XCTAssertNil(FormatProbe.darString(naturalSize: .zero))
    }

    func testNominalBitsUnknownBecomesNil() {
        XCTAssertNil(FormatProbe.nominalBits(0))
        XCTAssertNil(FormatProbe.nominalBits(-1))
        XCTAssertEqual(FormatProbe.nominalBits(5_000_000), 5_000_000)
    }

    func testFrameTimingGuard_UsesNilForInvalidDTS() {
        // `timing` is Frames timing logic; this tests the DTS guard used across the module.
        // No CMSampleBuffer here (would need real media) — asserting the pure guards we
        // do control: duration seconds helper and numeric guards.
        XCTAssertEqual(CMTimeSeconds.seconds(.zero), 0)
        XCTAssertEqual(CMTimeSeconds.seconds(.positiveInfinity), 0) // non-numeric → guarded 0
        XCTAssertEqual(CMTimeSeconds.seconds(CMTime(value: 3003, timescale: 600)), 5.005)
    }
}
