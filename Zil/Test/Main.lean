import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Macro
import Zil.Test.Declarations
import Zil.Test.RevisionCausal
import Zil.Test.Conformance
import Zil.Test.Workflow
import Zil.Test.Formalization

/-- Executable validation target for native ZIL, workflow, and formalization scheduling. -/
def main : IO Unit := do
  IO.println "zil-lean native validation passed"
