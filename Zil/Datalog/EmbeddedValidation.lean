module

public meta import Zil.Datalog.Attach
public meta import Zil.Datalog.Claim

@[expose] public section

open Lean Elab Command

namespace Zil.Datalog

private meta partial def collectAxiomsAux (env : Environment) (pending : List Name)
    (seen axioms : NameSet) : NameSet :=
  match pending with
  | [] => axioms
  | declaration :: rest =>
      if seen.contains declaration then
        collectAxiomsAux env rest seen axioms
      else
        let seen := seen.insert declaration
        match env.find? declaration with
        | some (.axiomInfo _) => collectAxiomsAux env rest seen (axioms.insert declaration)
        | some info =>
            collectAxiomsAux env (info.getUsedConstantsAsSet.toList ++ rest) seen axioms
        | none => collectAxiomsAux env rest seen axioms

/-- The complete transitive axiom closure of a compiled Lean declaration. -/
meta def declarationAxioms (env : Environment) (declaration : Name) : Array Name :=
  collectAxiomsAux env [declaration] default default |>.toArray.qsort Name.quickLt

/-- Stable type identity used by ZIL drift baselines and native checks. -/
meta def declarationTypeFingerprint (info : ConstantInfo) : String :=
  s!"lean-hash:{hash info.type}"

declare_syntax_cat zilEmbeddedCheck
syntax "no_new_axioms" : zilEmbeddedCheck
syntax "no_sorry" : zilEmbeddedCheck
syntax "claim_linked" : zilEmbeddedCheck
syntax "requirement_linked" : zilEmbeddedCheck
syntax "type_fingerprint " str : zilEmbeddedCheck

syntax (name := zilValidateEmbeddedCmd)
  "#zil_validate_embedded " ident " where "
    zilEmbeddedCheck (", " zilEmbeddedCheck)* : command

@[command_elab zilValidateEmbeddedCmd]
meta def elabZilValidateEmbedded : CommandElab := fun stx => do
  match stx with
  | `(command| #zil_validate_embedded $target:ident where
      $first:zilEmbeddedCheck $[, $rest:zilEmbeddedCheck]*) =>
      let declaration ← resolveGlobalConstNoOverload target
      let env ← getEnv
      let some info := env.find? declaration
        | throwErrorAt target "unknown Lean declaration '{declaration}'"
      let checks := first :: rest.toList
      let axioms := declarationAxioms env declaration
      let fingerprint := declarationTypeFingerprint info
      for check in checks do
        match check with
        | `(zilEmbeddedCheck| no_new_axioms) =>
            unless axioms.isEmpty do
              throwErrorAt check
                "ZIL no_new_axioms failed for '{declaration}': {axioms.toList}"
        | `(zilEmbeddedCheck| no_sorry) =>
            if axioms.contains ``sorryAx then
              throwErrorAt check "ZIL no_sorry failed for '{declaration}': depends on sorryAx"
        | `(zilEmbeddedCheck| claim_linked) =>
            if zilClaimAttr.getParam? env declaration |>.isNone then
              throwErrorAt check "ZIL claim_linked failed for '{declaration}'"
        | `(zilEmbeddedCheck| requirement_linked) =>
            if zilRequiresAttr.getParam? env declaration |>.isNone then
              throwErrorAt check "ZIL requirement_linked failed for '{declaration}'"
        | `(zilEmbeddedCheck| type_fingerprint $expected:str) =>
            unless expected.getString = fingerprint do
              throwErrorAt expected
                "ZIL type fingerprint changed for '{declaration}': expected {expected.getString}, found {fingerprint}"
        | _ => throwErrorAt check "unknown embedded ZIL validation check"
      logInfoAt stx m!"validated embedded ZIL for {declaration} (type={fingerprint}, axioms={axioms.size})"
  | _ => throwUnsupportedSyntax

end Zil.Datalog
