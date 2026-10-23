import Zil.Control.Durable
import Zil.Edn.Reader

/-!
# `zilControl`: exchange client, control plane and durable control store

    zilControl exchange <operation> <input-path> [operation-arguments...]
    zilControl run <operation> <input-path> [operation-arguments...]
    zilControl capabilities
    zilControl store status|verify|project <database> <stream>
    zilControl store invoke <database> <stream> <expected-revision> <actor> <operation> <input-path> [arguments...]
    zilControl store record <database> <stream> <expected-revision> <actor> <event-type> <decision-sha256> <payload.edn|json>

Exit status: 0 on success, 1 for a valid operation that fails or a verification that finds a mismatch, 2 for a malformed
command or an error of the exchange itself.
-/

open Zil.Json Zil.Control Zil.Store.ControlEvent Zil.Worker

private def usage : String :=
  "zilControl exchange <operation> <input-path> [operation-arguments...]\n" ++
  "zilControl run <operation> <input-path> [operation-arguments...]\n" ++
  "zilControl capabilities\n" ++
  "zilControl store status <database> <stream>\n" ++
  "zilControl store verify <database> <stream>\n" ++
  "zilControl store project <database> <stream>\n" ++
  "zilControl store invoke <database> <stream> <expected-revision> <actor> <operation> <input-path> [arguments...]\n" ++
  "zilControl store record <database> <stream> <expected-revision> <actor> <event-type> <decision-sha256> <payload.edn|json>"

private def usageError : IO α := throw (IO.userError s!"invalid-command: {usage}")

private def revision (text : String) : IO Nat :=
  match text.toNat? with
  | some n => pure n
  | none => throw (IO.userError s!"invalid-command: expected revision must be an integer ({text})")

private def okOf (value : J) : Bool := value.get? "ok" == some (.bool true)

private def exitCode (ok : Bool) : UInt32 := if ok then 0 else 1

private def printJson (value : J) : IO Unit := IO.println (write value)

private def readPayload (path : String) : IO J := do
  let text ← IO.FS.readFile path
  let parsed := if path.endsWith ".json" then Zil.Json.parse text else Zil.Edn.readCanonical text
  match parsed with
  | .ok value => pure value
  | .error message => throw (IO.userError s!"invalid-command: cannot read {path}: {message}")

private def fieldOf (payload : J) (names : List String) : Option String :=
  names.findSome? payload.getStr?

private def freshRequestId : IO String := do
  let bytes ← IO.getRandomBytes 16
  return "request:" ++ (Zil.Crypto.Sha256.toHex bytes).take 32

private def runStore (command : String) (database stream : String) (tail : List String) : IO UInt32 := do
  let db : System.FilePath := database
  match command, tail with
  | "status", [] =>
      let value ← Durable.workflowStatus db stream
      printJson value
      return exitCode (((value.get? "integrity").map okOf).getD false)
  | "verify", [] =>
      let value ← verifyStore db stream
      printJson value
      return exitCode (okOf value)
  | "project", [] =>
      let value ← Durable.projectWorkflows db stream
      printJson value
      return exitCode (okOf value)
  | "invoke", expected :: actor :: operation :: inputPath :: arguments =>
      let plane ← Runtime.start 1
      try
        let value ← Durable.invokeAndRecord plane db
          { stream, expectedRevision := ← revision expected, actor, operation, inputPath, arguments := arguments.toArray }
        Runtime.stop plane
        printJson value
        return exitCode (okOf value)
      catch error =>
        try Runtime.stop plane catch _ => pure ()
        throw error
  | "record", [expected, actor, eventType, decisionSha, payloadPath] =>
      let payload ← readPayload payloadPath
      let result ← Durable.recordWorkflowEvent db
        { stream, expectedRevision := ← revision expected, eventType, actor,
          requestId := fieldOf payload ["request_id", "request-id"],
          baseRevision := (fieldOf payload ["base_revision", "base-revision"]).orElse fun _ => some "-",
          contextBundleId := (fieldOf payload ["context_bundle_id", "context-bundle-id"]).orElse fun _ => some "-",
          decisionSha256 := decisionSha,
          pluginId := (fieldOf payload ["plugin_id", "plugin-id"]).orElse fun _ => some "-", payload }
      printJson result.toJson
      return exitCode true
  | _, _ => usageError

private def run (args : List String) : IO UInt32 := do
  match args with
  | ["capabilities"] =>
      printJson Capability.inventoryJson
      return exitCode true
  | "store" :: command :: database :: stream :: tail => runStore command database stream tail
  | cmd :: operation :: inputPath :: arguments =>
      if cmd == "exchange" then
        let response ← invokeOnce (← buildRequest (← freshRequestId) operation inputPath "-" arguments.toArray) {} (← configuredTimeoutMs)
        printJson response.toJson
        return exitCode (response.status == "ok")
      else if cmd == "run" then
        let plane ← Runtime.start 1
        try
          let response ← Runtime.execute plane operation inputPath arguments.toArray
          Runtime.stop plane
          printJson response.toJson
          return exitCode (response.status == "ok")
        catch error =>
          try Runtime.stop plane catch _ => pure ()
          throw error
      else usageError
  | _ => usageError

def main (args : List String) : IO UInt32 := do
  let args := match args with | "--" :: rest => rest | other => other
  try
    run args
  catch error =>
    IO.eprintln s!"{error}"
    return (2 : UInt32)
