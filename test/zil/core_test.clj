(ns zil.core-test
  (:require [clojure.test :refer [deftest is run-tests testing]]
            [datascript.core :as d]
            [zil.core :as core]
            [zil.runtime.datascript :as zr]))

(deftest query-exec-smoke-test
  (let [program "MODULE demo.
app:a#mirrored_by@app:b.
QUERY mirrors:
FIND ?x WHERE ?x#mirrored_by@?y.
"
        out (core/execute-program program)]
    (is (= "demo" (:module out)))
    (is (= [["app:a"]]
           (get-in out [:queries "mirrors" :rows])))))

(deftest query-plan-adaptive-ordering-test
  (let [program "MODULE qp.demo.
QUERY_PACK qp_main [queries=[q1]].
DSL_PROFILE qp_profile [query_pack=qp_main, planner_hint=high_selectivity_first].
app:a#r_big@app:b.
app:c#r_big@app:d.
node:fixed#r_small@value:true.
QUERY q1:
FIND ?x WHERE ?x#r_big@?y AND node:fixed#r_small@?x.
"
        plan (core/query-plan-program program)
        q1 (->> (:queries plan)
                (filter #(= "q1" (:name %)))
                first)]
    (is (= :high_selectivity_first (:planner_hint plan)))
    (is (= [:r_small :r_big] (:planned_relations q1)))))

(deftest query-ci-dsl-profile-selection-test
  (let [program "MODULE query.ci.demo.
QUERY_PACK ops_pack [queries=[q_ops], must_return=[q_ops]].
QUERY_PACK infra_pack [queries=[q_infra]].
DSL_PROFILE ops [query_pack=ops_pack].
DSL_PROFILE infra [query_pack=infra_pack].
svc:api#kind@entity:service.
svc:db#kind@entity:service.
QUERY q_ops:
FIND ?x WHERE ?x#kind@entity:service.
QUERY q_infra:
FIND ?x WHERE ?x#kind@entity:host.
"
        report (core/query-ci-program program {:profile "ops"})]
    (is (:ok report))
    (is (= ["ops"] (:selected_dsl_profiles report)))
    (is (= ["ops_pack"] (:selected_query_packs report)))
    (is (= ["q_ops"] (sort (:selected_queries report))))
    (is (= 2 (get-in report [:checks :must_return 0 :row_count])))
    (is (= #{"q_ops"} (set (keys (:queries report)))))))

(deftest query-ci-must-return-failure-test
  (let [program "MODULE query.ci.fail.demo.
QUERY_PACK ops_pack [queries=[q_empty], must_return=[q_empty]].
DSL_PROFILE ops [query_pack=ops_pack].
svc:api#kind@entity:service.
QUERY q_empty:
FIND ?x WHERE ?x#kind@entity:host.
"
        report (core/query-ci-program program)]
    (is (false? (:ok report)))
    (is (= ["q_empty"] (get-in report [:checks :failed_must_return])))
    (is (= 0 (get-in report [:checks :must_return 0 :row_count])))))

(deftest rule-negation-derivation-test
  (testing "Negated literal derives fact when negated atom is absent"
    (let [program "MODULE demo.
app:a#depends_on@service:db.
RULE degrade:
IF app:a#depends_on@service:db AND NOT service:db#available@value:true
THEN app:a#status@value:degraded.
QUERY status:
FIND ?s WHERE app:a#status@?s.
"
          out (core/execute-program program)]
      (is (= [["value:degraded"]]
             (get-in out [:queries "status" :rows])))))
  (testing "Negated literal blocks derivation when atom is present"
    (let [program "MODULE demo.
app:a#depends_on@service:db.
service:db#available@value:true.
RULE degrade:
IF app:a#depends_on@service:db AND NOT service:db#available@value:true
THEN app:a#status@value:degraded.
QUERY status:
FIND ?s WHERE app:a#status@?s.
"
          out (core/execute-program program)]
      (is (= []
             (get-in out [:queries "status" :rows]))))))

(deftest stratification-detects-negative-cycle-test
  (let [program "MODULE demo.
RULE bad:
IF NOT x#a@y
THEN x#a@y.
"]
    (is (thrown? clojure.lang.ExceptionInfo
                 (core/compile-program program)))))

(deftest refinement-relation-stdlib-parse-test
  (let [program "MODULE vstack.demo.
REFINES core_to_logic [spec=tla:CoreMetaVM, impl=lean4:StepFn, mapping=map:core_to_logic].
CORRESPONDS logic_to_runtime [left=lean4:StepFn, right=acl2:ExecStep, refines=core_to_logic].
PROOF_OBLIGATION po_refines_sound [relation=core_to_logic, statement=\"next-state preserves invariant\", tool=z3, criticality=high].
QUERY q:
FIND ?x WHERE ?x#kind@entity:proof_obligation.
"
        out (core/execute-program program)]
    (is (= [["proof_obligation:po_refines_sound"]]
           (get-in out [:queries "q" :rows])))))

(deftest native-macro-expansion-test
  (testing "Macro emits facts with parameter substitution"
    (let [program "MODULE demo.
MACRO link_pair(a,b):
EMIT {{a}}#linked_to@{{b}}.
EMIT {{b}}#linked_to@{{a}}.
ENDMACRO.
USE link_pair(node:a, node:b).
QUERY q:
FIND ?x WHERE ?x#linked_to@node:b.
"
          out (core/execute-program program)]
      (is (= [["node:a"]]
             (get-in out [:queries "q" :rows])))))
  (testing "Nested macro expansion works without Clojure macros"
    (let [program "MODULE demo.
MACRO one(a,b):
EMIT {{a}}#edge@{{b}}.
ENDMACRO.
MACRO both(a,b):
EMIT USE one({{a}}, {{b}}).
EMIT USE one({{b}}, {{a}}).
ENDMACRO.
USE both(n:1, n:2).
QUERY q:
FIND ?x WHERE ?x#edge@n:2.
"
          out (core/execute-program program)]
      (is (= [["n:1"]]
             (get-in out [:queries "q" :rows]))))))

(deftest tlm-domain-macro-layer-smoke-test
  (let [program "MODULE tlm.demo.
MACRO TLM_COMPONENT(name, role):
EMIT tlm:component:{{name}}#kind@entity:tlm_component.
EMIT tlm:component:{{name}}#role@value:{{role}}.
ENDMACRO.
MACRO TLM_CHANNEL(name, src, dst, timing):
EMIT tlm:channel:{{name}}#kind@entity:tlm_channel.
EMIT tlm:channel:{{name}}#from@tlm:component:{{src}}.
EMIT tlm:channel:{{name}}#to@tlm:component:{{dst}}.
EMIT tlm:channel:{{name}}#timing@value:{{timing}}.
ENDMACRO.
MACRO TLM_TRANSACTION(id, cmd, addr, payload, size, priority, timing):
EMIT tlm:tx:{{id}}#kind@entity:tlm_transaction.
EMIT tlm:tx:{{id}}#command@value:{{cmd}}.
EMIT tlm:tx:{{id}}#address@value:{{addr}}.
EMIT tlm:tx:{{id}}#payload@value:{{payload}}.
EMIT tlm:tx:{{id}}#size@value:{{size}}.
EMIT tlm:tx:{{id}}#priority@value:{{priority}}.
EMIT tlm:tx:{{id}}#timing_profile@value:{{timing}}.
ENDMACRO.
MACRO TLM_COMPUTE(step, component, op):
EMIT tlm:step:{{step}}#kind@entity:tlm_step.
EMIT tlm:step:{{step}}#phase@value:compute.
EMIT tlm:step:{{step}}#component@tlm:component:{{component}}.
EMIT tlm:step:{{step}}#operation@value:{{op}}.
ENDMACRO.
MACRO TLM_SEND(id, src, channel):
EMIT tlm:tx:{{id}}#phase@value:communication.
EMIT tlm:tx:{{id}}#issued_by@tlm:component:{{src}}.
EMIT tlm:tx:{{id}}#via@tlm:channel:{{channel}}.
EMIT tlm:tx:{{id}}#status@value:issued.
ENDMACRO.
MACRO TLM_ACCEPT(id, dst):
EMIT tlm:tx:{{id}}#accepted_by@tlm:component:{{dst}}.
EMIT tlm:tx:{{id}}#status@value:accepted.
ENDMACRO.
USE TLM_COMPONENT(cpu0, initiator).
USE TLM_COMPONENT(mem0, target).
USE TLM_CHANNEL(main_bus, cpu0, mem0, loosely_timed).
USE TLM_TRANSACTION(t1, read, addr_4096, word32, 4, high, loosely_timed).
USE TLM_COMPUTE(cpu0_decode, cpu0, decode_read).
USE TLM_SEND(t1, cpu0, main_bus).
USE TLM_ACCEPT(t1, mem0).
RULE source_consistency:
IF ?tx#issued_by@?src AND ?tx#via@?ch AND ?ch#from@?src
THEN ?tx#source_consistent@value:true.
QUERY consistent:
FIND ?tx WHERE ?tx#source_consistent@value:true.
QUERY timing:
FIND ?t WHERE tlm:tx:t1#timing_profile@?t.
QUERY compute_steps:
FIND ?s WHERE ?s#phase@value:compute.
"
        out (core/execute-program program)]
    (is (= [["tlm:tx:t1"]]
           (get-in out [:queries "consistent" :rows])))
    (is (= [["value:loosely_timed"]]
           (get-in out [:queries "timing" :rows])))
    (is (= [["tlm:step:cpu0_decode"]]
           (get-in out [:queries "compute_steps" :rows])))))

(deftest tpl-domain-macro-layer-smoke-test
  (let [program "MODULE tpl.demo.
MACRO TPL_ACTION(name, class):
EMIT tpl:action:{{name}}#kind@entity:tpl_action.
EMIT tpl:action:{{name}}#class@value:{{class}}.
ENDMACRO.
MACRO TPL_VISIBLE(name):
EMIT USE TPL_ACTION({{name}}, visible).
ENDMACRO.
MACRO TPL_TAU(name):
EMIT USE TPL_ACTION({{name}}, tau).
ENDMACRO.
MACRO TPL_PREFIX(proc, action, next_proc):
EMIT tpl:proc:{{proc}}#kind@entity:tpl_process.
EMIT tpl:proc:{{proc}}#operator@value:prefix.
EMIT tpl:proc:{{proc}}#action@tpl:action:{{action}}.
EMIT tpl:proc:{{proc}}#next@tpl:proc:{{next_proc}}.
ENDMACRO.
MACRO TPL_NIL(proc):
EMIT tpl:proc:{{proc}}#kind@entity:tpl_process.
EMIT tpl:proc:{{proc}}#operator@value:nil.
ENDMACRO.
MACRO TPL_OMEGA(proc):
EMIT tpl:proc:{{proc}}#kind@entity:tpl_process.
EMIT tpl:proc:{{proc}}#operator@value:omega.
EMIT tpl:proc:{{proc}}#blocks_tick@value:true.
ENDMACRO.
MACRO TPL_CHOICE(proc, left_proc, right_proc):
EMIT tpl:proc:{{proc}}#kind@entity:tpl_process.
EMIT tpl:proc:{{proc}}#operator@value:choice.
EMIT tpl:proc:{{proc}}#left@tpl:proc:{{left_proc}}.
EMIT tpl:proc:{{proc}}#right@tpl:proc:{{right_proc}}.
ENDMACRO.
RULE prefix_visible_patient:
IF ?p#operator@value:prefix AND ?p#action@?a AND ?a#class@value:visible
THEN ?p#patient@value:true AND ?p#can_sigma@value:true.
RULE prefix_tau_ready:
IF ?p#operator@value:prefix AND ?p#action@?a AND ?a#class@value:tau
THEN ?p#can_tau@value:true.
RULE maximal_progress_blocks_tick:
IF ?p#can_tau@value:true
THEN ?p#blocks_tick@value:true.
RULE choice_blocks_left:
IF ?p#operator@value:choice AND ?p#left@?l AND ?l#blocks_tick@value:true
THEN ?p#blocks_tick@value:true.
RULE choice_blocks_right:
IF ?p#operator@value:choice AND ?p#right@?r AND ?r#blocks_tick@value:true
THEN ?p#blocks_tick@value:true.
USE TPL_VISIBLE(act_a).
USE TPL_TAU(act_tau).
USE TPL_NIL(p0).
USE TPL_PREFIX(p_visible, act_a, p0).
USE TPL_PREFIX(p_tau_only, act_tau, p0).
USE TPL_OMEGA(p_omega).
USE TPL_CHOICE(p_insistent, p_visible, p_omega).
QUERY patient:
FIND ?p WHERE ?p#patient@value:true.
QUERY blocked:
FIND ?p WHERE ?p#blocks_tick@value:true.
"
        out (core/execute-program program)
        patient (set (map first (get-in out [:queries "patient" :rows])))
        blocked (set (map first (get-in out [:queries "blocked" :rows])))]
    (is (contains? patient "tpl:proc:p_visible"))
    (is (contains? blocked "tpl:proc:p_insistent"))
    (is (contains? blocked "tpl:proc:p_tau_only"))))

(deftest pi-vc-domain-macro-layer-smoke-test
  (let [program "MODULE pi.vc.demo.
MACRO PI_CHANNEL(name):
EMIT pi:name:{{name}}#kind@entity:pi_channel.
ENDMACRO.
MACRO PI_VALUE(name):
EMIT pi:name:{{name}}#kind@entity:pi_value.
ENDMACRO.
MACRO PI_NIL(proc):
EMIT pi:proc:{{proc}}#kind@entity:pi_process.
EMIT pi:proc:{{proc}}#operator@value:nil.
ENDMACRO.
MACRO PI_SEND(proc, channel, payload, next_proc):
EMIT pi:proc:{{proc}}#kind@entity:pi_process.
EMIT pi:proc:{{proc}}#operator@value:send.
EMIT pi:proc:{{proc}}#channel@pi:name:{{channel}}.
EMIT pi:proc:{{proc}}#payload@pi:name:{{payload}}.
EMIT pi:proc:{{proc}}#next@pi:proc:{{next_proc}}.
ENDMACRO.
MACRO PI_RECV(proc, channel, bind_name, next_proc):
EMIT pi:proc:{{proc}}#kind@entity:pi_process.
EMIT pi:proc:{{proc}}#operator@value:recv.
EMIT pi:proc:{{proc}}#channel@pi:name:{{channel}}.
EMIT pi:proc:{{proc}}#bind@pi:name:{{bind_name}}.
EMIT pi:proc:{{proc}}#next@pi:proc:{{next_proc}}.
ENDMACRO.
MACRO PI_PAR(proc, left_proc, right_proc):
EMIT pi:proc:{{proc}}#kind@entity:pi_process.
EMIT pi:proc:{{proc}}#operator@value:par.
EMIT pi:proc:{{proc}}#left@pi:proc:{{left_proc}}.
EMIT pi:proc:{{proc}}#right@pi:proc:{{right_proc}}.
ENDMACRO.
MACRO VC_ACTOR(actor):
EMIT vc:actor:{{actor}}#kind@entity:vc_actor.
ENDMACRO.
MACRO VC_COUNTER(counter):
EMIT vc:ctr:{{counter}}#kind@entity:vc_counter.
ENDMACRO.
MACRO VC_LT(low, high):
EMIT vc:ctr:{{low}}#lt@vc:ctr:{{high}}.
ENDMACRO.
MACRO VC_EVENT(event):
EMIT vc:event:{{event}}#kind@entity:vc_event.
ENDMACRO.
MACRO VC_COMPONENT(event, actor, counter):
EMIT vc:event:{{event}}#vc_counter@vc:actor:{{actor}} [counter=vc:ctr:{{counter}}].
ENDMACRO.
MACRO VC_DISTINCT(e1, e2):
EMIT vc:event:{{e1}}#distinct_from@vc:event:{{e2}}.
EMIT vc:event:{{e2}}#distinct_from@vc:event:{{e1}}.
ENDMACRO.
RULE pi_parallel_sync:
IF ?p#operator@value:par AND ?p#left@?s AND ?p#right@?r AND ?s#operator@value:send AND ?r#operator@value:recv AND ?s#channel@?c AND ?r#channel@?c AND ?s#payload@?v AND ?s#next@?sn AND ?r#next@?rn
THEN ?p#can_tau@value:true AND ?p#sync_payload@?v.
RULE vc_lt_transitive:
IF ?a#lt@?b AND ?b#lt@?c
THEN ?a#lt@?c.
RULE vc_strict_witness:
IF ?e1#vc_counter@?actor [counter=?c1] AND ?e2#vc_counter@?actor [counter=?c2] AND ?c1#lt@?c2
THEN ?e1#vc_strict_witness@?e2.
RULE vc_violation_over:
IF ?e1#vc_counter@?actor [counter=?c1] AND ?e2#vc_counter@?actor [counter=?c2] AND ?c2#lt@?c1
THEN ?e1#vc_violation_over@?e2.
RULE vc_before:
IF ?e1#kind@entity:vc_event AND ?e2#kind@entity:vc_event AND ?e1#distinct_from@?e2 AND ?e1#vc_strict_witness@?e2 AND NOT ?e1#vc_violation_over@?e2
THEN ?e1#before@?e2.
USE PI_CHANNEL(x).
USE PI_VALUE(v1).
USE PI_VALUE(y).
USE PI_NIL(p0).
USE PI_SEND(sx, x, v1, p0).
USE PI_RECV(rx, x, y, p0).
USE PI_PAR(parx, sx, rx).
USE VC_ACTOR(a).
USE VC_ACTOR(b).
USE VC_COUNTER(c0).
USE VC_COUNTER(c1).
USE VC_COUNTER(c2).
USE VC_LT(c0, c1).
USE VC_LT(c1, c2).
USE VC_EVENT(e1).
USE VC_EVENT(e2).
USE VC_DISTINCT(e1, e2).
USE VC_COMPONENT(e1, a, c1).
USE VC_COMPONENT(e1, b, c0).
USE VC_COMPONENT(e2, a, c2).
USE VC_COMPONENT(e2, b, c1).
QUERY pi_tau:
FIND ?p WHERE ?p#can_tau@value:true.
QUERY vc_before_q:
FIND ?t WHERE vc:event:e1#before@?t.
"
        out (core/execute-program program)]
    (is (= [["pi:proc:parx"]]
           (get-in out [:queries "pi_tau" :rows])))
    (is (= [["vc:event:e2"]]
           (get-in out [:queries "vc_before_q" :rows])))))

(deftest petrinet-nd-macro-layer-smoke-test
  (let [program (slurp "examples/petrinet-nd-macro-layer.zc")
        out (core/execute-program program)
        abstraction (set (map first (get-in out [:queries "abstraction_consistency" :rows])))]
    (is (= [["pn:place:conn_socket_ready"]]
           (get-in out [:queries "flatten_ref_targets" :rows])))
    (is (= [["pn:place:conn_socket_ready"]]
           (get-in out [:queries "transition_enabling_witnesses" :rows])))
    (is (= #{"pn:place:conn_socket_ready" "pn:place:channel_ready"}
           abstraction))
    (is (= [["pn:token:tok_conn_1"]]
           (get-in out [:queries "lifted_tokens_on_abstract_places" :rows])))
    (is (= [["pn:transition:t_upgrade_channel"]]
           (get-in out [:queries "tm_bridge_valid" :rows])))
    (is (= [["pn:transition:t_upgrade_channel"]]
           (get-in out [:queries "pi_bridge_valid" :rows])))
    (is (= [["pn:transition:t_authenticate"]]
           (get-in out [:queries "lambda_bridge_valid" :rows])))))

(deftest unknown-macro-fails-fast-test
  (let [program "MODULE demo.
USE missing_macro(x,y).
"]
    (is (thrown? clojure.lang.ExceptionInfo
                 (core/execute-program program)))))


(deftest stdlib-language-grammar-parser-adapter-query-test
  (let [program "MODULE grammar.port.demo.
LANGUAGE_PROFILE ocaml_base [family=ocaml, module_system=ml_module, artifact=typed_ast].
GRAMMAR_PROFILE ocaml_expr_ebnf [language=ocaml_base, notation=ebnf, entrypoints=[expr module_item], status=draft].
PARSER_ADAPTER antlr_ocaml_bridge [language=ocaml_base, grammar=ocaml_expr_ebnf, runtime=jvm, input_profile=source_text, output_profile=vetc_ir, determinism=best_effort].
QUERY adapters:
FIND ?a WHERE ?a#kind@entity:parser_adapter.
QUERY adapter_language:
FIND ?l WHERE parser_adapter:antlr_ocaml_bridge#language@?l.
QUERY adapter_grammar:
FIND ?g WHERE parser_adapter:antlr_ocaml_bridge#grammar@?g.
"
        out (core/execute-program program)]
    (is (= [["parser_adapter:antlr_ocaml_bridge"]]
           (get-in out [:queries "adapters" :rows])))
    (is (= [["language_profile:ocaml_base"]]
           (get-in out [:queries "adapter_language" :rows])))
    (is (= [["grammar_profile:ocaml_expr_ebnf"]]
           (get-in out [:queries "adapter_grammar" :rows])))))

(deftest stdlib-declaration-lowering-test
  (let [program "MODULE demo.
PROVIDER aws [source=\"hashicorp/aws\", version=\"~> 5.0\", language=hcl, engine=opentofu].
SERVICE payment [env=prod, tier=critical].
HOST host1 [environment=prod, timezone=\"America/Mexico_City\"].
DATASOURCE app_metrics [type=rest, format=json, provider=aws].
METRIC latency [source=datasource:app_metrics, unit=ms].
POLICY latency_guard [condition=\"latency > 120\", criticality=HIGH].
EVENT deploy [start_time=\"2026-03-16T10:00:00-06:00\", labels=[\"ops\", \"deploy\"]].
QUERY services:
FIND ?s WHERE ?s#kind@entity:service.
QUERY providers:
FIND ?p WHERE ?p#kind@entity:provider.
QUERY source_type:
FIND ?t WHERE datasource:app_metrics#type@?t.
QUERY ds_provider:
FIND ?p WHERE datasource:app_metrics#provider@?p.
QUERY policy_criticality:
FIND ?c WHERE policy:latency_guard#criticality@?c.
QUERY event_labels:
FIND ?l WHERE event:deploy#labels@?l.
"
        out (core/execute-program program)]
    (is (= [["service:payment"]]
           (get-in out [:queries "services" :rows])))
    (is (= [["provider:aws"]]
           (get-in out [:queries "providers" :rows])))
    (is (= [["value:rest"]]
           (get-in out [:queries "source_type" :rows])))
    (is (= [["provider:aws"]]
           (get-in out [:queries "ds_provider" :rows])))
    (is (= [["value:high"]]
           (get-in out [:queries "policy_criticality" :rows])))
    (is (= #{"value:ops" "value:deploy"}
           (set (map first (get-in out [:queries "event_labels" :rows])))))))

(deftest stdlib-duplicate-declaration-fails-test
  (let [program "MODULE demo.
SERVICE payment [env=prod].
SERVICE payment [env=qa].
"]
    (is (thrown? clojure.lang.ExceptionInfo
                 (core/compile-program program)))))

(deftest attrs-supports-nested-edn-values-test
  (let [program "MODULE demo.
app:a#cfg@value:ok [meta={:foo 1, :bar [1 2]}, tags=#{:blue :green}].
"
        compiled (core/compile-program program)
        fact (first (:facts compiled))]
    (is (= {:foo 1 :bar [1 2]}
           (get-in fact [:attrs :meta])))
    (is (= #{:blue :green}
           (get-in fact [:attrs :tags])))))

(deftest service-declaration-dependency-semantics-test
  (let [program "MODULE demo.
SERVICE api [depends=[db], criticality=LOW].
SERVICE db [env=prod].
QUERY uses:
FIND ?x WHERE service:api#uses@?x.
QUERY used_by:
FIND ?x WHERE service:db#used_by@?x.
QUERY depends_on:
FIND ?x WHERE service:api#depends_on@?x.
QUERY crit:
FIND ?c WHERE service:api#criticality@?c.
"
        out (core/execute-program program)]
    (is (= [["service:db"]]
           (get-in out [:queries "uses" :rows])))
    (is (= [["service:api"]]
           (get-in out [:queries "used_by" :rows])))
    (is (= [["service:db"]]
           (get-in out [:queries "depends_on" :rows])))
    (is (= [["value:low"]]
           (get-in out [:queries "crit" :rows])))))

(deftest tm-atom-declaration-query-test
  (let [program "MODULE tm.demo.
TM_ATOM parity [states=#{q0 qa qr}, alphabet=#{0 _}, blank=_, initial=q0, accept=#{qa}, reject=#{qr}, transitions={[q0 0] [q0 0 :R], [q0 _] [qa _ :N]}].
QUERY transitions:
FIND ?t WHERE tm_atom:parity#transition@?t.
"
        out (core/execute-program program)]
    (is (= 2 (count (get-in out [:queries "transitions" :rows]))))))

(deftest lts-atom-declaration-query-test
  (let [program "MODULE lts.demo.
LTS_ATOM deploy_flow [states=#{draft reviewing approved rejected}, initial=draft, transitions={[draft submit] [reviewing], [reviewing approve] [approved], [reviewing reject] [rejected notify_author]}].
QUERY edges:
FIND ?e WHERE lts_atom:deploy_flow#edge@?e.
"
        out (core/execute-program program)]
    (is (= 3 (count (get-in out [:queries "edges" :rows]))))))

(deftest datascript-native-inference-positive-rules-test
  (testing "DataScript rule engine does inference for programs with only positive rules"
    (let [program "MODULE native.demo.
a:1#parent@b:1.
b:1#kind@entity:group.
RULE member:
IF ?P#parent@?G AND ?G#kind@entity:group
THEN ?P#member_of@?G.
QUERY members:
FIND ?p ?g WHERE ?p#member_of@?g.
"
          compiled      (core/compile-program program)
          full-result   (core/execute-compiled compiled)
          native-result (zr/execute-with-native-datascript
                         (:facts compiled) (:rules compiled) (:queries compiled))]
      (is (empty? (:skipped-rules native-result))
          "no rules skipped — no NOT literals")
      (is (= #{:member_of} (:derived-rels native-result)))
      (is (= [["a:1" "b:1"]]
             (get-in full-result [:queries "members" :rows])))
      (is (= (get-in full-result [:queries "members" :rows])
             (get-in native-result [:query-results "members" :rows]))
          "native DataScript inference must match custom evaluator"))))

(deftest datascript-native-inference-chain-test
  (testing "Multi-level rule chain: DataScript semi-naive evaluation across strata"
    (let [program "MODULE chain.demo.
x:1#a@y:1.
y:1#c@z:1.
RULE derive_b:
IF ?X#a@?Y
THEN ?X#b@?Y.
RULE derive_d:
IF ?X#b@?Z AND ?Z#c@?W
THEN ?X#d@?W.
QUERY result:
FIND ?x ?w WHERE ?x#d@?w.
"
          compiled      (core/compile-program program)
          full-result   (core/execute-compiled compiled)
          native-result (zr/execute-with-native-datascript
                         (:facts compiled) (:rules compiled) (:queries compiled))]
      (is (= #{:b :d} (:derived-rels native-result)))
      (is (= [["x:1" "z:1"]]
             (get-in full-result [:queries "result" :rows])))
      (is (= (get-in full-result [:queries "result" :rows])
             (get-in native-result [:query-results "result" :rows]))
          "multi-level chain via DataScript must match custom evaluator"))))

(deftest datascript-native-inference-negated-rules-skipped-test
  (testing "Rules with NOT are reported as skipped, not compiled to DataScript"
    (let [program "MODULE negation.demo.
svc:a#kind@entity:service.
RULE degrade:
IF svc:a#kind@entity:service AND NOT svc:a#available@value:true
THEN svc:a#status@value:degraded.
QUERY status:
FIND ?s WHERE svc:a#status@?s.
"
          compiled      (core/compile-program program)
          native-result (zr/execute-with-native-datascript
                         (:facts compiled) (:rules compiled) (:queries compiled))]
      (is (= ["degrade"] (:skipped-rules native-result))
          "negated rule must be reported as skipped")
      (is (= #{} (:derived-rels native-result))
          "no rules compiled when all contain NOT"))))

(deftest datascript-conn-in-execute-result-test
  (let [program "MODULE demo.
app:a#kind@entity:service.
app:b#kind@entity:service.
RULE chain:
IF ?x#kind@entity:service
THEN ?x#active@value:true.
QUERY kinds:
FIND ?x WHERE ?x#kind@entity:service.
"
        result (core/execute-program program)
        conn   (:conn result)]
    (is (some? conn) "execute-program must return :conn")
    (is (map? result))
    (let [db (d/db conn)]
      (is (pos? (count (d/q '[:find ?e :where [?e :zil/relation :kind]] db)))
          "DataScript DB must be queryable after execution")
      (is (pos? (count (d/q '[:find ?e :where [?e :zil/relation :active]] db)))
          "Derived facts must also be present in DataScript"))))

(deftest materialize-datascript-returns-conn-test
  (let [program "MODULE ds.test.
svc:x#kind@entity:host.
QUERY hosts:
FIND ?h WHERE ?h#kind@entity:host.
"
        {:keys [conn result]} (core/materialize-datascript program)]
    (is (some? conn))
    (is (= [["svc:x"]] (get-in result [:queries "hosts" :rows])))
    (let [db (d/db conn)]
      (is (= 1 (count (d/q '[:find ?o :where [?e :zil/relation :kind] [?e :zil/object ?o]] db)))))))

(defn -main
  [& _]
  (let [{:keys [fail error]} (run-tests 'zil.core-test)]
    (when (pos? (+ fail error))
      (System/exit 1))))
