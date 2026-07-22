import Zil.Core.Rule

namespace Zil.Export

inductive LogicFormat where
  | souffle
  | prolog
  deriving Repr, BEq, Inhabited

private def sanitizeChar (c : Char) : Char :=
  if c.isAlphanum then c.toLower else '_'

private def sanitizeName (name : Name) : String :=
  let raw := name.toString.map sanitizeChar
  if raw.isEmpty then "zil_relation"
  else if raw.front.isDigit then "zil_" ++ raw else raw

private def escapeAtom (value : String) : String :=
  value.replace "\\" "\\\\" |>.replace "'" "\\'"

private def renderGround (name : Name) : String :=
  s!"'{escapeAtom name.toString}'"

private def renderVariable (name : Name) : String :=
  "V_" ++ sanitizeName name

private def renderTerm : Zil.Term → String
  | .var name => renderVariable name
  | .node node => renderGround node.name

private def renderRelation (relation : Zil.RelExpr) : String :=
  s!"{sanitizeName relation.relation}({renderTerm relation.subject}, {renderTerm relation.object})"

private def relationNames (facts : Array Zil.RelExpr) (rules : Array Zil.Rule) : Array Name :=
  let fromFacts := facts.map (·.relation)
  let fromRules := rules.foldl (init := #[]) fun acc rule =>
    acc ++ rule.premises.map (·.relation) ++ #[rule.conclusion.relation]
  (fromFacts ++ fromRules).foldl (init := #[]) fun acc name =>
    if acc.contains name then acc else acc.push name

private def renderFact (fact : Zil.RelExpr) : String :=
  renderRelation fact ++ "."

private def renderRule (rule : Zil.Rule) : String :=
  let body := String.intercalate ", " (rule.premises.map renderRelation).toList
  s!"{renderRelation rule.conclusion} :- {body}."

private def renderSouffleDecl (name : Name) : String :=
  s!".decl {sanitizeName name}(subject:symbol, object:symbol)"

/-- Deterministically export canonical graph knowledge to Soufflé or Prolog. -/
def exportProgram (format : LogicFormat) (facts : Array Zil.RelExpr)
    (rules : Array Zil.Rule) : String :=
  let factRows := facts.map renderFact
  let ruleRows := rules.map renderRule
  match format with
  | .prolog => String.intercalate "\n" (factRows ++ ruleRows).toList
  | .souffle =>
      let declarations := relationNames facts rules |>.map renderSouffleDecl
      String.intercalate "\n" (declarations ++ #[""] ++ factRows ++ ruleRows).toList

/-- Export one persistent environment without changing graph trust. -/
def exportEnvironment (format : LogicFormat) (env : Lean.Environment) : String :=
  exportProgram format (Zil.Environment.facts env) (Zil.Environment.rules env)

end Zil.Export