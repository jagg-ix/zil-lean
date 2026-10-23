# Installing and Using ZIL

ZIL is a Lean 4 system. Lean is the semantic and verification kernel, and the native `bin/zil` commands (compile, expand, query, authorize, impact, audits) are all it takes. An earlier Clojure runtime was removed; see `spec/clojure-removal.md`.

This guide covers installation, initial verification, common commands, the exchange worker, macro libraries, and the test gates.

## Choose an installation profile

| Profile | Install | Typical use |
|---|---|---|
| Lean SDK | Git, curl, Elan/Lean | Everything: the native library and CLI, macro libraries, authorization, provenance, impact, safety auditing, and the test gates |

External tools such as Z3, TLAPS, and ACL2 are optional and are not installed by ZIL.

## Supported environments

`bin/zil` is a Bash launcher.

- **Linux:** use a normal Bash environment.
- **macOS:** use Terminal; Bash or Zsh can invoke the launcher.
- **Windows:** WSL 2 is recommended for the complete repository workflow.
- **Native Windows:** Lean can be installed natively; use direct `lake exe zil -- ...` commands unless a compatible Bash environment is installed.

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

Run the complete native test profile (Lean build, tests, the macro matrix, the extension libraries, the corpus record, a worker parse and the no-Clojure guard):

```bash
bin/zil test --profile lean
```

Display the public command surface:

```bash
bin/zil --help
```

If executable permissions were lost:

```bash
chmod +x bin/zil
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

A model that uses macros from a library is given that library with `--lib DIR`: the direct `.zc` children of `DIR`, in sorted order, are composed before the model. `compile` and `expand` both take it, and a single library file can be given by putting it alone in a directory.

Expand the checked-in example:

```bash
bin/zil expand examples/macro-extension/model.zc /tmp/macro-expanded.zc --lib examples/macro-extension/lib
```

Compile it:

```bash
bin/zil compile examples/macro-extension/model.zc /tmp/MacroExtension.lean Example.MacroExtension --lib examples/macro-extension/lib
```

Qualify every macro library against its reviewed golden expansion, then compile and typecheck the generated Lean:

```bash
tools/macro_extension_matrix.sh
tools/macro_extension_matrix.sh --only tlm       # one row
tools/macro_extension_matrix.sh --update         # after an intended change; review the golden diff
```

## 9. Exchange worker

The worker speaks `ZIL-EXCHANGE/1` as JSON Lines and exposes these Lean-authoritative operations:

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

One request on standard input, one response on standard output:

```bash
bin/zil worker --once < examples/exchange/parse-request.json
```

Or a stream of requests:

```bash
bin/zil worker --stdio
```

The worker validates the request's `input_sha256` identifier and carries it through; the caller computes it over the exact input bytes.

## 10. The corpus record

Compile every `.zc` file under `lib/` and `examples/` alone and compare the outcome with `spec/corpus-status.tsv`:

```bash
bin/zil corpus
bin/zil corpus --update    # after an intended change; review the diff
```

A macro file, or a model that needs its library, is rejected alone and recorded as such. The macro matrix covers those with their libraries.

## 11. Agent and safety commands

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

## 12. Revisions and snapshots

For a ZIL revision envelope:

```bash
bin/zil revision-summary path/to/store.zilr
bin/zil snapshot path/to/store.zilr 10 /tmp/revision-10.txt
bin/zil causal-check path/to/store.zilr
```

## 13. Removed commands

The Clojure runtime was removed. Its control plane, plugin loader, release attestation, placement evaluation, embedded blocks, datasource ingest and HCL/TLA+/LTS tools are now Lean executables behind `bin/zil control`, `plugin`, `release-attest`, `evaluate-runtime`, `embedded-*`, `ingest`, `import-data`, `convert-data`, `import-hcl`, `export-tla` and `export-lean`. These stay removed and print what to use instead: `exchange` (use `control exchange`), `control-store` (use `control store`), `export-data`, `library`, `conformance-suite`, `macro-compile`, `macro-expand`, `macro-parity`, `--legacy`, and the standalone JAR. `spec/clojure-removal.md` lists them with the last commit that had them.

## 14. Exit behavior

Commands generally use:

- `0` for success or a passing audit;
- `1` for a valid operation that denies, rejects, reports unsafe state, or fails semantic validation;
- `2` for malformed arguments, missing runtimes, or launcher errors.

Transport success does not imply authorization allow, known impact, safe recovery, or kernel proof. Inspect the report payload.

## 15. Updating

```bash
git pull --ff-only
lake build
```

For development validation:

```bash
lake exe zilLeanTests
bin/zil test --profile lean
```

Elan follows `lean-toolchain`.

## 16. Cleaning

Remove reproducible Lean build caches:

```bash
rm -rf .lake
```

Review generated outputs before deleting them:

```text
.zil
```

## 17. Troubleshooting

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

### `bin/zil: Permission denied`

```bash
chmod +x bin/zil
```

### A command says it was removed

It belonged to the removed Clojure runtime. The message names the replacement; see `spec/clojure-removal.md`.

### External solver not found

ZIL does not install external proof tools: install the solver you want and put it on `PATH`.

### Native Windows launcher issues

Use WSL 2 for the complete workflow. In native PowerShell, use direct commands:

```powershell
lake exe zil -- compile examples/authorization/access.zc -
```

## Further documentation

- `README.md` — language and project overview
- `spec/exchange-protocol-v1.md` — `ZIL-EXCHANGE/1`
- `spec/clojure-removal.md` — what was removed and where each part went
