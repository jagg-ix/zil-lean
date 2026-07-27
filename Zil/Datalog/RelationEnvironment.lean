module

public import Lean
public meta import Zil.Datalog.RelationEval

@[expose] public section

open Lean Elab Command

namespace Zil.Datalog

meta inductive RelationEntry where
  | schema (profile : Name) (version : Nat)
  | revision (token : String)
  | relation (definition : RelationDef)
  | validated
  | tuple (tuple : RelationTuple)
  deriving Repr, Inhabited

meta structure RelationState where
  schema : RelationSchema := { profile := `default, version := 1 }
  store : TupleStore := { revision := { token := "unversioned" } }
  validated : Bool := false
  deriving Repr, Inhabited

meta def RelationState.add (state : RelationState) : RelationEntry → RelationState
  | .schema profile version =>
      { state with
        schema := { state.schema with profile, version },
        validated := false,
        store := { state.store with
          revision := state.store.revision.withSchema profile version } }
  | .revision token =>
      { state with store := { state.store with
          revision := { state.store.revision with token } } }
  | .relation definition =>
      let schema := { state.schema with
        definitions := state.schema.definitions ++ [definition] }
      { state with schema := schema, validated := false }
  | .validated => { state with validated := true }
  | .tuple tuple =>
      { state with store := { state.store with tuples := state.store.tuples ++ [tuple] } }

meta initialize relationExt : SimplePersistentEnvExtension RelationEntry RelationState ←
  registerSimplePersistentEnvExtension {
    name := `Zil.Datalog.relationExt
    addEntryFn := RelationState.add
    addImportedFn := fun modules =>
      modules.foldl (fun state entries => entries.foldl RelationState.add state) {}
  }

declare_syntax_cat zilRelationExpr
syntax "this" : zilRelationExpr
syntax "computed(" ident ")" : zilRelationExpr
syntax "union(" zilRelationExpr "," zilRelationExpr ")" : zilRelationExpr
syntax "intersection(" zilRelationExpr "," zilRelationExpr ")" : zilRelationExpr
syntax "difference(" zilRelationExpr "," zilRelationExpr ")" : zilRelationExpr
syntax "compose(" ident "," ident ")" : zilRelationExpr

meta partial def relationExprFromSyntax (stx : Syntax) : CommandElabM RelationExpr := do
  match stx with
  | `(zilRelationExpr| this) => pure .this
  | `(zilRelationExpr| computed($relation:ident)) => pure (.computed relation.getId)
  | `(zilRelationExpr| union($left:zilRelationExpr, $right:zilRelationExpr)) =>
      pure (.union (← relationExprFromSyntax left) (← relationExprFromSyntax right))
  | `(zilRelationExpr| intersection($left:zilRelationExpr, $right:zilRelationExpr)) =>
      pure (.intersection (← relationExprFromSyntax left) (← relationExprFromSyntax right))
  | `(zilRelationExpr| difference($left:zilRelationExpr, $right:zilRelationExpr)) =>
      pure (.difference (← relationExprFromSyntax left) (← relationExprFromSyntax right))
  | `(zilRelationExpr| compose($tupleset:ident, $computed:ident)) =>
      pure (.compose tupleset.getId computed.getId)
  | _ => throwErrorAt stx "invalid ZIL relation expression"

syntax (name := zilSchemaCmd) "zil_schema " ident " version " num : command
syntax (name := zilRelationSnapshotCmd) "zil_relation_snapshot " str : command
syntax (name := zilRelationCmd) "zil_relation " ident " := " zilRelationExpr : command
syntax (name := zilValidateSchemaCmd) "zil_validate_schema" : command
syntax (name := zilTupleCmd) "zil_tuple " str " # " ident " @ " str : command
syntax (name := zilRelationSetTupleCmd)
  "zil_tuple " str " # " ident " @ " str " # " ident : command

@[command_elab zilSchemaCmd]
meta def elabZilSchema : CommandElab := fun stx => do
  match stx with
  | `(zil_schema $profile:ident version $ver:num) =>
      modifyEnv fun env => relationExt.addEntry env (.schema profile.getId ver.getNat)
  | _ => throwUnsupportedSyntax

@[command_elab zilRelationSnapshotCmd]
meta def elabZilRelationSnapshot : CommandElab := fun stx => do
  match stx with
  | `(zil_relation_snapshot $revision:str) =>
      let token := revision.getString
      unless token.startsWith "sha256:" && token.length = 71 do
        throwErrorAt revision "relation snapshot must be `sha256:` followed by 64 hexadecimal characters"
      modifyEnv fun env =>
        let env := relationExt.addEntry env (.revision token)
        let state := relationExt.getState env
        relationExt.setState env { state with
          store := { state.store with
            revision := state.store.revision.withEnvironment env.mainModule } }
  | _ => throwUnsupportedSyntax

@[command_elab zilRelationCmd]
meta def elabZilRelation : CommandElab := fun stx => do
  match stx with
  | `(zil_relation $name:ident := $expression:zilRelationExpr) =>
      let state := relationExt.getState (← getEnv)
      if (state.schema.find? name.getId).isSome then
        throwErrorAt name "duplicate ZIL relation `{name.getId}`"
      let expression ← relationExprFromSyntax expression
      modifyEnv fun env => relationExt.addEntry env (.relation { name := name.getId, expression })
  | _ => throwUnsupportedSyntax

@[command_elab zilValidateSchemaCmd]
meta def elabZilValidateSchema : CommandElab := fun stx => do
  let state := relationExt.getState (← getEnv)
  match state.schema.validate with
  | .ok () =>
      modifyEnv fun env => relationExt.addEntry env .validated
      logInfo m!"ZIL schema validated: profile={state.schema.profile}, version={state.schema.version}, relations={state.schema.definitions.length}"
  | .error error => throwErrorAt stx "invalid ZIL relation schema: {repr error}"

meta def requireValidated (stx : Syntax) : CommandElabM RelationState := do
  let state := relationExt.getState (← getEnv)
  unless state.validated do
    throwErrorAt stx "ZIL relation schema is not validated; run `zil_validate_schema` after all relation declarations"
  pure state

meta def requireDefinedRelation (stx : Syntax) (state : RelationState) (relation : Name) :
    CommandElabM Unit := do
  unless (state.schema.find? relation).isSome do
    throwErrorAt stx "undefined ZIL relation `{relation}`"

@[command_elab zilTupleCmd]
meta def elabZilTuple : CommandElab := fun stx => do
  match stx with
  | `(zil_tuple $object:str # $relation:ident @ $subject:str) =>
      let state ← requireValidated stx
      requireDefinedRelation relation state relation.getId
      modifyEnv fun env => relationExt.addEntry env (.tuple {
        object := .mkSimple object.getString
        relation := relation.getId
        subject := .node (.mkSimple subject.getString)
      })
  | _ => throwUnsupportedSyntax

@[command_elab zilRelationSetTupleCmd]
meta def elabZilRelationSetTuple : CommandElab := fun stx => do
  match stx with
  | `(zil_tuple $object:str # $relation:ident @ $subjectObject:str # $subjectRelation:ident) =>
      let state ← requireValidated stx
      requireDefinedRelation relation state relation.getId
      requireDefinedRelation subjectRelation state subjectRelation.getId
      modifyEnv fun env => relationExt.addEntry env (.tuple {
        object := .mkSimple object.getString
        relation := relation.getId
        subject := .relationSet (.mkSimple subjectObject.getString) subjectRelation.getId
      })
  | _ => throwUnsupportedSyntax

syntax (name := zilCheckCmd) "#zil_check " str " # " ident " @ " str (" fuel " num)? : command
syntax (name := zilExpandCmd) "#zil_expand " str " # " ident " @ " str (" fuel " num)? : command
syntax (name := zilReadCmd) "#zil_read " str " # " ident : command

meta def queryParts (object : TSyntax `str) (relation : TSyntax `ident)
    (subject : TSyntax `str) : Name × Name × Name :=
  (.mkSimple object.getString, relation.getId, .mkSimple subject.getString)

@[command_elab zilCheckCmd]
meta def elabZilCheck : CommandElab := fun stx => do
  match stx with
  | `(#zil_check $object:str # $relation:ident @ $subject:str $[fuel $amount:num]?) =>
      let state ← requireValidated stx
      requireDefinedRelation relation state relation.getId
      let (objectName, relationName, subjectName) := queryParts object relation subject
      let limit := EvalLimits.depthOnly (amount.map (·.getNat) |>.getD 32)
      match check limit state.schema state.store objectName relationName subjectName with
      | .yes derivation => logInfo m!"ZIL check: yes, revision={repr state.store.revision}, derivation={repr derivation.tree}"
      | .no => logInfo m!"ZIL check: no, revision={repr state.store.revision}"
      | .unknown reason => logInfo m!"ZIL check: unknown, revision={repr state.store.revision}, reason={repr reason}"
  | _ => throwUnsupportedSyntax

@[command_elab zilExpandCmd]
meta def elabZilExpand : CommandElab := fun stx => do
  match stx with
  | `(#zil_expand $object:str # $relation:ident @ $subject:str $[fuel $amount:num]?) =>
      let state ← requireValidated stx
      requireDefinedRelation relation state relation.getId
      let (objectName, relationName, subjectName) := queryParts object relation subject
      let limit := EvalLimits.depthOnly (amount.map (·.getNat) |>.getD 32)
      let result := expand limit state.schema state.store objectName relationName subjectName
      logInfo m!"ZIL expand: revision={repr state.store.revision}, derivations={repr result.derivations}, unknown={repr result.unknown}"
  | _ => throwUnsupportedSyntax

@[command_elab zilReadCmd]
meta def elabZilRead : CommandElab := fun stx => do
  match stx with
  | `(#zil_read $object:str # $relation:ident) =>
      let state ← requireValidated stx
      requireDefinedRelation relation state relation.getId
      let rows := read state.store (.mkSimple object.getString) relation.getId
      logInfo m!"ZIL read: revision={repr state.store.revision}, tuples={repr rows}"
  | _ => throwUnsupportedSyntax

end Zil.Datalog
