import Zil.Core.Revision
import Zil.Codec.Canonical

namespace Zil.Codec.Revision

private def escape (value : String) : String :=
  value.replace "\\" "\\\\" |>.replace "\n" "\\n" |>.replace "\t" "\\t"

private def unescape (value : String) : String :=
  let rec loop (chars : List Char) (out : String) : String :=
    match chars with
    | [] => out
    | '\\' :: 'n' :: rest => loop rest (out.push '\n')
    | '\\' :: 't' :: rest => loop rest (out.push '\t')
    | '\\' :: '\\' :: rest => loop rest (out.push '\\')
    | char :: rest => loop rest (out.push char)
  loop value.data ""

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun current segment =>
    if current == Name.anonymous then Name.mkSimple segment else Name.str current segment

private def operationName : FactOperation → String
  | .assert => "assert"
  | .retract => "retract"

private def parseOperation : String → Except String FactOperation
  | "assert" => .ok .assert
  | "retract" => .ok .retract
  | value => .error s!"unknown revision operation {value}"

/-- Deterministic line-oriented revision and causal envelope. -/
def encodeStore (store : RevisionStore) : String :=
  let header := #["ZILR\t1", s!"module\t{store.moduleName}"]
  let records := store.records.map fun record =>
    String.intercalate "\t" #[
      "record",
      toString record.revision,
      toString record.event,
      operationName record.operation,
      escape (Zil.Codec.encodeRelation record.fact)
    ]
  let edges := store.causal.edges.map fun edge =>
    String.intercalate "\t" #["before", toString edge.left, toString edge.right]
  String.intercalate "\n" (header ++ records ++ edges).toList ++ "\n"

/-- Decode and validate one revision envelope. -/
def decodeStore (text : String) : Except String RevisionStore := do
  let lines := text.splitOn "\n" |>.filter (fun line => !line.isEmpty) |>.toArray
  unless lines.size >= 2 do throw "revision envelope requires header and module rows"
  unless lines[0]! == "ZILR\t1" do throw "invalid ZILR header"
  let moduleParts := lines[1]!.splitOn "\t"
  unless moduleParts.length == 2 && moduleParts[0]? == some "module" do
    throw "invalid revision module row"
  let moduleName := nameFromString moduleParts[1]!
  let mut records : Array RevisionedFact := #[]
  let mut edges : Array CausalEdge := #[]
  for line in lines.extract 2 lines.size do
    let parts := line.splitOn "\t"
    match parts with
    | ["record", revisionText, eventText, operationText, relationText] =>
        let revision ← revisionText.toNat?.toExcept "invalid revision number"
        let operation ← parseOperation operationText
        let fact ← Zil.Codec.decodeRelation (unescape relationText)
        records := records.push {
          fact, revision
          event := nameFromString eventText
          operation
        }
    | ["before", left, right] =>
        edges := edges.push { left := nameFromString left, right := nameFromString right }
    | _ => throw s!"invalid revision envelope row: {line}"
  let store : RevisionStore := { moduleName, records, causal := { edges } }
  unless store.valid do throw "decoded revision store is invalid"
  pure store

/-- Semantic round-trip check for a revision store. -/
def roundTrips (store : RevisionStore) : Bool :=
  match decodeStore (encodeStore store) with
  | .error _ => false
  | .ok decoded =>
      decoded.moduleName == store.moduleName &&
      decoded.records.size == store.records.size &&
      decoded.causal.edges == store.causal.edges &&
      (decoded.records.zip store.records).all fun pair =>
        pair.1.revision == pair.2.revision &&
        pair.1.event == pair.2.event &&
        pair.1.operation == pair.2.operation &&
        pair.1.fact.semanticallyEqual pair.2.fact

end Zil.Codec.Revision
