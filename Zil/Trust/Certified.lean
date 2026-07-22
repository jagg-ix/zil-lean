import Lean
import Zil.Environment.Knowledge

namespace Zil.Trust

/-- A graph rule accompanied by a kernel-checked Lean proposition and proof. -/
structure CertifiedRule where
  rule : Zil.Rule
  proposition : Prop
  proof : proposition

namespace CertifiedRule

/-- Construct a certified wrapper while forcing the exported graph rule trust class. -/
def mkChecked (rule : Zil.Rule) (proposition : Prop) (proof : proposition) : CertifiedRule :=
  { rule := { rule with trust := .certified }, proposition, proof }

/-- The graph rule visible to the query engine. -/
def graphRule (certified : CertifiedRule) : Zil.Rule := certified.rule

/-- Certification can only be observed through the proof-carrying wrapper. -/
def isCertified (certified : CertifiedRule) : Bool :=
  certified.rule.trust == .certified

end CertifiedRule

abbrev CertifiedState := Array CertifiedRule

private def appendCertified (state : CertifiedState) (entry : CertifiedRule) : CertifiedState :=
  if state.any fun current => current.rule.name == entry.rule.name then state else state.push entry

private def importCertified (states : Array CertifiedState) : CertifiedState :=
  states.foldl (init := #[]) fun acc state => state.foldl (init := acc) appendCertified

initialize certifiedRuleExtension : Lean.SimplePersistentEnvExtension CertifiedRule CertifiedState ←
  Lean.registerSimplePersistentEnvExtension {
    name := `zilCertifiedRuleExtension
    addEntryFn := appendCertified
    addImportedFn := importCertified
  }

def certifiedRules (env : Lean.Environment) : CertifiedState :=
  certifiedRuleExtension.getState env

def addCertifiedRule (entry : CertifiedRule) : Lean.CoreM Unit :=
  Lean.modifyEnv fun env => certifiedRuleExtension.addEntry env entry

/-- Graph rules available for inference, including proof-carrying certified rules. -/
def inferenceRules (env : Lean.Environment) : Array Zil.Rule :=
  Zil.Environment.rules env ++ (certifiedRules env).map (·.graphRule)

end Zil.Trust
