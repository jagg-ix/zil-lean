# Zil DataScript Runtime Profile v0.1 (Draft)

## Purpose

This profile defines one concrete execution target for Zil using
DataScript (Clojure / ClojureScript Datalog engine).

It is a runtime profile, not the core language.
Core semantics remain backend-agnostic and are defined in:
- `spec/zil-v0.1r1.md`
- `spec/time-core-v0.1.md`

## Canonical Runtime IR

A conforming runtime adapter must lower source syntax into one of two IR records:

1. fact record

```clj
{:type :fact
 :object "app:svc1"
 :relation :depends_on
 :subject "service:db1"
 :attrs {:critical true}
 :revision 42
 :event :e42
 :op :assert}
```

2. causal edge record

```clj
{:type :before
 :left :e41
 :right :e42}
```

`type`, `relation`, `op`, `event`, `left`, `right` are keywords.
`object` and `subject` are scalar identity strings in this profile.

## Data Mapping

The DataScript profile maps IR fields to datoms:

- fact entity attributes:
  - `:zil/object`
  - `:zil/relation`
  - `:zil/subject`
  - `:zil/attrs`
  - `:zil/revision`
  - `:zil/event`
  - `:zil/op`
- causal edge attributes:
  - `:zil/event-left`
  - `:zil/event-right`

Composite tuple attributes are required in this profile:

- `:zil/fact-key = [:zil/object :zil/relation :zil/subject]`
- `:zil/fact-at-rev = [:zil/object :zil/relation :zil/subject :zil/revision]`
- `:zil/before-key = [:zil/event-left :zil/event-right]`

The tuple constraints provide:
- identity/upsert behavior for duplicate logical facts,
- deterministic keying for revisioned facts,
- identity of causal edges.

## Execution Semantics

### Rule Evaluation

Rule/query evaluation uses DataScript Datalog semantics.
Recursive reachability (for causal closure) is expressed as recursive rules.

### Snapshot Frontier

For `snapshot(frontier_revision)`:

1. select all fact rows where `revision <= frontier_revision`,
2. group by `(object, relation, subject)`,
3. keep max revision per group,
4. include row only if `op == :assert`.

This yields deterministic snapshot materialization from append-style updates.

### Causal Core

`before(e1, e2)` is represented by `:before` IR records and interpreted by:
- direct edge relation, plus
- transitive closure via recursive Datalog rules.

`concurrent(e1, e2)` iff neither `before(e1, e2)` nor `before(e2, e1)` holds.

## Time Profiles (Optional Overlay)

Clock representations are profile metadata only.
They must not redefine causal core truth.

Allowed overlays include:
- vector clock
- lamport
- hybrid logical clock
- relativistic coordinate profile

A conforming overlay:
1. never contradicts derived causal order,
2. remains deterministic,
3. preserves incomparability where causality is unknown.

## Zanzibar Compatibility Separation

Zanzibar concepts are not part of this runtime profile.
They are layered via `profiles/zanzibar-compat-v0.1.md`.

This keeps:
- core + runtime semantics general-purpose,
- Zanzibar semantics explicitly optional and separable.

## Conformance Checklist (Profile-Specific)

A DataScript-backed implementation is conformant to this profile if it:

1. accepts canonical runtime IR records above,
2. stores records with required tuple constraints,
3. computes snapshot frontier exactly as defined,
4. supports recursive causal closure query for `before*`,
5. keeps optional clock data observational (non-authoritative for causality).
