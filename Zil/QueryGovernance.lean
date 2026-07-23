import Zil.Core.Program
import Zil.Engine.Query

namespace Zil.QueryGovernance

/-- Native query-body planning policy. -/
inductive PlannerHint where
  | asIs
  | boundFirst
  | highSelectivityFirst
  deriving Repr, BEq, Inhabited

namespace PlannerHint

def ofToken? : String → Option PlannerHint
  | "as_is" => some .asIs
  | "bound_first" => some .boundFirst
  | "high_selectivity_first" => some .highSelectivityFirst
  | _ => none

def token : PlannerHint → String
  | .asIs => "as_is"
  | .boundFirst => "bound_first"
  | .highSelectivityFirst => "high_selectivity_first"

end PlannerHint

/-- One validated query-pack declaration. -/
structure QueryPack where
  name : Name
  queries : Array Name
  mustReturn : Array Name := #[]
  deriving Repr, Inhabited

/-- One validated DSL profile selecting query packs and a planner policy. -/
structure DslProfile where
  name : Name
  queryPacks : Array Name
  plannerHint : Option PlannerHint := none
  deriving Repr, Inhabited

/-- One query before and after deterministic planning. -/
structure QueryPlan where
  name : Name
  selected : Array Name
  original : Array Zil.RelExpr
  planned : Array Zil.RelExpr
  deriving Repr, Inhabited

/-- Complete planner report for one program. -/
structure PlanReport where
  moduleName : Name
  plannerHint : PlannerHint
  profiles : Array Name
  relationCardinality : Array (Name × Nat)
  queries : Array QueryPlan
  deriving Repr, Inhabited

/-- `must_return` result for one selected query. -/
structure MustReturnCheck where
  query : Name
  rowCount : Nat
  ok : Bool
  deriving Repr, Inhabited

/-- Native DSL-aware query-governance report. -/
structure CiReport where
  moduleName : Name
  plannerHint : PlannerHint
  requestedProfile : Option Name
  activeProfiles : Array Name
  selectedProfiles : Array Name
  selectedPacks : Array Name
  selectedQueries : Array Name
  missingPacks : Array Name
  missingQueries : Array Name
  mustReturn : Array MustReturnCheck
  queryRows : Array (Name × Nat)
  factsCount : Nat
  ok : Bool
  deriving Repr, Inhabited

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def sortedNames (names : Array Name) : Array Name :=
  let insert (value : Name) : List Name → List Name
    | [] => [value]
    | head :: tail =>
        match compare value.toString head.toString with
        | .lt => value :: head :: tail
        | .eq => head :: tail
        | .gt => head :: insert value tail
  (names.foldl (init := []) fun out value => insert value out).toArray

private def stripPrefix (prefix value : String) : String :=
  if value.startsWith (prefix ++ ".") then value.drop (prefix.length + 1)
  else if value.startsWith (prefix ++ ":") then value.drop (prefix.length + 1)
  else value

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun current segment =>
    if current == Name.anonymous then Name.mkSimple segment else Name.str current segment

private def canonicalRef (prefix : String) (value : String) : Name :=
  nameFromString (stripPrefix prefix value)

private def declarationTokens (declaration : Zil.Declaration) (key : Name) : Array String :=
  match declaration.attr? key with
  | none => #[]
  | some attr => attr.value.members.filterMap Zil.DeclValue.token?

private def queryPackOf (declaration : Zil.Declaration) : Option QueryPack :=
  if declaration.kind != .queryPack then none
  else
    let queries := declarationTokens declaration `queries |>.map (canonicalRef "query")
    let mustReturn := declarationTokens declaration `must_return |>.map (canonicalRef "query")
    some {
      name := canonicalRef "query_pack" declaration.name.toString
      queries := queries.foldl (init := #[]) pushName
      mustReturn := mustReturn.foldl (init := #[]) pushName
    }

private def profileOf (declaration : Zil.Declaration) : Except String (Option DslProfile) := do
  if declaration.kind != .dslProfile then return none
  let queryPacks := declarationTokens declaration `query_pack |>.map (canonicalRef "query_pack")
  let hint ← match declarationTokens declaration `planner_hint with
    | #[] => pure none
    | #[token] =>
        match PlannerHint.ofToken? token with
        | some value => pure (some value)
        | none => throw s!"DSL profile {declaration.name} has invalid planner hint {token}"
    | _ => throw s!"DSL profile {declaration.name} has multiple planner hints"
  pure <| some {
    name := canonicalRef "dsl_profile" declaration.name.toString
    queryPacks := queryPacks.foldl (init := #[]) pushName
    plannerHint := hint
  }

/-- Parse all query-pack declarations in source order. -/
def queryPacks (program : Zil.Program) : Array QueryPack :=
  program.declarations.filterMap queryPackOf

/-- Parse all DSL profiles in source order. -/
def dslProfiles (program : Zil.Program) : Except String (Array DslProfile) := do
  let mut out : Array DslProfile := #[]
  for declaration in program.declarations do
    match ← profileOf declaration with
    | none => pure ()
    | some profile => out := out.push profile
  pure out

/-- The first explicit profile hint wins, matching the legacy declaration order. -/
def plannerHint (program : Zil.Program) : Except String PlannerHint := do
  let profiles ← dslProfiles program
  pure <| (profiles.findSome? (·.plannerHint)).getD .highSelectivityFirst

private def relationCardinality (facts : Array Zil.RelExpr) (relation : Name) : Nat :=
  (facts.filter fun fact => fact.relation == relation).size

private def relationCardinalities (facts : Array Zil.RelExpr) : Array (Name × Nat) :=
  let names := facts.foldl (init := #[]) fun out fact => pushName out fact.relation
  sortedNames names |>.map fun relation => (relation, relationCardinality facts relation)

private def constantCount (relation : Zil.RelExpr) : Nat :=
  let endpoints :=
    (match relation.subject with | .node _ => 1 | .var _ => 0) +
    (match relation.object with | .node _ => 1 | .var _ => 0)
  relation.attrs.foldl (init := endpoints) fun count attr =>
    match attr.value with
    | .term (.var _) => count
    | _ => count + 1

private def boundCount (bound : Array Name) (relation : Zil.RelExpr) : Nat :=
  (relation.variables.filter bound.contains).size

private def better
    (hint : PlannerHint)
    (facts : Array Zil.RelExpr)
    (bound : Array Name)
    (left right : Nat × Zil.RelExpr) : Bool :=
  let leftCardinality := relationCardinality facts left.2.relation
  let rightCardinality := relationCardinality facts right.2.relation
  let leftBound := boundCount bound left.2
  let rightBound := boundCount bound right.2
  let leftConstants := constantCount left.2
  let rightConstants := constantCount right.2
  match hint with
  | .asIs => left.1 < right.1
  | .boundFirst =>
      leftBound > rightBound ||
      (leftBound == rightBound && leftCardinality < rightCardinality) ||
      (leftBound == rightBound && leftCardinality == rightCardinality &&
        leftConstants > rightConstants) ||
      (leftBound == rightBound && leftCardinality == rightCardinality &&
        leftConstants == rightConstants && left.1 < right.1)
  | .highSelectivityFirst =>
      leftCardinality < rightCardinality ||
      (leftCardinality == rightCardinality && leftBound > rightBound) ||
      (leftCardinality == rightCardinality && leftBound == rightBound &&
        leftConstants > rightConstants) ||
      (leftCardinality == rightCardinality && leftBound == rightBound &&
        leftConstants == rightConstants && left.1 < right.1)

private def chooseBest
    (hint : PlannerHint)
    (facts : Array Zil.RelExpr)
    (bound : Array Name) : List (Nat × Zil.RelExpr) → Option (Nat × Zil.RelExpr)
  | [] => none
  | head :: tail =>
      some <| tail.foldl (init := head) fun best candidate =>
        if better hint facts bound candidate best then candidate else best

private def removeIndexed
    (index : Nat) : List (Nat × Zil.RelExpr) → List (Nat × Zil.RelExpr)
  | [] => []
  | head :: tail => if head.1 == index then tail else head :: removeIndexed index tail

private def addVariables (bound : Array Name) (relation : Zil.RelExpr) : Array Name :=
  relation.variables.foldl (init := bound) pushName

private def planPositive
    (hint : PlannerHint)
    (facts : Array Zil.RelExpr)
    (remaining : List (Nat × Zil.RelExpr))
    (bound : Array Name := #[])
    (out : Array Zil.RelExpr := #[]) : Array Zil.RelExpr :=
  match remaining with
  | [] => out
  | _ =>
      match chooseBest hint facts bound remaining with
      | none => out
      | some selected =>
          planPositive hint facts (removeIndexed selected.1 remaining)
            (addVariables bound selected.2) (out.push selected.2)

/-- Plan positive premises and retain negative premises at the end. -/
def planQuery
    (facts : Array Zil.RelExpr)
    (hint : PlannerHint)
    (query : Zil.Query) : QueryPlan :=
  let indexed := query.premises.toList.zipIdx.map fun pair => (pair.2, pair.1)
  let plannedPositive :=
    if hint == .asIs || query.premises.size <= 1 then query.premises
    else planPositive hint facts indexed
  {
    name := query.name
    selected := query.select
    original := query.premises ++ query.negativePremises
    planned := plannedPositive ++ query.negativePremises
  }

/-- Build the native adaptive planner report. -/
def planProgram (program : Zil.Program) : Except String PlanReport := do
  unless program.valid do throw "query planner requires a structurally valid program"
  let moduleName ← match program.moduleName with
    | some value => pure value
    | none => throw "query planner requires MODULE"
  let hint ← plannerHint program
  let profiles ← dslProfiles program
  let facts := program.facts
  pure {
    moduleName
    plannerHint := hint
    profiles := sortedNames (profiles.map (·.name))
    relationCardinality := relationCardinalities facts
    queries := program.queries.map (planQuery facts hint)
  }

private def findPack? (packs : Array QueryPack) (name : Name) : Option QueryPack :=
  packs.find? fun pack => pack.name == name

private def findQuery? (queries : Array Zil.Query) (name : Name) : Option Zil.Query :=
  queries.find? fun query => query.name == name

private def selectedProfiles
    (profiles : Array DslProfile)
    (requested : Option Name) : Except String (Array DslProfile) :=
  match requested with
  | none => pure profiles
  | some name =>
      let selected := profiles.filter fun profile => profile.name == name
      if selected.isEmpty then
        throw s!"requested DSL profile {name} was not found"
      else pure selected

private def unionNames (groups : Array (Array Name)) : Array Name :=
  groups.foldl (init := #[]) fun out group => group.foldl (init := out) pushName

/-- Run DSL profile and query-pack governance over the native engine. -/
def checkProgram
    (program : Zil.Program)
    (requestedProfile : Option Name := none)
    (fuel : Nat := 64) : Except String CiReport := do
  unless program.valid do throw "query CI requires a structurally valid program"
  let moduleName ← match program.moduleName with
    | some value => pure value
    | none => throw "query CI requires MODULE"
  let profiles ← dslProfiles program
  let selected ← selectedProfiles profiles requestedProfile
  let packs := queryPacks program
  let selectedPackNames := unionNames (selected.map (·.queryPacks))
  let selectedPackRows := selectedPackNames.filterMap (findPack? packs)
  let missingPacks := selectedPackNames.filter fun name => (findPack? packs name).isNone
  let allQueryNames := program.queries.map (·.name)
  let requestedQueries :=
    if selectedPackRows.isEmpty then allQueryNames
    else unionNames (selectedPackRows.map (·.queries))
  let missingQueries := requestedQueries.filter fun name => (findQuery? program.queries name).isNone
  let activeQueries := requestedQueries.filterMap (findQuery? program.queries)
  let required := unionNames (selectedPackRows.map (·.mustReturn))
  let closed ← Zil.Engine.closureChecked program.facts program.allRules fuel
  let queryRows := activeQueries.map fun query => (query.name, (Zil.Engine.solve closed query).size)
  let checks := required.map fun name =>
    let rows := (queryRows.find? fun row => row.1 == name).map (·.2) |>.getD 0
    { query := name, rowCount := rows, ok := rows > 0 }
  let hint ← plannerHint program
  let ok := missingPacks.isEmpty && missingQueries.isEmpty && checks.all (·.ok)
  pure {
    moduleName
    plannerHint := hint
    requestedProfile
    activeProfiles := sortedNames (profiles.map (·.name))
    selectedProfiles := sortedNames (selected.map (·.name))
    selectedPacks := sortedNames (selectedPackRows.map (·.name))
    selectedQueries := requestedQueries
    missingPacks := sortedNames missingPacks
    missingQueries := sortedNames missingQueries
    mustReturn := checks
    queryRows := queryRows
    factsCount := closed.size
    ok
  }

private def relationList (relations : Array Zil.RelExpr) : String :=
  String.intercalate "," (relations.toList.map fun relation => relation.relation.toString)

private def namesText (names : Array Name) : String :=
  String.intercalate "," (names.toList.map Name.toString)

/-- Stable tab-separated adaptive planner report. -/
def renderPlan (report : PlanReport) : String :=
  let cardinality := report.relationCardinality.toList.map fun row =>
    String.intercalate "\t" ["cardinality", row.1.toString, toString row.2]
  let queries := report.queries.toList.map fun query =>
    String.intercalate "\t" [
      "query", query.name.toString, namesText query.selected,
      relationList query.original, relationList query.planned
    ]
  String.intercalate "\n" <|
    ["ZIL-QUERY-PLAN\t1",
     "module\t" ++ report.moduleName.toString,
     "planner-hint\t" ++ report.plannerHint.token,
     "profiles\t" ++ namesText report.profiles] ++ cardinality ++ queries ++ [""]

/-- Stable tab-separated query-governance report. -/
def renderCi (report : CiReport) : String :=
  let mustReturn := report.mustReturn.toList.map fun check =>
    String.intercalate "\t" ["must-return", check.query.toString,
      toString check.rowCount, if check.ok then "pass" else "fail"]
  let queryRows := report.queryRows.toList.map fun row =>
    String.intercalate "\t" ["query", row.1.toString, toString row.2]
  String.intercalate "\n" <|
    ["ZIL-QUERY-CI\t1",
     "status\t" ++ (if report.ok then "pass" else "fail"),
     "module\t" ++ report.moduleName.toString,
     "planner-hint\t" ++ report.plannerHint.token,
     "requested-profile\t" ++ report.requestedProfile.map Name.toString |>.getD "",
     "active-profiles\t" ++ namesText report.activeProfiles,
     "selected-profiles\t" ++ namesText report.selectedProfiles,
     "selected-packs\t" ++ namesText report.selectedPacks,
     "selected-queries\t" ++ namesText report.selectedQueries,
     "missing-packs\t" ++ namesText report.missingPacks,
     "missing-queries\t" ++ namesText report.missingQueries,
     "facts\t" ++ toString report.factsCount] ++ mustReturn ++ queryRows ++ [""]

end Zil.QueryGovernance
