# Zil Lang

Zil Lang (short name: Zil) is a declarative tuple-and-rule language for general knowledge modeling,
verification, and policy reasoning.

This repository now includes both:
- language design artifacts (normative specs), and
- an initial Clojure + DataScript runtime scaffold that executes core ideas.

## Scope and Architecture

ZIL core is domain-agnostic and general-purpose.

Current built-in declarations are IT-oriented because they are the primary
immediate use case in this repository, but they are layered above the core
tuple/rule semantics and do not define language boundaries.

The declaration layer includes an explicit external `PROVIDER` concept so
models can reference external systems/adapters (for example OpenTofu/HCL
providers) without hardwiring provider semantics into the core language.

## DataScript Leverage

We leverage the Clojure DataScript engine as a concrete runtime target:
- immutable in-memory DB values for snapshot-friendly semantics,
- Datalog query/rule execution as the primary evaluation model,
- tuple attributes and unique constraints for composite identity and integrity,
- direct support for recursive rules and stratified negation patterns.

See:
- `spec/runtime-datascript-profile-v0.1.md`
- `docs/datascript-leverage.md`
- `src/zil/runtime/datascript.clj`

## Quick Start (Clojure)

```bash
clojure -M -e "(require 'zil.runtime.datascript) (println :ok)"
```

Core engine load:

```bash
clojure -M -e "(require 'zil.core) (println :ok)"
```

Minimal usage:

```clj
(require '[zil.runtime.datascript :as zr])

(def conn (zr/make-conn))

(zr/transact-facts! conn
  [{:object "app:svc1"
    :relation :depends_on
    :subject "service:db1"
    :revision 1
    :event :e1}
   {:object "service:db1"
    :relation :available
    :subject "value:true"
    :revision 1
    :event :e1}])

(zr/facts-at-or-before @conn 1)
```

Run a `.zc` file through the core engine:

```bash
clojure -M -m zil.cli examples/it-infra-minimal.zc
```

Import HCL/OpenTofu descriptions into ZIL:

```bash
clojure -M -m zil.cli import-hcl path/to/infra/ [output.zc] [module_name]
./bin/zil import-hcl path/to/infra/ /tmp/infra-imported.zc hcl.import.infra
```

Import external JSON/YAML/CSV into generated ZIL facts:

```bash
./bin/zil import-data examples/data/interop-sample.json /tmp/interop_from_json.zc interop.import json
./bin/zil import-data examples/data/interop-sample.yaml /tmp/interop_from_yaml.zc interop.import yaml
./bin/zil import-data examples/data/interop-sample.csv /tmp/interop_from_csv.zc interop.import csv
```

Export model outputs in JSON/YAML/CSV:

```bash
./bin/zil export-data examples/interop-json-yaml-csv.zc json /tmp/zil_queries.json queries
./bin/zil export-data examples/interop-json-yaml-csv.zc yaml /tmp/zil_queries.yaml queries
./bin/zil export-data examples/interop-json-yaml-csv.zc csv /tmp/service_states.csv service_states
```

Generate Kubernetes/Helm compatibility macro layer + runnable example automatically:

```bash
python3 tools/generate_k8s_helm_compat.py
./bin/zil preprocess examples/k8s-helm-compat.zc /tmp/k8s_helm_compat.pre.zc libsets/k8s-helm-compat
./bin/zil /tmp/k8s_helm_compat.pre.zc
./tools/k8s_helm_compat_smoke.sh
```

Extract AWS whitepaper model inputs and run AWS compatibility smoke:

```bash
python3 tools/extract_aws_overview_model_inputs.py
./bin/zil examples/generated/aws-overview-model-inputs.zc
./tools/aws_overview_compat_smoke.sh
./tools/aws_extension_icons_smoke.sh
```



## Standalone Runtime (No Clojure CLI Needed)

Build once (requires Clojure tooling on build machine):

```bash
cd zil
./bin/build-jar
```

Run anywhere with Java only:

```bash
cd zil
./bin/zil examples/it-infra-minimal.zc
./bin/zil bundle-check examples lts
./bin/zil export-tla examples/quickstart-beginner.zc /tmp/quickstart_bridge.tla QuickstartBridgeFromZil
java -jar dist/zil-standalone.jar bundle-check examples/quickstart-beginner.zc lts
```

Notes:

- `./bin/zil` prefers `dist/zil-standalone.jar` when present.
- if jar is missing, it falls back to `clojure -M -m zil.cli`.
- if neither Java+jar nor Clojure is available, it prints a build hint.

Native host + WASM/JS screen automation modeling example:

```bash
./bin/zil examples/native-host-wasm-screen-automation.zc
./bin/zil bundle-check examples/native-host-wasm-screen-automation.zc lts
./bin/zil bundle-check examples/native-host-wasm-screen-automation.zc constraint
```

Declarative config macro-layer example:

```bash
./bin/zil preprocess examples/config-declarative-macros.zc /tmp/config.pre.zc libsets/config-declarative
./bin/zil /tmp/config.pre.zc
```

Transaction-level modeling (TLM) macro-layer example:

```bash
./bin/zil examples/tlm-domain-macros.zc
```

TLM formal backend bridge example (Z3/TLA+/Lean4):

```bash
./bin/zil bundle-check examples/tlm-formal-bridge.zc lts
./bin/zil bundle-check examples/tlm-formal-bridge.zc constraint
./bin/zil export-tla examples/tlm-formal-bridge.zc /tmp/tlm_bridge.tla TLMBridgeFromZil
./bin/zil export-lean examples/tlm-formal-bridge.zc /tmp/tlm_bridge.lean Zil.Generated.TLM
```

## Native Macro System

Portable ZIL annotations can be embedded in host-language comments and scanned
without compiling or rewriting the host source:

```lean
/-
@zil target=self
self#formalizes@claim:embedded_identity.
self#requires@assumption:natural_number.
@endzil
-/
theorem EmbeddedExample.identity (n : Nat) : n = n := rfl
```

```bash
clojure -M -m zil.cli embedded-scan \
  examples/embedded /tmp/embedded.zc embedded.example
```

The initial scanner recognizes `.lean`, `.py`, `.clj`/`.cljs`/`.cljc`, and
`.rs` declarations. `self` deterministically attaches to the first declaration
after the block; `@zil target=...` provides an explicit target. Output is
canonical compilable `.zc` plus source hashes, line spans, block identities,
and `trust:asserted_annotation`. The scanner never modifies host source and
accepts only canonical ground facts in this initial profile.

Embedded blocks may invoke the same pure language macros used by standalone
`.zc` files:

```text
@zil target=self
USE FORMAL_CLAIM(self, claim:embedded_identity).
@endzil
```

Macro libraries are discovered from the nearest `lib/` directory or selected
with the optional `lib_dir` CLI argument. Expansion uses the existing bounded
`Syntax → Syntax` macro engine: parameter substitution and recursive `USE` are
allowed, while I/O and host-code mutation are impossible. Each block records a
`macro_revision` SHA-256 digest so library changes are visible to later drift
validation.

Create a versioned drift baseline and validate it in CI:

```bash
clojure -M -m zil.cli embedded-snapshot \
  examples/embedded embedded-baseline.json

clojure -M -m zil.cli embedded-drift-check \
  examples/embedded embedded-baseline.json
```

`embedded-drift-check` exits successfully only when the baseline still matches.
It reports added/removed blocks and separately classifies `source_changed`,
`macro_changed`, `target_changed`, and `expansion_changed`. Block identity uses
the source path plus block ordinal, so unrelated line movement preserves the
identity while remaining visible through the source hash and line metadata.

Embedded macro invocations also receive deterministic host-aware bindings:

```text
self  file  module  namespace  project  revision
declaration_kind  source_span
```

These values are inert ZIL terms. For example, Lean input may resolve them to
`lean:Demo.answer`, `file:Acme/Demo.lean`,
`lean_module:Acme.Demo`, `lean_namespace:Demo`, and
`lean4_kind:theorem`. Named Lean namespace blocks are tracked when resolving
unqualified declarations.

Zil has its own language-level macro system (independent of Clojure macros):

```zc
MACRO link_pair(a,b):
EMIT {{a}}#connected_to@{{b}}.
EMIT {{b}}#connected_to@{{a}}.
ENDMACRO.

USE link_pair(location:dcA, location:dcB).
```

Rules:
- define with `MACRO name(params): ... ENDMACRO.`
- each body line is `EMIT ...`
- invoke with `USE name(args).`
- placeholders are `{{param}}`

## Current Status

- Core: Draft
- Time model: Draft (causal core + optional time profiles)
- Zanzibar compatibility profile: Draft
- DataScript runtime profile: Draft
