import Zil.Test.Userset
import Zil.Test.TupleParser
import Zil.Test.QuotedTerm
import Zil.Test.Continuation
import Zil.Test.KeywordTerm
import Zil.Test.Attributes
import Zil.Test.ProgramParser
import Zil.Test.StratifiedNegation
import Zil.Test.Fixpoint
import Zil.Test.Macro
import Zil.Test.MacroLibrary
import Zil.Test.DatalogMacro
import Zil.Test.DatalogChecked
import Zil.Test.DatalogCertify
import Zil.Test.DatalogPerfect
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
import Zil.Test.ProofObligation
import Zil.Test.TheoremAudit
import Zil.Test.RecoveryAudit
import Zil.Test.Exchange
import Zil.Test.Horn
import Zil.Test.HornGrounding
import Zil.Test.Sha256
import Zil.Test.JsonOrdered
import Zil.Test.Ingest
import Zil.Test.EdnReader
import Zil.Test.ControlEvent

/-- Executable validation target for native safety and hybrid exchange contracts. -/
def main : IO Unit := do
  IO.println "zil-lean native validation passed"
