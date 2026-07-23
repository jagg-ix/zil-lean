# ZIL theorem statement locks v1

## Source

A lock baseline may be created only from a `zil.proof-token-resolution.v0.1` document whose every row has `resolved` status.

## Lock document

```json
{
  "format": "zil.theorem-locks.v0.1",
  "complete": true,
  "module": "Demo",
  "strict": true,
  "source_event_batch_fingerprint": "sha256:...",
  "source_token_batch_fingerprint": "sha256:...",
  "lock_count": 1,
  "locks": [{
    "token_id": "proof:answer",
    "declaration": "Demo.answer",
    "module": "Demo",
    "kind": "theorem",
    "type_fingerprint": "lean-hash:answer-v1"
  }],
  "document_fingerprint": "sha256:..."
}
```

Token IDs and declarations are unique. Every row belongs to the document module. `document_fingerprint` covers the canonical document body excluding the fingerprint field itself.

## Check states

```text
unchanged
fingerprint_changed
declaration_changed
module_changed
kind_changed
missing_token
current_unresolved
unexpected_token
additional_allowed
```

## Comparison order

For one locked token, checks are applied in this order:

1. current token exists;
2. current token remains resolved;
3. declaration name is unchanged;
4. row module is unchanged;
5. declaration kind is unchanged;
6. type fingerprint is unchanged.

This order gives one primary status per locked token.

## Strict sets

When `strict=true`, current token IDs absent from the lock document receive `unexpected_token` and fail the check.

When `strict=false`, they receive `additional_allowed`.

## Check report

```json
{
  "format": "zil.theorem-lock-check.v0.1",
  "ok": true,
  "module": "Demo",
  "strict": true,
  "lock_document_fingerprint": "sha256:...",
  "current_event_batch_fingerprint": "sha256:...",
  "current_token_batch_fingerprint": "sha256:...",
  "lock_count": 1,
  "current_token_count": 1,
  "unchanged": 1,
  "changed": 0,
  "status_counts": {"unchanged": 1},
  "failures": [],
  "results": [{
    "token_id": "proof:answer",
    "declaration": "Demo.answer",
    "status": "unchanged",
    "type_fingerprint": "lean-hash:answer-v1"
  }]
}
```

`:ok` is true exactly when there is no report-module change and every result is `unchanged` or `additional_allowed`.

## Meaning

A fingerprint change signals that Lean reports a different declaration type. The lock does not claim that unchanged type fingerprints imply unchanged proof terms, source text, or external scientific meaning.
