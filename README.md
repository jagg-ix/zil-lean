# ZIL Lean

**A declarative systems architecture language, relational inference engine, and formal verification substrate embedded in [Lean 4](https://lean-lang.org/).**

ZIL provides a framework for modeling distributed systems, cloud infrastructure topologies, cascading failure modes, and architectural contracts. Powered by a machine-checked Datalog inference engine in Lean 4, ZIL computes transitive closures, evaluates stratified negation, and proves structural invariants across complex software codebases.

---

## Relation to Google Zanzibar 

While based on Google's [Zanzibar](https://storage.googleapis.com/gweb-research2023-media/pubtools/5068.pdf) that popularize relational assertions for user access control (ReBAC/RBAC), **ZIL is meant for systems engineering, infrastructure reliability, and formal verification.**

This was initially used for the [Entropic-physlib](https://github.com/jagg-ix/entropic-physlib) project to link theorems as a single coherent framework

## Quick Start

### Prerequisites
- [Elan](https://github.com/leanprover/elan) (Lean 4 toolchain manager)

### Installation & Build

```bash
git clone https://github.com/jagg-ix/zil-lean
cd zil-lean

# Build the Lean library and verification kernel
lake build

# Build the standalone command-line tool (bin/zil)
lake build zil
```

---

## Core Concepts: Relational Tuples & Rules 

System state in ZIL is declared as a set of strongly typed **relation tuples**, Google Zanzibar core lang shines here:
```text
<entity>#<relationship>@<target> [optional_attributes].
```

Zil describes concepts, can be physical or virtual nodes, networks, cloud resources, microservices, or state machines. Inference rules (Datalog Horn clauses) derive new relationships and system states:

```zc
// Multi-region interconnect
location:dc_west#connected_to@location:dc_east [link="mpls", bandwidth_gbps=100].

// Infrastructure deployment
service:payment_api#deployed_on@location:dc_west.
service:payment_api#depends_on@service:postgres_cluster.

// Cascading failure rule with stratified negation
RULE cascadingDegradation:
IF ?service#depends_on@?dep AND NOT ?dep#status@value:healthy
THEN ?service#status@value:degraded.
```

---

## Capabilities & Hands-On Examples

### 1. Service Topology, Cycle Detection & Change Impact Analysis

ZIL uses a macro system leveraged from Lean4, one scenario would  use it to  model complex service architectures to detect circular dependencies 
and calculate blast radius prior to infrastructure deployments or migrations.

Save the following model as `service_mesh.zc`:

```zc
MODULE service_mesh.

// Service Dependencies
service:frontend#depends_on@service:gateway.
service:gateway#depends_on@service:auth.
service:gateway#depends_on@service:orders.
service:orders#depends_on@service:database.
service:auth#depends_on@service:database.

// Upstream Infrastructure Dependency
service:database#hosted_on@infra:rds_primary.

// Circular Dependency Bug (Detected by ZIL)
service:monitoring_agent#depends_on@service:telemetry_collector.
service:telemetry_collector#depends_on@service:monitoring_agent.

// Transitive Dependency Propagation Rule
RULE transitiveDependency:
IF ?service#depends_on@?dep AND ?dep#depends_on@?upstream
THEN ?service#depends_on@?upstream.
```

#### A. Detect Dependency Topologies and Cycles
Inspect the directed graph and identify circular dependency cycles:

```bash
./bin/zil dependency-graph service_mesh.zc
```

**Output:**
```text
ZIL-DEPENDENCY-GRAPH    1
nodes   8
edges   8
cycles  service.monitoring_agent,service.telemetry_collector
edge    service.frontend           zil.dependsOn  service.gateway              1
edge    service.gateway            zil.dependsOn  service.auth                 2
edge    service.gateway            zil.dependsOn  service.orders               3
edge    service.orders             zil.dependsOn  service.database             4
edge    service.auth               zil.dependsOn  service.database             5
edge    service.database           zil.hostedOn   infra.rds_primary            6
edge    service.monitoring_agent   zil.dependsOn  service.telemetry_collector  7
edge    service.telemetry_collector zil.dependsOn service.monitoring_agent     8
```

#### B. Calculate Change Impact & Blast Radius
Calculate every component impacted if `infra:rds_primary` undergoes maintenance or experiences an outage:

```bash
./bin/zil impact service_mesh.zc infra:rds_primary
```

**Output:**
```text
ZIL-CHANGE-IMPACT       1
status          known
changed         infra.rds_primary
cycles          service.monitoring_agent,service.telemetry_collector
affected        5
impact          service.database   1   direct      service.database#zil.hostedOn@infra.rds_primary
impact          service.auth       2   transitive  service.auth#zil.dependsOn@service.database -> service.database#zil.hostedOn@infra.rds_primary
impact          service.orders     2   transitive  service.orders#zil.dependsOn@service.database -> service.database#zil.hostedOn@infra.rds_primary
impact          service.gateway    3   transitive  service.gateway#zil.dependsOn@service.orders -> ...
impact          service.frontend   4   transitive  service.frontend#zil.dependsOn@service.gateway -> ...
```

---

###  Infrastructure Reliability & Audit Provenance

ZIL's Datalog engine evaluates **stratified negation** to model degraded operational states, network failovers, and circuit breakers.

Save the following model as `infrastructure.zc`:

```zc
MODULE infrastructure.

// Datacenter Interconnects
location:dc_west#connected_to@location:dc_east [link="mpls"].
location:dc_west#connected_to@location:dc_east [link="internet"].
network:vpn_overlay#overlays@link:internet.

// Service Topology & Primary/Replica Mirroring
app:api_server#deployed_on@location:dc_west.
app:api_server#mirrored_by@app:api_server_standby.
app:api_server#depends_on@service:database_cluster.

// Cascading Failure Invariant Rule:
// If a dependency is not marked healthy, the dependent application is degraded
RULE dependencyFailure:
IF ?app#depends_on@?dep AND NOT ?dep#status@value:healthy
THEN ?app#state@value:degraded.

QUERY degraded_services:
FIND ?app WHERE ?app#state@value:degraded.
```


###  Compiling System Architectures to Machine-Checked Lean 4 Code

ZIL models compile directly into strongly typed Lean 4 definitions, inductive AST expressions, and formal Datalog programs:

```bash
./bin/zil compile infrastructure.zc -
```

**Generated Lean 4 Output:**
```lean
import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Generated.infrastructure

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `location.dc_west)
      `zil.connectedTo
      (.ground `location.dc_east) with
    attrs := #[{ key := `link, value := .text "mpls" }]
    source := { frontend := "zc", line := some 4 } }

private def sourceRule0 : Zil.Rule := {
  name := `dependencyFailure
  variables := #[`app, `dep]
  premises := #[
    { Zil.RelExpr.mkWithAttrs (.variable `app) `zil.dependsOn (.variable `dep) #[] with
      source := { frontend := "zc", line := some 14 } }
  ]
  negativePremises := #[
    { Zil.RelExpr.mkWithAttrs (.variable `dep) `zil.status (.ground `value.healthy) #[] with
      source := { frontend := "zc", line := some 14 } }
  ]
  conclusion := {
    Zil.RelExpr.mkWithAttrs (.variable `app) `zil.state (.ground `value.degraded) #[] with
    source := { frontend := "zc", line := some 15 }
  }
  trust := .graphDerived
  source := { frontend := "zc", line := some 13 }
}
end Zil.Generated.infrastructure
```

Because ZIL compiles to native Lean 4, system properties can be checked against the Lean 4 kernel with mathematical proofs guaranteeing deterministic evaluation and termination.



### Distributed Protocols & State Machines (`LTS_ATOM`)

ZIL natively supports Labeled Transition Systems (`LTS_ATOM`) to model distributed protocol state transitions, connection handshakes, and recovery states:

```zc
MODULE protocol.

LTS_ATOM tunnel_session [
  states=#{offline connecting ready degraded},
  initial=offline,
  transitions={
    [offline start] [connecting],
    [connecting auth_ok] [ready],
    [ready transport_drop] [degraded],
    [degraded recover] [ready]
  }
].

POLICY no_split_brain_transport [
  condition="NOT (single_path AND dual_path)",
  criticality=high
].
```

Export state machine models directly to TLA+ for temporal model checking with TLC:

```bash
./bin/zil export-tla protocol.zc -
```

---

## Companion Library: `zil-lib`
Zil needs help ! this began with the idea that we need a generalized way to describe how systems and concepts aka knowledge graph (db)
should leverage lean4 to allow AI agents to link tla+ specs, system behaviors and verify system using lean4 as foundations. 

Project would benefit from DSL Design and core language as well as the lean4 community and the tla+ community
so far project has a companion repo; it includes some Advanced formal verification and solver integration capabilities maintained in 
[zil-lib](https://github.com/jagg-ix/zil-lib) library that leveraged Zil Macro system:

- **SMT-Backed Policy Equivalence (`zilLib equiv`):** Formally proves that two refactored rule sets or architectures are semantically identical using Z3.
- **Rule Repair Hints (`zilLib repair`):** Automatically suggests minimal rule modifications to repair broken architectural invariants.
- **Automated Test Generation (`zilLib gentests`):** Generates test suites achieving 100% path coverage over complex rule graphs.
- **Causal Revisions & Stale Views (`spec/stale-views-v0.1.md`):** Models distributed replica lag, causal bounds, and read/write consistency.
- **Numeric Limits & Quota Arithmetic (`spec/numeric-limits-v0.1.md`):** Models concurrency quotas, rate-limiting budgets, and burst capacities.
- **Assume-Guarantee Policy Composition (`spec/composition-v0.1.md`):** Verifies modular sub-systems under formal environment assumptions.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
