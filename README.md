# ZIL Lean

**ZIL Lean** is a declarative, graph-relational policy language and Datalog inference engine embedded in [Lean 4](https://lean-lang.org/).

Inspired by Google's [Zanzibar](https://storage.googleapis.com/gweb-research2023-media/pubtools/5068.pdf) authorization model, ZIL allows engineers to specify entities, relationships, and inference rules that derive additional relationships. It provides a single source of truth for:

- **Fine-Grained Authorization (FGA):** Relationship-Based Access Control (ReBAC), Role-Based Access Control (RBAC), and user group hierarchies.
- **Service & Infrastructure Topologies:** Microservice architectures, cloud dependencies, and component relationships.
- **Change Impact Analysis:** Transitive dependency tracking, blast radius calculation, and regression prevention.
- **Audit Provenance:** Complete, step-by-step explanations of every derived access grant or relationship.
- **Formally Verified Semantics:** A machine-checked Datalog evaluator in Lean 4 that guarantees deterministic termination and mathematical correctness.

---

## Quick Start

### Prerequisites
- [Elan](https://github.com/leanprover/elan) (Lean 4 toolchain manager)

### Installation & Build

```bash
git clone https://github.com/jagg-ix/zil-lean
cd zil-lean

# Build the Lean library and test suites
lake build

# Build the standalone command-line tool (bin/zil)
lake build zil
```

---

## Core Concepts: Relational Tuples

At its core, ZIL represents system state as a set of **relation tuples**. Following the Zanzibar convention, relationships are expressed as:

```text
<object>#<relation>@<subject>
```

A subject can be a concrete entity (such as a user ID) or a **userset** (a dynamic group defined by another relation):

| Pattern | Tuple Syntax | Meaning |
|---|---|---|
| **Direct Assignment** | `doc:readme#owner@user:10.` | User `10` is an owner of `doc:readme`. |
| **Group Membership** | `group:engineering#member@user:11.` | User `11` is a member of `group:engineering`. |
| **Inherited Access (Userset)** | `doc:readme#viewer@group:engineering#member.` | All members of `group:engineering` are viewers of `doc:readme`. |
| **Hierarchical Structure** | `doc:readme#parent@folder:specs.` | `doc:readme` inherits permissions from `folder:specs`. |

---

## Hands-On Examples

### Example 1: Access Control (ReBAC & RBAC)

Create an authorization policy model in `access_policy.zc`:

```zc
MODULE access_policy.

// 1. Identity & Team Membership
group:engineering#member@user:alice.
group:engineering#member@user:bob.

// 2. Resource Permissions
doc:architecture_spec#owner@user:alice.
doc:architecture_spec#viewer@group:engineering#member.

// 3. Inference Rules
// Rule: Document owners automatically inherit editor access
RULE ownerCanEdit:
IF ?doc#owner@?user
THEN ?doc#editor@?user.

// Rule: Document editors automatically inherit viewer access
RULE editorCanView:
IF ?doc#editor@?user
THEN ?doc#viewer@?user.
```

#### 1. Check Authorization
Evaluate whether user `alice` has `viewer` access to `doc:architecture_spec`:

```bash
./bin/zil authorize access_policy.zc doc:architecture_spec viewer user:alice
```

**Output:**
```text
decision        allow
source          derived
object          doc.architecture_spec
relation        zil.viewer
subject         user.alice
base-facts      4
closed-facts    6
deriving-rules  ownerCanEdit, editorCanView
```

#### 2. Explain Authorization (Audit Provenance)
Inspect the exact derivation chain and rules that allowed access:

```bash
./bin/zil explain-authorization access_policy.zc doc:architecture_spec viewer user:alice
```

**Output:**
```text
ZIL-FACT-EXPLANATION    1
decision        present
source          rule
target          rel     node:doc.architecture_spec   zil.viewer   node:user.alice
-- provenance --
fact    2       0       rel     node:doc.architecture_spec   zil.owner    node:user.alice     origin  base
fact    4       0       rel     node:doc.architecture_spec   zil.editor   node:user.alice     origin  rule  ownerCanEdit  2   doc=doc.architecture_spec,user=user.alice
fact    5       0       rel     node:doc.architecture_spec   zil.viewer   node:user.alice     origin  rule  editorCanView 4   doc=doc.architecture_spec,user=user.alice
```

---

### Example 2: Service Architecture & Change Impact Analysis

ZIL models infrastructure and software architecture dependencies to calculate blast radius before deploying changes.

Save the following model as `service_mesh.zc`:

```zc
MODULE service_mesh.

// Service Dependencies
service:frontend#depends_on@service:gateway.
service:gateway#depends_on@service:auth.
service:gateway#depends_on@service:orders.
service:orders#depends_on@service:database.
service:auth#depends_on@service:database.

// Transitive Dependency Rule
RULE transitiveDependency:
IF ?service#depends_on@?dep AND ?dep#depends_on@?upstream
THEN ?service#depends_on@?upstream.
```

#### 1. Generate Dependency Graph
Extract the directed dependency topology across services:

```bash
./bin/zil dependency-graph service_mesh.zc
```

**Output:**
```text
ZIL-DEPENDENCY-GRAPH    1
nodes   5
edges   5
cycles
edge    service.frontend  zil.dependsOn  service.gateway   1
edge    service.gateway   zil.dependsOn  service.auth      2
edge    service.gateway   zil.dependsOn  service.orders    3
edge    service.orders    zil.dependsOn  service.database  4
edge    service.auth      zil.dependsOn  service.database  5
```

#### 2. Change Impact Analysis (Blast Radius)
Analyze what components are impacted if `service:database` is modified or experiences downtime:

```bash
./bin/zil impact service_mesh.zc service:database
```

**Output:**
```text
ZIL-CHANGE-IMPACT       1
status          known
changed         service.database
affected        4
impact          service.auth       1       direct          service.auth#zil.dependsOn@service.database
impact          service.orders     1       direct          service.orders#zil.dependsOn@service.database
impact          service.gateway    2       transitive      service.gateway#zil.dependsOn@service.database
impact          service.frontend   3       transitive      service.frontend#zil.dependsOn@service.database
```

---

### Example 3: Native Lean 4 DSL Integration

You can define and query ZIL relationships directly within Lean 4 source files using native macros:

```lean
import Zil

-- Define facts directly in Lean 4
zil_fact
  node(service.apiGateway)
    ⟶[dependsOn]
  node(service.authService)

zil_fact
  node(service.authService)
    ⟶[owner]
  node(team.platformSecurity)

zil_fact
  node(doc.apiSpec)
    ⟶[viewer]
  node(team.platformSecurity)
```

Lean 4 expressions can evaluate ZIL closures at compile-time or run-time, combining general-purpose functional programming with formal logic.

---

## Key Features & Capabilities

- **Unified Relational Graph:** Model access controls, data catalogs, service boundaries, requirements, and compliance controls in a single consistent format.
- **Datalog Inference Engine:** Compute transitive closures over complex graphs with support for stratified negation.
- **Mathematically Proved Semantics:** Core evaluator semantics (`Zil.Datalog`) are formally certified with machine-checked theorems in Lean 4 (see `spec/datalog-semantics-v1.md`).
- **Audit Trails & Zero-Trust Verification:** Every derived relationship includes verifiable provenance tracking.
- **Cross-Ecosystem Interoperability:** Import and export models between ZIL, Terraform/OpenTofu, TLA+, and Lean 4 (see `spec/interop-v1.md`).
- **Embedded Comments Scanner:** Extract ZIL relational tuples embedded in comments across Python, Go, Rust, Clojure, Lean, and Markdown files.

---

## Common CLI Commands

The `bin/zil` CLI provides a unified toolchain for working with policy models:

| Command | Description |
|---|---|
| `bin/zil authorize <model.zc> <obj> <rel> <subj>` | Evaluates an authorization query (`allow` / `deny`). |
| `bin/zil explain-authorization <model.zc> <obj> <rel> <subj>` | Displays step-by-step provenance for an access decision. |
| `bin/zil dependency-graph <model.zc>` | Generates a directed dependency graph of entities. |
| `bin/zil impact <model.zc> <changed-node>` | Calculates blast radius and downstream dependencies. |
| `bin/zil compile <model.zc> [output.lean]` | Compiles a `.zc` model into native Lean 4 declarations. |
| `bin/zil expand <model.zc> [output.zc] [--lib DIR]` | Expands high-level domain macros into canonical tuples. |
| `bin/zil test` | Runs the test suite across supported profiles. |
| `bin/zil doctor` | Inspects local toolchain health and environment prerequisites. |

Run `./bin/zil --help` for the complete list of available subcommands.

---

## Extensibility & Macro Libraries

ZIL includes an extensible macro layer allowing teams to construct custom domain-specific languages (DSLs) for specific application domains (e.g., process algebra, cloud compliance, state machines).

Pre-built domain macro libraries (`libsets/`) are maintained in the companion [zil-lib](https://github.com/jagg-ix/zil-lib) repository. To expand a model using a macro library:

```bash
./bin/zil expand model.zc - --lib /path/to/zil-lib/libsets/check-vocab
```

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
