import Zil.Interop.Exchange

namespace Zil.Interop

/-- Incremental change set applied to one exchange snapshot. -/
structure KnowledgeDelta where
  baseRevision : Nat
  targetRevision : Nat
  addFacts : Array Zil.RelExpr := #[]
  removeFacts : Array Zil.RelExpr := #[]
  addRules : Array Zil.Rule := #[]
  removeRules : Array Name := #[]
  profileName : Option String := none
  profileVersion : Option String := none
  deriving Repr, Inhabited

inductive DeltaError where
  | staleRevision (expected actual : Nat)
  | nonIncreasingRevision (base target : Nat)
  | missingFact (fact : Zil.RelExpr)
  | missingRule (name : Name)
  deriving Repr, Inhabited

private def pushFact (facts : Array Zil.RelExpr) (fact : Zil.RelExpr) : Array Zil.RelExpr :=
  if facts.any (·.semanticallyEqual fact) then facts else facts.push fact

private def removeFact? (facts : Array Zil.RelExpr) (target : Zil.RelExpr) : Option (Array Zil.RelExpr) :=
  if facts.any (·.semanticallyEqual target) then
    some (facts.filter fun fact => !fact.semanticallyEqual target)
  else none

private def pushRule (rules : Array Zil.Rule) (rule : Zil.Rule) : Array Zil.Rule :=
  if rules.any fun current => current.name == rule.name then
    rules.map fun current => if current.name == rule.name then rule else current
  else rules.push rule

private def removeRule? (rules : Array Zil.Rule) (name : Name) : Option (Array Zil.Rule) :=
  if rules.any fun rule => rule.name == name then
    some (rules.filter fun rule => rule.name != name)
  else none

/-- Apply a delta only when its base revision matches the snapshot. -/
def applyDelta (snapshot : ExchangeEnvelope) (delta : KnowledgeDelta) : Except DeltaError ExchangeEnvelope := do
  unless delta.baseRevision == snapshot.knowledgeRevision do
    throw (.staleRevision snapshot.knowledgeRevision delta.baseRevision)
  unless delta.targetRevision > delta.baseRevision do
    throw (.nonIncreasingRevision delta.baseRevision delta.targetRevision)
  let mut facts := snapshot.facts
  for fact in delta.removeFacts do
    facts ← (removeFact? facts fact).toExcept (.missingFact fact)
  for fact in delta.addFacts do
    facts := pushFact facts fact
  let mut rules := snapshot.rules
  for name in delta.removeRules do
    rules ← (removeRule? rules name).toExcept (.missingRule name)
  for rule in delta.addRules do
    rules := pushRule rules rule
  pure { snapshot with
    knowledgeRevision := delta.targetRevision
    profileName := delta.profileName.orElse snapshot.profileName
    profileVersion := delta.profileVersion.orElse snapshot.profileVersion
    facts, rules }

/-- Compose adjacent deltas. Removal/addition conflicts are retained in order. -/
def composeDelta (first second : KnowledgeDelta) : Except DeltaError KnowledgeDelta := do
  unless first.targetRevision == second.baseRevision do
    throw (.staleRevision first.targetRevision second.baseRevision)
  pure {
    baseRevision := first.baseRevision
    targetRevision := second.targetRevision
    addFacts := first.addFacts ++ second.addFacts
    removeFacts := first.removeFacts ++ second.removeFacts
    addRules := first.addRules ++ second.addRules
    removeRules := first.removeRules ++ second.removeRules
    profileName := second.profileName.orElse first.profileName
    profileVersion := second.profileVersion.orElse first.profileVersion }

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

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun acc part =>
    if acc == Name.anonymous then Name.mkSimple part else Name.str acc part

/-- Deterministic line protocol for incremental change sets. -/
def encodeDelta (delta : KnowledgeDelta) : String :=
  let header := #[s!"ZILD\t1", s!"base\t{delta.baseRevision}", s!"target\t{delta.targetRevision}",
    s!"profile\t{delta.profileName.getD "-"}\t{delta.profileVersion.getD "-"}"]
  let addFacts := delta.addFacts.map fun fact => s!"add-fact\t{escape (Zil.Codec.encodeRelation fact)}"
  let removeFacts := delta.removeFacts.map fun fact => s!"remove-fact\t{escape (Zil.Codec.encodeRelation fact)}"
  let addRules := delta.addRules.map fun rule => s!"add-rule\t{escape (Zil.Codec.encodeRule rule)}"
  let removeRules := delta.removeRules.map fun name => s!"remove-rule\t{name}"
  String.intercalate "\n" (header ++ addFacts ++ removeFacts ++ addRules ++ removeRules).toList

/-- Decode one incremental change set. -/
def decodeDelta (text : String) : Except String KnowledgeDelta := do
  let lines := text.splitOn "\n"
  unless lines[0]? == some "ZILD\t1" do throw "invalid ZILD header"
  let baseParts := (← lines[1]?.toExcept "missing base row").splitOn "\t"
  let targetParts := (← lines[2]?.toExcept "missing target row").splitOn "\t"
  let profileParts := (← lines[3]?.toExcept "missing profile row").splitOn "\t"
  unless baseParts[0]? == some "base" && targetParts[0]? == some "target" &&
      profileParts[0]? == some "profile" do throw "invalid ZILD metadata"
  let baseRevision ← (← baseParts[1]?.toExcept "missing base revision").toNat?.toExcept "invalid base revision"
  let targetRevision ← (← targetParts[1]?.toExcept "missing target revision").toNat?.toExcept "invalid target revision"
  let profileName := profileParts[1]?.bind fun value => if value == "-" then none else some value
  let profileVersion := profileParts[2]?.bind fun value => if value == "-" then none else some value
  let mut addFacts := #[]
  let mut removeFacts := #[]
  let mut addRules := #[]
  let mut removeRules := #[]
  for line in lines.drop 4 do
    if line.isEmpty then continue
    let parts := line.splitOn "\t"
    unless parts.length == 2 do throw "malformed delta row"
    let payload := unescape parts[1]!
    match parts[0]! with
    | "add-fact" => addFacts := addFacts.push (← Zil.Codec.decodeRelation payload)
    | "remove-fact" => removeFacts := removeFacts.push (← Zil.Codec.decodeRelation payload)
    | "add-rule" => addRules := addRules.push (← Zil.Codec.decodeRule payload)
    | "remove-rule" => removeRules := removeRules.push (nameFromString payload)
    | other => throw s!"unknown delta row {other}"
  pure { baseRevision, targetRevision, addFacts, removeFacts, addRules, removeRules,
    profileName, profileVersion }

end Zil.Interop