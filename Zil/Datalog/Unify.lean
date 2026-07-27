module

public import Zil.Datalog.Basic

@[expose] public section

namespace Zil.Datalog

def lookup (name : String) (substitution : Substitution) : Option Value :=
  substitution.lookup name

def bind (name : String) (value : Value) (substitution : Substitution) : Option Substitution :=
  match lookup name substitution with
  | none => some ((name, value) :: substitution)
  | some existing => if existing == value then some substitution else none

def unifyTerm (term : Term) (value : Value) (substitution : Substitution) : Option Substitution :=
  match term with
  | .value expected => if expected == value then some substitution else none
  | .variable name => bind name value substitution

/-- Pattern attributes are subset constraints: every requested key must occur
in the ground atom and unify under the shared substitution. -/
def unifyAttrs : PatternAttrs → AtomAttrs → Substitution → Option Substitution
  | [], _, substitution => some substitution
  | (key, term) :: rest, attrs, substitution => do
      let value ← attrs.lookup key
      let substitution ← unifyTerm term value substitution
      unifyAttrs rest attrs substitution

def unify (pattern : Pattern) (atom : Atom) (substitution : Substitution := []) : Option Substitution := do
  if pattern.relation != atom.relation then none else
  let substitution ← unifyTerm pattern.object atom.object substitution
  let substitution ← unifyTerm pattern.subject atom.subject substitution
  unifyAttrs pattern.attrs atom.attrs substitution

def instantiateTerm (substitution : Substitution) : Term → Option Value
  | .value value => some value
  | .variable name => lookup name substitution

def instantiateAttrs (substitution : Substitution) : PatternAttrs → Option AtomAttrs
  | [] => some []
  | (key, term) :: rest => do
      let value ← instantiateTerm substitution term
      let values ← instantiateAttrs substitution rest
      pure ((key, value) :: values)

def instantiate (pattern : Pattern) (substitution : Substitution) : Option Atom := do
  let object ← instantiateTerm substitution pattern.object
  let subject ← instantiateTerm substitution pattern.subject
  let attrs ← instantiateAttrs substitution pattern.attrs
  pure { object, relation := pattern.relation, subject, attrs }

end Zil.Datalog
