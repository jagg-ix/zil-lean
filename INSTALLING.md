# Installing and Using ZIL

ZIL is a hybrid Lean 4 and Clojure system:

- **Lean 4** is the authoritative semantic and verification kernel.
- **Clojure/JVM** provides workspace and corpus orchestration, worker supervision, plugins, persistence, and external-tool adapters.
- A **Lean-only profile** remains supported for native compilation, queries, authorization, provenance, impact, and safety auditing.

This guide covers installation, initial verification, common commands, the formal control plane, extensions, and legacy compatibility.

## Choose an installation profile

| Profile | Install | Typical use |
|---|---|---|
| Lean SDK | Git, curl, Elan/Lean | Native library and CLI, direct Lean integration, authorization and safety tools |
| Full workbench | Lean SDK, Java, official Clojure CLI | Macro libraries, recursive corpus tooling, exchange/control plane, plugins, external tools |
| Operational extensions | Java, official Clojure CLI | Extensions that do not require Lean, such as repository scanning and report export |
| Legacy compatibility | Full workbench, or Java plus a built standalone JAR | Explicit use of the older Clojure runtime |

External tools such as Z3, TLAPS, and ACL2 are optional and are not installed by ZIL.

## Supported environments

`bin/zil` is a Bash launcher.

- **Linux:** use a normal Bash environment.
- **macOS:** use Terminal; Bash or Zsh can invoke the launcher.
- **Windows:** WSL 2 is recommended for the complete repository workflow.
- **Native Windows:** Lean and Clojure can be installed natively, but use direct `lake exe ...` and `clojure -M:...` commands unless a compatible Bash environment is installed.

## 1. Install prerequisites

### Git and curl

Verify both commands:

```bash
git --version
curl --version
```

Installation information:

- Git: <https://git-scm.com/install/>
- Lean manual installation: <https://lean-lang.org/install/manual/>

### Lean and Elan

Elan manages Lean versions and automatically selects the version pinned by each project.

Linux, macOS, WSL, and compatible POSIX shells:

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

This repository currently pins:

```text
leanprover/lean4:v4.31.0
```

The version is read from `lean-toolchain`. Do not replace it with a different global Lean version.

Native Windows PowerShell users may install Elan with:

```powershell
curl -O --location https://elan.lean-lang.org/elan-init.ps1
powershell -ExecutionPolicy Bypass -f elan-init.ps1
del elan-init.ps1
```

Close and reopen the terminal afterward.

### Java for the full workbench

Clojure requires Java. Java 17 or Java 21 is a suitable LTS choice.

```bash
java --version
```

A cross-platform OpenJDK distribution is available from:

<https://adoptium.net/>

### Official Clojure CLI

ZIL uses tools.deps aliases such as `-M:test`, `-M:control`, and `-M:plugins`. Install the official Clojure CLI, not only a bare Clojure JAR or a package that lacks `-M` and `-Sdescribe`.

Verify it with:

```bash
clojure -Sdescribe
```

Official installation guide:

<https://clojure.org/guides/install_clojure>

#### macOS with Homebrew

Install Java first, then:

```bash
brew trust clojure/tools
brew install clojure/tools/clojure
```

#### Linux

Install Java, Bash, curl, and `rlwrap`, then:

```bash
curl -L -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh
chmod +x linux-install.sh
sudo ./linux-install.sh
rm linux-install.sh
```

The official guide also provides `posix-install.sh` for other POSIX environments.

#### Windows

For the full workbench, use WSL 2 and follow the Linux instructions inside WSL. Native Windows users can use the Windows installer documented by Clojure, but `bin/zil` still requires Bash.

## 2. Clone ZIL

```bash
git clone https://github.com/jagg-ix/zil-lean.git
cd zil-lean
```

The remaining commands assume the current directory is the repository root.

## 3. Build and verify

Build the Lean package:

```bash
lake build
```

Elan installs the pinned toolchain automatically when needed.

Run the native validation target:

```bash
lake exe zilLeanTests
```

For the full workbench, resolve Clojure dependencies:

```bash
clojure -Spath >/dev/null
```

Run the Clojure tests when validating a development checkout:

```bash
clojure -M:test
```

Display the public command surface:

```bash
bin/zil --help
```

If executable permissions were lost:

```bash
chmod +x bin/zil bin/zil-legacy bin/build-jar
```

Verify native compilation:

```bash
bin/zil compile examples/authorization/access.zc -
```

Verify authorization:

```bash
bin/zil authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

## 4. Optional shell command

`bin/zil` derives the repository root from its own path. Do not copy it elsewhere, and avoid a symlink that changes the apparent script location.

Add a shell function to `~/.bashrc` or `~/.zshrc` instead:

```bash
export ZIL_HOME="$HOME/src/zil-lean"
zil() {
  "$ZIL_HOME/bin/zil" "$@"
}
```

Set `ZIL_HOME` to the real checkout path, reload the shell, and run:

```bash
zil --help
```

## 5. Basic `.zc` usage

A source file can contain tuples, rules, queries, macros, and typed declarations.

```zc
MODULE example.access.

group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#owner@user:10.

RULE serviceOperator:
IF ?service#depends_on@?dependency AND ?dependency#operator@?user
THEN ?service#operator@?user.
```

Compile a file to Lean:

```bash
bin/zil compile access.zc GeneratedAccess.lean Example.GeneratedAccess
```

Write the generated module to standard output:

```bash
bin/zil compile access.zc - Example.GeneratedAccess
```

Expand macros without generating Lean:

```bash
bin/zil expand access.zc expanded.zc
```

Emit the deterministic semantic representation:

```bash
bin/zil conformance access.zc access.zilc
```

## 6. Use ZIL from Lean

The package exports `import Zil`.

Run the progressive examples:

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
lake env lean examples/lean/02_TheoremShapedRule.lean
lake env lean examples/lean/03_TypedRule.lean
lake env lean examples/lean/04_MultiStepQuery.lean
lake env lean examples/lean/KnowledgeBase.lean
lake env lean examples/lean/05_ImportedKnowledge.lean
```

A local Lean file can use native ZIL syntax:

```lean
import Zil

zil_fact
  node(doc.readme)
    ⟶[owner]
  node(user.u10)
```

Save it as `MyKnowledge.lean` in this checkout and elaborate it with:

```bash
lake env lean MyKnowledge.lean
```

## 7. Queries, provenance, authorization, and impact

Authorization:

```bash
bin/zil authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

Explain the derivation:

```bash
bin/zil explain-authorization \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

Provenance trace:

```bash
bin/zil trace examples/provenance/access.zc /tmp/provenance.txt
```

Query planning and governance:

```bash
bin/zil query-plan examples/query-governance/operations.zc
bin/zil query-ci examples/query-governance/operations.zc
```

Dependency graph and impact:

```bash
bin/zil dependency-graph examples/impact/project.zc
bin/zil impact examples/impact/project.zc lean:Parser.parse
```

Use names declared by the selected source file. An unknown node is a semantic result, not a transport failure.

## 8. Macro libraries

These commands require the full workbench. Clojure performs deterministic workspace and `lib/*.zc` discovery; Lean remains authoritative for expansion and compilation.

Without `--lib`, ZIL finds the nearest ancestor `lib/` directory, reads its direct `.zc` children in sorted order, and prepends them to the model.

Expand the checked-in example:

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

Compare Clojure and Lean expansion:

```bash
bin/zil macro-parity \
  examples/macro-extension/model.zc \
  --output /tmp/macro-parity.edn
```

Use an explicit library:

```bash
bin/zil macro-expand model.zc --lib path/to/lib
```

## 9. Formal control plane and exchange worker

The supervised exchange exposes these Lean-authoritative operations:

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

Use the formal control plane:

```bash
bin/zil control compile examples/authorization/access.zc -
```

For `compile`, `-` selects the namespace derived from the source.

Use the exchange client directly:

```bash
bin/zil exchange authorize \
  examples/authorization/access.zc \
  doc:readme viewer user:11
```

Start the raw JSON Lines worker:

```bash
bin/zil worker --stdio
```

The raw worker is for integrations implementing `ZIL-EXCHANGE/1`. Normal use should prefer `control`, `exchange`, or the higher-level commands.

## 10. Recursive corpus workflows

These commands require Lean and Clojure.

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

Run differential conformance:

```bash
bin/zil conformance-suite \
  --root lib \
  --root libsets \
  --root examples \
  --output generated/zil/conformance.edn
```

Check embedded ZIL blocks:

```bash
bin/zil embedded-native --root examples --check
```

Generate and verify embedded modules:

```bash
bin/zil embedded-native \
  --root examples \
  --out generated/embedded \
  --manifest generated/embedded/manifest.edn
```

## 11. Extensions

Extensions use `ZIL-EXTENSION/1` manifests. The registry prevents command shadowing and reuse of authoritative capability identifiers.

List manifests:

```bash
bin/zil plugin list extensions
```

Inspect a manifest and fingerprint:

```bash
bin/zil plugin inspect \
  extensions/reference/repository-scanner/extension.json
```

### Repository scanner

This extension requires Java and Clojure but not Lean.

```bash
bin/zil plugin run \
  extensions/reference/repository-scanner/extension.json \
  repository-scan .
```

Produce byte-attested evidence:

```bash
bin/zil plugin evidence \
  extensions/reference/repository-scanner/extension.json \
  examples/extensions/repository-scan.edn
```

### Report exporter

```bash
bin/zil plugin run \
  extensions/reference/report-exporter/extension.json \
  report-export \
  examples/extensions/sample-report.edn \
  /tmp/sample-report.json \
  json
```

Evidence request:

```bash
bin/zil plugin evidence \
  extensions/reference/report-exporter/extension.json \
  examples/extensions/report-export-request.edn
```

### External solver adapter

The adapter does not install the solver. The configured executable must already be on `PATH`.

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

External results are evidence, not automatic Lean proofs or authorization decisions.

## 12. Agent and safety commands

Agent context using an actual changed node from the example:

```bash
bin/zil agent-context \
  examples/agent-context/project.zc \
  task:demo agent:a src/demo lean:Parser.parse
```

Action-token issuance:

```bash
bin/zil action-token \
  examples/action-token/request.zc \
  request:issue
```

Checkpoint and single-use lifecycle:

```bash
bin/zil token-lifecycle \
  examples/token-lifecycle/lifecycle.zc \
  request:issue
```

Postcondition and recovery audit:

```bash
bin/zil recovery-audit \
  examples/recovery-audit/recovered.zc \
  request:issue
```

Proof-obligation governance:

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

This command audits declarations and evidence; it does not execute external solvers.

Theorem and external-claim audit:

```bash
bin/zil theorem-audit examples/theorem-audit/contracts.zc
```

## 13. Revisions and snapshots

For a ZIL revision envelope:

```bash
bin/zil revision-summary path/to/store.zilr
bin/zil snapshot path/to/store.zilr 10 /tmp/revision-10.txt
bin/zil causal-check path/to/store.zilr
```

## 14. Legacy compatibility

Legacy commands are explicit:

```bash
bin/zil --legacy <legacy-command> [arguments...]
```

or:

```bash
bin/zil-legacy <legacy-command> [arguments...]
```

The legacy launcher uses either Java plus `dist/zil-standalone.jar`, or the Clojure CLI.

Build the standalone JAR:

```bash
bin/build-jar
```

Override its location:

```bash
export ZIL_JAR=/path/to/zil-standalone.jar
```

Temporary fallback of unknown commands to the legacy CLI:

```bash
export ZIL_LEGACY_MODE=allow
```

Prefer explicit `--legacy` in scripts.

## 15. Exit behavior

Commands generally use:

- `0` for success or a passing audit;
- `1` for a valid operation that denies, rejects, reports unsafe state, or fails semantic validation;
- `2` for malformed arguments, missing runtimes, or launcher errors.

Transport success does not imply authorization allow, known impact, safe recovery, or kernel proof. Inspect the report payload.

## 16. Updating

```bash
git pull --ff-only
lake build
clojure -Spath >/dev/null
```

For development validation:

```bash
lake exe zilLeanTests
clojure -M:test
```

Elan follows `lean-toolchain`; Clojure dependencies follow `deps.edn`.

## 17. Cleaning

Remove reproducible Lean build caches:

```bash
rm -rf .lake
```

Review generated outputs before deleting them:

```text
generated/zil
generated/embedded
dist/zil-standalone.jar
```

## 18. Troubleshooting

### `lake: command not found`

```bash
source "$HOME/.elan/env"
elan show
lake --version
```

### Wrong Lean version

Run commands from the repository root and inspect:

```bash
cat lean-toolchain
elan show
lean --version
```

Do not modify `lean-toolchain` to solve a local PATH problem.

### `clojure` rejects `-M` or `-Sdescribe`

Install the official Clojure CLI/tools.deps distribution:

<https://clojure.org/guides/install_clojure>

### Java is unavailable

```bash
java --version
```

Install an OpenJDK distribution and ensure `java` is on `PATH` or `JAVA_HOME` is configured.

### `bin/zil: Permission denied`

```bash
chmod +x bin/zil
```

### A command says Clojure is required

Lean-only commands include `compile`, `expand`, `authorize`, `trace`, `impact`, and the safety/audit commands.

Commands such as `macro-compile`, `library`, `conformance-suite`, `embedded-native`, `control`, and `plugin` require the Clojure CLI.

### Extension requirement unavailable

A manifest requiring `ZIL-EXCHANGE/1` or a Lean capability needs a live Lean worker pool. Operational extensions requiring only extension or evidence schemas can run without Lean.

```bash
bin/zil plugin inspect path/to/extension.json
```

### External solver not found

Install the configured executable, put it on `PATH`, or update its EDN argument-vector configuration. ZIL does not install external proof tools.

### Native Windows launcher issues

Use WSL 2 for the complete workflow. In native PowerShell, use direct commands:

```powershell
lake exe zil -- compile examples/authorization/access.zc -
clojure -M:plugins list extensions
```

## Further documentation

- `README.md` — language and project overview
- `docs/architecture/hybrid-system.md` — Lean/Clojure authority boundary
- `docs/architecture/control-plane-and-extensions.md` — control plane and extension SDK
- `docs/lean4/hybrid-exchange-worker.md` — worker and supervision
- `docs/lean4/macro-extension-parity.md` — macro libraries
- `spec/exchange-protocol-v1.md` — `ZIL-EXCHANGE/1`
- `spec/extension-manifest-v1.md` — `ZIL-EXTENSION/1`
- `spec/evidence-envelope-v1.md` — `ZIL-EVIDENCE/1`
