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

#guard request.validate.isOk
#guard requiredCapability? "authorize" == some "authorization-v1"
#guard requiredArity? "authorize" == some 3
#guard (Request.validate { request with capabilities := #[] }).isError
#guard (Request.validate { request with operation := "shell" }).isError
#guard (Request.validate { request with inputSha256 := "sha256:bad" }).isError

private def requestJson : String :=
  "{\"schema\":\"ZIL-EXCHANGE/1\",\"request_id\":\"request:test\"," ++
  "\"protocol_version\":1,\"operation\":\"parse\"," ++
  "\"input_path\":\"examples/authorization/access.zc\",\"base_revision\":\"-\"," ++
  "\"input_sha256\":\"" ++ digest ++ "\",\"capabilities\":[\"parse-v1\"],\"arguments\":[]}"

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
