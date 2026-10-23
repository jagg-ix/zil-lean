import Zil.Exchange.Protocol
import Zil.Json.Ordered

/-!
# Capability ownership

Which capability is owned by whom. The semantic capabilities are Lean's and each is bound to one exchange operation;
the operational ones (durable store, control plane, supervision, projection, evaluation, extensions) are Lean programs
too now, and external tools stay external. `validate` fails closed when the table is ambiguous or disagrees with the
worker's allowlist, so a command can only be dispatched to a capability Lean owns.
-/

namespace Zil.Control.Capability

open Zil.Json

def schema : String := "ZIL-CAPABILITY-OWNERSHIP/1"

structure Capability where
  id : String
  authority : String
  assurance : Option String := none
  operation : Option String := none
  commands : List String := []
  schemaId : Option String := none
  deriving Inhabited

def authorities : List String := ["lean", "external"]
def assuranceLevels : List String := ["exploratory", "validated", "kernel-backed", "externally-attested", "byte-attested"]

private def semantic (id operation assurance : String) (commands : List String) : Capability :=
  { id, authority := "lean", assurance := some assurance, operation := some operation, commands }

/-- The inventory. -/
def inventory : List Capability := [
  semantic "parse-v1" "parse" "validated" ["parse"],
  semantic "compile-v1" "compile" "validated" ["compile"],
  semantic "expand-v1" "expand" "validated" ["expand"],
  semantic "conformance-v1" "conformance" "validated" ["conformance"],
  { id := "query-v1", authority := "lean", assurance := some "validated", operation := some "query",
    commands := ["query-plan", "query-ci", "explain-query"] },
  { id := "authorization-v1", authority := "lean", assurance := some "validated", operation := some "authorize",
    commands := ["authorize", "explain-authorization"] },
  { id := "impact-v1", authority := "lean", assurance := some "validated", operation := some "impact",
    commands := ["dependency-graph", "impact"] },
  { id := "recovery-audit-v1", authority := "lean", assurance := some "validated", operation := some "recovery-audit",
    commands := ["recovery-audit"] },
  { id := "formalization-v1", authority := "lean", assurance := some "validated",
    commands := ["formalization-plan", "formalization-next"] },
  { id := "agent-context-v1", authority := "lean", assurance := some "validated", commands := ["agent-context"] },
  { id := "proof-obligation-v1", authority := "lean", assurance := some "validated", commands := ["proof-obligations"] },
  { id := "theorem-audit-v1", authority := "lean", assurance := some "kernel-backed", commands := ["theorem-audit"] },
  { id := "action-token-v1", authority := "lean", assurance := some "validated", commands := ["action-token"] },
  { id := "token-lifecycle-v1", authority := "lean", assurance := some "validated", commands := ["token-lifecycle"] },
  { id := "event-store-v1", authority := "lean", assurance := some "byte-attested", commands := ["control-store"] },
  { id := "control-event-v1", authority := "lean", schemaId := some "ZIL-CONTROL-EVENT/1" },
  { id := "control-receipt-v1", authority := "lean", assurance := some "byte-attested",
    schemaId := some "ZIL-CONTROL-RECEIPT/1" },
  { id := "workflow-projection-v1", authority := "lean", assurance := some "exploratory",
    schemaId := some "ZIL-WORKFLOW-PROJECTION/1" },
  { id := "worker-supervision-v1", authority := "lean", assurance := some "byte-attested" },
  { id := "control-plane-v1", authority := "lean", assurance := some "byte-attested", commands := ["control", "exchange"] },
  { id := "runtime-evaluation-v1", authority := "lean", assurance := some "exploratory",
    schemaId := some "ZIL-RUNTIME-EVALUATION/1", commands := ["evaluate-runtime"] },
  { id := "extension-registry-v1", authority := "lean", assurance := some "exploratory",
    schemaId := some "ZIL-EXTENSION/1", commands := ["plugin"] },
  { id := "evidence-envelope-v1", authority := "lean", schemaId := some "ZIL-EVIDENCE/1" },
  { id := "external-tool-v1", authority := "external", assurance := some "externally-attested" },
  { id := "exchange-v1", authority := "lean", schemaId := some "ZIL-EXCHANGE/1" }]

private def duplicates (values : List String) : List String :=
  (values.filter fun v => (values.filter (· == v)).length > 1).eraseDups

/-- Fail closed on an ambiguous inventory or one that disagrees with the worker's allowlist. -/
def validate (capabilities : List Capability := inventory) : Except String Unit := do
  let ids := capabilities.map (·.id)
  unless (duplicates ids).isEmpty do throw s!"duplicate capability identifiers {duplicates ids}"
  let operations := capabilities.filterMap (·.operation)
  unless (duplicates operations).isEmpty do throw s!"duplicate operation ownership declarations {duplicates operations}"
  for capability in capabilities do
    unless authorities.contains capability.authority do throw s!"capability {capability.id} has an invalid authority"
    if let some level := capability.assurance then
      unless assuranceLevels.contains level do throw s!"capability {capability.id} has an invalid assurance level"
    if let some operation := capability.operation then
      unless capability.authority == "lean" do throw s!"exchange operation {operation} must remain Lean-authoritative"
      match Zil.Exchange.requiredCapability? operation with
      | none => throw s!"inventory declares an unknown worker operation {operation}"
      | some required => unless capability.id == required do
          throw s!"capability {capability.id} disagrees with the worker protocol ({required})"
  for operation in ["parse", "compile", "expand", "conformance", "query", "authorize", "impact", "recovery-audit"] do
    unless operations.contains operation do throw s!"worker operation {operation} has no ownership declaration"

/-- The capability that owns an exchange operation. -/
def forOperation? (operation : String) (capabilities : List Capability := inventory) : Option Capability :=
  capabilities.find? (·.operation == some operation)

/-- The owner of `operation`, which must be Lean. -/
def requireLeanOperation (operation : String) (capabilities : List Capability := inventory) : Except String Capability := do
  match forOperation? operation capabilities with
  | none => throw s!"operation {operation} is not declared in the control-plane inventory"
  | some capability =>
      unless capability.authority == "lean" do throw s!"operation {operation} is not Lean-authoritative"
      return capability

def Capability.toJson (capability : Capability) : J :=
  .obj <| #[("id", .str capability.id), ("authority", .str capability.authority)] ++
    (match capability.assurance with | some a => #[("assurance", .str a)] | none => #[]) ++
    (match capability.operation with | some o => #[("operation", .str o)] | none => #[]) ++
    (match capability.schemaId with | some s => #[("schema", .str s)] | none => #[]) ++
    (if capability.commands.isEmpty then #[] else #[("commands", .arr (capability.commands.toArray.map .str))])

def inventoryJson : J :=
  .obj #[("schema", .str schema), ("capabilities", .arr (inventory.toArray.map Capability.toJson))]

end Zil.Control.Capability
