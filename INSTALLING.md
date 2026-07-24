# Installing and Using ZIL

This guide covers the supported ways to install and run ZIL from this repository.

ZIL is deliberately hybrid:

- **Lean 4** is the authoritative semantic and verification kernel.
- **Clojure/JVM** provides the operational control plane, corpus tooling, extension registry, external-tool adapters, and byte attestation.
- A **Lean-only installation** remains supported for native parsing, compilation, queries, authorization, safety checks, and direct use from Lean projects.

## Installation profiles

Choose the smallest profile that provides the commands you need.

| Profile | Required software | Provides |
|---|---|---|
| Lean SDK | Git, curl, Elan/Lean | Native library, compiler, parser, query engine, authorization, provenance, impact, safety and audit commands |
| Full workbench | Lean SDK, Java, official Clojure CLI | Formal control plane, macro-library discovery, recursive corpus tooling, conformance suites, embedded compilation, plugins, persistence and external integrations |
| Extension-only operational profile | Java, official Clojure CLI | Extensions that do not require Lean, such as repository scanning and report export |
| Legacy compatibility | Full workbench, or Java plus a built standalone JAR | Explicit access to the older Clojure CLI through `--legacy` |

External proof tools such as Z3, TLAPS, or ACL2 are optional and are not installed by ZIL.

## Supported environments

The repository launcher, `bin/zil`, is a Bash script.

- **Linux:** supported through a normal Bash environment.
- **macOS:** supported through Terminal with Bash or Zsh invoking the Bash launcher.
- **Windows:** WSL 2 is the recommended environment for the complete workbench and `bin/zil`.
- **Native Windows:** Lean and Clojure can be installed natively, but use direct `lake exe ...` and `clojure -M:...` commands unless a compatible Bash environment is available.

## Prerequisites

### Git and curl

Verify that both commands are installed:

```bash
git --version
curl --version
```

Installation information:

- Git: <https://git-scm.com/install/>
- Lean prerequisites and manual installation: <https://lean-lang.org/install/manual/>

### Install Lean with Elan

Elan is the Lean toolchain manager. From Linux, macOS, WSL, or another compatible POSIX shell:

```bash
curl https://elan.lean-lang.org/elan-init.sh -sSf | sh
source "$HOME/.elan/env"
```

Verify the installation:

```bash
elan --version
lean --version
lake --version
```

The repository contains `lean-toolchain` and currently pins:

```text
leanprover/lean4:v4.31.0
```

Do not manually replace the project toolchain with a different Lean version. When a command is executed inside the repository, Elan selects and installs the pinned version as needed.

For native Windows PowerShell, follow the Lean installation page or use:

```powershell
curl -O --location https://elan.lean-lang.org/elan-init.ps1
powershell -ExecutionPolicy Bypass -f elan-init.ps1
del elan-init.ps1
```

Close and reopen the terminal after installation.

### Install Java for the full workbench

Clojure requires Java. A current LTS JDK such as Java 17 or Java 21 is recommended.

Verify Java:

```bash
java --version
```

One cross-platform OpenJDK distribution is Eclipse Temurin:

<https://adoptium.net/>

### Install the official Clojure CLI

ZIL uses `deps.edn` aliases such as `-M:test`, `-M:control`, and `-M:plugins`. Install the **official Clojure CLI / tools.deps**, not only a bare Clojure JAR or a package that lacks `-M` and `-Sdescribe` support.

Verify the CLI:

```bash
clojure -Sdescribe
```

Official instructions:

<https://clojure.org/guides/install_clojure>

#### macOS with Homebrew

Install Java first, then:

```bash
brew trust clojure/tools
brew install clojure/tools/clojure
```

#### Linux

Install Java, Bash, curl, and `rlwrap`, then use the official installer:

```bash
curl -L -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh
chmod +x linux-install.sh
sudo ./linux-install.sh
rm linux-install.sh
```

For other POSIX systems, the official Clojure guide also provides `posix-install.sh`.

#### Windows

For the complete ZIL workbench, install WSL 2 and follow the Linux instructions inside WSL.

Native Windows users may install the Clojure CLI through the Windows installer described in the official Clojure guide. The repository Bash launcher may still require WSL or another Bash environment.

## Clone the repository

```bash
git clone https://github.com/jagg-ix/zil-lean.git
cd zil-lean
```

All commands below assume the current directory is the repository root.

## Build the Lean package

```bash
lake build
```

The first invocation may download the pinned Lean toolchain and build artifacts.

Run the native Lean validation target:

```bash
lake exe zilLeanTests
```

For the full workbench, resolve the Clojure dependency graph:

```bash
clojure -Spath >/dev/null
```

Run the Clojure test suite when validating a development checkout:

```bash
clojure -M:test
```

## Verify the installation

Display the public command surface:

```bash
bin/zil --help
```

If executable permissions were lost while copying the repository:

```bash
chmod +x bin/zil bin/zil-legacy bin/build-jar
```

Compile the checked-in authorization example to standard output:

```bash
bin/zil compile examples/authorization/access.zc -
```

Evaluate an authorization request:

```bash
bin/zil authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

The installation is operational when the Lean build succeeds and these native commands run.

## Optional shell command

`bin/zil` determines the repository root from its own file location. Do not copy the script to another directory, and do not rely on a symlink that changes the apparent script path.

Instead, add a shell function to `~/.bashrc` or `~/.zshrc`:

```bash
export ZIL_HOME="$HOME/src/zil-lean"
zil() {
  "$ZIL_HOME/bin/zil" "$@"
}
```

Adjust `ZIL_HOME` to the actual checkout location, then reload the shell:

```bash
source ~/.bashrc
```

or:

```bash
source ~/.zshrc
```

You can then run:

```bash
zil --help
```

## Basic `.zc` usage

A standalone ZIL file contains a module declaration, relation tuples, optional rules, queries, macros, and typed declarations.

Example:

```zc
MODULE example.access.

group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#owner@user:10.

RULE serviceOperator:
IF ?service#depends_on@?dependency AND ?dependency#operator@?user
THEN ?service#operator@?user.
```

Save this as `access.zc`, then compile it:

```bash
bin/zil compile access.zc GeneratedAccess.lean Example.GeneratedAccess
```

Compile to standard output instead:

```bash
bin/zil compile access.zc - Example.GeneratedAccess
```

Expand source macros without generating Lean:

```bash
bin/zil expand access.zc expanded.zc
```

Produce the deterministic conformance representation:

```bash
bin/zil conformance access.zc access.zilc
```

## Native Lean usage

The Lean package exports the `Zil` library.

Run the progressive examples:

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
lake env lean examples/lean/02_TheoremShapedRule.lean
lake env lean examples/lean/03_TypedRule.lean
lake env lean examples/lean/04_MultiStepQuery.lean
lake env lean examples/lean/KnowledgeBase.lean
lake env lean examples/lean/05_ImportedKnowledge.lean
```

A Lean file can import the complete API:

```lean
import Zil

zil_fact
  node(doc.readme)
    ⟶[owner]
  node(user.u10)
```

Inside this checkout, save the file as `MyKnowledge.lean` and elaborate it with:

```bash
lake env lean MyKnowledge.lean
```

## Query, provenance, authorization, and impact

### Authorization

```bash
bin/zil authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

Explain the complete derivation for one authorization fact:

```bash
bin/zil explain-authorization \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

### Provenance trace

```bash
bin/zil trace examples/provenance/access.zc /tmp/provenance.txt
```

### Query planning and governance

```bash
bin/zil query-plan examples/query-governance/operations.zc
bin/zil query-ci examples/query-governance/operations.zc
```

### Dependency and change impact

```bash
bin/zil dependency-graph examples/impact/project.zc
bin/zil impact examples/impact/project.zc lean:Parser.parse
```

Use the node names declared by the selected source file. An unknown node is a semantic result, not a transport failure.

## Macro libraries

The hybrid macro commands use Clojure for deterministic workspace and `lib/*.zc` discovery, then send semantic expansion or compilation to the Lean worker.

Without `--lib`, the command searches for the nearest ancestor `lib/` directory, reads only its direct `.zc` children, sorts them, and prepends them to the model.

Expand the checked-in macro example:

```bash
bin/zil macro-expand \
  examples/macro-extension/model.zc \
  --output /tmp/macro-expanded.zc
```

Compile it:

```bash
bin/zil macro-compile \
  examples/macro-extension/model.zc \
  --output /tmp/MacroExtension.lean \
  --namespace Example.MacroExtension
```

Compare the Clojure and Lean macro expansion paths:

```bash
bin/zil macro-parity \
  examples/macro-extension/model.zc \
  --output /tmp/macro-parity.edn
```

Use an explicit library directory:

```bash
bin/zil macro-expand model.zc --lib path/to/lib
```

## Formal control plane and exchange worker

The full workbench exposes eight Lean-authoritative exchange operations:

```text
parse
compile
expand
conformance
query
authorize
impact
recovery-audit
```

Invoke the formal Clojure control plane directly:

```bash
bin/zil control compile examples/authorization/access.zc -
```

The `-` argument tells `compile` to derive its namespace from the source.

Invoke authorization through the supervised exchange path:

```bash
bin/zil exchange authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

Start the raw JSON Lines worker:

```bash
bin/zil worker --stdio
```

The raw worker is intended for integrations implementing `ZIL-EXCHANGE/1`. Normal users should prefer `bin/zil control`, `bin/zil exchange`, or the higher-level commands.

## Recursive corpus workflows

These commands require the full Lean+Clojure workbench.

### Compile the repository corpus

Check the complete corpus without writing generated modules:

```bash
bin/zil library --check \
  --root lib \
  --root libsets \
  --root examples
```

Generate modules and a manifest:

```bash
bin/zil library \
  --root lib \
  --root libsets \
  --root examples \
  --out generated/zil \
  --manifest generated/zil/manifest.edn
```

### Differential conformance

```bash
bin/zil conformance-suite \
  --root lib \
  --root libsets \
  --root examples \
  --output generated/zil/conformance.edn
```

This compares the legacy Clojure semantic report with the Lean-authoritative report over the same prepared source.

### Embedded ZIL blocks

Scan supported host-language files and check embedded blocks:

```bash
bin/zil embedded-native \
  --root examples \
  --check
```

Generate and verify Lean files:

```bash
bin/zil embedded-native \
  --root examples \
  --out generated/embedded \
  --manifest generated/embedded/manifest.edn
```

Generated Lean elaboration is an external verification step performed after Lean-authoritative ZIL compilation.

## Extension registry

Extensions are described by `ZIL-EXTENSION/1` manifests. The registry prevents extensions from shadowing built-in commands or authoritative capability identifiers.

List installed manifests:

```bash
bin/zil plugin list extensions
```

Inspect one manifest and its deterministic fingerprint:

```bash
bin/zil plugin inspect \
  extensions/reference/repository-scanner/extension.json
```

### Repository scanner

This extension does not require a Lean worker. It needs Java and the Clojure CLI.

```bash
bin/zil plugin run \
  extensions/reference/repository-scanner/extension.json \
  repository-scan .
```

Produce a byte-attested evidence envelope:

```bash
bin/zil plugin evidence \
  extensions/reference/repository-scanner/extension.json \
  examples/extensions/repository-scan.edn
```

### Report exporter

Convert the checked-in EDN report to deterministic JSON:

```bash
bin/zil plugin run \
  extensions/reference/report-exporter/extension.json \
  report-export \
  examples/extensions/sample-report.edn \
  /tmp/sample-report.json \
  json
```

Produce evidence using the checked-in request:

```bash
bin/zil plugin evidence \
  extensions/reference/report-exporter/extension.json \
  examples/extensions/report-export-request.edn
```

### External solver adapter

The adapter does not install a solver. The configured executable must already be on `PATH`.

The sample configuration invokes `z3` without a shell:

```bash
bin/zil plugin run \
  extensions/reference/external-solver/extension.json \
  solver-run z3 examples/extensions/sample-goal.smt2 \
  --config examples/extensions/external-solver-config.edn
```

Produce externally attested evidence:

```bash
bin/zil plugin evidence \
  extensions/reference/external-solver/extension.json \
  examples/extensions/external-solver-request.edn \
  --config examples/extensions/external-solver-config.edn
```

An external solver result remains external evidence. It is not automatically a Lean theorem, authorization decision, or kernel-backed proof.

## Agent and mutation-safety commands

These native commands are available in the Lean SDK profile.

### Agent context

```bash
bin/zil agent-context \
  examples/agent-context/project.zc \
  task:demo agent:a src/demo changed.node
```

Comma-separated lists are accepted for changed nodes, queries, and formalization targets.

### Action-token issuance

```bash
bin/zil action-token \
  examples/action-token/request.zc \
  request:issue
```

### Checkpoint and single-use lifecycle

```bash
bin/zil token-lifecycle \
  examples/token-lifecycle/lifecycle.zc \
  request:issue
```

### Postcondition and recovery audit

```bash
bin/zil recovery-audit \
  examples/recovery-audit/recovered.zc \
  request:issue
```

### Proof-obligation governance

```bash
bin/zil proof-obligations \
  examples/proof-obligations/governance.zc
```

The optional tool selector is one of:

```text
all
-
z3
tlaps
lean4
acl2
manual
```

This command audits declarations and evidence. It does not execute external solvers.

### Theorem and external-claim audit

```bash
bin/zil theorem-audit \
  examples/theorem-audit/contracts.zc
```

## Revision and snapshot commands

For a `ZILR` revision envelope:

```bash
bin/zil revision-summary path/to/store.zilr
bin/zil snapshot path/to/store.zilr 10 /tmp/revision-10.txt
bin/zil causal-check path/to/store.zilr
```

## Legacy compatibility

Legacy commands are explicit and are not selected by default:

```bash
bin/zil --legacy <legacy-command> [arguments...]
```

or:

```bash
bin/zil-legacy <legacy-command> [arguments...]
```

The legacy launcher uses either:

1. Java and `dist/zil-standalone.jar`; or
2. the Clojure CLI.

Build the standalone JAR:

```bash
bin/build-jar
```

Override its location with:

```bash
export ZIL_JAR=/path/to/zil-standalone.jar
```

Temporary fallback of unknown public commands to the legacy CLI can be enabled with:

```bash
export ZIL_LEGACY_MODE=allow
```

Prefer explicit `--legacy` invocation in scripts so the selected runtime remains visible.

## Exit behavior

Commands generally use:

- `0` for successful execution or a passing audit;
- `1` for a valid operation that rejects, denies, reports unsafe state, or fails semantic validation;
- `2` for malformed command arguments, unavailable required runtimes, or launcher-level errors.

A successful exchange transport does not imply that authorization allowed, impact found a node, or recovery was safe. Inspect the command payload or report.

## Updating an installation

From the repository root:

```bash
git pull --ff-only
lake build
clojure -Spath >/dev/null
```

Elan follows the version in `lean-toolchain`. Clojure dependencies follow `deps.edn`.

For a development checkout, rerun:

```bash
lake exe zilLeanTests
clojure -M:test
```

## Cleaning local build artifacts

Remove only reproducible build caches:

```bash
rm -rf .lake
```

Generated directories may contain outputs you chose to create. Review them before removal:

```text
generated/zil
generated/embedded
dist/zil-standalone.jar
```

## Troubleshooting

### `lake: command not found`

Reload Elan in the current shell:

```bash
source "$HOME/.elan/env"
```

Then verify:

```bash
elan show
lake --version
```

### Lean uses the wrong version

Run the command from the repository root and inspect:

```bash
cat lean-toolchain
elan show
lean --version
```

Do not delete or override `lean-toolchain` to solve a local PATH problem.

### `clojure` rejects `-M` or `-Sdescribe`

The installed command is not the official Clojure CLI/tools.deps distribution. Replace it using:

<https://clojure.org/guides/install_clojure>

### Java is unavailable

```bash
java --version
```

Install a supported OpenJDK distribution and ensure either `java` is on `PATH` or `JAVA_HOME` is configured.

### `bin/zil: Permission denied`

```bash
chmod +x bin/zil
```

### A full-workbench command says Clojure is required

Native commands such as `compile`, `authorize`, and `impact` require Lean only. Commands such as `macro-compile`, `library`, `conformance-suite`, `embedded-native`, `control`, and `plugin` require the Clojure CLI. Install the full workbench prerequisites or use the native equivalent where one exists.

### An extension requirement is unavailable

A manifest that requires `ZIL-EXCHANGE/1` or a Lean capability must run with a live control plane and Lean worker pool. Operational extensions that require only extension/evidence schemas can run without Lean.

Inspect the manifest:

```bash
bin/zil plugin inspect path/to/extension.json
```

### An external solver is not found

ZIL does not install external proof tools. Install the configured executable and verify it is on `PATH`, or update the EDN configuration with the correct argument vector.

### Native Windows launcher problems

Use WSL 2 for the complete repository workflow. In native PowerShell, invoke the corresponding direct command, for example:

```powershell
lake exe zil -- compile examples/authorization/access.zc -
clojure -M:plugins list extensions
```

## Further documentation

- `README.md` — language and project overview
- `docs/architecture/hybrid-system.md` — Lean/Clojure authority boundary
- `docs/architecture/control-plane-and-extensions.md` — formal control plane and extension SDK
- `docs/lean4/hybrid-exchange-worker.md` — exchange worker and supervision
- `docs/lean4/macro-extension-parity.md` — macro-library behavior
- `spec/exchange-protocol-v1.md` — `ZIL-EXCHANGE/1`
- `spec/extension-manifest-v1.md` — `ZIL-EXTENSION/1`
- `spec/evidence-envelope-v1.md` — `ZIL-EVIDENCE/1`
