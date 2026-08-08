module

public import Zil.Horn.Basic

@[expose] public section

namespace Zil.Horn

def lookup (name : Variable) (substitution : Substitution) : Option Term :=
  substitution.lookup name

/-- Fully apply a well-founded substitution. `partial` is used because Lean
cannot infer termination from the occurs-check invariant maintained by `bind`. -/
partial def Term.substitute (substitution : Substitution) : Term → Term
  | .variable name =>
      match lookup name substitution with
      | none => .variable name
      | some value => value.substitute substitution
  | .app symbol arguments => .app symbol (arguments.map (substitute substitution))

def Atom.substitute (substitution : Substitution) (atom : Atom) : Atom :=
  { atom with arguments := atom.arguments.map (Term.substitute substitution) }

def Clause.substitute (substitution : Substitution) (clause : Clause) : Clause :=
  { head := clause.head.substitute substitution,
    body := clause.body.map (Atom.substitute substitution) }

def occurs (name : Variable) (term : Term) (substitution : Substitution) : Bool :=
  (term.substitute substitution).variables.contains name

/-- Extend a substitution using sound first-order unification. -/
def bind (name : Variable) (term : Term) (substitution : Substitution) : Option Substitution :=
  let normalized := term.substitute substitution
  if normalized == .variable name then some substitution
  else if occurs name normalized substitution then none
  else some ((name, normalized) :: substitution)

mutual
  partial def unifyTerm (left right : Term) (substitution : Substitution := []) : Option Substitution := do
    let left := left.substitute substitution
    let right := right.substitute substitution
    match left, right with
    | .variable name, term => bind name term substitution
    | term, .variable name => bind name term substitution
    | .app leftSymbol leftArguments, .app rightSymbol rightArguments =>
        if leftSymbol != rightSymbol then none
        else unifyTerms leftArguments rightArguments substitution

  partial def unifyTerms : List Term → List Term → Substitution → Option Substitution
    | [], [], substitution => some substitution
    | left :: leftRest, right :: rightRest, substitution => do
        let substitution ← unifyTerm left right substitution
        unifyTerms leftRest rightRest substitution
    | _, _, _ => none
end

def unifyAtom (left right : Atom) (substitution : Substitution := []) : Option Substitution :=
  if left.predicate != right.predicate then none
  else unifyTerms left.arguments right.arguments substitution

def normalizeSubstitution (substitution : Substitution) : Substitution :=
  substitution.map fun entry => (entry.1, entry.2.substitute substitution)

def projectSubstitution (variables : List Variable) (substitution : Substitution) : Substitution :=
  variables.filterMap fun name =>
    match lookup name substitution with
    | none => none
    | some value => some (name, value.substitute substitution)

def renderSubstitution (substitution : Substitution) : String :=
  if substitution.isEmpty then "true"
  else String.intercalate ", " (substitution.map fun entry => s!"{entry.1} = {entry.2.render}")

end Zil.Horn

