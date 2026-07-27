# Local setup and testing

ZIL provides host and container setup paths. These scripts do not change the Lean/Clojure authority model: they install or diagnose runtimes, invoke existing commands, isolate generated files, and collect reports.

## Quick start

From the repository root:

```bash
bin/zil doctor --profile full
bin/zil setup --profile full
bin/zil test --profile smoke
```

Install missing Elan and the official Clojure CLI in user space:

```bash
bin/zil setup --profile full --install-tools
```

The setup script does not install Java, Git, Docker, Make, or system packages and does not invoke `sudo`.

## Installation profiles

| Profile | Required runtime | Purpose |
|---|---|---|
| `lean` | Git, curl, Elan, Lean, Lake | Native library and CLI |
| `full` | Lean profile, Java, official Clojure CLI | Complete workbench |
| `extensions` | Java, official Clojure CLI | Operational extensions without Lean |
| `legacy` | Clojure CLI or Java plus standalone JAR | Explicit legacy runtime |
| `container` | Docker with Compose | Reproducible test workbench |
| `all` | Full profile, Make, Docker | Complete developer environment |

The authoritative machine-readable list is `config/test-profiles.edn`.

## Environment doctor

```bash
bin/zil doctor --profile lean
bin/zil doctor --profile full --report .zil/doctor-full.tsv
bin/zil doctor --profile container
```

The report schema is:

```text
ZIL-DOCTOR/1
```

Required and optional checks remain separate. A missing optional legacy path does not fail a full profile when another supported path exists.

## POSIX setup

```bash
bash scripts/setup.sh --profile full
```

Useful options:

```text
--install-tools
--prefix DIR
--no-build
--test
--test-profile PROFILE
--offline
--report FILE
```

`--install-tools` may install:

- Elan under `~/.elan`;
- the official Clojure CLI under `~/.local` or the supplied prefix.

The script creates:

```text
.zil/setup-report.tsv
.zil/setup.env
.zil/doctor-<profile>.tsv
```

Source the generated environment file when a user prefix is not already on `PATH`:

```bash
source .zil/setup.env
```

## Native Windows setup

From PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup.ps1 -Profile full
```

Elan may be installed with `-InstallTools`. Java and the official Clojure CLI must be installed explicitly. WSL 2 remains the closest match to the complete POSIX workflow.

## Test profiles

```bash
bin/zil test --profile smoke
bin/zil test --profile lean
bin/zil test --profile clojure
bin/zil test --profile hybrid
bin/zil test --profile durable
bin/zil test --profile all
```

The runner:

- validates the selected environment first;
- isolates generated modules, SQLite stores, and intermediate artifacts in a temporary directory;
- writes the report and one persistent log per step outside that temporary directory;
- continues after individual failures;
- accepts explicitly documented nonzero semantic outcomes where appropriate;
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
bin/zil test --profile hybrid --keep-workdir --verbose
```

Skip a repeated Lean build when the checkout is already built:

```bash
bin/zil test --profile durable --skip-build
```

### Smoke

Covers:

- environment diagnostics;
- Lean package build;
- native compilation and authorization;
- extension discovery;
- supervised exchange parsing;
- runtime-evaluation model validation.

### Lean

Covers:

- `lake build`;
- `zilLeanTests`;
- `.zc` to Lean generation;
- elaboration of generated Lean;
- native authorization and impact.

### Clojure

Covers:

- tools.deps resolution;
- the Clojure test suite;
- extension discovery;
- repository scanner;
- report exporter;
- architecture evaluation with empty and sample measurements.

### Hybrid

Covers:

- exchange and control-plane calls;
- macro parity;
- recursive library checks;
- differential conformance;
- embedded ZIL compilation checks.

### Durable

Covers:

- durable Lean decision recording;
- expected-revision workflow append;
- event, payload, and receipt verification;
- workflow projection;
- the SQLite `StoreBackend` reference extension.

### All

Runs the Lean, Clojure, hybrid, and durable suites. Build completion is reused within the same runner process, and suite prefixes keep every report row and log name unique.

## PowerShell tests

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1 -Profile smoke
powershell -ExecutionPolicy Bypass -File scripts/test.ps1 -Profile all -KeepWorkdir
```

The PowerShell runner calls Lake and Clojure aliases directly because `bin/zil` is a Bash launcher. It emits the same report schema and stores logs beside the report.

## Make targets

```bash
make doctor SETUP_PROFILE=full
make setup SETUP_PROFILE=full
make bootstrap SETUP_PROFILE=full
make test PROFILE=smoke
make test-all
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

The image pins:

- Ubuntu 24.04;
- OpenJDK 21 from the distribution;
- a versioned official Clojure CLI installer;
- the Lean version selected by the repository `lean-toolchain` file.

Override the Clojure CLI version when testing an upgrade:

```bash
CLOJURE_TOOLS_VERSION=<version> make container-test PROFILE=smoke
```

## Report interpretation

`ZIL-TEST-REPORT/1` begins with run metadata, including both the temporary work directory and persistent log directory, and then one row per step:

```text
step	description	expected	exit	status	duration_seconds	log	command
```

The final rows contain total duration, step count, failure count, and overall result.

A test process exit code and a ZIL semantic outcome are not interchangeable. For example, the architecture evaluator may return `1` when evidence proposes a human-reviewed candidate change; the profile declares that expected result explicitly.

## Cleaning local outputs

```bash
make clean-test
```

The generated `.zil/` directory is ignored by Git.

## Validation boundary

The scripts are execution infrastructure, not semantic authorities:

- Lean remains authoritative for ZIL semantic results;
- Clojure remains authoritative for operational orchestration and durable transactions;
- Docker and Make only reproduce command execution;
- a passing transport or setup check does not promote external evidence to Lean proof.
