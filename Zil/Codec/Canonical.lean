import Zil.Core.Rule
import Zil.Codec.Attribute

namespace Zil.Codec

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun acc part =>
    if acc == Name.anonymous then Name.mkSimple part else Name.str acc part

private def encodeName (name : Name) : String := toString name

private def encodeTerm : Zil.Term → String
  | .var name => s!"var:{encodeName name}"
  | .node node => s!"node:{encodeName node.name}"

private def decodeTerm (text : String) : Except String Zil.Term :=
  match text.splitOn ":" with
  | ["var", name] => .ok (.variable (nameFromString name))
  | ["node", name] => .ok (.ground (nameFromString name))
  | _ => .error s!"invalid canonical term: {text}"

/-- Stable tab-separated encoding for one canonical relation. -/
def encodeRelation (relation : Zil.RelExpr) : String :=
  String.intercalate "\t" #[
    "rel", encodeTerm relation.subject, encodeName relation.relation,
    encodeTerm relation.object, encodeAttributes relation.attrs]

/-- Parse one canonical relation encoding. Four-column rows remain accepted as attribute-free input. -/
def decodeRelation (text : String) : Except String Zil.RelExpr := do
  match text.splitOn "\t" with
  | ["rel", subject, relation, object] =>
      pure <| .mk' (← decodeTerm subject) (nameFromString relation) (← decodeTerm object)
  | ["rel", subject, relation, object, attrs] =>
      pure <| .mkWithAttrs
        (← decodeTerm subject)
        (nameFromString relation)
        (← decodeTerm object)
        (← decodeAttributes attrs)
  | _ => throw s!"invalid canonical relation: {text}"

private def encodeNames (names : Array Name) : String :=
  String.intercalate "," (names.map encodeName)

private def decodeNames (text : String) : Array Name :=
  if text.isEmpty then #[] else (text.splitOn ",").toArray.map nameFromString

private def trustName : Zil.TrustClass → String
  | .asserted => "asserted"
  | .graphDerived => "graphDerived"
  | .certified => "certified"

private def decodeTrust : String → Except String Zil.TrustClass
  | "asserted" => .ok .asserted
  | "graphDerived" => .ok .graphDerived
  | "certified" => .ok .certified
  | other => .error s!"invalid trust class: {other}"

/-- Emit a deterministic multiline representation of a canonical Horn rule. -/
def encodeRule (rule : Zil.Rule) : String :=
  let header := String.intercalate "\t" #[
    "rule", encodeName rule.name, encodeNames rule.variables, trustName rule.trust]
  let premises := rule.premises.map fun premise => s!"premise\t{encodeRelation premise}"
  let negatives := rule.negativePremises.map fun premise =>
    s!"negative\t{encodeRelation premise}"
  let conclusion := s!"conclusion\t{encodeRelation rule.conclusion}"
  String.intercalate "\n" (#[header] ++ premises ++ negatives ++ #[conclusion])

/-- Parse the deterministic canonical Horn-rule representation. -/
def decodeRule (text : String) : Except String Zil.Rule := do
  let lines := text.splitOn "\n" |>.toArray
  if lines.size < 2 then throw "canonical rule requires a header and conclusion"
  let header := lines[0]!
  let (ruleName, variables, trust) ←
    match header.splitOn "\t" with
    | ["rule", name, variables, trust] =>
        pure (nameFromString name, decodeNames variables, ← decodeTrust trust)
    | _ => throw "invalid canonical rule header"
  let mut premises : Array Zil.RelExpr := #[]
  let mut negativePremises : Array Zil.RelExpr := #[]
  let mut conclusion : Option Zil.RelExpr := none
  for line in lines.extract 1 lines.size do
    match line.splitOn "\t" with
    | "premise" :: rest =>
        premises := premises.push (← decodeRelation (String.intercalate "\t" rest))
    | "negative" :: rest =>
        negativePremises := negativePremises.push
          (← decodeRelation (String.intercalate "\t" rest))
    | "conclusion" :: rest =>
        if conclusion.isSome then throw "duplicate canonical rule conclusion"
        conclusion := some (← decodeRelation (String.intercalate "\t" rest))
    | _ => throw s!"invalid canonical rule line: {line}"
  let conclusion ← conclusion.toExcept "canonical rule has no conclusion"
  pure { name := ruleName, variables, premises, negativePremises, conclusion, trust }

/-- Semantic round-trip check for relations. -/
def relationRoundTrips (relation : Zil.RelExpr) : Bool :=
  match decodeRelation (encodeRelation relation) with
  | .ok decoded => relation.semanticallyEqual decoded
  | .error _ => false

private def relationArraysEqual (left right : Array Zil.RelExpr) : Bool :=
  left.size == right.size &&
  ((left.zip right).all fun pair => pair.1.semanticallyEqual pair.2)

/-- Semantic round-trip check for rules, ignoring source metadata. -/
def ruleRoundTrips (rule : Zil.Rule) : Bool :=
  match decodeRule (encodeRule rule) with
  | .ok decoded =>
      decoded.name == rule.name &&
      decoded.variables == rule.variables &&
      decoded.trust == rule.trust &&
      relationArraysEqual decoded.premises rule.premises &&
      relationArraysEqual decoded.negativePremises rule.negativePremises &&
      decoded.conclusion.semanticallyEqual rule.conclusion
  | .error _ => false

end Zil.Codec
