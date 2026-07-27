# ZIL installation and test infrastructure v1

## Scope

This specification defines local installation bootstrap, environment diagnostics, test profiles, report formats, and the optional container workbench.

It does not define ZIL semantics, proof authority, durable mutation authorization, or CI policy.

## Public entry points

```text
bin/zil self-check
bin/zil setup
bin/zil doctor
bin/zil test
bin/zil test-container
```

Direct scripts:

```text
scripts/self-check.sh
scripts/setup.sh
scripts/doctor.sh
scripts/test.sh
scripts/setup.ps1
scripts/test.ps1
```

Make targets and the container entry point are adapters over these scripts.

## Installation self-check

Schema:

```text
ZIL-INSTALL-SELF-CHECK/1
```

The self-check MUST NOT build Lean or run the Clojure test suite.

It MUST validate:

- required setup and test files;
- Bash syntax for every shell entry point;
- pinned Dockerfile base and test entry point.

When the corresponding optional parser is available, it MUST also validate:

- EDN profiles and port-gate configuration through Clojure;
- PowerShell setup and test syntax;
- Compose configuration;
- Makefile parsing.

An unavailable optional parser is reported as `skip`. A parser that is available but rejects a contract fails the self-check.

## Installation profiles

The machine-readable profile inventory is:

```text
config/test-profiles.edn
```

Schema:

```text
ZIL-TEST-PROFILES/1
```

Supported environment profiles:

```text
lean
full
extensions
legacy
container
all
```

Supported executable test profiles:

```text
smoke
lean
clojure
hybrid
durable
all
```

## Bootstrap requirements

The POSIX bootstrap MAY install missing:

- Elan under the user home;
- the official Clojure CLI under a user-controlled prefix.

It MUST NOT automatically:

- invoke `sudo`;
- install Java;
- install Git;
- install Docker;
- install Make;
- install operating-system packages;
- alter repository semantic or authority configuration.

The native Windows bootstrap MAY install Elan when explicitly requested. Java and the official Clojure CLI remain explicit prerequisites.

## Doctor report

Schema:

```text
ZIL-DOCTOR/1
```

Header:

```text
profile	<profile>
root	<repository-root>
os	<platform>
arch	<architecture>
```

Rows:

```text
category	name	required	status	detail
```

Required checks fail the doctor unless status is `ok`. Optional checks remain visible but do not fail the selected profile.

The doctor MUST distinguish an official tools.deps Clojure CLI from a `clojure` executable that lacks `-Sdescribe`.

## Setup report

Schema:

```text
ZIL-SETUP-REPORT/1
```

The report records:

- selected profile;
- repository root;
- installation prefix;
- platform and architecture;
- whether a build was requested;
- offline mode;
- available runtime versions;
- final result.

The POSIX bootstrap also creates `.zil/setup.env`. Native PowerShell creates `.zil/setup.env.ps1`.

## Test report

Schema:

```text
ZIL-TEST-REPORT/1
```

Run metadata MUST identify both:

- the temporary generated-artifact work directory;
- the persistent step-log directory.

Each step row has:

```text
step	description	expected	exit	status	duration_seconds	log	command
```

Final rows include:

```text
finished_epoch
duration_seconds
steps
failures
result
```

A test profile MUST:

- run the matching doctor profile before functional steps;
- isolate generated outputs in a temporary workspace;
- retain one persistent log per step beside the report;
- continue after individual failures;
- declare accepted exit codes explicitly;
- return `1` when any selected step fails;
- return `2` for malformed runner arguments.

Deleting the temporary workspace MUST NOT delete the report or its step logs.

The `all` profile MUST use unique step identifiers and SHOULD reuse a successful Lean build within the same process.

## Semantic exit distinction

A nonzero process status may represent an expected semantic or governance outcome rather than infrastructure failure.

For example, runtime evaluation may return `1` when evidence proposes a candidate placement change requiring human review. The selected profile may list `0,1` as accepted for that exact step.

No profile may convert:

- transport failure into semantic denial;
- external evidence into Lean proof;
- setup success into authorization;
- Docker build success into semantic assurance.

## Container workbench

Files:

```text
Dockerfile.test
compose.test.yml
.dockerignore
```

The container MUST:

- use a versioned base distribution;
- install a versioned official Clojure CLI;
- use the repository `lean-toolchain` file for Lean selection;
- invoke `scripts/test.sh` as its test entry point;
- support a mounted report and log directory;
- preserve default reports when a caller supplies custom test arguments;
- avoid embedding local caches or generated outputs in the build context.

The default image command runs the `all` profile with the already-built Lean package.

## Make interface

Required targets:

```text
self-check
setup
bootstrap
doctor
test
test-smoke
test-lean
test-clojure
test-hybrid
test-durable
test-all
container-build
container-test
clean-test
```

## Windows boundary

`bin/zil` remains a Bash launcher. Native Windows testing uses the direct Lake and Clojure aliases from `scripts/test.ps1`.

WSL 2 remains a supported route to the POSIX scripts.

## Governance

The infrastructure surface MUST remain represented by:

- profile contract tests;
- self-check contract tests;
- launcher routing tests;
- Make and container contract tests;
- `port-gate.edn` evidence files;
- user-facing testing documentation.

No GitHub Actions workflow is required by this specification.
