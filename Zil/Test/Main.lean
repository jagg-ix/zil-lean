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
import Zil.Test.AgentContext
import Zil.Test.ProofObligation
import Zil.Test.TheoremAudit
import Zil.Test.ActionToken
import Zil.Test.TokenLifecycle
import Zil.Test.RecoveryAudit

/-- Executable validation target for native mutation lifecycle contracts. -/
def main : IO Unit := do
  IO.println "zil-lean native validation passed"
