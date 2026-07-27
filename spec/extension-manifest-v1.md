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
  "entrypoint": "example.plugin/create",
  "capabilities": ["evidence-producer", "external-tool"],
  "requires": ["ZIL-EVIDENCE/1", "ZIL-EXTENSION/1"],
  "inputs": ["ZIL-EXCHANGE/1"],
  "outputs": ["ZIL-EVIDENCE/1"],
  "authority": "external",
  "trusted": false
}
```

Required fields:

- `schema` exactly `ZIL-EXTENSION/1`;
- globally stable `id` beginning with `extension:`;
- semantic `version`;
- `runtime`: `lean`, `clojure`, or `external`;
- runtime-specific `entrypoint`;
- sorted unique capability identifiers;
- sorted unique protocol or capability requirements;
- declared input and output schemas;
- `authority` from `lean`, `clojure`, `shared`, or `external`;
- Boolean `trusted`.

The registry normalizes arrays before fingerprinting, but a checked-in manifest SHOULD already use canonical sorted arrays.

## Runtime classes

### Lean extension

A Lean extension may provide syntax, checked declarations, proof-producing transformations, or verified decision procedures. Its entrypoint is a Lean module name.

`trusted=true` means that exact evidence may be checked by the configured Lean environment. It does not grant authority over unrelated capabilities.

Lean extensions are not dynamically loaded by the Clojure registry in version 1. They are configured through the Lean build and expose new compiled protocol capabilities.

### Clojure extension

A Clojure extension may provide connectors, storage adapters, external-tool runners, project scanners, report exporters, or scheduling policies.

It may create exchange requests and evidence envelopes. It may not return `validated` or `kernel-backed` on its own.

The version-1 dynamic registry loads only Clojure runtime extensions through `requiring-resolve`. The entrypoint resolves to a factory accepting:

```clojure
(extension-manifest config)
```

The result must implement `zil.plugin.api/Extension`.

A Clojure runtime extension may use `authority=external` when it is an adapter around an external producer. It may not use `authority=lean` or `authority=shared`.

### External extension

An external extension is executed through a declared adapter. Its result is externally attested evidence unless a Lean capability separately validates a statement derived from it.

An external runtime manifest must declare `authority=external`.

## SDK protocols

The stable version-1 protocols are:

- `Extension`;
- `Capability`;
- `EvidenceProducer`;
- `CommandProvider`;
- `StoreBackend`.

Every registered extension implements `Extension`. Other protocols are optional and capability-specific.

`Extension` lifecycle hooks are:

```text
extension-manifest
start-extension!
stop-extension!
```

A startup hook may return an updated extension value, but its capabilities and commands must remain identical to the pre-start contract.

## Admission

Registration is fail closed.

The registry verifies:

1. manifest schema, ID, semantic version, runtime, entrypoint, authority, and trust rules;
2. manifest fingerprint determinism;
3. every `requires` entry is available in the active runtime profile;
4. runtime-provided capabilities equal manifest capabilities exactly;
5. command authority equals manifest authority;
6. no command shadows any built-in or previously registered command;
7. no extension capability shadows an authoritative capability;
8. startup preserves the declared capabilities and command descriptors.

Commands and capabilities are published only after startup succeeds.

A requirement for `ZIL-EXCHANGE/1` or an exchange operation capability is available only when the registry has an active Lean worker pool. Ownership declarations alone do not imply runtime availability.

## Capability providers and replacement

Extension capabilities are provider interfaces, not necessarily singletons. Several active extensions MAY provide the same non-authoritative capability, such as:

```text
evidence-producer
repository-connector
report-exporter
```

The registry records a deterministic provider set for each such capability. Removing one extension removes only that provider and leaves the capability available while another active provider remains.

An extension capability MUST NOT reuse an authoritative capability ID from the ownership inventory. Replacing an existing authoritative capability requires:

1. a new capability identifier or protocol version;
2. an explicit migration policy;
3. conformance fixtures;
4. authority review;
5. deterministic failure semantics.

Command names remain unique because command dispatch must resolve to exactly one implementation. Silent command shadowing is forbidden.

## Isolation

The Clojure registry isolates failures and records extension identity and version on every result.

Lifecycle states include:

```text
starting
active
quarantined
removed
```

Startup, command, or evidence failure quarantines the extension. A quarantined extension may not serve additional commands, capabilities, output schemas, or evidence.

The Lean worker accepts only protocol operations compiled into its allowlist; it does not dynamically execute extension-supplied shell commands.

## Evidence

Evidence-producing extensions return `ZIL-EVIDENCE/1` envelopes.

The registry verifies:

- evidence schema;
- registered extension identity;
- manifest/evidence authority agreement;
- input and output digest forms;
- exact payload/output digest binding;
- assurance ceiling for the extension runtime.

See `spec/evidence-envelope-v1.md`.

## Determinism

Canonical manifest fields have explicit order. Capability, requirement, input, and output arrays are sorted and deduplicated before fingerprinting.

Runtime-local paths and timestamps are excluded from the canonical manifest fingerprint unless a future versioned extension contract explicitly requires them.
