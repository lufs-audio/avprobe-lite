//
// EnvelopeTests.swift
// avprobe-liteTests
//
// Unit 05 — the bplate JSON envelope shape. These are pure-logic tests (no AVFoundation
// needed at construct time) and run identically wherever the macOS-only module builds.
//

import XCTest
@testable import avprobe_lite

final class EnvelopeTests: XCTestCase {

    func testSuccessEnvelopeShape() throws {
        let model = SourceModel(
            schemaVersion: 1,
            durationS: 12.5,
            playable: true,
            video: nil,
            audio: nil
        )
        let json = Envelope.success(model)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["status"] as? String, "success")
        let inner = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(inner["schemaVersion"] as? Int, 1)
        XCTAssertEqual(inner["durationS"] as? Double, 12.5)
        XCTAssertEqual(inner["playable"] as? Bool, true)
        // video/audio omitted when nil (honest, not fabricated) — but Codable omits them
        // only when the type uses optional + synthesized encode; they decode as absent.
        XCTAssertNil(inner["video"])
        XCTAssertNil(inner["audio"])
    }

    func testErrorEnvelopeShape() throws {
        let json = Envelope.error(code: 5, message: "boom")
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["status"] as? String, "error")
        XCTAssertEqual(obj["code"] as? Int, 5)
        XCTAssertEqual(obj["message"] as? String, "boom")
    }

    func testEnvelopeIsSortedAndDeterministic() {
        // Homogeneous payload (heterogeneous literals can't infer a single Encodable).
        let payload: [String: Int] = ["z": 1, "a": 2]
        let json1 = Envelope.success(payload)
        let json2 = Envelope.success(payload)
        XCTAssertEqual(json1, json2, "same input must produce identical bytes")
        // Sorted keys: "a" appears before "z".
        let ia = json1.range(of: "\"a\"")!.lowerBound
        let iz = json1.range(of: "\"z\"")!.lowerBound
        XCTAssertLessThan(ia, iz)
    }
}
