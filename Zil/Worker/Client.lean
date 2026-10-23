import Zil.Exchange.Protocol
import Zil.Crypto.Sha256
import Zil.Json.Ordered

/-!
# Exchange worker client

Supervises a native `zilWorker` process speaking `ZIL-EXCHANGE/1` over JSON Lines. The client builds the canonical
request, binds it to the SHA-256 of the exact input bytes, refuses any response that changes the request's identity or
claims more than the protocol allows, and adds the transport SHA-256 of the result payload. Lean stays the semantic
authority: the client never changes `authority`, `assurance`, the payload or the errors.
-/

namespace Zil.Worker

open Zil.Json Zil.Crypto

def defaultTimeoutMs : Nat := 30000
def pendingAttestationWarning : String := "result-sha256-pending-client-attestation"
def workerStatuses : List String := ["ok", "invalid", "unsupported", "error"]

/-- `sha256:` and the digest of a file's exact bytes. -/
def sha256File (path : System.FilePath) : IO String := do
  return Sha256.prefixed (← IO.FS.readBinFile path)

/-- Raised for anything that is a failure of the exchange rather than a semantic result. -/
def transportError (message : String) : IO α := throw (IO.userError s!"transport-error: {message}")

private def sortedDistinct (values : Array String) : Array String :=
  (values.qsort (· < ·)).foldl (fun out v => if out.back? == some v then out else out.push v) #[]

/-- The request with its fields in the protocol's order, bound to the input's current bytes. -/
def buildRequest (requestId operation inputPath : String) (baseRevision : String := "-")
    (arguments : Array String := #[]) (capabilities : Option (Array String) := none) : IO Zil.Exchange.Request := do
  let capability? := Zil.Exchange.requiredCapability? operation
  let capabilities := capabilities.getD (match capability? with | some c => #[c] | none => #[])
  return { schema := Zil.Exchange.schema, requestId, protocolVersion := Zil.Exchange.protocolVersion, operation,
           inputPath, baseRevision, inputSha256 := ← sha256File inputPath,
           capabilities := sortedDistinct capabilities, arguments }

/-- One request as the line written to the worker. -/
def requestLine (request : Zil.Exchange.Request) : String :=
  write (escapeSlash := false) <| .obj #[
    ("schema", .str request.schema), ("request_id", .str request.requestId),
    ("protocol_version", .int request.protocolVersion), ("operation", .str request.operation),
    ("input_path", .str request.inputPath), ("base_revision", .str request.baseRevision),
    ("input_sha256", .str request.inputSha256), ("capabilities", .arr (request.capabilities.map .str)),
    ("arguments", .arr (request.arguments.map .str))]

/-- A decoded worker response, with every field the protocol defines. -/
structure Response where
  schema : String
  requestId : String
  protocolVersion : Nat
  operation : String
  status : String
  authority : String
  assurance : String
  inputSha256 : String
  resultSha256 : String
  payload : String
  errors : Array String
  warnings : Array String

private def strArray (value : J) (key : String) : Except String (Array String) :=
  match value.get? key with
  | some (.arr items) => items.mapM fun item => match item with | .str s => pure s | _ => throw s!"{key} must hold strings"
  | _ => throw s!"response lacks {key}"

def Response.decode (line : String) : Except String Response := do
  let json ← parse line
  let str (key : String) : Except String String :=
    match json.getStr? key with | some s => pure s | none => throw s!"response lacks {key}"
  let version ← match json.getInt? "protocol_version" with | some n => pure n.toNat | none => throw "response lacks protocol_version"
  return { schema := ← str "schema", requestId := ← str "request_id", protocolVersion := version,
           operation := ← str "operation", status := ← str "status", authority := ← str "authority",
           assurance := ← str "assurance", inputSha256 := ← str "input_sha256", resultSha256 := ← str "result_sha256",
           payload := ← str "payload", errors := ← strArray json "errors", warnings := ← strArray json "warnings" }

def Response.toJson (response : Response) : J :=
  .obj #[("schema", .str response.schema), ("request_id", .str response.requestId),
         ("protocol_version", .int response.protocolVersion), ("operation", .str response.operation),
         ("status", .str response.status), ("authority", .str response.authority),
         ("assurance", .str response.assurance), ("input_sha256", .str response.inputSha256),
         ("result_sha256", .str response.resultSha256), ("payload", .str response.payload),
         ("errors", .arr (response.errors.map .str)), ("warnings", .arr (response.warnings.map .str))]

/-- Refuse a response that does not answer this request, or claims more than the protocol allows. -/
def validateResponse (request : Zil.Exchange.Request) (response : Response) : Except String Unit := do
  unless response.schema == Zil.Exchange.schema do throw "worker returned an unsupported schema"
  unless response.protocolVersion == Zil.Exchange.protocolVersion do
    throw "worker returned an unsupported protocol version"
  unless response.requestId == request.requestId do throw "worker response request_id mismatch"
  unless response.operation == request.operation do throw "worker response operation mismatch"
  unless response.inputSha256 == request.inputSha256 do throw "worker response input_sha256 mismatch"
  unless response.authority == "lean" do throw "worker response lost Lean authority"
  unless workerStatuses.contains response.status do throw "worker returned an unsupported status"
  unless response.resultSha256.isEmpty do throw "Lean worker must leave result_sha256 for client attestation"
  if response.status == "ok" then
    unless response.assurance == "validated" do throw "successful worker response lost validated assurance"
    unless response.warnings.contains pendingAttestationWarning do
      throw "successful worker response lost attestation boundary"
  else
    unless response.assurance.isEmpty do throw "failed worker response must not claim assurance"
    if response.errors.isEmpty then throw "failed worker response must include an error"

/-- Add byte attestation without changing authority, assurance, payload or errors. -/
def attest (response : Response) : Response :=
  { response with
    resultSha256 := Sha256.ofText response.payload
    warnings := response.warnings.filter (· != pendingAttestationWarning) }

/-- The command that starts a worker: `ZIL_WORKER_COMMAND` (words separated by spaces; a test hook) if set, else the
`zilWorker` next to this executable, else through Lake. -/
def defaultCommand : IO (String × Array String) := do
  if let some override := ← IO.getEnv "ZIL_WORKER_COMMAND" then
    match (override.splitOn " ").filter (· ≠ "") with
    | cmd :: args => return (cmd, args.toArray)
    | [] => pure ()
  let app ← IO.appPath
  match app.parent with
  | some dir =>
      let sibling := dir / "zilWorker"
      if ← sibling.pathExists then return (sibling.toString, #["--stdio"])
  | none => pure ()
  return ("lake", #["exe", "zilWorker", "--stdio"])

/-- The response deadline: `ZIL_WORKER_TIMEOUT_MS` if set, else thirty seconds. -/
def configuredTimeoutMs : IO Nat := do
  return ((← IO.getEnv "ZIL_WORKER_TIMEOUT_MS").bind String.toNat?).getD defaultTimeoutMs

structure Options where
  command : Option (String × Array String) := none
  directory : Option System.FilePath := none
  environment : Array (String × Option String) := #[]

structure Worker where
  child : IO.Process.Child { stdin := .null, stdout := .piped, stderr := .piped }
  /-- The worker's standard input. Holding it here, and nowhere else, is what lets `closeInput` end the worker. -/
  stdin : IO.Ref (Option IO.FS.Handle)
  errors : Task (Except IO.Error String)

def startWorker (options : Options := {}) : IO Worker := do
  let (cmd, args) ← match options.command with | some c => pure c | none => defaultCommand
  let spawned ← IO.Process.spawn
    { cmd, args, cwd := options.directory, env := options.environment, stdin := .piped, stdout := .piped,
      stderr := .piped }
  let (stdin, child) ← spawned.takeStdin
  let errors ← IO.asTask (prio := .dedicated) child.stderr.readToEnd
  return { child, stdin := ← IO.mkRef (some stdin), errors }

/-- Drop the last reference to the worker's input, which closes it. -/
def closeInput (worker : Worker) : IO Unit := worker.stdin.set none

/-- Read one line within `timeoutMs`; on timeout the worker is killed and the call fails. -/
private def readLine (worker : Worker) (timeoutMs : Nat) : IO String := do
  let reader ← IO.asTask (prio := .dedicated) worker.child.stdout.getLine
  let timer ← IO.asTask (prio := .dedicated) (do IO.sleep timeoutMs.toUInt32; pure "")
  let _ ← IO.waitAny [reader, timer]
  if (← IO.hasFinished reader) then
    match reader.get with
    | .ok line => return line
    | .error error => throw error
  else
    try worker.child.kill catch _ => pure ()
    transportError s!"timed out waiting for a Lean worker response ({timeoutMs} ms)"

/-- Send one request to a worker and return the verified, byte-attested response. -/
def invoke (worker : Worker) (request : Zil.Exchange.Request) (timeoutMs : Nat := defaultTimeoutMs) : IO Response := do
  match request.validate with
  | .ok () => pure ()
  | .error message => throw (IO.userError s!"invalid-request: {message}")
  try
    match ← worker.stdin.get with
    | some stdin =>
        stdin.putStr (requestLine request ++ "\n")
        stdin.flush
    | none => throw (IO.userError "worker input is closed")
  catch _ =>
    try worker.child.kill catch _ => pure ()
    transportError "Lean worker is not running"
  let line ← readLine worker timeoutMs
  if line.isEmpty then
    try worker.child.kill catch _ => pure ()
    transportError "Lean worker closed without a response"
  match Response.decode line with
  | .error message =>
      try worker.child.kill catch _ => pure ()
      transportError s!"Lean worker returned malformed JSON ({message})"
  | .ok response =>
      match validateResponse request response with
      | .ok () => return attest response
      | .error message =>
          try worker.child.kill catch _ => pure ()
          transportError message

/-- True while the worker process has not exited. -/
def alive (worker : Worker) : IO Bool := do
  return (← worker.child.tryWait).isNone

/-- Close the worker's input, wait for it, and return its exit code and what it wrote to standard error. -/
def stopWorker (worker : Worker) : IO (UInt32 × String) := do
  closeInput worker
  let code ← worker.child.wait
  let errors ← match worker.errors.get with | .ok text => pure text | .error _ => pure ""
  return (code, errors)

/-- Start a worker, send one request, stop it. -/
def invokeOnce (request : Zil.Exchange.Request) (options : Options := {}) (timeoutMs : Nat := defaultTimeoutMs) : IO Response := do
  let worker ← startWorker options
  try
    let response ← invoke worker request timeoutMs
    let _ ← stopWorker worker
    return response
  catch error =>
    try worker.child.kill catch _ => pure ()
    try let _ ← stopWorker worker catch _ => pure ()
    throw error

end Zil.Worker
