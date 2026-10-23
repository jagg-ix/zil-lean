import Zil.Crypto.Sha256
import Zil.Json.Ordered

/-!
# Extension manifests (`ZIL-EXTENSION/1`)

A manifest declares an extension: its identity, how it runs, what it provides and requires, and what authority it
claims. Validation fails closed, and the fingerprint of the canonical bytes identifies the exact manifest that was
registered.

Runtimes: `lean` (an entrypoint compiled into this program) and `external` (a command run without a shell). Authorities:
`lean` and `shared` are Lean's own, `operational` is a byte-attested program that makes no semantic claim, `external`
is a producer outside this program. Only a configured Lean extension may be `trusted`.
-/

namespace Zil.Plugin

open Zil.Json Zil.Crypto

def manifestSchema : String := "ZIL-EXTENSION/1"
def runtimes : List String := ["lean", "external"]
def authorities : List String := ["lean", "shared", "operational", "external"]

structure Manifest where
  schema : String := manifestSchema
  id : String
  version : String
  runtime : String
  entrypoint : String
  capabilities : Array String := #[]
  requires : Array String := #[]
  inputs : Array String := #[]
  outputs : Array String := #[]
  authority : String
  trusted : Bool := false
  deriving Inhabited

private def sortedUnique (values : Array String) : Array String :=
  (values.qsort (· < ·)).foldl (fun out v => if out.back? == some v then out else out.push v) #[]

/-- `1.2.3`, optionally with `-prerelease` and `+build`. -/
def semanticVersion (text : String) : Bool :=
  let (core, rest) := match text.splitOn "-" with
    | [c] => (match c.splitOn "+" with | [c', _] => (c', "") | _ => (c, ""))
    | c :: tail => (c, String.intercalate "-" tail)
    | [] => ("", "")
  let parts := core.splitOn "."
  let number (p : String) : Bool :=
    !p.isEmpty && p.all Char.isDigit && (p == "0" || !p.startsWith "0")
  let tailOk (s : String) : Bool :=
    s.all fun c => c.isAlphanum || c == '.' || c == '-' || c == '+'
  parts.length == 3 && parts.all number && tailOk rest

private def strings (value : Option J) : Array String :=
  match value with
  | some (.arr items) => items.filterMap J.asStr?
  | _ => #[]

/-- Read a manifest from JSON, without validating it. -/
def ofJson (json : J) : Manifest :=
  { schema := (json.getStr? "schema").getD "", id := (json.getStr? "id").getD "", version := (json.getStr? "version").getD "",
    runtime := (json.getStr? "runtime").getD "", entrypoint := (json.getStr? "entrypoint").getD "",
    capabilities := sortedUnique (strings (json.get? "capabilities")), requires := sortedUnique (strings (json.get? "requires")),
    inputs := sortedUnique (strings (json.get? "inputs")), outputs := sortedUnique (strings (json.get? "outputs")),
    authority := (json.getStr? "authority").getD "", trusted := json.get? "trusted" == some (.bool true) }

private def blank (s : String) : Bool := s.all Char.isWhitespace

/-- Fail closed on a manifest that is not valid. -/
def validate (manifest : Manifest) : Except String Manifest := do
  unless manifest.schema == manifestSchema do throw "unsupported extension manifest schema"
  if blank manifest.id || !manifest.id.startsWith "extension:" then throw "extension id must begin with extension:"
  unless semanticVersion manifest.version do throw "extension version must be semantic"
  if manifest.runtime == "clojure" then
    throw "the Clojure runtime was removed; a manifest declares runtime lean (a compiled-in entrypoint) or external (a command)"
  unless runtimes.contains manifest.runtime do throw "extension runtime is invalid"
  if blank manifest.entrypoint then throw "extension entrypoint must be nonempty"
  if manifest.authority == "clojure" then
    throw "authority clojure was removed; use operational for a byte-attested program that makes no semantic claim"
  unless authorities.contains manifest.authority do throw "extension authority is invalid"
  if manifest.runtime == "external" && manifest.authority != "external" then
    throw "external extensions must declare external authority"
  if manifest.authority == "operational" && manifest.trusted then
    throw "an operational extension cannot be trusted"
  if manifest.trusted && manifest.runtime != "lean" then throw "trusted=true is reserved for configured Lean extensions"
  if !manifest.trusted && (manifest.authority == "lean" || manifest.authority == "shared") then
    throw "only a trusted extension can claim Lean or shared authority"
  return manifest

private def fieldOrder : List String :=
  ["schema", "id", "version", "runtime", "entrypoint", "capabilities", "requires", "inputs", "outputs", "authority",
   "trusted"]

def Manifest.toJson (manifest : Manifest) : J :=
  .obj #[("schema", .str manifest.schema), ("id", .str manifest.id), ("version", .str manifest.version),
         ("runtime", .str manifest.runtime), ("entrypoint", .str manifest.entrypoint),
         ("capabilities", .arr (manifest.capabilities.map .str)), ("requires", .arr (manifest.requires.map .str)),
         ("inputs", .arr (manifest.inputs.map .str)), ("outputs", .arr (manifest.outputs.map .str)),
         ("authority", .str manifest.authority), ("trusted", .bool manifest.trusted)]

/-- Canonical bytes of a valid manifest. -/
def canonicalJson (manifest : Manifest) : Except String String := do
  let valid ← validate manifest
  return write (escapeSlash := false) valid.toJson

/-- Digest of the canonical bytes. -/
def fingerprint (manifest : Manifest) : Except String String := do
  return Sha256.ofText (← canonicalJson manifest)

/-- The manifest with its fingerprint, as JSON. -/
def withFingerprint (manifest : Manifest) : Except String J := do
  let valid ← validate manifest
  match valid.toJson with
  | .obj fields => return .obj (fields.push ("fingerprint", .str (← fingerprint valid)))
  | other => return other

/-- Read and validate a manifest file. -/
def read (path : System.FilePath) : IO Manifest := do
  match Zil.Json.parse (← IO.FS.readFile path) with
  | .error message => throw (IO.userError s!"extension-manifest-error: {path} is not JSON: {message}")
  | .ok json =>
      match validate (ofJson json) with
      | .ok manifest => return manifest
      | .error message => throw (IO.userError s!"extension-manifest-error: {message} ({path})")

end Zil.Plugin
