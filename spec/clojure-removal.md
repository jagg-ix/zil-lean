# Removal of the Clojure runtime

ZIL is Lean. The Clojure runtime that once sat beside it was removed from this repository. The last commit that still contained it is `bf130927edd3ecdad959173d1e63d59130864909`; everything below is recoverable from there with `git show bf13092:<path>`.

## Why

Lean already owned every semantic result (parse, compile, expand, conformance, query, authorization, impact, formalization, agent context, proof obligations, theorem audit, action tokens, token lifecycle, recovery audit). What Clojure still held was a second implementation of the language for comparison, plus orchestration around the Lean commands. Comparing with a second implementation fixed the answers to that implementation's lossy spellings (a name such as `namespace` came back as `namespace_`, a quoted value lost its quotes), and keeping both meant two toolchains to install, test and trust.

## What replaced what

| Removed | Use instead |
|---|---|
| `bin/zil-legacy`, `--legacy`, the standalone JAR, `zil.cli` | the native commands in `bin/zil --help` |
| `macro-compile`, `macro-expand` | `bin/zil compile` and `bin/zil expand` with `--lib DIR` |
| `macro-parity`, `tools/macro_extension_matrix.sh --legacy-parity` | `tools/macro_extension_matrix.sh`: native expansion against a reviewed golden in `spec/macro-extension-golden/`, then native compile and a Lean typecheck |
| `library --check`, `conformance-suite` | `bin/zil corpus` (`scripts/check-corpus.sh`): every `.zc` file compiled alone, compared with `spec/corpus-status.tsv` |
| the port gate and retirement report (`port-gate.edn`, `legacy-retirement.edn`) | nothing: they measured agreement with the removed runtime |
| `clojure -M:test` and the Clojure test profiles | `bin/zil test --profile lean`, including `scripts/check-no-clojure.sh` |
| the tuple exporter (`tuple-lean`) | `bin/zil compile` |
| `export-snapshot` of a model | none; `bin/zil snapshot` still replays an existing `.zilr` revision log |
| the Soufflé bridge and Soufflé parity | none; `libsets/souffle-compat` keeps the macros |

## Removed without a replacement

These were operational features of the Clojure runtime, not part of the language. Nothing in this repository used them in its own checks.

- the formal control plane (`exchange`, `control`), worker supervision and the worker pool, with the SQLite event store and its hash-chained control events and receipts (`control-store`), and the workflow projection;
- the extension registry and plugin loader (`plugin`, `ZIL-EXTENSION/1`) and its four reference extensions;
- runtime architecture evaluation (`evaluate-runtime`) and the capability ownership map;
- release attestation, proof tokens and theorem locks, the workflow runner, `verify-generated`;
- embedded ZIL blocks (`embedded-native`, the `@zil` annotation scan), library and embedded manifests;
- the DataScript runtime and its REST, command, file and Cucumber adapters, and the HCL, TLA, vstack, Lean 4 delta and Z3 profile bridges;
- the LTS-atom Lean exporter (`export-lean`). The generated modules in `examples/lean4-integration/generated/` remain as written.

The Lean exchange worker (`bin/zil worker`, `ZIL-EXCHANGE/1`) stays: it is Lean, and a client of any language can drive it. The caller computes the SHA-256 of the input bytes and of the result payload; the worker validates and carries the input digest.

## Keeping it removed

`scripts/check-no-clojure.sh` fails when a Clojure or EDN file is tracked, or when a tool, script, build file or container file calls Clojure, selects a deps alias, or reaches for a removed entry point. It runs in the `lean` test profile.
