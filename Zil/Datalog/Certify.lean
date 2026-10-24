module

public import Zil.Datalog.Checked

@[expose] public section

/-!
# A certificate checker with a proof

After Tantow, Gerlach, Mennicke and Krötzsch, "Verifying Datalog Reasoning with Lean" (ITP 2025, LIPIcs 36). A reasoner says that a set
of facts is what a program entails. A **certificate** is that set, each fact with its reason: it is a fact of the program, or a rule
derived it from facts that come earlier in the list. `checkCertificate` checks two things, and `checkCertificate_sound` proves that
when it says yes the set is a stable model of the program (`IsStableModel`), and, for a program without negation, the least model:

* **soundness** (the paper's ordered proof graph, section 4.4): every fact has a reason that uses only facts before it, so there is no
  circular argument, and the negative literals of the rule are absent from the set;
* **closure** (the paper's model check, section 5): the facts of the program are in the set, and no rule derives a fact outside it.

Nothing is trusted but the matching functions `unify` and `instantiate`, which say what a rule means; the reasoner that produced the
certificate is not. The proof is in this file and in `Zil.Datalog.LeastModel`.

This is the checker for the Lean-embedded Datalog (`Zil.Datalog.Program`). `zilLib certify`, in the zil-lib repository, checks the
engine's own programs the same way, with a checker that is tested but not proved.
-/

namespace Zil.Datalog

/-- One fact of a certificate and its reason. -/
structure CertNode where
  atom : Atom
  /-- `none` for a fact of the program; otherwise the name of the rule and the numbers of the nodes that its positive literals
  matched, in the order of the literals. -/
  origin : Option (String × List Nat) := none
  deriving Repr, DecidableEq, Inhabited

abbrev Certificate := List CertNode

/-- Match the patterns against the atoms, one for each, in order. -/
def matchChain : List Pattern → List Atom → Substitution → Option Substitution
  | [], [], σ => some σ
  | p :: ps, a :: as, σ => (unify p a σ).bind (matchChain ps as)
  | _, _, _ => none

theorem matchChain_bodyMatches :
    ∀ (ps : List Pattern) (as : List Atom) (σ σ' : Substitution), matchChain ps as σ = some σ' →
      BodyMatches as ps σ σ' := by
  intro ps
  induction ps with
  | nil =>
      intro as σ σ' h
      cases as with
      | nil =>
          have : σ = σ' := Option.some.inj h
          subst this
          exact .nil
      | cons a as => simp [matchChain] at h
  | cons p ps ih =>
      intro as σ σ' h
      cases as with
      | nil => simp [matchChain] at h
      | cons a as =>
          simp only [matchChain] at h
          cases hu : unify p a σ with
          | none => simp [hu] at h
          | some σ1 =>
              simp only [hu, Option.bind_some] at h
              exact .cons (List.mem_cons_self ..) hu
                ((ih as σ1 σ' h).mono fun c hc => List.mem_cons_of_mem _ hc)

/-- The rule justifies `atom` from the premise atoms, with its negative literals read against `certified`. -/
def ruleJustifies (certified : List Atom) (rule : Rule) (premises : List Atom) (atom : Atom) : Bool :=
  match matchChain rule.positiveBody premises [] with
  | none => false
  | some σ =>
      rule.negativePatterns.all (fun p => excludesPattern certified p σ) && instantiate rule.head σ == some atom

theorem ruleJustifies_mem {certified : List Atom} {rule : Rule} {premises : List Atom} {atom : Atom}
    (h : ruleJustifies certified rule premises atom = true) : atom ∈ applyRuleUnder certified premises rule := by
  unfold ruleJustifies at h
  cases hm : matchChain rule.positiveBody premises [] with
  | none => simp [hm] at h
  | some σ =>
      simp only [hm, Bool.and_eq_true, List.all_eq_true, beq_iff_eq] at h
      obtain ⟨hneg, hinst⟩ := h
      rw [mem_applyRuleUnder]
      exact ⟨σ, matchChain_bodyMatches _ _ _ _ hm, fun p hp => excludesPattern_iff.mp (hneg p hp), hinst⟩

/-- The nodes before this one that the premises name, or `none` if a number is out of range. -/
def premiseAtoms (earlier : List Atom) (ids : List Nat) : Option (List Atom) :=
  ids.mapM fun i => earlier[i]?

theorem premiseAtoms_mem {earlier : List Atom} :
    ∀ {ids : List Nat} {as : List Atom}, premiseAtoms earlier ids = some as → ∀ a, a ∈ as → a ∈ earlier := by
  intro ids
  induction ids with
  | nil =>
      intro as h a ha
      have : as = [] := by simpa [premiseAtoms] using h.symm
      subst this
      simp at ha
  | cons i ids ih =>
      intro as h a ha
      unfold premiseAtoms at h
      simp only [List.mapM_cons] at h
      cases hi : earlier[i]? with
      | none => simp [hi] at h
      | some b =>
          cases hr : ids.mapM (fun i => earlier[i]?) with
          | none => simp [hi, hr] at h
          | some rest =>
              simp only [hi, hr] at h
              have has : as = b :: rest := (Option.some.inj h).symm
              subst has
              rcases List.mem_cons.mp ha with rfl | hmem
              · exact List.mem_of_getElem? hi
              · exact ih (by simpa [premiseAtoms] using hr) a hmem

/-- Is this node justified, given the nodes before it and the whole certified set? -/
def nodeOk (program : Program) (certified earlier : List Atom) (node : CertNode) : Bool :=
  match node.origin with
  | none => program.facts.contains node.atom
  | some (name, ids) =>
      match premiseAtoms earlier ids with
      | none => false
      | some premises => program.rules.any fun rule => rule.name == name && ruleJustifies certified rule premises node.atom

theorem nodeOk_derives {program : Program} {certified earlier : List Atom} {node : CertNode}
    (h : nodeOk program certified earlier node = true)
    (hearlier : ∀ a, a ∈ earlier → DerivesUnder program certified a) : DerivesUnder program certified node.atom := by
  unfold nodeOk at h
  cases ho : node.origin with
  | none =>
      simp only [ho, List.contains_eq_mem, decide_eq_true_eq] at h
      exact .fact h
  | some origin =>
      obtain ⟨name, ids⟩ := origin
      simp only [ho] at h
      cases hp : premiseAtoms earlier ids with
      | none => simp [hp] at h
      | some premises =>
          simp only [hp, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at h
          obtain ⟨rule, hrule, _, hj⟩ := h
          exact .rule rule premises hrule (fun c hc => hearlier c (premiseAtoms_mem hp c hc)) (ruleJustifies_mem hj)

/-- Every node is justified by the nodes before it; `earlier` holds the atoms of the nodes already passed. -/
def checkNodes (program : Program) (certified : List Atom) : List CertNode → List Atom → Bool
  | [], _ => true
  | node :: rest, earlier =>
      nodeOk program certified earlier node && checkNodes program certified rest (earlier ++ [node.atom])

theorem checkNodes_derives {program : Program} {certified : List Atom} :
    ∀ (nodes : List CertNode) (earlier : List Atom), checkNodes program certified nodes earlier = true →
      (∀ a, a ∈ earlier → DerivesUnder program certified a) →
      ∀ n, n ∈ nodes → DerivesUnder program certified n.atom := by
  intro nodes
  induction nodes with
  | nil => intro earlier _ _ n hn; simp at hn
  | cons node rest ih =>
      intro earlier h hearlier n hn
      simp only [checkNodes, Bool.and_eq_true] at h
      have hhead := nodeOk_derives h.1 hearlier
      rcases List.mem_cons.mp hn with rfl | hmem
      · exact hhead
      · apply ih (earlier ++ [node.atom]) h.2 _ n hmem
        intro a ha
        rcases List.mem_append.mp ha with ha | ha
        · exact hearlier a ha
        · rcases List.mem_singleton.mp ha with rfl
          exact hhead

/-- The certificate lists the facts of the program, and each fact is justified by the facts before it, and nothing more can be
derived. -/
def checkCertificate (program : Program) (cert : Certificate) : Bool :=
  let certified := cert.map (·.atom)
  checkNodes program certified cert [] &&
  program.facts.all certified.contains &&
  (program.rules.flatMap (applyRule certified)).all certified.contains

/-- **Soundness of the checker.** If it says yes, the facts of the certificate are a stable model of the program: they are closed under
the rules and contain the program's facts, and each has a finite derivation in which the negative literals are checked against the
set. -/
theorem checkCertificate_sound {program : Program} {cert : Certificate} (h : checkCertificate program cert = true) :
    IsStableModel program (cert.map (·.atom)) := by
  unfold checkCertificate at h
  simp only [Bool.and_eq_true] at h
  obtain ⟨⟨hnodes, hfacts⟩, hclosed⟩ := h
  refine ⟨⟨?_, ?_⟩, ?_⟩
  · intro a ha
    simpa using List.all_eq_true.mp hfacts a ha
  · intro rule hrule a ha
    have hmem : a ∈ program.rules.flatMap (applyRule (cert.map (·.atom))) :=
      List.mem_flatMap.mpr ⟨rule, hrule, ha⟩
    simpa using List.all_eq_true.mp hclosed a hmem
  · intro a ha
    obtain ⟨n, hn, rfl⟩ := List.mem_map.mp ha
    exact checkNodes_derives cert [] hnodes (by simp) n hn

/-- **For a program without negation, the facts of an accepted certificate are the least model**: a model, inside every model, and the
set of facts that have a derivation. -/
theorem checkCertificate_leastModel {program : Program} (hpos : program.IsPositive) {cert : Certificate}
    (h : checkCertificate program cert = true) :
    IsModel program (cert.map (·.atom)) ∧
      (∀ other, IsModel program other → ∀ a, a ∈ cert.map (·.atom) → a ∈ other) ∧
      ∀ a, a ∈ cert.map (·.atom) ↔ Derives program a := by
  have hstable := checkCertificate_sound h
  obtain ⟨hmodel, hsound⟩ := (isStableModel_iff_sound hpos).mp hstable
  obtain ⟨hleast, hiff⟩ := leastModel_of_sound_model hpos hmodel hsound
  exact ⟨hmodel, hleast, hiff⟩

/-! ## Producing a certificate (not trusted)

The checker accepts any certificate, so the code that makes one needs no proof: if it is wrong, the check says no. This one runs the
checked evaluation to learn the set of facts, then adds the facts round by round, each with the rule and the earlier nodes that
derive it. The negative literals are read against the set. -/

/-- Every way the positive patterns match `facts`, in order: the substitution and the atoms used. -/
def matchAll (facts : List Atom) : List Pattern → Substitution → List (Substitution × List Atom)
  | [], σ => [(σ, [])]
  | p :: ps, σ =>
      facts.flatMap fun a =>
        match unify p a σ with
        | none => []
        | some σ' => (matchAll facts ps σ').map fun (σ'', used) => (σ'', a :: used)

/-- The nodes a round adds to `nodes`: one for each new fact, with the first rule instance found for it. -/
def freshNodes (program : Program) (certified : List Atom) (nodes : List CertNode) : List CertNode :=
  let atoms := nodes.map (·.atom)
  let found := program.rules.flatMap fun rule =>
    (matchAll atoms rule.positiveBody []).filterMap fun (σ, used) =>
      if rule.negativePatterns.all (excludesPattern certified · σ) then
        match instantiate rule.head σ with
        | some head =>
            if atoms.contains head then none
            else some { atom := head, origin := some (rule.name, used.map (atoms.idxOf ·)) }
        | none => none
      else none
  found.foldl (fun kept node => if kept.any (·.atom == node.atom) then kept else kept ++ [node]) []

/-- Add rounds of fresh nodes until a round adds none, or `none` when `fuel` rounds are not enough. -/
def buildNodes (program : Program) (certified : List Atom) : Nat → List CertNode → Option (List CertNode)
  | 0, _ => none
  | fuel + 1, nodes =>
      let fresh := freshNodes program certified nodes
      if fresh.isEmpty then some nodes else buildNodes program certified fuel (nodes ++ fresh)

/-- A certificate for the facts that follow from the program, or the reason there is none. -/
def certifyProgram (program : Program) (fuel : Nat := defaultFuel) : Except String Certificate := do
  let certified ← deriveProgramChecked program fuel
  let facts : Certificate := program.facts.eraseDups.map fun atom => { atom }
  match buildNodes program certified fuel facts with
  | some nodes => .ok nodes
  | none => .error s!"no certificate within {fuel} rounds"

end Zil.Datalog
