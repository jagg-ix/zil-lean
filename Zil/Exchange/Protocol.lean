import Lean.Data.Json

namespace Zil.Exchange

open Lean

/-- Stable protocol identifier shared by the Lean worker and Clojure control plane. -/
def schema : String := "ZIL-EXCHANGE/1"

/-- Current exchange protocol version. -/
def protocolVersion : Nat := 1

/-- One allowlisted worker request. Version 1 is file-oriented. -/
structure Request where
  schema : String
  requestId : String
  protocolVersion : Nat
  operation : String
  inputPath : String
  baseRevision : String
  inputSha256 : String
  capabilities : Array String
  arguments : Array String
  deriving Repr, Inhabited

/-- One deterministic worker response. The Clojure client adds result SHA-256. -/
structure Response where
  schema : String := Zil.Exchange.schema
  requestId : String
  protocolVersion : Nat := Zil.Exchange.protocolVersion
  operation : String
  status : String
  authority : String := "lean"
  assurance : String
  inputSha256 : String
  resultSha256 : String := ""
  payload : String := ""
  errors : Array String := #[]
  warnings : Array String := #[]
  deriving Repr, Inhabited

/-- Capability required by each compiled worker operation. -/
def requiredCapability? : String → Option String
  | "parse" => some "parse-v1"
  | "expand" => some "expand-v1"
  | "query" => some "query-v1"
  | "authorize" => some "authorization-v1"
  | "impact" => some "impact-v1"
  | "recovery-audit" => some "recovery-audit-v1"
  | _ => none

/-- Required positional argument count for each version-1 operation. -/
def requiredArity? : String → Option Nat
  | "parse" => some 0
  | "expand" => some 0
  | "query" => some 1
  | "authorize" => some 3
  | "impact" => some 1
  | "recovery-audit" => some 1
  | _ => none

private def insertString (value : String) : List String → List String
  | [] => [value]
  | head :: tail =>
      match compare value head with
      | .lt => value :: head :: tail
      | .eq => head :: tail
      | .gt => head :: insertString value tail

private def sortedUnique (values : Array String) : Array String :=
  (values.foldl (init := []) fun out value => insertString value out).toArray

private def validSha256Id (value : String) : Bool :=
  let isHex (char : Char) : Bool :=
    ('0' ≤ char && char ≤ '9') ||
    ('a' ≤ char && char ≤ 'f') ||
    ('A' ≤ char && char ≤ 'F')
  value.startsWith "sha256:" && value.length == 71 &&
    (value.drop 7).data.all isHex

/-- Fail-closed structural and capability validation before dispatch. -/
def Request.validate (request : Request) : Except String Unit := do
  unless request.schema == Zil.Exchange.schema do
    throw s!"unsupported exchange schema {request.schema}"
  unless request.protocolVersion == Zil.Exchange.protocolVersion do
    throw s!"unsupported protocol version {request.protocolVersion}"
  if request.requestId.isEmpty then throw "request_id must be nonempty"
  if request.inputPath.isEmpty then throw "input_path must be nonempty"
  if request.baseRevision.isEmpty then throw "base_revision must be nonempty"
  unless validSha256Id request.inputSha256 do
    throw "input_sha256 must be sha256:<64 hex>"
  unless sortedUnique request.capabilities == request.capabilities do
    throw "capabilities must be sorted and unique"
  let capability ← match requiredCapability? request.operation with
    | some value => pure value
    | none => throw s!"unsupported operation {request.operation}"
  unless request.capabilities.contains capability do
    throw s!"operation {request.operation} requires capability {capability}"
  let arity ← match requiredArity? request.operation with
    | some value => pure value
    | none => throw s!"unsupported operation {request.operation}"
  unless request.arguments.size == arity do
    throw s!"operation {request.operation} requires {arity} arguments"

/-- Decode a request from one JSON value. -/
def Request.fromJson (json : Json) : Except String Request := do
  pure {
    schema := ← json.getObjValAs? String "schema"
    requestId := ← json.getObjValAs? String "request_id"
    protocolVersion := ← json.getObjValAs? Nat "protocol_version"
    operation := ← json.getObjValAs? String "operation"
    inputPath := ← json.getObjValAs? String "input_path"
    baseRevision := ← json.getObjValAs? String "base_revision"
    inputSha256 := ← json.getObjValAs? String "input_sha256"
    capabilities := ← json.getObjValAs? (Array String) "capabilities"
    arguments := ← json.getObjValAs? (Array String) "arguments"
  }

/-- Parse and validate one JSON-line request. -/
def Request.parse (line : String) : Except String Request := do
  let json ← Json.parse line
  let request ← Request.fromJson json
  request.validate
  pure request

private def stringArrayJson (values : Array String) : Json :=
  Json.arr (values.map Json.str)

/-- Structured representation for callers that do not require canonical field order. -/
def Response.toJson (response : Response) : Json :=
  Json.mkObj [
    ("schema", Json.str response.schema),
    ("request_id", Json.str response.requestId),
    ("protocol_version", toJson response.protocolVersion),
    ("operation", Json.str response.operation),
    ("status", Json.str response.status),
    ("authority", Json.str response.authority),
    ("assurance", Json.str response.assurance),
    ("input_sha256", Json.str response.inputSha256),
    ("result_sha256", Json.str response.resultSha256),
    ("payload", Json.str response.payload),
    ("errors", stringArrayJson response.errors),
    ("warnings", stringArrayJson response.warnings)
  ]

private def jsonString (value : String) : String :=
  (Json.str value).compress

private def jsonStrings (values : Array String) : String :=
  (stringArrayJson values).compress

/-- Compact JSON with an explicit protocol field order. -/
def Response.render (response : Response) : String :=
  "{" ++
  "\"schema\":" ++ jsonString response.schema ++ "," ++
  "\"request_id\":" ++ jsonString response.requestId ++ "," ++
  "\"protocol_version\":" ++ toString response.protocolVersion ++ "," ++
  "\"operation\":" ++ jsonString response.operation ++ "," ++
  "\"status\":" ++ jsonString response.status ++ "," ++
  "\"authority\":" ++ jsonString response.authority ++ "," ++
  "\"assurance\":" ++ jsonString response.assurance ++ "," ++
  "\"input_sha256\":" ++ jsonString response.inputSha256 ++ "," ++
  "\"result_sha256\":" ++ jsonString response.resultSha256 ++ "," ++
  "\"payload\":" ++ jsonString response.payload ++ "," ++
  "\"errors\":" ++ jsonStrings response.errors ++ "," ++
  "\"warnings\":" ++ jsonStrings response.warnings ++
  "}"

/-- Successful authoritative evaluation. -/
def Response.success
    (request : Request)
    (payload : String)
    (warnings : Array String := #["result-sha256-pending-client-attestation"]) : Response := {
  requestId := request.requestId
  operation := request.operation
  status := "ok"
  assurance := "validated"
  inputSha256 := request.inputSha256
  payload
  warnings
}

/-- Invalid or failed authoritative evaluation. -/
def Response.failure
    (requestId operation inputSha256 status error : String) : Response := {
  requestId
  operation
  status
  assurance := ""
  inputSha256
  errors := #[error]
}

/-- Error response for malformed transport input where request identity is unavailable. -/
def Response.transportFailure (error : String) : Response :=
  Response.failure "-" "-" "" "invalid" error

end Zil.Exchange
