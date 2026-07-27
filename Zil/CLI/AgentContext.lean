import Zil.Parser.DeclarationProgram
import Zil.AgentContext

namespace Zil.CLI

private def loadContextProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeContextOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

private def contextName (token : String) : IO Name :=
  match Zil.Parser.nameFromToken token with
  | .ok name => pure name
  | .error error => throw <| IO.userError error

private def contextNames (text : String) : IO (Array Name) := do
  if text == "-" || text.isEmpty then return #[]
  let mut out : Array Name := #[]
  for token in text.splitOn "," do
    let trimmed := token.trim
    if trimmed.isEmpty then
      throw <| IO.userError "context name lists may not contain empty values"
    out := out.push (← contextName trimmed)
  pure out

/-- Build and emit one deterministic agent context bundle. -/
def agentContextFile
    (inputPath taskId agentId scope changedText : String)
    (queryText : String := "-")
    (targetText : String := "-")
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadContextProgram inputPath
  let changed ← contextNames changedText
  let queries ← contextNames queryText
  let targets ← contextNames targetText
  let request : Zil.AgentContext.Request := {
    taskId
    agentId
    scope
    changedNodes := changed
    requestedQueries := queries
    requestedTargets := targets
  }
  let bundle ← match Zil.AgentContext.build program request with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeContextOutput (Zil.AgentContext.render bundle) outputPath
  pure bundle.complete

end Zil.CLI
