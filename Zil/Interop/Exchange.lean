import Zil.Codec.Canonical

namespace Zil.Interop

/-- Revisioned frontend-neutral payload exchanged between Lean and Clojure. -/
structure ExchangeEnvelope where
  schemaVersion : String := "1"
  knowledgeRevision : Nat
  profileName : Option String := none
  profileVersion : Option String := none
  facts : Array Zil.RelExpr := #[]
  rules : Array Zil.Rule := #[]
  deriving Repr, Inhabited

private def escape (value : String) : String :=
  value.replace "\\" "\\\\" |>.replace "\n" "\\n" |>.replace "\t" "\\t"

private def unescape (value : String) : String :=
  let rec loop (chars : List Char) (out : String) : String :=
    match chars with
    | [] => out
    | '\\' :: 'n' :: rest => loop rest (out.push '\n')
    | '\\' :: 't' :: rest => loop rest (out.push '\t')
    | '\\' :: '\\' :: rest => loop rest (out.push '\\')
    | c :: rest => loop rest (out.push c)
  loop value.data ""

private def optionString : Option String → String
  | none => "-"
  | some value => escape value

/-- Deterministic line-oriented exchange encoding. -/
def encodeEnvelope (envelope : ExchangeEnvelope) : String :=
  let header := #[
    s!"ZILX\t{envelope.schemaVersion}",
    s!"revision\t{envelope.knowledgeRevision}",
    s!"profile\t{optionString envelope.profileName}\t{optionString envelope.profileVersion}"
  ]
  let facts := envelope.facts.map fun fact => s!"fact\t{escape (Zil.Codec.encodeRelation fact)}"
  let rules := envelope.rules.map fun rule => s!"rule\t{escape (Zil.Codec.encodeRule rule)}"
  String.intercalate "\n" (header ++ facts ++ rules).toList

private def parseOptionString (value : String) : Option String :=
  if value == "-" then none else some (unescape value)

/-- Decode one revisioned exchange envelope. Unknown rows are rejected. -/
def decodeEnvelope (text : String) : Except String ExchangeEnvelope := do
  let lines := text.splitOn "\n"
  let first ← lines.head?.toExcept "missing ZILX header"
  let header := first.splitOn "\t"
  unless header.length == 2 && header[0]? == some "ZILX" do
    throw "invalid ZILX header"
  let schema ← header[1]?.toExcept "missing schema version"
  let revisionLine ← lines[1]?.toExcept "missing knowledge revision"
  let revisionParts := revisionLine.splitOn "\t"
  unless revisionParts.length == 2 && revisionParts[0]? == some "revision" do
    throw "invalid revision row"
  let revisionText ← revisionParts[1]?.toExcept "missing revision value"
  let revision ← revisionText.toNat?.toExcept "invalid knowledge revision"
  let profileLine ← lines[2]?.toExcept "missing profile row"
  let profileParts := profileLine.splitOn "\t"
  unless profileParts.length == 3 && profileParts[0]? == some "profile" do
    throw "invalid profile row"
  let profileName := parseOptionString (profileParts[1]!.trim)
  let profileVersion := parseOptionString (profileParts[2]!.trim)
  let mut facts : Array Zil.RelExpr := #[]
  let mut rules : Array Zil.Rule := #[]
  for line in lines.drop 3 do
    if line.isEmpty then continue
    let parts := line.splitOn "\t"
    unless parts.length == 2 do throw "malformed exchange row"
    let payload := unescape parts[1]!
    match parts[0]! with
    | "fact" => facts := facts.push (← Zil.Codec.decodeRelation payload)
    | "rule" => rules := rules.push (← Zil.Codec.decodeRule payload)
    | other => throw s!"unknown exchange row {other}"
  pure { schemaVersion := schema, knowledgeRevision := revision,
    profileName, profileVersion, facts, rules }

/-- Semantic parity check used by both frontend fixtures. -/
def semanticallyEqual (left right : ExchangeEnvelope) : Bool :=
  left.schemaVersion == right.schemaVersion &&
  left.knowledgeRevision == right.knowledgeRevision &&
  left.profileName == right.profileName &&
  left.profileVersion == right.profileVersion &&
  left.facts.size == right.facts.size &&
  left.rules.size == right.rules.size &&
  (left.facts.zip right.facts |>.all fun pair => pair.1.semanticallyEqual pair.2) &&
  (left.rules.zip right.rules |>.all fun pair => Zil.Codec.ruleSemanticallyEqual pair.1 pair.2)

end Zil.Interop