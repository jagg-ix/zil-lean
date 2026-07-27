module

@[expose] public section

namespace Zil.Datalog

inductive Value where
  | symbol (value : String)
  | string (value : String)
  | integer (value : Int)
  | boolean (value : Bool)
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

/-- Canonical ground atom attributes. Keys are expected to be unique; list
representation keeps snapshots deterministic and portable across runtimes. -/
abbrev AtomAttrs := List (String × Value)

structure Atom where
  object : Value
  relation : String
  subject : Value
  attrs : AtomAttrs := []
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

inductive Term where
  | variable (name : String)
  | value (value : Value)
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

/-- Attribute patterns use the same keys as ground attributes and may bind variables. -/
abbrev PatternAttrs := List (String × Term)

structure Pattern where
  object : Term
  relation : String
  subject : Term
  attrs : PatternAttrs := []
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

/-- Explicit literal polarity for the stratified core. Rule migration uses this
type while the existing positive-rule field remains source compatible. -/
inductive Literal where
  | positive (pattern : Pattern)
  | negative (pattern : Pattern)
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

def Term.variables : Term → List String
  | .variable name => [name]
  | .value _ => []

def Pattern.variables (pattern : Pattern) : List String :=
  (pattern.object.variables ++ pattern.subject.variables ++
    pattern.attrs.flatMap fun pair => pair.2.variables).eraseDups

def Literal.variables : Literal → List String
  | .positive pattern | .negative pattern => pattern.variables

structure Rule where
  name : String
  head : Pattern
  /-- Canonical ordered rule body. Literal order and polarity are preserved. -/
  literals : List Literal := []
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

def Rule.effectiveLiterals (rule : Rule) : List Literal :=
  rule.literals

def Rule.positiveBody (rule : Rule) : List Pattern :=
  rule.effectiveLiterals.filterMap fun literal =>
    match literal with | .positive pattern => some pattern | .negative _ => none

def Rule.negativePatterns (rule : Rule) : List Pattern :=
  rule.effectiveLiterals.filterMap fun literal =>
    match literal with | .negative pattern => some pattern | .positive _ => none

/-- Stable names for rules produced from a multi-head declaration. The first
head preserves the declaration name for single-head source compatibility. -/
def loweredRuleName (base : String) (headIndex : Nat) : String :=
  if headIndex = 0 then base else s!"{base}#{headIndex + 1}"

/-- Deterministically lower a general ZIL multi-head rule into the canonical
single-head core consumed by evaluation and proof semantics. -/
def lowerRuleHeads (name : String) (heads : List Pattern)
    (literals : List Literal) : List Rule :=
  heads.mapIdx fun index head => {
    name := loweredRuleName name index
    head
    literals
  }

/-- Variables produced by the head must be bound by a positive body pattern. -/
def Rule.unboundHeadVariables (rule : Rule) : List String :=
  let bodyVariables := (rule.positiveBody.flatMap Pattern.variables).eraseDups
  rule.head.variables.filter fun variableName => !bodyVariables.contains variableName

def Rule.unboundNegativeVariables (rule : Rule) : List String :=
  let bodyVariables := (rule.positiveBody.flatMap Pattern.variables).eraseDups
  (rule.negativePatterns.flatMap Pattern.variables).eraseDups.filter fun variableName =>
    !bodyVariables.contains variableName

def Rule.isSafe (rule : Rule) : Bool :=
  rule.unboundHeadVariables.isEmpty && rule.unboundNegativeVariables.isEmpty

inductive RuleDependencyPolarity where
  | positive
  | negative
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

structure RuleDependency where
  source : String
  target : String
  polarity : RuleDependencyPolarity
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

def RuleDependency.ofPattern (polarity : RuleDependencyPolarity) (headRelation : String)
    (pattern : Pattern) : RuleDependency where
  source := pattern.relation
  target := headRelation
  polarity := polarity

def Rule.dependencies (rule : Rule) : List RuleDependency :=
  rule.effectiveLiterals.map fun literal =>
    match literal with
    | .positive pattern => RuleDependency.ofPattern .positive rule.head.relation pattern
    | .negative pattern => RuleDependency.ofPattern .negative rule.head.relation pattern

structure Program where
  facts : List Atom := []
  rules : List Rule := []
  deriving Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Inhabited

def Program.dependencies (program : Program) : List RuleDependency :=
  program.rules.flatMap Rule.dependencies

def Program.reachesAux (program : Program) (target : String) :
    Nat → List String → String → Bool
  | 0, _, _ => false
  | fuel + 1, visited, current =>
      if current == target then true
      else if visited.contains current then false
      else
        (program.dependencies.filter (·.source == current)).any fun dependency =>
          program.reachesAux target fuel (current :: visited) dependency.target

def Program.reaches (program : Program) (target current : String) : Bool :=
  program.reachesAux target (program.dependencies.length + 1) [] current

/-- A negative dependency may not participate in any dependency cycle. This is
the standard graph criterion for existence of a stratification. -/
def Program.isStratified (program : Program) : Bool :=
  program.dependencies.all fun dependency =>
    dependency.polarity == .positive || !program.reaches dependency.source dependency.target

abbrev RelationStrata := List (String × Nat)

def RelationStrata.get (strata : RelationStrata) (relation : String) : Nat :=
  strata.lookup relation |>.getD 0

def RelationStrata.set (strata : RelationStrata) (relation : String) (value : Nat) : RelationStrata :=
  (relation, value) :: strata.filter fun entry => entry.1 != relation

def Program.relations (program : Program) : List String :=
  (program.facts.map (·.relation) ++ program.rules.map (·.head.relation) ++
    program.dependencies.flatMap fun dependency => [dependency.source, dependency.target]).eraseDups

def Program.relaxStrata (program : Program) (strata : RelationStrata) : RelationStrata :=
  program.dependencies.foldl (fun current dependency =>
    let increment := if dependency.polarity == .negative then 1 else 0
    let required := current.get dependency.source + increment
    if current.get dependency.target < required then
      current.set dependency.target required
    else current) strata

def Program.computeStrataAux (program : Program) : Nat → RelationStrata → RelationStrata
  | 0, strata => strata
  | fuel + 1, strata => program.computeStrataAux fuel (program.relaxStrata strata)

/-- Least dependency levels for a stratifiable program, computed by bounded
Bellman-Ford-style relaxation. -/
def Program.computeStrata (program : Program) : RelationStrata :=
  let initial := program.relations.map fun relation => (relation, 0)
  program.computeStrataAux (program.relations.length) initial

def Program.stratumOf (program : Program) (relation : String) : Nat :=
  program.computeStrata.get relation

def Program.maxStratum (program : Program) : Nat :=
  program.computeStrata.foldl (fun maximum entry => max maximum entry.2) 0

/-- The first executable negation profile permits absence checks only against
extensional snapshot relations. This keeps the existing simultaneous positive
fixed point correct until evaluation is explicitly ordered by strata. -/
def Program.hasExtensionalNegation (program : Program) : Bool :=
  let derivedRelations := program.rules.map (·.head.relation)
  program.dependencies.all fun dependency =>
    dependency.polarity == .positive || !derivedRelations.contains dependency.source

def Program.supportsNegation (program : Program) : Bool :=
  program.isStratified

abbrev Substitution := List (String × Value)

end Zil.Datalog
