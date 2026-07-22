import Zil.Syntax.Certified

open Zil

private def graphRule : Rule :=
  { name := `certifiedExample
    variables := #[`claim]
    premises := #[.mk' (.variable `claim) `zil.supportedBy (.ground `source.kernel)]
    conclusion := .mk' (.variable `claim) `zil.status (.ground `status.checked)
    trust := .graphDerived }

private theorem certificateProposition : True := True.intro

def certified : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificateProposition

zil_register_certified_rule certified

#guard certified.isCertified
#guard certified.graphRule.trust == .certified
#guard graphRule.trust == .graphDerived

run_cmd do
  let env ← getEnv
  unless (Zil.Trust.certifiedRules env).any (fun entry => entry.rule.name == `certifiedExample) do
    throwError "certified rule was not persisted"
