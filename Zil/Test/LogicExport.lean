import Zil.Export.Logic

open Zil

private def facts : Array RelExpr := #[
  .mk' (.ground `lean.Export.metric) `zil.formalizes (.ground `claim.metric),
  .mk' (.ground `lean.Export.metric) `zil.requires (.ground `requirement.lorentzian)]

private def rule : Rule :=
  { name := `exportRequirement
    variables := #[`declaration, `claim, `requirement]
    premises := #[
      .mk' (.variable `declaration) `zil.formalizes (.variable `claim),
      .mk' (.variable `declaration) `zil.requires (.variable `requirement)]
    conclusion := .mk' (.variable `claim) `zil.requiresClaim (.variable `requirement)
    trust := .graphDerived }

private def prolog := Zil.Export.exportProgram .prolog facts #[rule]
private def souffle := Zil.Export.exportProgram .souffle facts #[rule]

#guard prolog.splitOn "\n" |>.contains
  "zil_formalizes('lean.Export.metric', 'claim.metric')."

#guard prolog.splitOn "\n" |>.contains
  "zil_requiresclaim(V_claim, V_requirement) :- zil_formalizes(V_declaration, V_claim), zil_requires(V_declaration, V_requirement)."

#guard souffle.splitOn "\n" |>.contains
  ".decl zil_formalizes(subject:symbol, object:symbol)"

#guard !prolog.splitOn "\n" |>.any fun line => line.startsWith ".decl"