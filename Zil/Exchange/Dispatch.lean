import Zil.Exchange.Protocol
import Zil.Parser.DeclarationProgram
import Zil.Engine.Provenance
import Zil.Authorization
import Zil.Impact
import Zil.RecoveryAudit

namespace Zil.Exchange

private def loadProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def parseName (value : String) : IO Name :=
  match Zil.Parser.nameFromToken value with
  | .ok name => pure name
  | .error error => throw <| IO.userError error

private def authorizationRequest
    (object relation subject : String) : IO Zil.Authorization.Request := do
  let objectTerm ← match Zil.Parser.termFromToken object with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let relationName ← match Zil.Parser.relationNameFromToken relation with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let subjectTerm ← match Zil.Parser.termFromToken subject with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  pure { object := objectTerm, relation := relationName, subject := subjectTerm }

private def parseSummary (program : Zil.Program) : String :=
  String.intercalate "\n" [
    "ZIL-PARSE-SUMMARY\t1",
    "module\t" ++ (program.moduleName.map (·.toString)).getD "-",
    "valid\t" ++ (if program.valid then "true" else "false"),
    "tuples\t" ++ toString program.tuples.size,
    "facts\t" ++ toString program.facts.size,
    "rules\t" ++ toString program.allRules.size,
    "queries\t" ++ toString program.queries.size,
    "macros\t" ++ toString program.macros.size,
    "expansions\t" ++ toString program.expansions.size,
    "declarations\t" ++ toString program.declarations.size,
    ""
  ]

private def runParse (request : Request) : IO String := do
  let program ← loadProgram request.inputPath
  pure (parseSummary program)

private def runExpand (request : Request) : IO String := do
  let expanded ← Zil.Parser.MacroProgram.expandFile request.inputPath
  match expanded with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def runQuery (request : Request) : IO String := do
  let program ← loadProgram request.inputPath
  let queryName ← parseName request.arguments[0]!
  let query ← match program.queries.find? (fun query => query.name == queryName) with
    | some value => pure value
    | none => throw <| IO.userError s!"query {queryName} was not found"
  let trace ← match Zil.Engine.Provenance.traceProgram program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let witnesses := Zil.Engine.Provenance.queryWitnesses trace query
  pure (Zil.Engine.Provenance.renderQueryWitnesses trace query witnesses)

private def runAuthorize (request : Request) : IO String := do
  let program ← loadProgram request.inputPath
  let authorization ← authorizationRequest
    request.arguments[0]! request.arguments[1]! request.arguments[2]!
  let decision ← match Zil.Authorization.decide program authorization with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  pure (Zil.Authorization.render decision)

private def runImpact (request : Request) : IO String := do
  let program ← loadProgram request.inputPath
  let changed ← parseName request.arguments[0]!
  let graph ← match Zil.Impact.fromProgram program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  pure (Zil.Impact.renderImpact (Zil.Impact.analyze graph changed))

private def runRecoveryAudit (request : Request) : IO String := do
  let program ← loadProgram request.inputPath
  let requestNode ← parseName request.arguments[0]!
  let audit ← match Zil.RecoveryAudit.auditProgram program requestNode with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  pure (Zil.RecoveryAudit.render audit)

private def execute (request : Request) : IO String :=
  match request.operation with
  | "parse" => runParse request
  | "expand" => runExpand request
  | "query" => runQuery request
  | "authorize" => runAuthorize request
  | "impact" => runImpact request
  | "recovery-audit" => runRecoveryAudit request
  | value => throw <| IO.userError s!"unsupported operation {value}"

/-- Dispatch one validated request without accepting arbitrary executable names. -/
def dispatch (request : Request) : IO Response := do
  match request.validate with
  | .error error =>
      pure <| Response.failure request.requestId request.operation request.inputSha256
        "invalid" error
  | .ok _ =>
      try
        let payload ← execute request
        pure (Response.success request payload)
      catch error =>
        pure <| Response.failure request.requestId request.operation request.inputSha256
          "error" error.toString

end Zil.Exchange
