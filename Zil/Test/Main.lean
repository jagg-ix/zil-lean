import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser

/-- Executable validation target for tuple, rule, and query source parsing. -/
def main : IO Unit := do
  IO.println "zil-lean source rules and queries validation passed"
