import Zil.Core.Declaration

namespace Zil.DeclarationSet

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun current segment =>
    if current == Name.anonymous then Name.mkSimple segment else Name.str current segment

private def sanitize (value : String) : String :=
  value.replace ":" "." |>.replace "/" "." |>.replace "-" "_" |>.replace " " "_"

private def referenceName (prefix : String) (value : DeclValue) : Option Name :=
  value.token?.map fun token =>
    let normalized := sanitize token
    if normalized.splitOn "." |>.length > 1 then nameFromString normalized
    else nameFromString (prefix ++ "." ++ normalized)

private def references (prefix : String) (value : DeclValue) : Array Name :=
  value.members.filterMap (referenceName prefix)

private def hasEntity (declarations : Array Declaration) (name : Name) : Bool :=
  declarations.any fun declaration => declaration.entityName == name

private def addIssue
    (issues : Array DeclarationIssue)
    (declaration : Declaration)
    (kind : DeclarationIssueKind)
    (message : String)
    (key : Option Name := none) : Array DeclarationIssue :=
  issues.push { kind, declaration := declaration.entityName, key, message }

private def checkReferences
    (declarations : Array Declaration)
    (declaration : Declaration)
    (key : Name)
    (prefix : String)
    (issues : Array DeclarationIssue) : Array DeclarationIssue :=
  match declaration.attr? key with
  | none => issues
  | some attr =>
      references prefix attr.value |>.foldl (init := issues) fun out reference =>
        if hasEntity declarations reference then out
        else addIssue out declaration .invalidReference
          s!"attribute {key} references missing declaration {reference}" (some key)

private def checkDeclarationReferences
    (declarations : Array Declaration)
    (declaration : Declaration)
    (issues : Array DeclarationIssue) : Array DeclarationIssue :=
  let issues :=
    if declaration.kind == .service then
      checkReferences declarations declaration `uses "service" issues |>
      checkReferences declarations declaration `used_by "service"
    else issues
  let issues :=
    if declaration.kind == .metric then
      checkReferences declarations declaration `source "datasource" issues
    else issues
  let issues :=
    checkReferences declarations declaration `provider "provider" issues |>
    checkReferences declarations declaration `providers "provider"
  let issues :=
    if declaration.kind == .grammarProfile then
      checkReferences declarations declaration `language "language_profile" issues
    else issues
  let issues :=
    if declaration.kind == .parserAdapter then
      checkReferences declarations declaration `language "language_profile" issues |>
      checkReferences declarations declaration `grammar "grammar_profile"
    else issues
  let issues :=
    if declaration.kind == .dslProfile then
      checkReferences declarations declaration `query_pack "query_pack" issues
    else issues
  let issues :=
    if declaration.kind == .proofObligation then
      checkReferences declarations declaration `relation "refines" issues
    else issues
  let issues :=
    if declaration.kind == .corresponds then
      checkReferences declarations declaration `refines "refines" issues
    else issues
  issues

private def serviceEdges (declarations : Array Declaration) : Array (Name × Name) :=
  declarations.foldl (init := #[]) fun edges declaration =>
    if declaration.kind != .service then edges
    else
      let direct := match declaration.attr? `uses with
        | none => #[]
        | some attr => references "service" attr.value |>.map fun target => (declaration.entityName, target)
      let inverse := match declaration.attr? `used_by with
        | none => #[]
        | some attr => references "service" attr.value |>.map fun source => (source, declaration.entityName)
      edges ++ direct ++ inverse

private def pushUniqueName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def nextNodes (edges : Array (Name × Name)) (frontier : Array Name) : Array Name :=
  edges.foldl (init := #[]) fun out edge =>
    if frontier.contains edge.1 then pushUniqueName out edge.2 else out

private def reachable
    (edges : Array (Name × Name))
    (start target : Name)
    (fuel : Nat) : Bool :=
  let rec loop (frontier visited : Array Name) : Nat → Bool
    | 0 => false
    | remaining + 1 =>
        if frontier.contains target then true
        else
          let next := nextNodes edges frontier |>.filter fun node => !visited.contains node
          if next.isEmpty then false
          else loop next (next.foldl (init := visited) pushUniqueName) remaining
  loop #[start] #[start] fuel

private def cycleIssues
    (declarations : Array Declaration)
    (issues : Array DeclarationIssue) : Array DeclarationIssue :=
  let edges := serviceEdges declarations
  let services := declarations.filter fun declaration => declaration.kind == .service
  services.foldl (init := issues) fun out declaration =>
    let cyclic := edges.any fun edge =>
      edge.1 == declaration.entityName &&
      reachable edges edge.2 declaration.entityName (services.size + 1)
    if cyclic then
      addIssue out declaration .dependencyCycle
        s!"service dependency cycle includes {declaration.entityName}"
    else out

/-- Validate local declarations, duplicate identities, cross references, and the
service dependency graph. -/
def issues (declarations : Array Declaration) : Array DeclarationIssue :=
  let local := declarations.foldl (init := #[]) fun out declaration =>
    out ++ declaration.issues
  let duplicates := declarations.foldl (init := local) fun out declaration =>
    let count := (declarations.filter fun candidate =>
      candidate.entityName == declaration.entityName).size
    if count > 1 && !(out.any fun issue =>
        issue.kind == .duplicateDeclaration && issue.declaration == declaration.entityName) then
      addIssue out declaration .duplicateDeclaration
        s!"duplicate declaration {declaration.entityName}"
    else out
  let referenced := declarations.foldl (init := duplicates) fun out declaration =>
    checkDeclarationReferences declarations declaration out
  cycleIssues declarations referenced

/-- True when the declaration collection is locally and globally valid. -/
def valid (declarations : Array Declaration) : Bool :=
  (issues declarations).isEmpty

/-- Lower all valid declarations to a deduplicated relation collection. -/
def lower (declarations : Array Declaration) : Except (Array DeclarationIssue) (Array RelExpr) :=
  let problems := issues declarations
  if !problems.isEmpty then .error problems
  else
    .ok <| declarations.foldl (init := #[]) fun facts declaration =>
      declaration.lower.foldl (init := facts) fun out fact =>
        if out.any (fun current => current.semanticallyEqual fact) then out
        else out.push fact

end Zil.DeclarationSet
