# Formal control plane and extension SDK

## Completed phases

This architecture implements the next two layers above `ZIL-EXCHANGE/1`.

### Phase 3: formal Clojure control plane

The control plane preserves Clojure's workspace, corpus, persistence, and process strengths while requiring Lean-authoritative semantic operations to pass through the exchange worker.

### Phase 4: extension SDK and registry

The extension SDK adds manifest-driven operational capabilities without permitting plugins to shadow the semantic kernel.

## Control-plane lifecycle

```clojure
(require '[zil.control.runtime :as control]
         '[zil.control.command :as command])

(def plane (control/start! {:pool-size 2}))

(def response
  (command/execute!
   plane
   "authorize"
   "examples/authorization/access.zc"
   ["doc:readme" "viewer" "user:11"]))

(control/stop! plane)
```

Startup performs:

1. load `architecture/capability-ownership.edn`;
2. validate schema, authorities, assurance labels, duplicate IDs, and duplicate operations;
3. compare every exchange operation with its declared Lean capability;
4. start the bounded Lean worker pool;
5. publish a nonreplaceable built-in command table.

A semantic response with `status` other than `ok` is not a transport error. `zil.control.runtime/payload!` raises a separate `semantic-operation-error` when a caller explicitly requires a successful authoritative payload.

## Port-tool adapters

Existing Clojure planners remain responsible for:

- nearest-library discovery and source composition;
- recursive source inventory;
- output namespace planning;
- atomic generated-file writes;
- stale-output handling;
- embedded host scanning;
- external elaboration of generated Lean files;
- differential report comparison.

The default semantic execution path is replaced with control-plane requests for:

```text
compile
expand
conformance
```

This covers:

```bash
bin/zil macro-compile ...
bin/zil macro-expand ...
bin/zil macro-parity ...
bin/zil library ...
bin/zil conformance-suite ...
bin/zil embedded-native ...
```

Injected runner hooks are retained for isolated tests and explicit external verification. They do not become a second semantic authority.

## Extension SDK

The SDK protocols are:

```text
Extension
Capability
EvidenceProducer
CommandProvider
StoreBackend
```

An extension may implement only the protocols it needs, except every registered extension must implement `Extension`.

### Registration

Registration is atomic with respect to command and capability publication:

1. validate and fingerprint the manifest;
2. compare manifest capabilities with runtime-provided capabilities;
3. check protocol requirements;
4. reject built-in and extension-to-extension collisions;
5. mark the extension `starting`;
6. invoke its startup hook;
7. publish commands and capabilities only after successful startup;
8. mark it `active`.

Startup failure leaves the extension quarantined and publishes no command.

### Invocation isolation

A command or evidence exception:

- records extension identity and error data;
- marks the extension `quarantined`;
- fails the current invocation;
- prevents later calls through the quarantined entry.

Registry shutdown invokes extension stop hooks and removes their command and capability registrations.

## Manifest commands

```bash
bin/zil plugin list extensions
bin/zil plugin inspect extensions/reference/repository-scanner/extension.json

bin/zil plugin run \
  extensions/reference/repository-scanner/extension.json \
  repository-scan .
```

Extension-specific configuration is supplied as EDN:

```bash
bin/zil plugin run \
  extensions/reference/external-solver/extension.json \
  solver-run z3 model.smt2 \
  --config solver-config.edn
```

Evidence requests are EDN maps interpreted by the selected extension:

```bash
bin/zil plugin evidence \
  extensions/reference/repository-scanner/extension.json \
  scan-request.edn
```

## Reference extensions

### Repository scanner

Produces a deterministic, sorted file inventory with byte counts and SHA-256 values. `.git`, `.lake`, and `target` are excluded by default.

Outputs:

```text
ZIL-REPOSITORY-SCAN/1
ZIL-EVIDENCE/1
```

### External solver

Runs only an allowlisted vector command. It does not invoke a shell. `{input}` tokens in the configured command vector are replaced by the input path.

It records:

- tool identity;
- exact command vector;
- input SHA-256;
- exit code;
- stdout and stderr bytes and hashes;
- timeout failures.

Its evidence remains `externally-attested`.

### Report exporter

Reads EDN or JSON and writes deterministic JSON or EDN using atomic replacement. Nested map keys and set values are canonicalized before output.

Outputs:

```text
ZIL-REPORT-EXPORT/1
ZIL-EVIDENCE/1
```

## Security and authority rules

- Built-in commands cannot be shadowed.
- Existing authoritative capability IDs cannot be reused by an extension.
- A Clojure extension cannot claim Lean or shared authority.
- A Clojure extension cannot emit `validated` or `kernel-backed` evidence.
- An external process result is not automatically a Lean theorem or ZIL authorization decision.
- Plugin discovery is deterministic; manifests are ordered by canonical path.
- Manifest and evidence fingerprints exclude timestamps and runtime-local process identifiers.
