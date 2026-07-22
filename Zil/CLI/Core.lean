import Zil.Interop.Exchange
import Zil.Interop.Delta
import Zil.Engine.Query
import Zil.Export.Logic

namespace Zil.CLI

structure Session where
  envelope : Zil.Interop.ExchangeEnvelope
  deriving Repr, Inhabited

inductive Command where
  | summary
  | closure
  | check (relation : Zil.RelExpr)
  | query (pattern : Zil.RelExpr)
  | export (format : Zil.Export.LogicFormat)
  deriving Repr, Inhabited

private def relationVariables (relation : Zil.RelExpr) : Array Name :=
  let variables := match relation.subject with
    | .var name => #[name]
    | .node _ => #[]
  match relation.object with
  | .var name => if variables.contains name then variables else variables.push name
  | .node _ => variables

private def renderBinding (binding : Zil.Engine.Binding) : String :=
  String.intercalate ", " <| binding.toList.map fun pair =>
    s!"{pair.1}={repr pair.2}"

private def summary (envelope : Zil.Interop.ExchangeEnvelope) : String :=
  String.intercalate "\n" [
    s!"schema: {envelope.schemaVersion}",
    s!"revision: {envelope.knowledgeRevision}",
    s!"profile: {envelope.profileName.map (·.toString) |>.getD "-"}",
    s!"profile-version: {envelope.profileVersion.getD "-"}",
    s!"facts: {envelope.facts.size}",
    s!"rules: {envelope.rules.size}"
  ]

/-- Execute one side-effect-free CLI command against native Lean graph state. -/
def execute (session : Session) : Command → String
  | .summary => summary session.envelope
  | .closure =>
      let closed := Zil.Engine.closure session.envelope.facts session.envelope.rules
      String.intercalate "\n" <| closed.toList.map Zil.Codec.encodeRelation
  | .check relation =>
      if Zil.Engine.entails session.envelope.facts session.envelope.rules relation
      then "true" else "false"
  | .query pattern =>
      let variables := relationVariables pattern
      let query : Zil.Query := {
        name := `cli.query
        variables
        select := variables
        premises := #[pattern] }
      let closed := Zil.Engine.closure session.envelope.facts session.envelope.rules
      let answers := Zil.Engine.solve closed query
      if answers.isEmpty then "no results"
      else String.intercalate "\n" <| answers.toList.map renderBinding
  | .export format =>
      Zil.Export.exportProgram format session.envelope.facts session.envelope.rules

/-- Parse a textual REPL or batch command. -/
def parseCommand (line : String) : Except String Command := do
  let trimmed := line.trim
  if trimmed == "summary" then pure .summary
  else if trimmed == "closure" then pure .closure
  else if trimmed == "export souffle" then pure (.export .souffle)
  else if trimmed == "export prolog" then pure (.export .prolog)
  else if trimmed.startsWith "check " then
    pure (.check (← Zil.Codec.decodeRelation (trimmed.drop 6)))
  else if trimmed.startsWith "query " then
    pure (.query (← Zil.Codec.decodeRelation (trimmed.drop 6)))
  else throw s!"unknown command: {trimmed}"

end Zil.CLI
