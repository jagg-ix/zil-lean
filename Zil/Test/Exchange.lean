import Zil.Exchange.Protocol

open Zil.Exchange

private def digest : String :=
  "sha256:" ++ String.mk (List.replicate 64 'a')

private def request : Request := {
  schema := Zil.Exchange.schema
  requestId := "request:test"
  protocolVersion := Zil.Exchange.protocolVersion
  operation := "parse"
  inputPath := "examples/authorization/access.zc"
  baseRevision := "-"
  inputSha256 := digest
  capabilities := #["parse-v1"]
  arguments := #[]
}

#guard match request.validate with
  | .ok _ => true
  | .error _ => false

#guard requiredCapability? "authorize" == some "authorization-v1"
#guard requiredArity? "authorize" == some 3

#guard match Request.validate { request with capabilities := #[] } with
  | .error _ => true
  | .ok _ => false

#guard match Request.validate { request with capabilities := #["parse-v1", "parse-v1"] } with
  | .error _ => true
  | .ok _ => false

#guard match Request.validate { request with capabilities := #["query-v1", "parse-v1"] } with
  | .error _ => true
  | .ok _ => false

#guard match Request.validate { request with operation := "shell" } with
  | .error _ => true
  | .ok _ => false

#guard ({ request with operation := "shell" } : Request).validationStatus == "unsupported"
#guard ({ request with protocolVersion := 2 } : Request).validationStatus == "unsupported"
#guard ({ request with capabilities := #[] } : Request).validationStatus == "invalid"

#guard match Request.validate { request with inputSha256 := "sha256:bad" } with
  | .error _ => true
  | .ok _ => false

private def requestJson : String :=
  "{\"schema\":\"ZIL-EXCHANGE/1\",\"request_id\":\"request:test\"," ++
  "\"protocol_version\":1,\"operation\":\"parse\"," ++
  "\"input_path\":\"examples/authorization/access.zc\",\"base_revision\":\"-\"," ++
  "\"input_sha256\":\"" ++ digest ++ "\",\"capabilities\":[\"parse-v1\"],\"arguments\":[]}"

#guard match Request.decode requestJson with
  | .ok value => value.requestId == "request:test" && value.operation == "parse"
  | .error _ => false

#guard match Request.parse requestJson with
  | .ok value => value.requestId == "request:test" && value.operation == "parse"
  | .error _ => false

run_cmd do
  let response := Response.success request "ZIL-PARSE-SUMMARY\t1\n"
  let rendered := response.render
  unless rendered.startsWith "{\"schema\":\"ZIL-EXCHANGE/1\"" do
    throwError "exchange response field order is not canonical"
  unless (rendered.splitOn "result-sha256-pending-client-attestation").length > 1 do
    throwError "exchange response lost transport-attestation warning"
  match Lean.Json.parse rendered with
  | .ok _ => pure ()
  | .error error => throwError error
