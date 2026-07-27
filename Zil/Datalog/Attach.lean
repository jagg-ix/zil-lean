module

public import Zil.Datalog.Environment
public meta import Lean.Elab.Command

@[expose] public section

open Lean Elab Command

namespace Zil.Datalog

/-- Source coordinates of a native, elaboration-validated ZIL attachment. -/
meta structure AttachmentSource where
  file : String
  startLine : Nat
  startColumn : Nat
  endLine : Nat
  endColumn : Nat
  deriving Repr, Inhabited

/-- A host-validated relation attached to an existing Lean declaration. `atom`
is also inserted into the canonical ZIL program environment. -/
meta structure DeclarationAttachment where
  declaration : Name
  module : Name
  declarationKind : String
  atom : Atom
  source : AttachmentSource
  trust : String := "elaboration_validated"
  deriving Repr, Inhabited

meta structure AttachmentState where
  entries : List DeclarationAttachment := []
  deriving Repr, Inhabited

meta def AttachmentState.add (state : AttachmentState)
    (entry : DeclarationAttachment) : AttachmentState :=
  { entries := state.entries ++ [entry] }

meta initialize attachmentExt :
    SimplePersistentEnvExtension DeclarationAttachment AttachmentState ←
  registerSimplePersistentEnvExtension {
    name := `Zil.Datalog.attachmentExt
    addEntryFn := AttachmentState.add
    addImportedFn := fun modules =>
      modules.foldl (fun state entries => entries.foldl AttachmentState.add state) {}
  }

/-- All persistent ZIL relations attached to `declaration`, in source order. -/
meta def attachmentsFor (env : Environment) (declaration : Name) :
    List DeclarationAttachment :=
  (attachmentExt.getState env).entries.filter (·.declaration == declaration)

/-- All persistent ZIL declaration attachments visible in an environment. -/
meta def declarationAttachments (env : Environment) : Array DeclarationAttachment :=
  (attachmentExt.getState env).entries.toArray

private meta def kindOf : ConstantInfo → String
  | .axiomInfo _ => "axiom"
  | .defnInfo _ => "definition"
  | .thmInfo _ => "theorem"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _ => "quotient"
  | .inductInfo _ => "inductive"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"

declare_syntax_cat zilAttachment
syntax ident " @ " zilTerm : zilAttachment
syntax (name := zilAttachCmd)
  "zil" " attach " ident " where " zilAttachment (", " zilAttachment)* : command

private meta def attachmentFromSyntax (self : Value) (stx : Syntax) :
    CommandElabM Atom :=
  match stx with
  | `(zilAttachment| $relation:ident @ $subject:zilTerm) => do
      match ← termFromSyntax subject with
      | .value value => pure {
          object := self
          relation := relation.getId.toString
          subject := value
        }
      | .variable _ =>
          throwErrorAt subject "zil attach subjects must be ground values"
  | _ => throwErrorAt stx "invalid ZIL declaration attachment"

@[command_elab zilAttachCmd]
meta def elabZilAttach : CommandElab := fun stx => do
  match stx with
  | `(command| zil attach $target:ident where $first:zilAttachment
      $[, $rest:zilAttachment]*) =>
      let declaration ← resolveGlobalConstNoOverload target
      let env ← getEnv
      let some info := env.find? declaration
        | throwErrorAt target "unknown Lean declaration '{declaration}'"
      let fileMap ← getFileMap
      let file ← getFileName
      let startPos := fileMap.toPosition (stx.getPos?.getD 0)
      let endPos := fileMap.toPosition (stx.getTailPos?.getD (stx.getPos?.getD 0))
      let source : AttachmentSource := {
        file
        startLine := startPos.line
        startColumn := startPos.column
        endLine := endPos.line
        endColumn := endPos.column
      }
      let self := Value.symbol s!"lean:{declaration}"
      let mut atoms := [← attachmentFromSyntax self first]
      for entry in rest do
        atoms := atoms ++ [← attachmentFromSyntax self entry]
      let moduleName := env.mainModule
      let declarationKind := kindOf info
      modifyEnv fun current => atoms.foldl (fun next atom =>
        let next := programExt.addEntry next (.fact atom)
        attachmentExt.addEntry next {
          declaration
          module := moduleName
          declarationKind
          atom
          source
        }) current
  | _ => throwUnsupportedSyntax

end Zil.Datalog

namespace Zil

export Datalog (AttachmentSource DeclarationAttachment attachmentsFor declarationAttachments)

end Zil
