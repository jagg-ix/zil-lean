# Proof token resolution

Proof tokens identify Lean declarations that a tool expects to use as checked evidence. Resolution links a token to current declaration metadata from a complete `zil.lean-events.v0.1` batch.

## Command

```bash
bin/zil-proof-tokens \
  examples/proof-tokens/tokens.json \
  examples/proof-tokens/lean-events.json \
  generated/proof-tokens/resolution.json
```

Equivalent invocation:

```bash
clojure -M:proof-tokens tokens.json lean-events.json resolution.json
```

The command returns zero only when every token resolves.

## Resolution requirements

A token resolves when exactly one Lean event has the requested declaration and:

- the event belongs to the requested module;
- the declaration kind matches when specified;
- `kernel_present` is true;
- `uses_sorry` is false;
- the event trust class is accepted by the token.

Successful results copy the declaration's current `type_fingerprint` and sorted dependency list.

## Result states

```text
resolved
missing
ambiguous
module_mismatch
kind_mismatch
kernel_missing
uses_sorry
trust_mismatch
```

Both input batches receive deterministic SHA-256 fingerprints in the result. These identify the exact token request and Lean declaration snapshot used for resolution.

## Trust boundary

A resolved token identifies a Lean declaration with acceptable kernel evidence. It does not assert that an external scientific or project claim is proved.

When a token includes a claim, the result records:

```text
claim_status = external_unproved
```

The Lean event batch must continue to contain:

```text
proved_claim = false
```

The declaration fingerprint may later be locked by the theorem statement-lock command. Token resolution itself does not compare a historical fingerprint.

## Validation

```bash
clojure -M:test
bin/zil-proof-tokens \
  examples/proof-tokens/tokens.json \
  examples/proof-tokens/lean-events.json \
  /tmp/proof-token-resolution.json
```
