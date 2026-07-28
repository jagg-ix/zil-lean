module

public import Zil.Engine.Query
public import Zil.Engine.Provenance
public import Zil.Impact
public import Zil.ProofObligation
public import Zil.TheoremAudit
public import Zil.QueryGovernance

/-- A successful compilation proves that module-system consumers can import the
native engine, provenance, and governance surfaces together. -/
def moduleSurfaceProbe : Nat := 0
