import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation

/-- Executable validation target for the native stratified source language. -/
def main : IO Unit := do
  IO.println "zil-lean stratified negation validation passed"
