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
| the Soufflé bridge and Soufflé parity | none; `libsets/souffle-compat` in zil-lib keeps the macros |

## Rewritten in Lean

These operational features were first removed and then rewritten as Lean executables. Each was checked against the removed implementation: its outputs were produced from the same inputs and the Lean tool must reproduce them (byte for byte where the output is text, as data where it is a report), and the gate that checks this does not run Clojure.

| Feature | Command | Specification |
|---|---|---|
| the formal control plane (`exchange`, `control`), worker supervision and the worker pool, the SQLite event store and its hash-chained events and receipts (`control-store`), the workflow projection | `bin/zil control` | `spec/control-event-store-v1.md`, `spec/exchange-protocol-v1.md` |
| the extension registry and plugin loader (`plugin`, `ZIL-EXTENSION/1`) and its four reference extensions | `bin/zil plugin` | `spec/extension-manifest-v1.md` |
| runtime placement evaluation (`evaluate-runtime`) | `bin/zil evaluate-runtime` | `spec/runtime-evaluation-v1.md` |
| release attestation | `bin/zil release-attest` | `spec/release-attestation-v1.md` |
| embedded ZIL blocks (`embedded-scan`, `embedded-snapshot`, `embedded-drift-check`, `embedded-native`) | the same names | `spec/embedded-blocks-v1.md` |
| the DataScript runtime's ingest side: the REST, command, file and Cucumber adapters, the format codecs, vector clocks and causal edges, the revision store | `bin/zil ingest`, `import-data`, `convert-data` | `spec/datasource-ingest-v1.md` |
| the HCL importer, the TLA+ bridge, the LTS-atom Lean exporter | `bin/zil import-hcl`, `export-tla`, `export-lean` | `spec/interop-v1.md` |

Differences that matter, all stated in the specifications: the control, plugin and embedded manifests are JSON where they were EDN (EDN input is still read); there is no `clojure` runtime or authority for an extension (`operational` is a program that makes no semantic claim); HTTP is done with `curl`; EDN keywords are read as their names; a term that would not parse as ZIL source is double-quoted in generated facts.

## Removed without a replacement

These were not part of the language, or were part of the second implementation. Nothing in this repository used them in its own checks.

- the DataScript query translation and native inference (`execute-with-native-datascript`): the Lean engine is the evaluator, and `bin/zil query-ci`, `trace` and `explain-query` are its interface;
- `export-data` (a model's query results as JSON, YAML or CSV), which needed the second evaluator and its spellings of names; `bin/zil convert-data` writes a data file in another format;
- proof tokens and theorem locks, the workflow runner, `verify-generated`, library manifests;
- the vstack, Lean 4 delta and Z3 profile bridges.

The Lean exchange worker (`bin/zil worker`, `ZIL-EXCHANGE/1`) stays: it is Lean, and a client of any language can drive it. The caller computes the SHA-256 of the input bytes and of the result payload; the worker validates and carries the input digest.

## Keeping it removed

`scripts/check-no-clojure.sh` fails when a Clojure or EDN file is tracked, or when a tool, script, build file or container file calls Clojure, selects a deps alias, or reaches for a removed entry point. It runs in the `lean` test profile. The test inputs that are themselves Clojure or EDN host files are stored with a `.sample` suffix and copied into place by the gate that uses them.
