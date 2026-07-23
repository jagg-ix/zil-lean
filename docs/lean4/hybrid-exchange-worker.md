# Hybrid Lean worker and Clojure client

The exchange worker gives the Clojure operational control plane a stable, allowlisted interface to Lean-authoritative ZIL capabilities.

## Start a persistent worker

```bash
bin/zil worker --stdio
```

The direct Lake form is:

```bash
lake exe zilWorker -- --stdio
```

Each standard-input line is one `ZIL-EXCHANGE/1` request. Each standard-output line is one response.

For one request:

```bash
bin/zil worker --once < examples/exchange/parse-request.json
```

The checked-in example uses a placeholder digest for readability. The Clojure client computes the actual input SHA-256 before sending a request.

## Clojure client

```clojure
(require '[zil.worker.client :as worker])

(def process (worker/start-worker!))

(def response
  (worker/invoke!
   process
   (worker/request
    {:operation "authorize"
     :input-path "examples/authorization/access.zc"
     :arguments ["doc:readme" "viewer" "user:11"]})))

(worker/stop-worker! process)
```

The client:

- computes SHA-256 over exact input bytes;
- starts or reuses a Lean worker;
- validates response schema, request identity, operation, input binding, and Lean authority;
- refuses a response that is already transport-attested;
- computes SHA-256 over exact payload bytes;
- never changes Lean semantic assurance, payload, or errors.

A command-line one-shot adapter is available through either form:

```bash
bin/zil exchange authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

```bash
clojure -M:exchange authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

## Bounded worker pool

```clojure
(require '[zil.worker.client :as worker]
         '[zil.worker.pool :as pool])

(def workers (pool/start-pool! {:size 4}))

(def response
  (pool/invoke!
   workers
   (worker/request
    {:operation "impact"
     :input-path "examples/impact/project.zc"
     :arguments ["lean:Parser.parse"]})))

(pool/stop-pool! workers)
```

The pool provides:

- a fixed concurrency bound;
- timeout-based acquisition;
- cleanup when partial startup fails;
- reuse of healthy workers;
- replacement of dead workers;
- deterministic shutdown of every supervised process.

## Initial operations

```text
parse
expand
query
authorize
impact
recovery-audit
```

Every operation has a compiled handler and a required capability token. The worker does not accept shell commands, executable paths, or dynamically supplied handlers.

## Status semantics

`status=ok` means that Lean evaluated the operation. It does not mean that authorization allowed, impact knew the node, or recovery was safe. Those are semantic values inside the deterministic payload.

`invalid`, `unsupported`, and `error` identify request or evaluation failures. A missing or malformed worker response is represented by the Clojure client as a transport error and is not converted into a semantic denial.

## Digest boundary

The initial worker validates the format and binding field of `input_sha256` but does not recompute it. The Clojure control plane owns file-byte attestation in version 1. Lean owns the semantic payload. This split is explicit in `spec/exchange-protocol-v1.md` and may be strengthened in a later version without changing capability ownership.
