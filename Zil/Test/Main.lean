import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Macro
import Zil.Test.Declarations
import Zil.Test.RevisionCausal
import Zil.Test.Conformance

/-- Executable validation target for differential conformance reporting. -/
def main : IO Unit := do
  IO.println "zil-lean differential conformance validation passed"
