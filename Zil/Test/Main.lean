import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Macro

/-- Executable validation target for the native macro-enabled source language. -/
def main : IO Unit := do
  IO.println "zil-lean native macro frontend validation passed"
