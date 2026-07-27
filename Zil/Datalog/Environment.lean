module

public import Lean
public import Zil.Datalog.Basic
public import Zil.Datalog.Revision
public meta import Zil.Datalog.Revision
public meta import Zil.Datalog.Eval

@[expose] public section

open Lean Elab Command

namespace Zil.Datalog

meta structure SnapshotMeta where
  revision : KnowledgeRevision
  deriving Repr, Inhabited

meta inductive ProgramEntry where
  | fact (atom : Atom)
  | rule (rule : Rule)
  | snapshot (metadata : SnapshotMeta)
  deriving Repr, Inhabited

meta structure ProgramState where
  program : Program := {}
  snapshots : List SnapshotMeta := []
  deriving Repr, Inhabited

meta def ProgramState.add (state : ProgramState) : ProgramEntry → ProgramState
  | .fact atom =>
      { state with program.facts := state.program.facts ++ [atom] }
  | .rule rule =>
      { state with program.rules := state.program.rules ++ [rule] }
  | .snapshot metadata =>
      { state with snapshots := state.snapshots ++ [metadata] }

meta initialize programExt : SimplePersistentEnvExtension ProgramEntry ProgramState ←
  registerSimplePersistentEnvExtension {
    name := `Zil.Datalog.programExt
    addEntryFn := ProgramState.add
    addImportedFn := fun modules =>
      modules.foldl (fun state entries => entries.foldl ProgramState.add state) {}
  }

/-- A hygienic macro placeholder is distinct from both a ZIL variable and a
literal value; substitution therefore cannot rewrite substrings or attributes
accidentally. -/
meta inductive MacroTerm where
  | parameter (name : Name)
  | value (value : Value)
  deriving Repr, DecidableEq, Inhabited

meta structure MacroAtom where
  object : MacroTerm
  relation : String
  subject : MacroTerm
  attrs : List (String × MacroTerm) := []
  deriving Repr, DecidableEq, Inhabited

meta structure ZilMacroDef where
  params : List Name
  facts : List MacroAtom
  deriving Repr, Inhabited

meta structure MacroState where
  definitions : List (Name × ZilMacroDef) := []
  deriving Repr, Inhabited

meta def MacroState.add (state : MacroState) (entry : Name × ZilMacroDef) : MacroState :=
  { definitions := state.definitions.filter (·.1 != entry.1) ++ [entry] }

meta initialize zilMacroExt :
    SimplePersistentEnvExtension (Name × ZilMacroDef) MacroState ←
  registerSimplePersistentEnvExtension {
    name := `Zil.Datalog.zilMacroExt
    addEntryFn := MacroState.add
    addImportedFn := fun modules =>
      modules.foldl (fun state entries => entries.foldl MacroState.add state) {}
  }

meta def currentProgram (env : Environment) : Program :=
  (programExt.getState env).program

declare_syntax_cat zilTerm
declare_syntax_cat zilAttr
declare_syntax_cat zilAtom
declare_syntax_cat zilLiteral
declare_syntax_cat zilMacroParam

syntax str : zilTerm
syntax num : zilTerm
syntax ident : zilTerm
syntax "?" ident : zilTerm
syntax "param(" ident ")" : zilTerm
syntax ident "=" zilTerm : zilAttr
syntax zilTerm "#" ident "@" zilTerm : zilAtom
syntax zilTerm "#" ident "@" zilTerm "[" zilAttr,* "]" : zilAtom
syntax zilAtom : zilLiteral
syntax "NOT " zilAtom : zilLiteral
syntax ident : zilMacroParam

meta def termFromSyntax (stx : Syntax) : CommandElabM Term := do
  match stx with
  | `(zilTerm| $value:str) => pure (.value (.symbol value.getString))
  | `(zilTerm| $value:num) => pure (.value (.integer value.getNat))
  | `(zilTerm| $value:ident) =>
      match value.getId.toString with
      | "true" => pure (.value (.boolean true))
      | "false" => pure (.value (.boolean false))
      | symbol => pure (.value (.symbol symbol))
  | `(zilTerm| ? $name:ident) => pure (.variable name.getId.toString)
  | `(zilTerm| param($name:ident)) =>
      throwErrorAt stx "macro placeholder 'param({name.getId})' is valid only inside zil_macro"
  | _ => throwErrorAt stx "unsupported ZIL term"

meta def attrFromSyntax (stx : Syntax) : CommandElabM (String × Term) :=
  match stx with
  | `(zilAttr| $key:ident = $value:zilTerm) => do
      pure (key.getId.toString, ← termFromSyntax value)
  | _ => throwErrorAt stx "invalid ZIL attribute"

meta def attrsFromSyntax (attrs : Array (TSyntax `zilAttr)) : CommandElabM PatternAttrs := do
  let parsed ← attrs.mapM attrFromSyntax
  let keys := parsed.map (·.1)
  unless keys.toList.eraseDups.length = keys.size do
    throwError "ZIL atom attribute keys must be unique"
  pure parsed.toList

meta def groundAttrs : PatternAttrs → CommandElabM AtomAttrs
  | [] => pure []
  | (key, .value value) :: rest => do
      pure ((key, value) :: (← groundAttrs rest))
  | (_, .variable _) :: _ =>
      throwError "zil_fact must be ground; variables are allowed only in rules and queries"

meta def patternFromSyntax (stx : Syntax) : CommandElabM Pattern :=
  match stx with
  | `(zilAtom| $object:zilTerm # $relation:ident @ $subject:zilTerm) =>
      return {
        object := ← termFromSyntax object
        relation := relation.getId.toString
        subject := ← termFromSyntax subject
      }
  | `(zilAtom| $object:zilTerm # $relation:ident @ $subject:zilTerm [$attrs:zilAttr,*]) =>
      return {
        object := ← termFromSyntax object
        relation := relation.getId.toString
        subject := ← termFromSyntax subject
        attrs := ← attrsFromSyntax attrs
      }
  | _ => throwErrorAt stx "invalid ZIL atom"

meta def atomFromSyntax (stx : Syntax) : CommandElabM Atom := do
  let pattern ← patternFromSyntax stx
  match pattern.object, pattern.subject with
  | .value object, .value subject =>
      let attrs ← groundAttrs pattern.attrs
      pure { object, relation := pattern.relation, subject, attrs }
  | _, _ => throwErrorAt stx "zil_fact must be ground; variables are allowed only in rules and queries"

meta def literalFromSyntax (stx : Syntax) : CommandElabM Literal :=
  match stx with
  | `(zilLiteral| $pattern:zilAtom) => do
      pure (.positive (← patternFromSyntax pattern))
  | `(zilLiteral| NOT $pattern:zilAtom) => do
      pure (.negative (← patternFromSyntax pattern))
  | _ => throwErrorAt stx "invalid ZIL literal"

meta def macroTermFromSyntax (params : List Name) (stx : Syntax) : CommandElabM MacroTerm := do
  if let `(zilTerm| param($name:ident)) := stx then
    if params.contains name.getId then pure (.parameter name.getId)
    else throwErrorAt name "undeclared ZIL macro parameter '{name.getId}'"
  else
    match ← termFromSyntax stx with
    | Term.value v => pure (.value v)
    | Term.variable varName => throwErrorAt stx
        "ZIL fact macros emit ground declarations; rule variable '?{varName}' is not allowed"

meta def macroAttrFromSyntax (params : List Name) (stx : Syntax) :
    CommandElabM (String × MacroTerm) :=
  match stx with
  | `(zilAttr| $key:ident = $value:zilTerm) => do
      pure (key.getId.toString, ← macroTermFromSyntax params value)
  | _ => throwErrorAt stx "invalid ZIL macro attribute"

meta def macroAtomFromSyntax (params : List Name) (stx : Syntax) : CommandElabM MacroAtom :=
  match stx with
  | `(zilAtom| $object:zilTerm # $relation:ident @ $subject:zilTerm) => do
      pure {
        object := ← macroTermFromSyntax params object
        relation := relation.getId.toString
        subject := ← macroTermFromSyntax params subject
      }
  | `(zilAtom| $object:zilTerm # $relation:ident @ $subject:zilTerm [$attrs:zilAttr,*]) => do
      let parsed ← attrs.getElems.toList.mapM fun attr => macroAttrFromSyntax params attr.raw
      unless (parsed.map (·.1)).eraseDups.length = parsed.length do
        throwErrorAt stx "ZIL macro atom attribute keys must be unique"
      pure {
        object := ← macroTermFromSyntax params object
        relation := relation.getId.toString
        subject := ← macroTermFromSyntax params subject
        attrs := parsed
      }
  | _ => throwErrorAt stx "invalid ZIL macro atom"

meta def MacroTerm.instantiate (bindings : List (Name × Value)) : MacroTerm → Option Value
  | .value v => some v
  | .parameter paramName => bindings.lookup paramName

meta def MacroAtom.instantiate (bindings : List (Name × Value)) (template : MacroAtom) : Option Atom := do
  let object ← template.object.instantiate bindings
  let subject ← template.subject.instantiate bindings
  let attrs ← template.attrs.mapM fun pair => do
    let value ← pair.2.instantiate bindings
    pure (pair.1, value)
  pure { object, relation := template.relation, subject, attrs }

syntax (name := zilSnapshotCmd)
  "zil_snapshot " str " completeness " ident : command

@[command_elab zilSnapshotCmd]
meta def elabZilSnapshot : CommandElab := fun stx => do
  match stx with
  | `(zil_snapshot $revision:str completeness $status:ident) =>
      let revisionValue := revision.getString
      unless revisionValue.startsWith "sha256:" && revisionValue.length = 71 do
        throwErrorAt revision "snapshot revision must be `sha256:` followed by 64 hexadecimal characters"
      let statusValue := status.getId.toString
      unless statusValue = "complete" || statusValue = "partial" do
        throwErrorAt status "snapshot completeness must be `complete` or `partial`"
      modifyEnv fun env => programExt.addEntry env (.snapshot {
        revision := .snapshot revisionValue
          (if statusValue = "complete" then .complete else .partialSnapshot)
          env.mainModule
      })
  | _ => throwUnsupportedSyntax

syntax (name := zilFactCmd) "zil_fact " zilAtom : command

@[command_elab zilFactCmd]
meta def elabZilFact : CommandElab := fun stx => do
  match stx with
  | `(zil_fact $atom:zilAtom) =>
      let atom ← atomFromSyntax atom
      modifyEnv fun env => programExt.addEntry env (.fact atom)
  | _ => throwUnsupportedSyntax

syntax (name := zilMacroCmd)
  "zil_macro " ident "(" zilMacroParam,* ")" "=>" zilAtom (" EMIT " zilAtom)* : command
syntax (name := zilUseCmd)
  "zil_use " ident "(" zilTerm,* ")" : command

@[command_elab zilMacroCmd]
meta def elabZilMacro : CommandElab := fun stx => do
  match stx with
  | `(zil_macro $name:ident ($params:zilMacroParam,*) => $first:zilAtom $[EMIT $rest:zilAtom]*) =>
      let paramNames := params.getElems.toList.map fun param => param.raw[0].getId
      unless paramNames.eraseDups.length = paramNames.length do
        throwErrorAt stx "ZIL macro parameter names must be unique"
      let state := zilMacroExt.getState (← getEnv)
      if (state.definitions.lookup name.getId).isSome then
        throwErrorAt name "duplicate ZIL macro '{name.getId}'"
      let mut facts := [← macroAtomFromSyntax paramNames first]
      for item in rest do
        facts := facts ++ [← macroAtomFromSyntax paramNames item]
      modifyEnv fun env => zilMacroExt.addEntry env (name.getId, { params := paramNames, facts })
  | _ => throwUnsupportedSyntax

@[command_elab zilUseCmd]
meta def elabZilUse : CommandElab := fun stx => do
  match stx with
  | `(zil_use $name:ident ($args:zilTerm,*)) =>
      let state := zilMacroExt.getState (← getEnv)
      let some definition := state.definitions.lookup name.getId
        | throwErrorAt name "undefined ZIL macro '{name.getId}'"
      let argSyntax := args.getElems.toList
      unless argSyntax.length = definition.params.length do
        throwErrorAt stx "ZIL macro '{name.getId}' expects {definition.params.length} arguments, got {argSyntax.length}"
      let mut values := []
      for arg in argSyntax do
        match ← termFromSyntax arg with
        | .value value => values := values ++ [value]
        | .variable _ => throwErrorAt arg "zil_use arguments must be ground values"
      let bindings := definition.params.zip values
      let some facts := definition.facts.mapM (·.instantiate bindings)
        | throwErrorAt stx "internal ZIL macro binding failure"
      modifyEnv fun env => facts.foldl (fun env fact => programExt.addEntry env (.fact fact)) env
  | _ => throwUnsupportedSyntax

syntax (name := zilRuleCmd)
  "zil_rule " ident ": " zilAtom (", " zilAtom)*
    " IF " zilLiteral (" AND " zilLiteral)* : command

@[command_elab zilRuleCmd]
meta def elabZilRule : CommandElab := fun stx => do
  match stx with
  | `(zil_rule $name:ident : $head:zilAtom $[, $heads:zilAtom]*
      IF $first:zilLiteral $[AND $rest:zilLiteral]*) =>
      let mut parsedHeads := [← patternFromSyntax head]
      for item in heads do
        parsedHeads := parsedHeads ++ [← patternFromSyntax item]
      let mut literals := [← literalFromSyntax first]
      for item in rest do
        literals := literals ++ [← literalFromSyntax item]
      let rules := lowerRuleHeads name.getId.toString parsedHeads literals
      for rule in rules do
        unless rule.isSafe do
          throwErrorAt stx "unsafe ZIL rule '{rule.name}': unbound head variables={rule.unboundHeadVariables}, unbound negative variables={rule.unboundNegativeVariables}"
      let state := programExt.getState (← getEnv)
      let prospective := { state.program with rules := state.program.rules ++ rules }
      unless prospective.isStratified do
        throwErrorAt stx "non-stratifiable ZIL rule '{name.getId}': a negative dependency participates in a cycle"
      modifyEnv fun env => rules.foldl (fun env rule => programExt.addEntry env (.rule rule)) env
  | _ => throwUnsupportedSyntax

syntax (name := zilQueryCmd) "#zil_query " zilAtom : command
syntax (name := zilQueryFuelCmd) "#zil_query " zilAtom " fuel " num : command

@[command_elab zilQueryCmd, command_elab zilQueryFuelCmd]
meta def elabZilQuery : CommandElab := fun stx => do
  match stx with
  | `(#zil_query $pattern:zilAtom) =>
      let state := programExt.getState (← getEnv)
      unless state.program.supportsNegation do
        throwErrorAt stx "cannot query a non-stratifiable ZIL program"
      let pattern ← patternFromSyntax pattern
      let queryFuel := 32
      let rows := query state.program pattern queryFuel
      let revisions := state.snapshots.map (fun metadata =>
        metadata.revision)
      logInfo m!"ZIL query (fuel={queryFuel}, snapshots={repr revisions}): {repr rows}"
  | `(#zil_query $pattern:zilAtom fuel $amount:num) =>
      let state := programExt.getState (← getEnv)
      unless state.program.supportsNegation do
        throwErrorAt stx "cannot query a non-stratifiable ZIL program"
      let pattern ← patternFromSyntax pattern
      let queryFuel := amount.getNat
      let rows := query state.program pattern queryFuel
      let revisions := state.snapshots.map (fun metadata =>
        metadata.revision)
      logInfo m!"ZIL query (fuel={queryFuel}, snapshots={repr revisions}): {repr rows}"
  | _ => throwUnsupportedSyntax

end Zil.Datalog
