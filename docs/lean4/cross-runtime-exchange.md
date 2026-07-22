# Cross-runtime exchange

`Zil.Interop.ExchangeEnvelope` is the revisioned transport boundary between Lean and Clojure.

The `ZILX/1` line protocol carries:

- knowledge revision;
- active profile name and version;
- canonical facts;
- canonical Horn rules;
- explicit trust classes.

Both runtimes encode canonical relations as:

```text
rel<TAB>subject<TAB>relation<TAB>object
```

Rule payloads reuse the canonical multiline codec and are escaped inside the envelope. Unknown rows and malformed revisions are rejected.

Lean:

```lean
let text := Zil.Interop.encodeEnvelope envelope
let decoded ← Zil.Interop.decodeEnvelope text
```

Clojure:

```clojure
(def text (zil.exchange/encode-envelope envelope))
(def decoded (zil.exchange/decode-envelope text))
```

This protocol is data-only. It never transfers Lean proof terms or upgrades graph trust.

Lean remains pinned to `leanprover/lean4:v4.31.0`.