import Zil.Native

/-!
# Model substrate tests

Contract: `spec/model-substrate-v0.1.md`. Checklist: `spec/model-substrate-targets-v0.md`.

Every test reads the shipped library files from `libsets/model-substrate/`, so it exercises the text
that is released. Each `run_cmd` block is one named test; a failure reports the test name.
-/

open Lean Elab Command
open Zil

namespace Zil.Test.ModelSubstrate

private def libraryDir : String := "libsets/model-substrate"

/-- Library sources in filename order, as the native CLI loads a `--lib` directory. -/
private def loadDirectory (directory : String) :
    IO (Array Zil.Parser.MacroProgram.LibrarySource) := do
  let entries ← System.FilePath.readDir (System.FilePath.mk directory)
  let files := (entries.filter fun entry => entry.fileName.endsWith ".zc")
    |>.qsort (fun left right => left.fileName < right.fileName)
  let mut libraries := #[]
  for entry in files do
    libraries := libraries.push {
      label := "lib/" ++ entry.fileName
      text := ← IO.FS.readFile entry.path
    }
  pure libraries

private def loadLibrary : IO (Array Zil.Parser.MacroProgram.LibrarySource) :=
  loadDirectory libraryDir

private def fixtureLibrary (path label : String) :
    IO Zil.Parser.MacroProgram.LibrarySource := do
  pure { label := label, text := ← IO.FS.readFile path }

/-- Statements of the expanded model, without blank lines or the MODULE line. -/
private def statements
    (libraries : Array Zil.Parser.MacroProgram.LibrarySource) (model : String) :
    Except String (List String) :=
  match Zil.Parser.MacroProgram.expandTextWithLibraries libraries "model.zc" model with
  | .error error => .error error.render
  | .ok text =>
      .ok <| (text.splitOn "\n").filterMap fun line =>
        let trimmed := line.trimAscii.toString
        if trimmed.isEmpty || trimmed.startsWith "MODULE " then none else some trimmed

/-- Sorted rows of one named query after the closure of the whole model. -/
private def rows
    (libraries : Array Zil.Parser.MacroProgram.LibrarySource) (model queryName : String) :
    Except String (List String) := do
  let program ← (Zil.Parser.DeclarationProgram.parseTextWithLibraries
    libraries "model.zc" model).mapError (·.render)
  let shelved ← Zil.Engine.closureChecked program.facts program.allRules
  match program.queries.find? (fun query => query.name.toString == queryName) with
  | none => throw s!"no query named {queryName}"
  | some query =>
      let rendered := (Zil.Engine.solve shelved query).toList.map fun binding =>
        String.intercalate "," <| query.select.toList.map fun selected =>
          match binding.lookup selected with
          | some (.node node) => node.name.toString
          | some (.var name) => "?" ++ name.toString
          | none => "_"
      pure (rendered.toArray.qsort (· < ·)).toList

private def expectStatements (test : String)
    (actual : Except String (List String)) (expected : List String) : CommandElabM Unit :=
  match actual with
  | .error message => throwError "{test}: expansion failed: {message}"
  | .ok got =>
      unless got == expected do
        throwError "{test}: expected {expected}, got {got}"

private def expectRows (test : String)
    (actual : Except String (List String)) (expected : List String) : CommandElabM Unit :=
  match actual with
  | .error message => throwError "{test}: {message}"
  | .ok got =>
      unless got == expected do
        throwError "{test}: expected rows {expected}, got {got}"

private def expectError (test needle : String)
    (actual : Except String (List String)) : CommandElabM Unit :=
  match actual with
  | .ok got => throwError "{test}: expected an error mentioning '{needle}', got {got}"
  | .error message =>
      unless (message.splitOn needle).length > 1 do
        throwError "{test}: error '{message}' does not mention '{needle}'"

private def header : String := "MODULE substrate.test.\n"

/-! ## T1 structure core -/

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_entity"
    (statements libs (header ++ "USE MODEL_ENTITY(book).\n"))
    ["book#model_kind@entity:model_entity."]

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_attr_op"
    (statements libs (header ++
      "USE MODEL_ATTR(book_title, book, value:string).\n" ++
      "USE MODEL_OP(book_lend, book).\n"))
    [ "book_title#model_kind@entity:model_attr."
    , "book#model_has_attr@book_title."
    , "book_title#model_type@value:string."
    , "book_lend#model_kind@entity:model_op."
    , "book#model_has_op@book_lend." ]

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_assoc"
    (statements libs (header ++ "USE MODEL_ASSOC(a, book, loan, one, many).\n"))
    [ "a#model_kind@entity:model_assoc."
    , "a#model_source@book."
    , "a#model_target@loan."
    , "a#model_source_mult@value:one."
    , "a#model_target_mult@value:many." ]

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_generalize"
    (statements libs (header ++ "USE MODEL_GENERALIZE(novel, book).\n"))
    ["novel#model_is_a@book."]

run_cmd do
  let libs ← loadLibrary
  expectRows "query_assoc_ends"
    (rows libs (header ++
      "USE MODEL_ASSOC(a, book, loan, one, many).\n" ++
      "USE MODEL_RULES(t).\n" ++
      "QUERY ends:\n" ++
      "FIND ?e WHERE a#model_end@?e.\n") "ends")
    ["book", "loan"]

run_cmd do
  let libs ← loadLibrary
  expectRows "query_is_a_star"
    (rows libs (header ++
      "USE MODEL_GENERALIZE(a, b).\n" ++
      "USE MODEL_GENERALIZE(b, c).\n" ++
      "USE MODEL_RULES(t).\n" ++
      "QUERY ancestors:\n" ++
      "FIND ?x WHERE a#model_is_a_star@?x.\n") "ancestors")
    ["b", "c"]

run_cmd do
  let libs ← loadLibrary
  expectError "unknown_macro_fails" "unknown macro MODEL_NOPE"
    (statements libs (header ++ "USE MODEL_NOPE(x).\n"))

run_cmd do
  let libs ← loadLibrary
  expectError "arity_fails" "macro MODEL_ENTITY expects 1 arguments, got 2"
    (statements libs (header ++ "USE MODEL_ENTITY(a, b).\n"))

/-! ## T2 structure behaviour -/

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_state_trans"
    (statements libs (header ++
      "USE MODEL_STATE(shelved, book).\n" ++
      "USE MODEL_STATE(lent, book).\n" ++
      "USE MODEL_INITIAL(shelved).\n" ++
      "USE MODEL_TRANS(t1, shelved, lend, lent).\n"))
    [ "shelved#model_kind@entity:model_state."
    , "book#model_has_state@shelved."
    , "lent#model_kind@entity:model_state."
    , "book#model_has_state@lent."
    , "shelved#model_initial@value:true."
    , "t1#model_kind@entity:model_transition."
    , "t1#model_from@shelved."
    , "t1#model_event@value:lend."
    , "t1#model_to@lent." ]

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_msg"
    (statements libs (header ++
      "USE MODEL_MSG(m1, client, server, server_open).\n" ++
      "USE MODEL_MSG(m2, server, client, client_ack).\n" ++
      "USE MODEL_MSG_AFTER(m2, m1).\n"))
    [ "m1#model_kind@entity:model_message."
    , "m1#model_from@client."
    , "m1#model_to@server."
    , "m1#model_calls@server_open."
    , "m2#model_kind@entity:model_message."
    , "m2#model_from@server."
    , "m2#model_to@client."
    , "m2#model_calls@client_ack."
    , "m2#model_after@m1." ]

private def messageModel : String := header ++
  "USE MODEL_MSG(m1, client, server, server_open).\n" ++
  "USE MODEL_MSG(m2, server, client, client_ack).\n" ++
  "USE MODEL_TRANS(t1, shelved, lend, lent).\n" ++
  "USE MODEL_RULES(t).\n" ++
  "QUERY client_ops:\n" ++
  "FIND ?op WHERE client#model_can_call@?op.\n" ++
  "QUERY server_ops:\n" ++
  "FIND ?op WHERE server#model_can_call@?op.\n" ++
  "QUERY shelved_ops:\n" ++
  "FIND ?op WHERE shelved#model_can_call@?op.\n"

run_cmd do
  let libs ← loadLibrary
  expectRows "query_can_call client" (rows libs messageModel "client_ops") ["server_open"]
  expectRows "query_can_call server" (rows libs messageModel "server_ops") ["client_ack"]
  -- a transition has a from-state but calls nothing, so a state reaches no operation
  expectRows "query_can_call state" (rows libs messageModel "shelved_ops") []

/-! ## T3 intent surface -/

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_actor_uc"
    (statements libs (header ++
      "USE MODEL_ACTOR(reader).\n" ++
      "USE MODEL_USECASE(borrow_book).\n" ++
      "USE MODEL_PARTICIPATES(reader, borrow_book).\n"))
    [ "reader#model_kind@entity:model_actor."
    , "borrow_book#model_kind@entity:model_usecase."
    , "reader#model_participates@borrow_book." ]

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_include_extend"
    (statements libs (header ++
      "USE MODEL_INCLUDE(borrow_book, check_card).\n" ++
      "USE MODEL_EXTEND(borrow_with_hold, borrow_book).\n"))
    [ "borrow_book#model_includes@check_card."
    , "borrow_with_hold#model_extends@borrow_book." ]

/-! ## T4 scenario core -/

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_feature_case"
    (statements libs (header ++
      "USE SCENARIO_FEATURE(f_loan, borrow_book).\n" ++
      "USE SCENARIO_CASE(s_happy, f_loan).\n"))
    [ "f_loan#scenario_kind@entity:scenario_feature."
    , "f_loan#scenario_title@value:borrow_book."
    , "s_happy#scenario_kind@entity:scenario_case."
    , "f_loan#scenario_has_case@s_happy." ]

run_cmd do
  let libs ← loadLibrary
  expectStatements "expand_gwt_order"
    (statements libs (header ++
      "USE SCENARIO_GIVEN(g1, s_happy, 1, book_exists).\n" ++
      "USE SCENARIO_WHEN(w1, s_happy, 2, reader_asks_to_borrow).\n" ++
      "USE SCENARIO_THEN(t1, s_happy, 3, loan_recorded).\n"))
    [ "g1#scenario_kind@entity:scenario_step."
    , "g1#scenario_keyword@value:given."
    , "g1#scenario_ordinal@value:1."
    , "g1#scenario_key@value:book_exists."
    , "s_happy#scenario_has_step@g1."
    , "w1#scenario_kind@entity:scenario_step."
    , "w1#scenario_keyword@value:when."
    , "w1#scenario_ordinal@value:2."
    , "w1#scenario_key@value:reader_asks_to_borrow."
    , "s_happy#scenario_has_step@w1."
    , "t1#scenario_kind@entity:scenario_step."
    , "t1#scenario_keyword@value:then."
    , "t1#scenario_ordinal@value:3."
    , "t1#scenario_key@value:loan_recorded."
    , "s_happy#scenario_has_step@t1." ]

private def stepsModel : String := header ++
  "USE SCENARIO_GIVEN(g1, s_happy, 1, book_exists).\n" ++
  "USE SCENARIO_WHEN(w1, s_happy, 2, reader_asks_to_borrow).\n" ++
  "USE SCENARIO_THEN(t1, s_happy, 3, loan_recorded).\n" ++
  "USE SCENARIO_GIVEN(g2, s_other, 1, book_missing).\n" ++
  "QUERY happy_steps:\n" ++
  "FIND ?st WHERE s_happy#scenario_has_step@?st.\n" ++
  "QUERY happy_order:\n" ++
  "FIND ?st ?n WHERE s_happy#scenario_has_step@?st AND ?st#scenario_ordinal@?n.\n" ++
  "QUERY then_steps:\n" ++
  "FIND ?st WHERE ?st#scenario_keyword@value:then.\n"

run_cmd do
  let libs ← loadLibrary
  expectRows "query_steps_for_scenario" (rows libs stepsModel "happy_steps") ["g1", "t1", "w1"]
  expectRows "query_step_ordinals" (rows libs stepsModel "happy_order")
    ["g1,value.n1", "t1,value.n3", "w1,value.n2"]
  expectRows "query_then_steps" (rows libs stepsModel "then_steps") ["t1"]

run_cmd do
  let libs ← loadLibrary
  expectStatements "tag_facts"
    (statements libs (header ++
      "USE SCENARIO_TAG(f_loan, area_lending).\n" ++
      "USE SCENARIO_TAG(s_happy, REQ-01).\n" ++
      "USE SCENARIO_TAG(borrow_book, release_one).\n"))
    [ "f_loan#scenario_tag@tag:area_lending."
    , "s_happy#scenario_tag@tag:REQ-01."
    , "borrow_book#scenario_tag@tag:release_one." ]

/-! ## T5 coverage bridges -/

run_cmd do
  let libs ← loadLibrary
  expectStatements "covered_by"
    (statements libs (header ++ "USE MODEL_COVERED_BY(borrow_book, s_happy).\n"))
    ["borrow_book#model_covered_by@s_happy."]
  expectStatements "step_realizes"
    (statements libs (header ++ "USE SCENARIO_REALIZES(t1, book_lend).\n"))
    ["t1#scenario_realizes@book_lend."]

private def coherenceBody : String :=
  "USE MODEL_USECASE(uc_borrow).\n" ++
  "USE MODEL_USECASE(uc_leave).\n" ++
  "USE SCENARIO_FEATURE(f, feature_title).\n" ++
  "USE SCENARIO_CASE(s_borrow, f).\n" ++
  "USE SCENARIO_CASE(s_real, f).\n" ++
  "USE SCENARIO_CASE(s_orphan, f).\n" ++
  "USE MODEL_COVERED_BY(uc_borrow, s_borrow).\n" ++
  "USE SCENARIO_THEN(t_borrow, s_borrow, 1, borrow_ok).\n" ++
  "USE SCENARIO_THEN(t_real, s_real, 1, real_ok).\n" ++
  "USE SCENARIO_REALIZES(t_real, op_x).\n" ++
  "USE SCENARIO_WHEN(w_orphan, s_orphan, 1, orphan_acts).\n"

run_cmd do
  let libs ← loadLibrary
  let model := header ++ coherenceBody ++ "USE MODEL_COHERENCE(c).\n"
  expectRows "coherence_uncovered" (rows libs model "c_uncovered_usecases") ["uc_leave"]
  -- s_borrow is linked by its use case, s_real by a realizing step, s_orphan by nothing
  expectRows "coherence_orphan" (rows libs model "c_orphan_scenarios") ["s_orphan"]
  -- t_borrow realizes nothing; t_real does
  expectRows "coherence_unrealized_then" (rows libs model "c_unrealized_then_steps") ["t_borrow"]

run_cmd do
  let libs ← loadLibrary
  let model := header ++ coherenceBody ++ "USE MODEL_COHERENCE(a).\nUSE MODEL_COHERENCE(b).\n"
  expectRows "coherence_two_instances a" (rows libs model "a_uncovered_usecases") ["uc_leave"]
  expectRows "coherence_two_instances b" (rows libs model "b_orphan_scenarios") ["s_orphan"]

run_cmd do
  let libs ← loadLibrary
  -- with nothing stated the violation queries are empty, not errors
  let model := header ++ "USE MODEL_COHERENCE(c).\n"
  expectRows "coherence_empty uncovered" (rows libs model "c_uncovered_usecases") []
  expectRows "coherence_empty orphan" (rows libs model "c_orphan_scenarios") []
  expectRows "coherence_empty unrealized" (rows libs model "c_unrealized_then_steps") []

/-! ## T6 composition -/

private def demoLibraryPath : String :=
  "test/fixtures/model-substrate/t6_compose/lib/50-demo-bridge.zc"

run_cmd do
  let libs ← loadLibrary
  let labels := libs.toList.map (·.label)
  unless labels == [ "lib/00-model-structure.zc", "lib/05-model-intent.zc", "lib/10-scenario.zc"
                   , "lib/20-model-bridges.zc", "lib/30-model-coherence.zc" ] do
    throwError "lib_order: unexpected library order {labels}"
  expectStatements "lib_order model"
    (statements libs (header ++
      "USE MODEL_ENTITY(book).\nUSE MODEL_ACTOR(reader).\nUSE SCENARIO_FEATURE(f, t).\n"))
    [ "book#model_kind@entity:model_entity."
    , "reader#model_kind@entity:model_actor."
    , "f#scenario_kind@entity:scenario_feature."
    , "f#scenario_title@value:t." ]

run_cmd do
  let libs ← loadLibrary
  let demo ← fixtureLibrary demoLibraryPath "lib/50-demo-bridge.zc"
  let all := libs.push demo
  expectStatements "domain_emits_substrate"
    (statements all (header ++ "USE DEMO_COMPONENT(cpu0, initiator).\n"))
    [ "demo:component:cpu0#demo_role@value:initiator."
    , "demo:component:cpu0#model_kind@entity:model_entity."
    , "demo:state:cpu0_idle#model_kind@entity:model_state."
    , "demo:component:cpu0#model_has_state@demo:state:cpu0_idle." ]
  -- the domain's own facts and the substrate's facts describe one subject
  expectRows "domain_ids_unify"
    (rows all (header ++
      "USE DEMO_COMPONENT(cpu0, initiator).\n" ++
      "QUERY shared:\n" ++
      "FIND ?c WHERE ?c#demo_role@value:initiator AND ?c#model_kind@entity:model_entity.\n")
      "shared")
    ["demo.component.cpu0"]

run_cmd do
  let libs ← loadLibrary
  let demo ← fixtureLibrary demoLibraryPath "lib/50-demo-bridge.zc"
  -- DEMO_STORY -> SCENARIO_GIVEN -> SCENARIO_STEP: three levels of EMIT USE
  expectStatements "nested_emit_use"
    (statements (libs.push demo) (header ++ "USE DEMO_STORY(s1, scen, key_a).\n"))
    [ "demo:step:s1#scenario_kind@entity:scenario_step."
    , "demo:step:s1#scenario_keyword@value:given."
    , "demo:step:s1#scenario_ordinal@value:1."
    , "demo:step:s1#scenario_key@value:key_a."
    , "scen#scenario_has_step@demo:step:s1." ]
  let loop : Zil.Parser.MacroProgram.LibrarySource := {
    label := "lib/60-loop.zc"
    text := "MODULE demo.loop.\nMACRO DEMO_LOOP(x):\nEMIT USE MODEL_ENTITY({{x}}).\n" ++
      "EMIT USE DEMO_LOOP({{x}}).\nENDMACRO.\n" }
  expectError "cyclic_domain_stub" "recursive macro cycle at DEMO_LOOP"
    (statements (libs.push loop) (header ++ "USE DEMO_LOOP(a).\n"))

run_cmd do
  let libs ← loadLibrary
  let composed := Zil.Parser.MacroProgram.composeLibraries libs "model.zc"
    (header ++ "USE MODEL_ENTITY(book).\n")
  let moduleLines := (composed.splitOn "\n").filter fun line =>
    line.trimAscii.toString.startsWith "MODULE "
  unless moduleLines == ["MODULE substrate.test."] do
    throwError "module_header_dropped: composed unit has {moduleLines}"

/-! ## T7 compatibility -/

run_cmd do
  -- no_lib_noop: a model with no library expands as it always did
  let model := "MODULE legacy.noop.\n" ++
    "MACRO pair(left, right):\nEMIT {{left}}#related@{{right}}.\nENDMACRO.\n" ++
    "USE pair(doc:a, doc:b).\n"
  expectStatements "no_lib_noop" (statements #[] model) ["doc:a#related@doc:b."]
  match Zil.Parser.MacroProgram.expandText model,
      Zil.Parser.MacroProgram.expandTextWithLibraries #[] "model.zc" model with
  | .ok plain, .ok composed =>
      unless plain == composed do
        throwError "no_lib_noop: an empty library list changed the expansion"
  | _, _ => throwError "no_lib_noop: expansion failed"

run_cmd do
  -- name_no_shadow: a TLM-only snippet expands byte for byte the same with the substrate loaded
  let libs ← loadLibrary
  let tlm ← fixtureLibrary "lib/tlm-macros.zc" "lib/tlm-macros.zc"
  let snippet ← IO.FS.readFile "test/fixtures/model-substrate/t7_tlm_only.zc"
  match Zil.Parser.MacroProgram.expandTextWithLibraries #[tlm] "model.zc" snippet,
      Zil.Parser.MacroProgram.expandTextWithLibraries (libs.push tlm) "model.zc" snippet with
  | .ok baseline, .ok loaded =>
      unless (baseline.splitOn "tlm:component:cpu0").length > 1 do
        throwError "name_no_shadow: the TLM snippet expanded to nothing useful"
      unless baseline == loaded do
        throwError "name_no_shadow: loading the substrate changed a TLM-only expansion"
  | .error error, _ => throwError "name_no_shadow: baseline failed: {error.render}"
  | _, .error error => throwError "name_no_shadow: with substrate failed: {error.render}"

private def libraryDirectories : IO (List String) := do
  let mut directories := ["lib"]
  for entry in ← System.FilePath.readDir "libsets" do
    if ← entry.path.isDir then
      directories := directories ++ [entry.path.toString]
  pure directories

run_cmd do
  -- no_collision: the substrate composes with every existing library directory that composes alone
  let libs ← loadLibrary
  let mut checked := 0
  for directory in ← libraryDirectories do
    unless directory == libraryDir do
      let others ← loadDirectory directory
      match Zil.Parser.MacroProgram.expandTextWithLibraries others "model.zc" header with
      | .error _ => pure ()
      | .ok _ =>
          checked := checked + 1
          match Zil.Parser.MacroProgram.expandTextWithLibraries (others ++ libs) "model.zc" header with
          | .ok _ => pure ()
          | .error error =>
              throwError "no_collision: {directory} no longer composes with the substrate: {error.render}"
  unless checked >= 10 do
    throwError "no_collision: only {checked} existing library directories were checked"

end Zil.Test.ModelSubstrate
