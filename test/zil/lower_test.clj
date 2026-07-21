(ns zil.lower-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.lower :as zl]))

(deftest service-lowering-emits-dependency-facts-test
  (let [facts (zl/declaration->facts
               {:kind :service
                :name "api"
                :attrs {:depends ["db" "cache"]
                        :criticality "HIGH"}})
        triples (set (map (juxt :object :relation :subject) facts))]
    (is (contains? triples ["service:api" :kind "entity:service"]))
    (is (contains? triples ["service:api" :uses "service:db"]))
    (is (contains? triples ["service:api" :depends_on "service:db"]))
    (is (contains? triples ["service:db" :used_by "service:api"]))
    (is (contains? triples ["service:cache" :used_by "service:api"]))
    (is (contains? triples ["service:api" :criticality "value:high"]))))

(deftest declaration-validation-rules-test
  (testing "Datasource enum validation rejects unsupported type"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :datasource :name "bad" :attrs {:type "ftp"}}))))

  (testing "Datasource enum validation accepts cucumber type"
    (is (true? (zl/validate-declaration!
                {:kind :datasource :name "cuk" :attrs {:type "cucumber"}}))))

  (testing "Datasource format validation accepts yaml/yml/csv"
    (is (true? (zl/validate-declaration!
                {:kind :datasource :name "y1" :attrs {:type "file" :format "yaml"}})))
    (is (true? (zl/validate-declaration!
                {:kind :datasource :name "y2" :attrs {:type "file" :format "yml"}})))
    (is (true? (zl/validate-declaration!
                {:kind :datasource :name "c1" :attrs {:type "file" :format "csv"}}))))

  (testing "Policy criticality accepts medium tier"
    (is (true? (zl/validate-declaration!
                {:kind :policy
                 :name "p_medium"
                 :attrs {:condition "x > 0" :criticality "medium"}}))))

  (testing "Service dependency references must exist"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :service
                    :name "api"
                    :attrs {:uses ["missing-service"]}}]))))

  (testing "Service dependency cycles are rejected"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :service :name "a" :attrs {:uses ["b"]}}
                   {:kind :service :name "b" :attrs {:uses ["a"]}}]))))

  (testing "Metric source must reference a datasource declaration"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :service :name "svc" :attrs {}}
                   {:kind :metric :name "lat" :attrs {:source "service:svc"}}]))))

  (testing "Valid dependency and metric references pass"
    (is (true? (zl/validate-declarations!
                [{:kind :service :name "svc" :attrs {:uses ["svc-db"]}}
                 {:kind :service :name "svc-db" :attrs {}}
                 {:kind :datasource :name "ds" :attrs {:type "rest"}}
                 {:kind :metric :name "lat" :attrs {:source "datasource:ds"}}]))))

  (testing "Provider references must resolve to PROVIDER declarations"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :datasource :name "cloud_ds" :attrs {:type "rest" :provider "aws"}}]))))

  (testing "Provider declaration requires namespaced source"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :provider :name "aws" :attrs {:source "aws"}}))))

  (testing "Provider references lower to provider+inverse facts"
    (let [facts (zl/declaration->facts {:kind :datasource
                                        :name "cloud_ds"
                                        :attrs {:type "rest" :provider "aws"}})
          triples (set (map (juxt :object :relation :subject) facts))]
      (is (contains? triples ["datasource:cloud_ds" :provider "provider:aws"]))
      (is (contains? triples ["provider:aws" :provides_for "datasource:cloud_ds"])))))

(deftest tm-atom-validation-and-lowering-test
  (let [tm {:kind :tm_atom
            :name "parity"
            :attrs {:states #{'q0 'qa 'qr}
                    :alphabet #{'0 '_}
                    :blank '_
                    :initial 'q0
                    :accept #{'qa}
                    :reject #{'qr}
                    :transitions {['q0 '0] ['q0 '0 :R]
                                  ['q0 '_] ['qa '_ :N]}}}
        facts (zl/declaration->facts tm)
        transition-facts (filter #(= :transition (:relation %)) facts)]
    (is (= 2 (count transition-facts)))
    (is (every? #(contains? #{:R :N} (get-in % [:attrs :move])) transition-facts)))

  (testing "TM_ATOM must be complete for non-halting states"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :tm_atom
                   :name "bad_tm"
                   :attrs {:states #{'q0 'qa 'qr}
                           :alphabet #{'0 '_}
                           :blank '_
                           :initial 'q0
                           :accept #{'qa}
                           :reject #{'qr}
                           :transitions {['q0 '0] ['q0 '0 :R]}}}))))
  (testing "TM_ATOM move must be L|R|N"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :tm_atom
                   :name "bad_move"
                   :attrs {:states #{'q0 'qa 'qr}
                           :alphabet #{'0 '_}
                           :blank '_
                           :initial 'q0
                           :accept #{'qa}
                           :reject #{'qr}
                           :transitions {['q0 '0] ['q0 '0 :X]
                                         ['q0 '_] ['qa '_ :N]}}})))))

(deftest lts-atom-validation-and-lowering-test
  (let [lts {:kind :lts_atom
             :name "service_flow"
             :attrs {:states #{'idle 'running 'failed}
                     :initial 'idle
                     :transitions {['idle 'start] ['running]
                                   ['running 'fail] ['failed 'alert_ops]}}}
        facts (zl/declaration->facts lts)
        edge-facts (filter #(= :edge (:relation %)) facts)]
    (is (= 2 (count edge-facts)))
    (is (= #{"start" "fail"}
           (set (map #(get-in % [:attrs :label]) edge-facts)))))

  (testing "LTS_ATOM initial must belong to states"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :lts_atom
                   :name "bad_initial"
                   :attrs {:states #{'idle}
                           :initial 'running
                           :transitions {['idle 'start] ['idle]}}}))))
  (testing "LTS_ATOM transition values must be [next] or [next effect]"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :lts_atom
                   :name "bad_transition"
                   :attrs {:states #{'idle 'running}
                           :initial 'idle
                           :transitions {['idle 'start] ['running 'notify 'extra]}}})))))

(deftest refinement-relation-layer-validation-and-lowering-test
  (let [decls [{:kind :refines
                :name "core_to_logic"
                :attrs {:spec "tla:CoreMetaVM"
                        :impl "lean4:StepFn"
                        :mapping "map:core_to_logic"}}
               {:kind :corresponds
                :name "logic_to_runtime"
                :attrs {:left "lean4:StepFn"
                        :right "acl2:ExecStep"
                        :refines "core_to_logic"}}
               {:kind :proof_obligation
                :name "po_refines_sound"
                :attrs {:relation "core_to_logic"
                        :statement "next-state preserves invariant"
                        :tool "z3"
                        :criticality "high"}}]
        facts (mapcat zl/declaration->facts decls)
        triples (set (map (juxt :object :relation :subject) facts))]
    (is (true? (zl/validate-declarations! decls)))
    (is (contains? triples ["refines:core_to_logic" :kind "entity:refines"]))
    (is (contains? triples ["corresponds:logic_to_runtime" :kind "entity:corresponds"]))
    (is (contains? triples ["proof_obligation:po_refines_sound" :kind "entity:proof_obligation"]))
    (is (contains? triples ["proof_obligation:po_refines_sound" :relation "refines:core_to_logic"]))
    (is (contains? triples ["proof_obligation:po_refines_sound" :criticality "value:high"]))
    (is (contains? triples ["proof_obligation:po_refines_sound" :logic "value:all"]))
    (is (contains? triples ["proof_obligation:po_refines_sound" :expectation "value:sat"])))

  (testing "PROOF_OBLIGATION relation target must resolve to REFINES or CORRESPONDS"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :proof_obligation
                    :name "po_bad_target"
                    :attrs {:relation "service:api"
                            :statement "invalid target"}}])))))


(deftest language-grammar-parser-adapter-validation-and-lowering-test
  (let [decls [{:kind :language_profile
                :name "ocaml_base"
                :attrs {:family "ocaml"
                        :module_system "ml_module"
                        :artifact "typed_ast"}}
               {:kind :grammar_profile
                :name "ocaml_expr_ebnf"
                :attrs {:language "ocaml_base"
                        :notation "ebnf"
                        :entrypoints ["expr" "module_item"]
                        :status "draft"}}
               {:kind :parser_adapter
                :name "antlr_ocaml_bridge"
                :attrs {:language "ocaml_base"
                        :grammar "ocaml_expr_ebnf"
                        :runtime "jvm"
                        :input_profile "source_text"
                        :output_profile "vetc_ir"
                        :determinism "best_effort"}}]
        facts (mapcat zl/declaration->facts decls)
        triples (set (map (juxt :object :relation :subject) facts))]
    (is (true? (zl/validate-declarations! decls)))
    (is (contains? triples ["language_profile:ocaml_base" :kind "entity:language_profile"]))
    (is (contains? triples ["grammar_profile:ocaml_expr_ebnf" :language "language_profile:ocaml_base"]))
    (is (contains? triples ["parser_adapter:antlr_ocaml_bridge" :language "language_profile:ocaml_base"]))
    (is (contains? triples ["parser_adapter:antlr_ocaml_bridge" :grammar "grammar_profile:ocaml_expr_ebnf"]))
    (is (contains? triples ["parser_adapter:antlr_ocaml_bridge" :output_profile "value:vetc_ir"])))

  (testing "GRAMMAR_PROFILE must reference existing LANGUAGE_PROFILE"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :grammar_profile
                    :name "bad_grammar"
                    :attrs {:language "missing_language"
                            :notation "ebnf"
                            :entrypoints ["expr"]}}]))))

  (testing "PARSER_ADAPTER grammar, when present, must reference GRAMMAR_PROFILE"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :language_profile
                    :name "ocaml_base"
                    :attrs {:family "ocaml" :module_system "ml_module"}}
                   {:kind :parser_adapter
                    :name "bad_parser"
                    :attrs {:language "ocaml_base"
                            :grammar "missing_grammar"
                            :runtime "jvm"
                            :input_profile "source_text"
                            :output_profile "vetc_ir"}}])))))

(deftest dsl-profile-query-pack-validation-and-lowering-test
  (let [decls [{:kind :query_pack
                :name "ops_pack"
                :attrs {:queries ["q_health" "q_latency"]}}
               {:kind :dsl_profile
                :name "ops_profile"
                :attrs {:query_pack "ops_pack"
                        :planner_hint "high_selectivity_first"
                        :verification_chain ["constraint" "proof_obligation"]}}]
        facts (mapcat zl/declaration->facts decls)
        triples (set (map (juxt :object :relation :subject) facts))]
    (is (true? (zl/validate-declarations! decls)))
    (is (contains? triples ["dsl_profile:ops_profile" :kind "entity:dsl_profile"]))
    (is (contains? triples ["dsl_profile:ops_profile" :query_pack "query_pack:ops_pack"]))
    (is (contains? triples ["dsl_profile:ops_profile" :planner_hint "value:high_selectivity_first"]))
    (is (contains? triples ["query_pack:ops_pack" :kind "entity:query_pack"])))

  (testing "DSL_PROFILE query_pack reference must exist"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declarations!
                  [{:kind :dsl_profile
                    :name "bad_profile"
                    :attrs {:query_pack "missing_pack"}}]))))

  (testing "QUERY_PACK must include at least one query name"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :query_pack
                   :name "empty_pack"
                   :attrs {:queries []}}))))

  (testing "QUERY_PACK must_return must be included in queries"
    (is (thrown? clojure.lang.ExceptionInfo
                 (zl/validate-declaration!
                  {:kind :query_pack
                   :name "bad_pack"
                   :attrs {:queries ["q1"]
                           :must_return ["q2"]}})))))
