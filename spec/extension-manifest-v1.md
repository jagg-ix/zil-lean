# ZIL extension manifest v1

## Scope

This specification describes extensions without granting them authority implicitly. Extensions may add operational integrations, evidence producers, commands, storage adapters, Lean syntax, or checked validators.

## Manifest

```json
{
  "schema": "ZIL-EXTENSION/1",
  "id": "extension:example",
  "version": "1.0.0",
  "runtime": "clojure",
  "entrypoint": "example.plugin/start",
  "capabilities": ["external-tool", "evidence-producer"],
  "requires": ["ZIL-EXCHANGE/1", "authorization-v1"],
  "inputs": ["ZIL-EXCHANGE/1"],
  "outputs": ["ZIL-EVIDENCE/1"],
  "authority": "external",
  "trusted": false
}
```

Required fields:

- `schema` exactly `ZIL-EXTENSION/1`;
- globally stable `id`;
- semantic `version`;
- `runtime`: `lean`, `clojure`, or `external`;
- runtime-specific `entrypoint`;
- sorted unique capability identifiers;
- sorted unique protocol or capability requirements;
- declared input and output schemas;
- `authority` from `lean`, `clojure`, `shared`, or `external`;
- Boolean `trusted`.

## Runtime classes

### Lean extension

A Lean extension may provide syntax, checked declarations, proof-producing transformations, or verified decision procedures. Its entrypoint is a Lean module name.

`trusted=true` means that exact evidence may be checked by the configured Lean environment. It does not grant authority over unrelated capabilities.

### Clojure extension

A Clojure extension may provide connectors, storage adapters, external-tool runners, project scanners, report exporters, or scheduling policies.

It may create exchange requests and evidence envelopes. It may not return `validated` or `kernel-backed` on its own.

### External extension

An external extension is executed through a declared adapter. Its result is externally attested evidence unless a Lean capability separately validates a statement derived from it.

## Capability replacement

An extension may add a new capability. Replacing an existing authoritative capability requires:

1. a new capability identifier or protocol version;
2. an explicit migration policy;
3. conformance fixtures;
4. authority review;
5. deterministic failure semantics.

Silent command shadowing is forbidden.

## Isolation

The Clojure registry must isolate failures and record extension identity on every produced request or evidence row. The Lean worker accepts only protocol operations compiled into its registry; it does not dynamically execute extension-supplied shell commands.

## Determinism

Manifest arrays are sorted before fingerprinting. Runtime-local paths and timestamps are excluded from the canonical manifest fingerprint unless the extension contract explicitly requires them.
