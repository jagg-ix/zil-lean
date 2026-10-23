# ZIL Lean

ZIL is a small relational language for describing  objects, the relationships between them, and rules that derive additional relationships.

Developers, review tools, CI, documentation tools, and AI assistants can query the same stored relationships.

## Quick start


```bash
git clone https://github.com/jagg-ix/zil-lean
cd zil-lean
lake build        # the library and its tests
lake build zil    # the command-line tool used below
```

The first build compiles the whole library and took about a minute on a laptop. While it builds, Lean prints deprecation warnings for
the library's source code. They do not affect the result.


## Relation tuples: from Zanzibar to ZIL

ZIL's relation model is influenced by the tuple-oriented model described in Google's Zanzibar paper:

[Zanzibar: Google's Consistent, Global Authorization System (USENIX ATC '19)](https://storage.googleapis.com/gweb-research2023-media/pubtools/5068.pdf)

Section 2.1 represents an authorization tuple as:

```text
object#relation@user
```

Table 1 gives these examples:

```text
doc:readme#owner@10
group:eng#member@11
doc:readme#viewer@group:eng#member
doc:readme#parent@folder:A#...
```

They describe four useful relation patterns:

```text
user 10 is an owner of doc:readme
user 11 is a member of group:eng
members of group:eng are viewers of doc:readme
doc:readme is in folder:A
```

The third tuple uses the userset:

```text
group:eng#member
```

This userset names everyone related to `group:eng` through `member`. A tuple can therefore refer to another relation, supporting group membership and inherited access.

The `.zc` syntax expresses the same tuples:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

The native Lean syntax expresses the same relations as Lean declarations:

```lean
import Zil

zil_fact
  node(doc.readme)
    ⟶[owner]
  node(user.u10)

zil_fact
  node(group.engineering)
    ⟶[member]
  node(user.u11)

zil_fact
  node(doc.readme)
    ⟶[viewer]
  node(group.engineering)
```

Zanzibar uses relation tuples to describe authorization data. ZIL uses the same compact relational building blocks for authorization models and for wider project relationships:

```text
document ───── viewer ──────▶ group
declaration ── implements ──▶ requirement
theorem ────── validates ────▶ component
module ─────── dependsOn ────▶ module
task ───────── blockedBy ────▶ issue
claim ──────── supportedBy ──▶ document
```

## Lean and ZIL in one project

ZIL stores relationships, dependencies and implements its own macro system that allows you to extend it with your own DSL 
extensions to the language so you can leverage lean4 powers.

Together they support questions such as:

- Which declaration implements a requirement?
- Which theorem validates a transformation?
- Which modules depend on a changed declaration?
- Which claims have supporting documents?
- Which work items are waiting for a result?
- Which advertised capabilities have implementation links?
- Which facts and rules produced an inferred relationship?
- Which project assumptions changed since the previous work session?

These relationships can connect Lean declarations to requirements, documents, issues, tests, tools, and external sources across many modules.


## Sharing the relationship graph between people and tools

ZIL stores selected project facts with the source code. Developers, reviewers, build tools, documentation tools, issue trackers, and AI
assistants can use the same graph.

### Explain derived relations

Each derived relation records its provenance:

```text
the rule that produced it
the variable bindings
the identifiers of the input facts
```

`bin/zil explain-query` prints this derivation step by step, so developers and tools can see how the engine reached a result
(`spec/derivation-provenance-v1.md`).


## Use cases

ZIL Lean can support:

- links from informal claims to Lean declarations;
- requirement-to-implementation tracking;
- theorem and component dependency analysis;
- change-impact queries across modules;
- evidence and source tracking;
- repository coverage checks;
- explicit task contracts for people and tools;
- AI assistants continuing work across sessions, guarded by revision and action-token checks;
- step-by-step explanations for inferred project relationships;
- interchange with Terraform/OpenTofu and TLA+ models.


## Macro libraries

The macro engine and the nearest-`lib/` rule are part of this repository. The opt-in macro libraries (`libsets/`: model substrate,
process algebra, proof evidence, discovery API, AWS, Souffle compatibility and others) live in
[zil-lib](https://github.com/jagg-ix/zil-lib). That repository depends on this one at a pinned commit, tests each library against
reviewed golden files, and keeps a catalog. Load a library with `--lib`:


```bash
bin/zil expand model.zc - --lib <zil-lib>/libsets/process-algebra
```

The last commit of this repository that still holds `libsets/` is tagged `last-with-libsets`.

A keyword value written with a leading colon, such as `move=:N`, is read as the name without the colon, so the Petri-net layer in
`examples/petrinet-nd-macro-layer.zc` compiles natively.



## License

[Apache License 2.0](LICENSE). A contribution is accepted under the same terms (section 5 of the license). The macro libraries that used
to live here are in [zil-lib](https://github.com/jagg-ix/zil-lib), under the same license.
