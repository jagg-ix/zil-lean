import Zil.Core.Program

namespace Zil.Formalization

/-- Lifecycle states accepted by `FORMALIZATION_TARGET`. -/
inductive Status where
  | draft
  | blocked
  | ready
  | inProgress
  | implemented
  | verified
  | reviewed
  | proved
  | rejected
  | superseded
  deriving Repr, BEq, Inhabited

namespace Status

def ofToken? : String → Option Status
  | "draft" => some .draft
  | "blocked" => some .blocked
  | "ready" => some .ready
  | "in_progress" => some .inProgress
  | "implemented" => some .implemented
  | "verified" => some .verified
  | "reviewed" => some .reviewed
  | "proved" => some .proved
  | "rejected" => some .rejected
  | "superseded" => some .superseded
  | _ => none

def token : Status → String
  | .draft => "draft"
  | .blocked => "blocked"
  | .ready => "ready"
  | .inProgress => "in_progress"
  | .implemented => "implemented"
  | .verified => "verified"
  | .reviewed => "reviewed"
  | .proved => "proved"
  | .rejected => "rejected"
  | .superseded => "superseded"

/-- States whose result can satisfy another target dependency. -/
def accepted : Status → Bool
  | .verified | .reviewed | .proved => true
  | _ => false

/-- States eligible for scheduling. -/
def selectable : Status → Bool
  | .ready | .inProgress => true
  | _ => false

end Status

/-- Native scheduling view of one validated declaration. -/
structure Target where
  id : Name
  moduleName : String
  file : String
  declaration : String
  status : Status
  priority : Nat
  dependencies : Array Name := #[]
  deriving Repr, Inhabited

namespace Target

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun current segment =>
    if current == Name.anonymous then Name.mkSimple segment else Name.str current segment

private def requiredToken
    (declaration : Zil.Declaration) (key : Name) : Except String String := do
  let attr ← match declaration.attr? key with
    | some value => pure value
    | none => throw s!"{declaration.name}: missing {key}"
  let token ← match attr.value.token? with
    | some value => pure value
    | none => throw s!"{declaration.name}: {key} must be scalar"
  if token.isEmpty then throw s!"{declaration.name}: {key} must be nonempty"
  pure token

private def priorityOf (declaration : Zil.Declaration) : Except String Nat := do
  let attr ← match declaration.attr? `priority with
    | some value => pure value
    | none => throw s!"{declaration.name}: missing priority"
  match attr.value with
  | .scalar (.integer value) =>
      if value < 0 then throw s!"{declaration.name}: priority must be nonnegative"
      else pure value.toNat
  | value =>
      let token ← match value.token? with
        | some result => pure result
        | none => throw s!"{declaration.name}: priority must be an integer"
      match token.toNat? with
      | some result => pure result
      | none => throw s!"{declaration.name}: priority must be a nonnegative integer"

private def attrValueToken? : Zil.AttrValue → Option String
  | .text value => some value
  | .integer value => some (toString value)
  | .decimal value => some value
  | .boolean value => some (if value then "true" else "false")
  | .term (.node node) => some node.name.toString
  | .term (.var _) => none

private def dependenciesOf (declaration : Zil.Declaration) : Array Name :=
  match declaration.attr? `dependencies with
  | none => #[]
  | some attr => attr.value.scalarValues.filterMap fun value =>
      match attrValueToken? value with
      | some token => if token.isEmpty then none else some (nameFromString token)
      | none => none

/-- Convert one typed declaration to a scheduler target. -/
def ofDeclaration (declaration : Zil.Declaration) : Except String Target := do
  unless declaration.kind == .formalizationTarget do
    throw s!"{declaration.name}: expected FORMALIZATION_TARGET"
  let moduleName ← requiredToken declaration `module
  let file ← requiredToken declaration `file
  let declarationName ← requiredToken declaration `declaration
  let statusToken ← requiredToken declaration `status
  let status ← match Status.ofToken? statusToken with
    | some value => pure value
    | none => throw s!"{declaration.name}: invalid status {statusToken}"
  let priority ← priorityOf declaration
  pure {
    id := declaration.name
    moduleName
    file
    declaration := declarationName
    status
    priority
    dependencies := dependenciesOf declaration
  }

end Target

/-- One scheduling decision and the explicit reasons it is blocked. -/
structure Decision where
  target : Target
  ready : Bool
  reasons : Array String := #[]
  deriving Repr, Inhabited

private def findTarget? (targets : Array Target) (id : Name) : Option Target :=
  targets.find? fun target => target.id == id

private def duplicateIds (targets : Array Target) : Array Name :=
  targets.foldl (init := #[]) fun out target =>
    if (targets.filter fun candidate => candidate.id == target.id).size > 1 &&
       !out.contains target.id then out.push target.id else out

private def missingDependencies (targets : Array Target) : Array (Name × Name) :=
  targets.foldl (init := #[]) fun out target =>
    target.dependencies.foldl (init := out) fun current dependency =>
      if (findTarget? targets dependency).isSome then current
      else current.push (target.id, dependency)

private def reaches
    (targets : Array Target)
    (current goal : Name)
    (visited : Array Name)
    (fuel : Nat) : Bool :=
  match fuel with
  | 0 => false
  | fuel + 1 =>
      if current == goal then true
      else if visited.contains current then false
      else
        match findTarget? targets current with
        | none => false
        | some target =>
            target.dependencies.any fun dependency =>
              reaches targets dependency goal (visited.push current) fuel

private def cyclicTargets (targets : Array Target) : Array Name :=
  targets.foldl (init := #[]) fun out target =>
    let cyclic := target.dependencies.any fun dependency =>
      reaches targets dependency target.id #[] (targets.size + 1)
    if cyclic && !out.contains target.id then out.push target.id else out

/-- Validate identity, references, and dependency acyclicity. -/
def validate (targets : Array Target) : Except String Unit := do
  let duplicates := duplicateIds targets
  unless duplicates.isEmpty do
    throw s!"duplicate formalization targets: {String.intercalate "," (duplicates.toList.map Name.toString)}"
  let missing := missingDependencies targets
  unless missing.isEmpty do
    let rows := missing.toList.map fun pair => s!"{pair.1}->{pair.2}"
    throw s!"missing formalization dependencies: {String.intercalate "," rows}"
  let cycles := cyclicTargets targets
  unless cycles.isEmpty do
    throw s!"formalization dependency cycle: {String.intercalate "," (cycles.toList.map Name.toString)}"

private def decisionFor (targets : Array Target) (target : Target) : Decision := Id.run do
  let mut reasons : Array String := #[]
  unless target.status.selectable do
    reasons := reasons.push s!"status:{target.status.token}"
  for dependency in target.dependencies do
    match findTarget? targets dependency with
    | none => reasons := reasons.push s!"missing:{dependency}"
    | some required =>
        unless required.status.accepted do
          reasons := reasons.push s!"dependency:{dependency}:{required.status.token}"
  return { target, ready := reasons.isEmpty, reasons }

private def comesBefore (left right : Decision) : Bool :=
  left.target.priority > right.target.priority ||
  (left.target.priority == right.target.priority &&
    compare left.target.id.toString right.target.id.toString == .lt)

private def insertDecision (value : Decision) : List Decision → List Decision
  | [] => [value]
  | head :: tail =>
      if comesBefore value head then value :: head :: tail
      else head :: insertDecision value tail

private def sortDecisions (values : Array Decision) : Array Decision :=
  (values.foldl (init := []) fun out value => insertDecision value out).toArray

/-- Validate and compute every target decision in deterministic priority order. -/
def plan (targets : Array Target) : Except String (Array Decision) := do
  validate targets
  pure <| sortDecisions (targets.map (decisionFor targets))

/-- Highest-priority ready target, if one exists. -/
def next? (targets : Array Target) : Except String (Option Target) := do
  let decisions ← plan targets
  pure <| (decisions.find? (·.ready)).map (·.target)

/-- Extract native scheduling targets from a parsed ZIL program. -/
def fromProgram (program : Zil.Program) : Except String (Array Target) := do
  let declarations := program.declarations.filter fun declaration =>
    declaration.kind == .formalizationTarget
  let mut targets : Array Target := #[]
  for declaration in declarations do
    targets := targets.push (← Target.ofDeclaration declaration)
  validate targets
  pure targets

private def dependencyText (target : Target) : String :=
  String.intercalate "," (target.dependencies.toList.map Name.toString)

/-- Stable tab-separated plan report. -/
def renderPlan (targets : Array Target) : Except String String := do
  let decisions ← plan targets
  let rows := decisions.toList.map fun decision =>
    String.intercalate "\t" [
      "target",
      decision.target.id.toString,
      decision.target.status.token,
      toString decision.target.priority,
      if decision.ready then "ready" else "blocked",
      dependencyText decision.target,
      String.intercalate "," decision.reasons.toList,
      decision.target.moduleName,
      decision.target.file,
      decision.target.declaration
    ]
  pure <| String.intercalate "\n" ("ZIL-FORMALIZATION-PLAN\t1" :: rows) ++ "\n"

/-- Stable one-target report. -/
def renderNext (targets : Array Target) : Except String String := do
  match ← next? targets with
  | none => pure "ZIL-FORMALIZATION-NEXT\t1\nnone\n"
  | some target =>
      pure <| String.intercalate "\t" [
        "ZIL-FORMALIZATION-NEXT",
        "1",
        target.id.toString,
        target.moduleName,
        target.file,
        target.declaration,
        toString target.priority,
        dependencyText target
      ] ++ "\n"

end Zil.Formalization
