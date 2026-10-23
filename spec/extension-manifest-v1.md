# ZIL extension manifest v1

## Scope

Extensions add operational integrations, evidence producers, commands and storage adapters to a Lean-owned core. They
never receive authority implicitly: the manifest declares the authority an extension claims, and the registry admits
the extension only if everything it does stays within it. `zilPlugin` lists, inspects, runs and asks evidence from
extensions.

## Manifest

```json
{
  "schema": "ZIL-EXTENSION/1",
  "id": "extension:example",
  "version": "1.0.0",
  "runtime": "external",
  "entrypoint": "example-extension.sh",
  "capabilities": ["evidence-producer", "external-tool"],
  "requires": ["ZIL-EVIDENCE/1", "ZIL-EXTENSION/1"],
  "inputs": ["ZIL-EXCHANGE/1"],
  "outputs": ["ZIL-EVIDENCE/1"],
  "authority": "external",
  "trusted": false
}
```

Validation fails closed:

- `schema` exactly `ZIL-EXTENSION/1`; `id` begins with `extension:`; `version` is semantic (`1.2.3`, optional `-pre`/`+build`);
- `runtime` is `lean` or `external`; `entrypoint` is not blank;
- `authority` is `lean`, `shared`, `operational` or `external`;
- an `external` runtime must declare `external` authority; an `operational` extension cannot be `trusted`;
- `trusted=true` is only for a `lean` runtime, and only a trusted extension can claim `lean` or `shared` authority.

The capability, requirement, input and output arrays are sorted and de-duplicated before the manifest is written
canonically (field order as above, `/` not escaped); the fingerprint is the SHA-256 of those bytes.

## Runtimes

**Lean.** The entrypoint names an extension compiled into the program: `repository-scanner`, `report-exporter`,
`external-solver`, `sqlite-event-store`. `trusted=true` means exact evidence may be checked by the configured Lean
environment; it does not grant authority over unrelated capabilities. A manifest cannot load new Lean code; new Lean
extensions are added by building them in.

**External.** The entrypoint is a command and its arguments, run without a shell, with the manifest's directory as the
working directory (a program inside that directory takes precedence over `PATH`). It speaks JSON: one request on its input,
one document on its output, a non-zero exit being a failure.

```text
{"op": "describe"}                                            -> {"capabilities": [...], "commands": {name: {"summary", "arguments"}}, "evidence": true|false}
{"op": "invoke", "command": c, "arguments": [...], "config": {...}}  -> any JSON
{"op": "evidence", "request": {...}, "config": {...}}          -> a part, or an array of parts {role, subject, input_sha256, payload, metadata}
```

The runtime of an external extension is declared `external` and its evidence is externally attested.

## Admission

Registration is fail closed. The registry verifies, in order:

1. the manifest, as above, and a deterministic fingerprint;
2. every `requires` entry is available in the active profile (`ZIL-EXCHANGE/1` and exchange operations only with a worker);
3. the capabilities the extension provides equal the manifest's exactly;
4. each command's authority equals the manifest's;
5. no command shadows a built-in or previously registered command;
6. no extension capability reuses an authoritative capability id of the ownership inventory;
7. startup preserves the declared capabilities and command descriptors.

Commands and capabilities are published only after startup succeeds. Several extensions may provide the same
non-authoritative capability; the registry keeps a deterministic provider set, and removing one provider leaves the others.
Command names are unique: command dispatch resolves to exactly one implementation.

## Isolation and evidence

Lifecycle states: `starting`, `active`, `quarantined`, `removed`. A failure at startup, in a command or while producing
evidence quarantines the extension: it serves no further commands, capabilities or evidence, and nothing it produced is
published. Every result records the extension's id and version.

Evidence-producing extensions return `ZIL-EVIDENCE/1` envelopes. The registry checks the schema, the registered identity,
that manifest and evidence agree on authority, the input and output digest forms, the exact binding of payload digest to
output, and the assurance ceiling of the extension's authority. See `spec/evidence-envelope-v1.md`.

## Reference extensions

`extensions/reference/` holds one manifest each for the four compiled-in extensions; `examples/extensions/` shows an
external extension (a shell program) and the request and report files it uses.

## Differences from the earlier implementation

The earlier registry loaded `clojure` runtime extensions by name; that runtime and the `clojure` authority are gone, and a
manifest that declares either is refused with a message that says so. A program that makes no semantic claim declares
`operational` authority.
