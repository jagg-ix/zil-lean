module

public import Zil.Datalog.Relation

@[expose] public section

open Lean

namespace Zil.Datalog

/-- Why bounded relation evaluation could not return a complete answer. -/
inductive UnknownReason where
  | fuelExhausted
  | nodeLimitExceeded (limit : Nat)
  | branchingLimitExceeded (limit : Nat)
  | derivationLimitExceeded (limit : Nat)
  | cycle (relation : Name)
  | unsupportedDifference
  | undefinedRelation (relation : Name)
  deriving Repr, DecidableEq, Inhabited

/-- Resource policy for native relation evaluation. A zero bound permits no
resource of that kind; callers that want the historical behavior can use
`EvalLimits.depthOnly`. -/
structure EvalLimits where
  maxDepth : Nat := 32
  maxNodes : Nat := 4096
  maxBranching : Nat := 256
  maxDerivations : Nat := 256
  deriving Repr, DecidableEq, Inhabited

def EvalLimits.depthOnly (depth : Nat) : EvalLimits := {
  maxDepth := depth
  maxNodes := 4096
  maxBranching := 256
  maxDerivations := 256
}

instance : Coe Nat EvalLimits := ⟨EvalLimits.depthOnly⟩

/-- A finite explanation tree produced by relation evaluation. -/
inductive RelationDerivation where
  | direct (tuple : RelationTuple)
  | relationSet (tuple : RelationTuple) (child : RelationDerivation)
  | computed (relation : Name) (child : RelationDerivation)
  | unionLeft (child : RelationDerivation)
  | unionRight (child : RelationDerivation)
  | intersection (left right : RelationDerivation)
  | differenceDirect (excludedRelation : Name) (left : RelationDerivation)
  | compose (edge : RelationTuple) (intermediate : Name) (child : RelationDerivation)
  deriving Repr, DecidableEq, Inhabited

structure EvalResult where
  derivations : List RelationDerivation := []
  unknown : Option UnknownReason := none
  deriving Repr, Inhabited

def directTuple (object relation subject : Name) (tuple : RelationTuple) : Bool :=
  tuple.object == object && tuple.relation == relation && tuple.subject == .node subject

def relationSetTuple (object relation : Name) (tuple : RelationTuple) : Bool :=
  tuple.object == object && tuple.relation == relation &&
    match tuple.subject with
    | .relationSet _ _ => true
    | .node _ => false

/-- Resolve the fragment for which right-side absence is decidable from direct snapshot tuples. -/
def directExpressionRelation? (schema : RelationSchema) (queriedRelation : Name) :
    RelationExpr → Option Name
  | .this => some queriedRelation
  | .computed relation =>
      match schema.find? relation with
      | some .this => some relation
      | _ => none
  | _ => none

/-- Validate an explanation tree against an immutable schema and tuple store. -/
def validateDerivation : Nat → RelationSchema → TupleStore → Name → Name → Name →
    RelationExpr → RelationDerivation → Bool
  | 0, _, _, _, _, _, _, _ => false
  | fuel + 1, schema, store, object, relation, subject, expression, derivation =>
      match expression, derivation with
      | .this, .direct tuple =>
          directTuple object relation subject tuple && store.tuples.contains tuple
      | .this, .relationSet tuple child =>
          tuple.object == object && tuple.relation == relation && store.tuples.contains tuple &&
            match tuple.subject with
            | .node _ => false
            | .relationSet nestedObject nestedRelation =>
                match schema.find? nestedRelation with
                | some nested => validateDerivation fuel schema store nestedObject nestedRelation
                    subject nested child
                | none => false
      | .computed expected, .computed actual child =>
          expected == actual &&
            match schema.find? expected with
            | some nested => validateDerivation fuel schema store object expected subject nested child
            | none => false
      | .union left _, .unionLeft child =>
          validateDerivation fuel schema store object relation subject left child
      | .union _ right, .unionRight child =>
          validateDerivation fuel schema store object relation subject right child
      | .intersection left right, .intersection leftTree rightTree =>
          validateDerivation fuel schema store object relation subject left leftTree &&
            validateDerivation fuel schema store object relation subject right rightTree
      | .difference left right, .differenceDirect excludedRelation leftTree =>
          validateDerivation fuel schema store object relation subject left leftTree &&
            directExpressionRelation? schema relation right == some excludedRelation &&
            !(store.tuples.any (relationSetTuple object excludedRelation)) &&
            !(store.tuples.any (directTuple object excludedRelation subject))
      | .compose tupleset computed, .compose edge intermediate child =>
          edge.object == object && edge.relation == tupleset && edge.subject == .node intermediate &&
            store.tuples.contains edge &&
            match schema.find? computed with
            | some nested => validateDerivation fuel schema store intermediate computed subject nested child
            | none => false
      | _, _ => false

private theorem noThisMember_of_snapshot_absence {schema : RelationSchema} {store : TupleStore}
    {fuel : Nat} {object relation subject : Name}
    (hsets : ∀ tuple, tuple ∈ store.tuples → tuple.object = object → tuple.relation = relation →
      (match tuple.subject with | .relationSet _ _ => true | .node _ => false) = false)
    (hnodes : ∀ tuple, tuple ∈ store.tuples → tuple.object = object → tuple.relation = relation →
      ¬tuple.subject = .node subject) :
    RelationExprMember schema store fuel object relation subject .this → False := by
  cases fuel with
  | zero => simp [RelationExprMember]
  | succ fuel =>
    simp only [RelationExprMember]
    rintro (⟨tuple, tuple_mem, object_eq, relation_eq, subject_eq⟩ |
      ⟨tuple, nestedObject, nestedRelation, nested, tuple_mem, object_eq, relation_eq,
        subject_eq, nestedFind, nestedMember⟩)
    · exact hnodes tuple tuple_mem object_eq relation_eq subject_eq
    · have := hsets tuple tuple_mem object_eq relation_eq
      simp [subject_eq] at this

private theorem noDirectExpressionMember {schema : RelationSchema} {store : TupleStore}
    {fuel : Nat} {object relation subject excluded : Name} {right : RelationExpr}
    (hresolve : directExpressionRelation? schema relation right = some excluded)
    (hsets : ∀ tuple, tuple ∈ store.tuples → tuple.object = object → tuple.relation = excluded →
      (match tuple.subject with | .relationSet _ _ => true | .node _ => false) = false)
    (hnodes : ∀ tuple, tuple ∈ store.tuples → tuple.object = object → tuple.relation = excluded →
      ¬tuple.subject = .node subject) :
    RelationExprMember schema store fuel object relation subject right → False := by
  cases fuel with
  | zero => simp [RelationExprMember]
  | succ fuel => cases right with
  | this =>
      simp [directExpressionRelation?] at hresolve
      subst excluded
      exact noThisMember_of_snapshot_absence hsets hnodes
  | computed nestedRelation =>
      cases hfind : schema.find? nestedRelation with
      | none => simp [directExpressionRelation?, hfind] at hresolve
      | some expression =>
        cases expression with
        | this =>
          simp [directExpressionRelation?, hfind] at hresolve
          subst nestedRelation
          intro member
          change (∃ resolved, schema.find? excluded = some resolved ∧
            RelationExprMember schema store fuel object excluded subject resolved) at member
          rcases member with ⟨resolved, resolved_eq, resolved_member⟩
          rw [hfind] at resolved_eq
          cases resolved_eq
          exact noThisMember_of_snapshot_absence hsets hnodes resolved_member
        | computed _ | union _ _ | intersection _ _ | difference _ _ | compose _ _ =>
          simp [directExpressionRelation?, hfind] at hresolve
  | union _ _ | intersection _ _ | difference _ _ | compose _ _ =>
      simp [directExpressionRelation?] at hresolve

/-- Boolean validation is sound for the independent declarative relation semantics. -/
theorem validateDerivation_sound {fuel : Nat} {schema : RelationSchema} {store : TupleStore}
    {object relation subject : Name} {expression : RelationExpr} {tree : RelationDerivation}
    (hvalid : validateDerivation fuel schema store object relation subject expression tree = true) :
    RelationExprMember schema store fuel object relation subject expression := by
  induction fuel generalizing object relation subject expression tree with
  | zero => simp [validateDerivation] at hvalid
  | succ fuel ih =>
      cases expression <;> cases tree <;>
        simp [validateDerivation, directTuple, relationSetTuple] at hvalid
      case this.direct tuple =>
        simp only [RelationExprMember]
        rcases hvalid with ⟨⟨⟨hobject, hrelation⟩, hsubject⟩, hmem⟩
        exact Or.inl ⟨tuple, hmem, hobject, hrelation, hsubject⟩
      case this.relationSet tuple child =>
        rcases hvalid with ⟨⟨⟨hobject, hrelation⟩, hmem⟩, htail⟩
        cases subjectKind : tuple.subject with
        | node name => simp [subjectKind] at htail
        | relationSet nestedObject nestedRelation =>
          cases hfind : schema.find? nestedRelation with
          | none => simp [subjectKind, hfind] at htail
          | some nested =>
            simp [subjectKind, hfind] at htail
            simp only [RelationExprMember]
            exact Or.inr ⟨tuple, nestedObject, nestedRelation, nested, hmem, hobject, hrelation,
              subjectKind, hfind, ih htail⟩
      case computed.computed expected actual child =>
        rcases hvalid with ⟨heq, hvalid⟩
        subst actual
        split at hvalid
        next nested hfind =>
          simp only [RelationExprMember]
          exact ⟨nested, hfind, ih hvalid⟩
        next => simp_all
      case union.unionLeft left right child =>
        simp only [RelationExprMember]
        exact Or.inl (ih hvalid)
      case union.unionRight left right child =>
        simp only [RelationExprMember]
        exact Or.inr (ih hvalid)
      case intersection.intersection left right leftTree rightTree =>
        exact ⟨ih hvalid.1, ih hvalid.2⟩
      case difference.differenceDirect left right excluded leftTree =>
        rcases hvalid with ⟨⟨⟨hleft, hresolve⟩, hsets⟩, hnodes⟩
        exact ⟨ih hleft, noDirectExpressionMember hresolve hsets hnodes⟩
      case compose.compose tupleset computed edge intermediate child =>
        rcases hvalid with ⟨⟨⟨⟨hobject, hrelation⟩, hsubject⟩, hmem⟩, htail⟩
        cases hfind : schema.find? computed with
        | none => simp [hfind] at htail
        | some nested =>
          simp [hfind] at htail
          simp only [RelationExprMember]
          exact ⟨edge, intermediate, nested, hmem, hobject, hrelation, hsubject,
            hfind, ih htail⟩

/-- On a positive schema, bounded denotational membership is complete for the
derivation validator. Difference is intentionally excluded because its current
closed-world evaluator supports only a restricted direct-exclusion fragment. -/
theorem validateDerivation_complete {fuel : Nat} {schema : RelationSchema} {store : TupleStore}
    {object relation subject : Name} {expression : RelationExpr}
    (hschema : schema.Positive) (hpositive : expression.Positive)
    (hmember : RelationExprMember schema store fuel object relation subject expression) :
    ∃ tree, validateDerivation fuel schema store object relation subject expression tree = true := by
  induction fuel generalizing object relation subject expression with
  | zero => simp [RelationExprMember] at hmember
  | succ fuel ih =>
      cases expression with
      | this =>
        simp only [RelationExprMember] at hmember
        rcases hmember with
          (⟨tuple, hmem, hobject, hrelation, hsubject⟩ |
            ⟨tuple, nestedObject, nestedRelation, nested, hmem, hobject, hrelation,
              hsubject, hfind, hnested⟩)
        · exact ⟨.direct tuple, by
            simp [validateDerivation, directTuple, hobject, hrelation, hsubject, hmem]⟩
        · obtain ⟨child, hchild⟩ := ih (hschema nestedRelation nested hfind) hnested
          exact ⟨.relationSet tuple child, by
            simp [validateDerivation, hobject, hrelation, hsubject, hmem, hfind, hchild]⟩
      | computed nestedRelation =>
        simp only [RelationExprMember] at hmember
        rcases hmember with ⟨nested, hfind, hnested⟩
        obtain ⟨child, hchild⟩ := ih (hschema nestedRelation nested hfind) hnested
        exact ⟨.computed nestedRelation child, by simp [validateDerivation, hfind, hchild]⟩
      | union left right =>
        rcases hpositive with ⟨hleftPositive, hrightPositive⟩
        rcases hmember with hleft | hright
        · obtain ⟨child, hchild⟩ := ih hleftPositive hleft
          exact ⟨.unionLeft child, by simpa [validateDerivation] using hchild⟩
        · obtain ⟨child, hchild⟩ := ih hrightPositive hright
          exact ⟨.unionRight child, by simpa [validateDerivation] using hchild⟩
      | intersection left right =>
        rcases hpositive with ⟨hleftPositive, hrightPositive⟩
        rcases hmember with ⟨hleft, hright⟩
        obtain ⟨leftTree, hleftTree⟩ := ih hleftPositive hleft
        obtain ⟨rightTree, hrightTree⟩ := ih hrightPositive hright
        exact ⟨.intersection leftTree rightTree, by
          simp [validateDerivation, hleftTree, hrightTree]⟩
      | difference left right => simp [RelationExpr.Positive] at hpositive
      | compose tupleset computed =>
        simp only [RelationExprMember] at hmember
        rcases hmember with
          ⟨edge, intermediate, nested, hmem, hobject, hrelation, hsubject, hfind, hnested⟩
        obtain ⟨child, hchild⟩ := ih (hschema computed nested hfind) hnested
        exact ⟨.compose edge intermediate child, by
          simp [validateDerivation, hobject, hrelation, hsubject, hmem, hfind, hchild]⟩

/-- Validator acceptance and bounded denotational membership coincide on the
positive schema fragment. -/
theorem exists_valid_derivation_iff {fuel : Nat} {schema : RelationSchema}
    {store : TupleStore} {object relation subject : Name} {expression : RelationExpr}
    (hschema : schema.Positive) (hpositive : expression.Positive) :
    (∃ tree, validateDerivation fuel schema store object relation subject expression tree = true) ↔
      RelationExprMember schema store fuel object relation subject expression := by
  constructor
  · rintro ⟨tree, hvalid⟩
    exact validateDerivation_sound hvalid
  · exact validateDerivation_complete hschema hpositive

def mergeUnknown (left right : Option UnknownReason) : Option UnknownReason :=
  left.orElse fun _ => right

def RelationDerivation.nodeCount : RelationDerivation → Nat
  | .direct _ => 1
  | .relationSet _ child | .computed _ child | .unionLeft child | .unionRight child |
      .differenceDirect _ child => child.nodeCount + 1
  | .intersection left right => left.nodeCount + right.nodeCount + 1
  | .compose _ _ child => child.nodeCount + 1

/-- Bounded relation evaluation with explicit cycle, fuel, and unsupported-operation results. -/
def evaluateRelation : Nat → List (Name × Name) → RelationSchema → TupleStore →
    Name → Name → Name → RelationExpr → EvalResult
  | 0, _, _, _, _, _, _, _ => { unknown := some .fuelExhausted }
  | fuel + 1, visiting, schema, store, object, relation, subject, expression =>
      match expression with
      | .this =>
          let tuples := store.tuples.filter fun tuple =>
            tuple.object == object && tuple.relation == relation
          tuples.foldl (fun accumulated tuple =>
            match tuple.subject with
            | .node nestedSubject =>
                if nestedSubject == subject then
                  { accumulated with
                    derivations := accumulated.derivations ++ [.direct tuple] }
                else accumulated
            | .relationSet nestedObject nestedRelation =>
                let key := (nestedObject, nestedRelation)
                if visiting.contains key then
                  { accumulated with
                    unknown := mergeUnknown accumulated.unknown (some (.cycle nestedRelation)) }
                else
                  match schema.find? nestedRelation with
                  | none =>
                      { accumulated with
                        unknown := mergeUnknown accumulated.unknown
                          (some (.undefinedRelation nestedRelation)) }
                  | some nested =>
                      let result := evaluateRelation fuel (key :: visiting) schema store
                        nestedObject nestedRelation subject nested
                      { derivations := accumulated.derivations ++ result.derivations.map
                          fun child => .relationSet tuple child
                        unknown := mergeUnknown accumulated.unknown result.unknown }) {}
      | .computed nestedRelation =>
          let key := (object, nestedRelation)
          if visiting.contains key then
            { unknown := some (.cycle nestedRelation) }
          else
            match schema.find? nestedRelation with
            | none => { unknown := some (.undefinedRelation nestedRelation) }
            | some nested =>
                let result := evaluateRelation fuel (key :: visiting) schema store
                  object nestedRelation subject nested
                let derivations := result.derivations.map fun child =>
                  RelationDerivation.computed nestedRelation child
                { result with derivations := derivations }
      | .union left right =>
          let leftResult := evaluateRelation fuel visiting schema store object relation subject left
          let rightResult := evaluateRelation fuel visiting schema store object relation subject right
          { derivations := leftResult.derivations.map RelationDerivation.unionLeft ++
              rightResult.derivations.map RelationDerivation.unionRight
            unknown := mergeUnknown leftResult.unknown rightResult.unknown }
      | .intersection left right =>
          let leftResult := evaluateRelation fuel visiting schema store object relation subject left
          let rightResult := evaluateRelation fuel visiting schema store object relation subject right
          { derivations := leftResult.derivations.flatMap fun leftTree =>
              rightResult.derivations.map fun rightTree => .intersection leftTree rightTree
            unknown := mergeUnknown leftResult.unknown rightResult.unknown }
      | .difference left right =>
          match directExpressionRelation? schema relation right with
          | none => { unknown := some .unsupportedDifference }
          | some excludedRelation =>
              if store.tuples.any (relationSetTuple object excludedRelation) then
                { unknown := some .unsupportedDifference }
              else
                let leftResult := evaluateRelation fuel visiting schema store
                  object relation subject left
                if store.tuples.any (directTuple object excludedRelation subject) then
                  { unknown := leftResult.unknown }
                else
                  { derivations := leftResult.derivations.map fun tree =>
                      .differenceDirect excludedRelation tree
                    unknown := leftResult.unknown }
      | .compose tupleset computed =>
          match schema.find? computed with
          | none => { unknown := some (.undefinedRelation computed) }
          | some nested =>
              let edges := store.tuples.filter fun tuple =>
                tuple.object == object && tuple.relation == tupleset
              edges.foldl (fun accumulated edge =>
                match edge.subject with
                | .relationSet _ _ => accumulated
                | .node intermediate =>
                    let result := evaluateRelation fuel ((intermediate, computed) :: visiting) schema store
                      intermediate computed subject nested
                    { derivations := accumulated.derivations ++ result.derivations.map
                        fun child => .compose edge intermediate child
                      unknown := mergeUnknown accumulated.unknown result.unknown }) {}

/-- Apply the non-depth resource policy to candidates produced by the sound
depth-bounded core. Candidates outside a bound are discarded, so limits can
only turn an otherwise complete answer into `unknown`, never manufacture a
positive answer. `maxBranching` bounds candidates admitted from one queried
expression; `maxDerivations` independently bounds the public explanation set. -/
def applyEvalLimits (limits : EvalLimits) (result : EvalResult) : EvalResult :=
  let withinNodes := result.derivations.filter (·.nodeCount ≤ limits.maxNodes)
  let nodeUnknown := if withinNodes.length == result.derivations.length then none
    else some (.nodeLimitExceeded limits.maxNodes)
  let withinBranching := withinNodes.take limits.maxBranching
  let branchingUnknown := if withinNodes.length ≤ limits.maxBranching then none
    else some (.branchingLimitExceeded limits.maxBranching)
  let derivations := withinBranching.take limits.maxDerivations
  let derivationUnknown := if withinBranching.length ≤ limits.maxDerivations then none
    else some (.derivationLimitExceeded limits.maxDerivations)
  { derivations
    unknown := mergeUnknown result.unknown
      (mergeUnknown nodeUnknown (mergeUnknown branchingUnknown derivationUnknown)) }

/-- Typed public entry point for bounded relation evaluation. -/
def evaluateRelationWithLimits (limits : EvalLimits) (visiting : List (Name × Name))
    (schema : RelationSchema) (store : TupleStore) (object relation subject : Name)
    (expression : RelationExpr) : EvalResult :=
  applyEvalLimits limits
    (evaluateRelation limits.maxDepth visiting schema store object relation subject expression)

/-- A recursively emitted computed-relation child is lifted into the enclosing
evaluator result when its object/relation key passes the cycle guard. -/
theorem evaluateRelation_computed_candidate {fuel : Nat} {visiting : List (Name × Name)}
    {schema : RelationSchema} {store : TupleStore} {object relation subject nestedRelation : Name}
    {nested : RelationExpr} {child : RelationDerivation}
    (hvisit : (object, nestedRelation) ∉ visiting)
    (hfind : schema.find? nestedRelation = some nested)
    (hchild : child ∈ (evaluateRelation fuel ((object, nestedRelation) :: visiting) schema store
      object nestedRelation subject nested).derivations) :
    .computed nestedRelation child ∈
      (evaluateRelation (fuel + 1) visiting schema store object relation subject
        (.computed nestedRelation)).derivations := by
  simp [evaluateRelation, hvisit, hfind, hchild]

/-- Candidate generation is compositional through the left branch of union. -/
theorem evaluateRelation_unionLeft_candidate {fuel : Nat} {visiting : List (Name × Name)}
    {schema : RelationSchema} {store : TupleStore} {object relation subject : Name}
    {left right : RelationExpr} {child : RelationDerivation}
    (hchild : child ∈
      (evaluateRelation fuel visiting schema store object relation subject left).derivations) :
    .unionLeft child ∈
      (evaluateRelation (fuel + 1) visiting schema store object relation subject
        (.union left right)).derivations := by
  simp [evaluateRelation, hchild]

/-- Candidate generation is compositional through the right branch of union. -/
theorem evaluateRelation_unionRight_candidate {fuel : Nat} {visiting : List (Name × Name)}
    {schema : RelationSchema} {store : TupleStore} {object relation subject : Name}
    {left right : RelationExpr} {child : RelationDerivation}
    (hchild : child ∈
      (evaluateRelation fuel visiting schema store object relation subject right).derivations) :
    .unionRight child ∈
      (evaluateRelation (fuel + 1) visiting schema store object relation subject
        (.union left right)).derivations := by
  simp [evaluateRelation, hchild]

/-- A pair of recursively emitted branch candidates is lifted through intersection. -/
theorem evaluateRelation_intersection_candidate {fuel : Nat}
    {visiting : List (Name × Name)} {schema : RelationSchema} {store : TupleStore}
    {object relation subject : Name} {left right : RelationExpr}
    {leftTree rightTree : RelationDerivation}
    (hleft : leftTree ∈
      (evaluateRelation fuel visiting schema store object relation subject left).derivations)
    (hright : rightTree ∈
      (evaluateRelation fuel visiting schema store object relation subject right).derivations) :
    .intersection leftTree rightTree ∈
      (evaluateRelation (fuel + 1) visiting schema store object relation subject
        (.intersection left right)).derivations := by
  simp [evaluateRelation, List.mem_flatMap, hleft, hright]

/-- A derivation paired with kernel-checked evidence that it validates. -/
structure CertifiedRelationDerivation (schema : RelationSchema) (store : TupleStore)
    (object relation subject : Name) (expression : RelationExpr) where
  tree : RelationDerivation
  valid : validateDerivation 64 schema store object relation subject expression tree = true

/-- Result of a bounded relation check. `no` is returned only for a complete negative result. -/
inductive CheckResult (schema : RelationSchema) (store : TupleStore)
    (object relation subject : Name) (expression : RelationExpr) where
  | yes (derivation : CertifiedRelationDerivation schema store object relation subject expression)
  | no
  | unknown (reason : UnknownReason)

/-- Independent bounded denotational relation membership at the certification depth. -/
def MemberOf (schema : RelationSchema) (store : TupleStore)
    (object relation subject : Name) (expression : RelationExpr) : Prop :=
  RelationExprMember schema store 64 object relation subject expression

def certifyFirst (schema : RelationSchema) (store : TupleStore)
    (object relation subject : Name) (expression : RelationExpr) :
    List RelationDerivation →
      Option (CertifiedRelationDerivation schema store object relation subject expression)
  | [] => none
  | tree :: rest =>
      if valid : validateDerivation 64 schema store object relation subject expression tree = true then
        some ⟨tree, valid⟩
      else
        certifyFirst schema store object relation subject expression rest

/-- Certification cannot miss a validator-accepted tree already present in its
candidate list. -/
theorem certifyFirst_complete {schema : RelationSchema} {store : TupleStore}
    {object relation subject : Name} {expression : RelationExpr}
    {trees : List RelationDerivation}
    (hcandidate : ∃ tree, tree ∈ trees ∧
      validateDerivation 64 schema store object relation subject expression tree = true) :
    ∃ certified, certifyFirst schema store object relation subject expression trees =
      some certified := by
  induction trees with
  | nil => simp at hcandidate
  | cons tree rest ih =>
      simp only [certifyFirst]
      split
      next valid => exact ⟨⟨tree, valid⟩, rfl⟩
      next invalid =>
        apply ih
        rcases hcandidate with ⟨candidate, candidate_mem, candidate_valid⟩
        simp only [List.mem_cons] at candidate_mem
        rcases candidate_mem with rfl | candidate_mem
        · exact False.elim (invalid candidate_valid)
        · exact ⟨candidate, candidate_mem, candidate_valid⟩

/-- Check one relation under a schema, returning proof-bearing positive results. -/
def check (limits : EvalLimits) (schema : RelationSchema) (store : TupleStore)
    (object relation subject : Name) : CheckResult schema store object relation subject
      (schema.find? relation |>.getD .this) :=
  let expression := schema.find? relation |>.getD .this
  let evaluated := evaluateRelationWithLimits limits [(object, relation)] schema store object relation subject expression
  match certifyFirst schema store object relation subject expression evaluated.derivations with
  | some derivation => .yes derivation
  | none => match evaluated.unknown with
    | some reason => .unknown reason
    | none => .no

/-- If bounded evaluation emits any validator-accepted candidate, `check`
returns a proof-bearing positive result. -/
theorem check_yes_of_valid_candidate {limits : EvalLimits} {schema : RelationSchema}
    {store : TupleStore} {object relation subject : Name}
    (hcandidate : ∃ tree,
      tree ∈ (evaluateRelationWithLimits limits [(object, relation)] schema store object relation subject
        (schema.find? relation |>.getD .this)).derivations ∧
      validateDerivation 64 schema store object relation subject
        (schema.find? relation |>.getD .this) tree = true) :
    ∃ certified, check limits schema store object relation subject = .yes certified := by
  obtain ⟨certified, hcertified⟩ := certifyFirst_complete hcandidate
  exact ⟨certified, by simp [check, hcertified]⟩

/-- Read direct tuples without recursive relation evaluation. -/
def read (store : TupleStore) (object relation : Name) : List RelationTuple :=
  store.tuples.filter fun tuple => tuple.object == object && tuple.relation == relation

/-- Expand returns all bounded explanation candidates and an explicit completeness signal. -/
def expand (limits : EvalLimits) (schema : RelationSchema) (store : TupleStore)
    (object relation subject : Name) : EvalResult :=
  let expression := schema.find? relation |>.getD .this
  evaluateRelationWithLimits limits [(object, relation)] schema store object relation subject expression

/-- A positive check result always yields certified relation membership. -/
theorem check_sound {limits : EvalLimits} {schema : RelationSchema} {store : TupleStore}
    {object relation subject : Name}
    {derivation : CertifiedRelationDerivation schema store object relation subject
      (schema.find? relation |>.getD .this)}
    (_h : check limits schema store object relation subject = .yes derivation) :
    MemberOf schema store object relation subject (schema.find? relation |>.getD .this) :=
  validateDerivation_sound derivation.valid

end Zil.Datalog
