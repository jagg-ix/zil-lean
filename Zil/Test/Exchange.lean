import Zil.Interop.Exchange

open Zil

private def exchangeRule : Rule :=
  { name := `exchangeRequirement
    variables := #[`declaration, `claim, `requirement]
    premises := #[
      .mk' (.variable `declaration) `zil.formalizes (.variable `claim),
      .mk' (.variable `declaration) `zil.requires (.variable `requirement)]
    conclusion := .mk' (.variable `claim) `zil.requiresClaim (.variable `requirement)
    trust := .graphDerived }

private def envelope : Zil.Interop.ExchangeEnvelope :=
  { knowledgeRevision := 17
    profileName := some "zil.profile.research"
    profileVersion := some "0.1"
    facts := #[.mk' (.ground `lean.Exchange.theorem) `zil.formalizes
      (.ground `claim.exchange)]
    rules := #[exchangeRule] }

#guard match Zil.Interop.decodeEnvelope (Zil.Interop.encodeEnvelope envelope) with
  | .ok decoded => Zil.Interop.semanticallyEqual envelope decoded
  | .error _ => false

#guard (Zil.Interop.decodeEnvelope "ZILX\t1\nrevision\tnot-a-number\nprofile\t-\t-").isError
#guard (Zil.Interop.decodeEnvelope "BAD\t1\nrevision\t0\nprofile\t-\t-").isError