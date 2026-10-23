# Local setup and testing

ZIL provides host and container setup paths. The scripts install or diagnose the Lean toolchain, invoke the native commands, isolate generated files, and collect reports. Nothing in them needs Clojure; `scripts/check-no-clojure.sh` keeps it that way.

## Quick start

From the repository root:

```bash
bin/zil doctor --profile lean
bin/zil setup --profile lean
bin/zil test --profile smoke
```

Install a missing Elan in user space:

```bash
bin/zil setup --profile lean --install-tools
```

The setup script does not install Git, Docker, Make, or system packages and does not invoke `sudo`.

## Installation profiles

| Profile | Required runtime | Purpose |
|---|---|---|
| `lean` | Git, curl, Elan, Lean, Lake | The native library, CLI and all gates |
| `container` | Docker with Compose | Reproducible test workbench |
| `all` | Lean profile, Make, Docker | Complete developer environment |

The machine-readable list of test profiles is `config/test-profiles.tsv`.

## Environment doctor

```bash
bin/zil doctor --profile lean
bin/zil doctor --profile lean --report .zil/doctor-lean.tsv
bin/zil doctor --profile container
```

The report schema is:

```text
ZIL-DOCTOR/1
```

## POSIX setup

```bash
bash scripts/setup.sh --profile lean
```

Useful options:

```text
--install-tools
--no-build
--test
--test-profile PROFILE
--offline
--report FILE
```

`--install-tools` may install Elan under `~/.elan`. The script creates:

```text
.zil/setup-report.tsv
.zil/setup.env
.zil/doctor-<profile>.tsv
```

## Native Windows setup

From PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup.ps1 -Profile lean
```

Elan may be installed with `-InstallTools`. WSL 2 remains the closest match to the complete POSIX workflow; the PowerShell runner covers the Lean build, tests, compilation, authorization and impact.

## Test profiles

```bash
bin/zil test --profile smoke
bin/zil test --profile lean
bin/zil test --profile all
```

The runner:

- validates the selected environment first;
- isolates generated modules and intermediate artifacts in a temporary directory;
- writes the report and one persistent log per step outside that temporary directory;
- continues after individual failures;
- emits `ZIL-TEST-REPORT/1`.

Default reports are written under:

```text
.zil/test-reports/
```

For a report named `smoke-latest.tsv`, logs are retained in:

```text
smoke-latest.tsv.logs/
```

Preserve temporary generated files as well as the persistent report and logs:

```bash
bin/zil test --profile lean --keep-workdir --verbose
```

Skip a repeated Lean build when the checkout is already built:

```bash
bin/zil test --profile lean --skip-build
```

### Smoke

Covers:

- environment diagnostics;
- Lean package build;
- native compilation and authorization;
- a parse through the native exchange worker.

### Lean

Covers:

- `lake build`;
- `zilLeanTests`, including first-order Horn parsing, occurs-check unification, recursive SLD resolution, backtracking, cutoff reporting, iterative deepening, proof-tree replay, tamper rejection, declarative/certificate completeness, `horn_solve`, and `horn_certify`;
- `.zc` to Lean generation and elaboration of the generated Lean;
- native authorization and impact;
- the macro matrix (`tools/macro_extension_matrix.sh`): every macro library expanded natively, compared with its reviewed golden, compiled, and typechecked;
- the extension libraries gate (`scripts/test-extension-libraries.sh`) and the model substrate gate (`scripts/test-model-substrate.sh`);
- the corpus record (`bin/zil corpus`);
- a parse through the native exchange worker;
- the no-Clojure guard (`scripts/check-no-clojure.sh`).

Run compatibility smoke tests against a HORC checkout with:

```bash
lake exe zilHorc "$HORC_ROOT/src/horn/list.hn" \
  'member(X, cons(nil,1))' 16
lake exe zilHorc "$HORC_ROOT/src/horn/map.hn" \
  'maps_to(cons(cons(nil,a,0),b,1), K, V)' 32
lake exe zilHorc "$HORC_ROOT/src/horn/tm.hn" \
  'natural(successor_natural(zero_natural))' 8
lake exe zilHorc "$HORC_ROOT/src/horn/horn.hn" \
  'variable(form_variable(empty_word))' 8
```

These commands exercise the original model syntax without modifying the HORC sources. A successful answer exits with status 0; finite failure or a runtime error exits with status 1; invalid command usage exits with status 2.

### All

The same as `lean`.

## PowerShell tests

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1 -Profile smoke
powershell -ExecutionPolicy Bypass -File scripts/test.ps1 -Profile lean -KeepWorkdir
```

The PowerShell runner calls Lake directly because `bin/zil` is a Bash launcher. It emits the same report schema and stores logs beside the report.

## Make targets

```bash
make doctor
make setup
make bootstrap
make test PROFILE=smoke
make test-all
make corpus
make matrix
make container-test PROFILE=all
```

## Container workbench

Build and run directly:

```bash
docker build -f Dockerfile.test -t zil-lean-test:local .
docker run --rm -v "$PWD/.zil/container-reports:/reports" \
  zil-lean-test:local \
  --profile all --skip-build --report /reports/all.tsv
```

Or use Compose:

```bash
ZIL_TEST_PROFILE=all docker compose -f compose.test.yml run --rm zil-test
```

Compose mounts the container's `.zil/test-reports` directory to `.zil/container-reports` on the host. This preserves reports and step logs even when custom test arguments replace the service's default command.

The image pins Ubuntu 24.04 and the Lean version selected by the repository `lean-toolchain` file.

## Report interpretation

`ZIL-TEST-REPORT/1` begins with run metadata, including both the temporary work directory and persistent log directory, and then one row per step:

```text
step	description	expected	exit	status	duration_seconds	log	command
```

The final rows contain total duration, step count, failure count, and overall result.

A test process exit code and a ZIL semantic outcome are not interchangeable: a step may declare a nonzero exit as its expected semantic result.

## Cleaning local outputs

```bash
make clean-test
```

The generated `.zil/` directory is ignored by Git.

## Validation boundary

The scripts are execution infrastructure, not semantic authorities: Lean is authoritative for ZIL semantic results, Docker and Make only reproduce command execution, and a passing setup check does not promote external evidence to a Lean proof.
