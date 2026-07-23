import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Macro
import Zil.Test.Declarations

/-- Executable validation target for macros and typed declarations. -/
def main : IO Unit := do
  IO.println "zil-lean typed declaration lowering validation passed"
