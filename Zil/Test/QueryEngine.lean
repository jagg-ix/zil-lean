import Zil.Engine.Query

open Zil

private def declaration := Term.ground `lean.query.demo
private def claim := Term.ground `claim.queryDemo
private def requirement := Term.ground `requirement.queryDemo

private def facts : Array RelExpr := #[
  RelExpr.mk' declaration `zil.formalizes claim,
  RelExpr.mk' declaration `zil.requires requirement
]

private def transfer : Rule :=
  { name := `queryTransfer
    variables := #[`declaration, `claim, `requirement]
    premises := #[
      RelExpr.mk' (.variable `declaration) `zil.formalizes (.variable `claim),
      RelExpr.mk' (.variable `declaration) `zil.requires (.variable `requirement)
    ]
    conclusion := RelExpr.mk' (.variable `claim) `zil.requiresClaim (.variable `requirement) }

private def target := RelExpr.mk' claim `zil.requiresClaim requirement

private def requirementQuery : Query :=
  { name := `requirementQuery
    variables := #[`claim, `requirement]
    select := #[`requirement]
    premises := #[RelExpr.mk' (.variable `claim) `zil.requiresClaim (.variable `requirement)] }

#guard Zil.Engine.entails facts #[transfer] target
#guard (Zil.Engine.closure facts #[transfer]).size == 3
#guard (Zil.Engine.solve (Zil.Engine.closure facts #[transfer]) requirementQuery).size == 1
#guard (Zil.Engine.closure facts #[transfer, transfer]).size == 3
