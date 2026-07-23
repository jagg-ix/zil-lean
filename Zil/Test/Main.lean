import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Macro
import Zil.Test.Declarations
import Zil.Test.RevisionCausal

/-- Executable validation target for revisioned facts and causal order. -/
def main : IO Unit := do
  IO.println "zil-lean revision and causal core validation passed"
