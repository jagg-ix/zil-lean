import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Macro
import Zil.Test.MacroLibrary
import Zil.Test.Declarations
import Zil.Test.RevisionCausal
import Zil.Test.Conformance
import Zil.Test.Workflow
import Zil.Test.Formalization
import Zil.Test.Authorization
import Zil.Test.QueryGovernance
import Zil.Test.Provenance
import Zil.Test.Impact
import Zil.Test.ActionToken
import Zil.Test.TokenLifecycle
import Zil.Test.AgentContext

/-- Executable validation target for native ZIL agent context bundles. -/
def main : IO Unit := do
  IO.println "zil-lean native validation passed"
