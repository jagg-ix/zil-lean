import Zil.Plugin.Manifest

/-!
# Evidence envelopes (`ZIL-EVIDENCE/1`)

An extension-produced artifact, recorded without promoting it beyond the authority and assurance of its producer. The
payload's SHA-256 is part of the envelope, and so is the identity of the extension and the inputs.
-/

namespace Zil.Plugin.Evidence

open Zil.Json Zil.Crypto

def schema : String := "ZIL-EVIDENCE/1"
def assuranceLevels : List String := ["exploratory", "externally-attested", "byte-attested", "validated", "kernel-backed"]

private def validSha256 (value : String) : Bool :=
  value.startsWith "sha256:" && value.length == 71 &&
    (value.toList.drop 7).all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')

/-- The assurance an extension's evidence carries unless it says otherwise. -/
def defaultAssurance (manifest : Manifest) : String :=
  match manifest.authority with
  | "external" => "externally-attested"
  | "operational" => "byte-attested"
  | "lean" => "validated"
  | "shared" => "byte-attested"
  | _ => "exploratory"

structure Request where
  manifest : Manifest
  role : String
  subject : String
  inputSha256 : Option String := none
  payload : String := ""
  metadata : J := .obj #[]
  assurance : Option String := none
  authority : Option String := none

/-- Build the envelope. -/
def make (request : Request) : Except String J := do
  let manifest ← validate request.manifest
  let authority := request.authority.getD manifest.authority
  let assurance := request.assurance.getD (defaultAssurance manifest)
  let outputSha := Sha256.ofText request.payload
  let inputSha := request.inputSha256.getD (Sha256.ofText "")
  if request.role.all Char.isWhitespace then throw "evidence role must be nonempty"
  if request.subject.all Char.isWhitespace then throw "evidence subject must be nonempty"
  unless validSha256 inputSha do throw "evidence input_sha256 is invalid"
  unless assuranceLevels.contains assurance do throw "evidence assurance is invalid"
  if !manifest.trusted && (assurance == "validated" || assurance == "kernel-backed") then
    throw "an extension that is not trusted cannot produce validated or kernel-backed evidence"
  let identity := manifest.id ++ "\n" ++ manifest.version ++ "\n" ++ request.role ++ "\n" ++ request.subject ++ "\n" ++
    inputSha ++ "\n" ++ outputSha
  let evidenceId := "evidence:" ++ (Sha256.ofText identity).drop 7
  return .obj #[("schema", .str schema), ("evidence_id", .str evidenceId), ("extension_id", .str manifest.id),
    ("extension_version", .str manifest.version), ("authority", .str authority), ("assurance", .str assurance),
    ("role", .str request.role), ("subject", .str request.subject), ("input_sha256", .str inputSha),
    ("output_sha256", .str outputSha), ("payload", .str request.payload), ("metadata", ← canonical request.metadata)]

/-- Check an envelope's structure and that its digest matches its payload. -/
def validate (envelope : J) : Except String J := do
  unless envelope.getStr? "schema" == some schema do throw "unsupported evidence schema"
  let id := (envelope.getStr? "evidence_id").getD ""
  unless id.startsWith "evidence:" && id.length == 73 do throw "evidence_id is invalid"
  unless validSha256 ((envelope.getStr? "input_sha256").getD "") do throw "evidence input_sha256 is invalid"
  unless some (Sha256.ofText ((envelope.getStr? "payload").getD "")) == envelope.getStr? "output_sha256" do
    throw "evidence output_sha256 does not match payload bytes"
  unless assuranceLevels.contains ((envelope.getStr? "assurance").getD "") do throw "evidence assurance is invalid"
  return envelope

end Zil.Plugin.Evidence
