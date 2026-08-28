# Unit 05 — cli-envelope

## Objective

Assemble the full `avprobe-lite` CLI with `swift-argument-parser`, `--json`, the bplate
JSON envelope, and the exit-code floor (0/2/5).

## Context

- Wraps Units 01–04. Conformance: `lufs-audio/bplate` envelope + exit-code floor (phase
  `SPEC.md`).

## Acceptance criteria

- [ ] Subcommands wired: `info`, `streams`, `frames`, `process`, plus `--check`, `--json`,
      `--version`.
- [ ] `--json` wraps output in `{"status":"success","data":…}` / `{"status":"error","code":N,"message":…}`.
- [ ] Exit codes: `0` success (including honest unsupported, for `process --check`),
      `2` usage/missing input, `5` contract (a promised schema field not producible).
- [ ] Deterministic JSON; no ANSI color / wall-clock in `--json` output.
- [ ] `--version` prints `schema_version`.

## Interface contract

```
avprobe-lite <info|streams|frames|process> FILE [--json] [--count N] [--effect E] [--check] [--version]
```

Exit codes `0/2/5`; envelope as above.

## Boundaries — do NOT touch

- Unit 01–04 component internals.

## Output

- `Sources/avprobe-lite/CLI.swift` (argument-parser) + `Tests/` for exit-code matrix and
  envelope shape.

## Verification

- `swift test` green; missing file exits 2 with `status:error`.
