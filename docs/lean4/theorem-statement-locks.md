# Theorem statement locks

Theorem locks detect changes to the checked statement identified by a resolved proof token. The lock compares declaration identity and Lean's `type_fingerprint`; it does not hash source formatting or proof implementation text.

## Create a baseline

First resolve proof tokens:

```bash
bin/zil-proof-tokens \
  examples/proof-tokens/tokens.json \
  examples/proof-tokens/lean-events.json \
  generated/proof-tokens/resolution.json
```

Then create the lock file:

```bash
bin/zil-theorem-locks create \
  generated/proof-tokens/resolution.json \
  theorem-locks.json
```

Baseline creation requires every token to have `resolved` status and every resolved declaration to have a nonempty type fingerprint. Multiple tokens cannot lock the same declaration.

## Check current declarations

Resolve the same token set against the current Lean event batch, then run:

```bash
bin/zil-theorem-locks check \
  theorem-locks.json \
  generated/proof-tokens/current-resolution.json \
  generated/proof-tokens/lock-check.json
```

The command returns nonzero when a lock changes.

## Drift classes

```text
fingerprint_changed
declaration_changed
module_changed
kind_changed
missing_token
current_unresolved
unexpected_token
```

`fingerprint_changed` means the declaration's checked type changed while its token and declaration name remained the same.

## Strict and extensible locks

New lock files use:

```json
"strict": true
```

Strict mode rejects newly introduced proof tokens as `unexpected_token`. An intentionally extensible lock file may use `strict=false`; additional current tokens then receive `additional_allowed` and do not fail the check.

## Lock integrity

Each lock document includes `document_fingerprint`, computed from its complete canonical JSON body. Validation rejects:

- modified lock fields without a matching document fingerprint;
- duplicate token IDs;
- duplicate declarations;
- lock rows from another module;
- empty identity, kind, or fingerprint fields;
- partial lock files.

## Scope

The lock protects theorem statement identity as represented by Lean declaration metadata. It does not freeze:

- proof term implementation details when the theorem type is unchanged;
- source whitespace or comments;
- external project or scientific claims;
- arbitrary declarations that have no resolved proof token.

## Validation

```bash
clojure -M:test
```
