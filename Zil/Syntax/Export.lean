import Lean
import Zil.Export.Logic

namespace Zil.Syntax

open Lean Elab Command

syntax (name := zilExportSouffle) "#zil_export_souffle" : command
syntax (name := zilExportProlog) "#zil_export_prolog" : command

elab_rules : command
  | `(#zil_export_souffle) =>
      logInfo (Zil.Export.exportEnvironment .souffle (← getEnv))
  | `(#zil_export_prolog) =>
      logInfo (Zil.Export.exportEnvironment .prolog (← getEnv))

end Zil.Syntax