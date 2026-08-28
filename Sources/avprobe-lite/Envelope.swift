//
// Envelope.swift
// avprobe-lite
//
// The bplate JSON envelope. All `--json` output is wrapped here:
//
//   success:  {"status":"success","data":…}
//   error:    {"status":"error","code":N,"message":…}
//
// Deterministic: no ANSI color, no wall-clock, no host name, no UUIDs — a given
// input yields the same bytes on every run. Envelope keys and order are fixed.
//

import Foundation

public enum Envelope {
    public static func success<T: Encodable>(_ data: T) -> String {
        struct StdOut<T: Encodable>: Encodable {
            let status = "success"
            var data: T
        }
        return Self.json(StdOut(data: data))
    }

    public static func error(code: Int32, message: String) -> String {
        struct Err: Encodable {
            let status = "error"
            var code: Int
            var message: String
        }
        return Self.json(Err(code: Int(code), message: message))
    }

    static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        // Sorted keys → the same logical object always serializes to the same
        // byte order. Doubles use Swift's default shortest round-trip form,
        // which is deterministic run-to-run for a given binary.
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            // Should not happen for Codable structs; keep the envelope guaranteed.
            return #"{"status":"error","code":5,"message":"encoding failure"}"#
        }
    }
}
