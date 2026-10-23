(ns zil.bridge-souffle-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.bridge.souffle :as bs]
            [zil.core :as core]))

;; ---------------------------------------------------------------------------
;; Unit tests — no Souffle binary required
;; ---------------------------------------------------------------------------

(deftest souffle-rel-name-test
  (is (= "zil_kind"        (bs/souffle-rel-name :kind)))
  (is (= "zil_member_of"   (bs/souffle-rel-name :member_of)))
  (is (= "zil_belongs_to"  (bs/souffle-rel-name :belongs_to))))

(deftest rules->souffle-test
  (let [rules [{:name "member"
                :if   [{:object "?P" :relation :parent :subject "?G" :attrs {}}
                       {:object "?G" :relation :kind   :subject "value:group" :attrs {}}]
                :then [{:object "?P" :relation :member_of :subject "?G"}]}]
        text (bs/rules->souffle rules)]
    (testing "derived decl"
      (is (str/includes? text ".decl zil_member_of(object:symbol, subject:symbol)")))
    (testing "rule body uses 2-arg form (no attrs column)"
      (is (str/includes? text "zil_parent(P, G)"))
      (is (str/includes? text "zil_kind(G, \"value:group\")")))
    (testing "rule head uses 2-arg form"
      (is (str/includes? text "zil_member_of(P, G) :-")))))

(deftest rules->souffle-negation-test
  (let [rules [{:name "degrade"
                :if   [{:object "?X" :relation :active :subject "value:true" :attrs {}}
                       {:object "?X" :relation :flag   :subject "value:ok"   :attrs {} :neg? true}]
                :then [{:object "?X" :relation :degraded :subject "value:true"}]}]
        text (bs/rules->souffle rules)]
    (testing "negated literal becomes !rel(...)"
      (is (str/includes? text "!zil_flag(X, \"value:ok\")")))))

(deftest attributed-literal-lowering-test
  (let [queries [{:name "clock_components"
                  :find ["?EVENT" "?ACTOR" "?COUNTER"]
                  :where [{:object "?EVENT" :relation :vc_component :subject "?ACTOR"
                           :attrs {:counter "?COUNTER"}}]}]
        text (first (bs/queries->souffle queries #{}))]
    (is (str/includes? text "zil_vc_component(EVENT, ACTOR)"))
    (is (str/includes? text
                       "zillang_attribute(\"zil_vc_component\", EVENT, ACTOR, \"counter\", COUNTER)"))))

(deftest attributed-negation-refuses-lossy-lowering-test
  (let [compiled {:facts [] :rules []
                  :queries [{:name "missing_clock" :find ["?EVENT"]
                             :where [{:object "?EVENT" :relation :vc_component :subject "?ACTOR"
                                      :attrs {:counter "?COUNTER"} :neg? true}]}]}]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"negated ZIL tuple attributes"
                          (bs/emit-souffle-schema compiled)))))

(deftest queries->souffle-test
  (let [derived-rels #{:member_of}
        queries [{:name "active_members"
                  :find ["?P" "?G"]
                  :where [{:object "?P" :relation :member_of :subject "?G" :attrs {}}
                          {:object "?P" :relation :active    :subject "value:true" :attrs {}}]}]
        texts (bs/queries->souffle queries derived-rels)
        text (first texts)]
    (testing "decl with correct arity"
      (is (str/includes? text ".decl active_members(P:symbol, G:symbol)")))
    (testing "output directive"
      (is (str/includes? text ".output active_members(IO=stdout")))
    (testing "both relations use 2-arg form (no attrs wildcard)"
      (is (str/includes? text "zil_member_of(P, G)"))
      (is (str/includes? text "zil_active(P, \"value:true\")")))))

(deftest emit-souffle-program-test
  (let [compiled
        {:facts   [{:object "g:1" :relation :kind :subject "value:group" :attrs {}}
                   {:object "p:1" :relation :parent :subject "g:1" :attrs {}}]
         :rules   [{:name "mem"
                    :if   [{:object "?P" :relation :parent :subject "?G" :attrs {}}
                           {:object "?G" :relation :kind   :subject "value:group" :attrs {}}]
                    :then [{:object "?P" :relation :member_of :subject "?G"}]}]
         :queries [{:name "q1"
                    :find ["?P" "?G"]
                    :where [{:object "?P" :relation :member_of :subject "?G" :attrs {}}]}]}
        text (bs/emit-souffle-program compiled)]
    (testing "fact decl present"
      (is (str/includes? text ".decl zil_kind(object:symbol, subject:symbol)")))
    (testing "derived decl present"
      (is (str/includes? text ".decl zil_member_of")))
    (testing "query output present"
      (is (str/includes? text ".output q1")))
    (testing "ground fact atoms present"
      (is (str/includes? text "zil_kind(\"g:1\", \"value:group\").")))
    (testing "rule present"
      (is (str/includes? text "zil_member_of(P, G) :-")))))

(deftest emit-souffle-schema-test
  (let [compiled
        {:facts   [{:object "g:1" :relation :kind :subject "value:group" :attrs {}}]
         :rules   [{:name "mem"
                    :if   [{:object "?G" :relation :kind :subject "value:group" :attrs {}}]
                    :then [{:object "?G" :relation :is_group :subject "value:true"}]}]
         :queries [{:name "q1" :find ["?G"] :where [{:object "?G" :relation :is_group :subject "value:true" :attrs {}}]}]}
        text (bs/emit-souffle-schema compiled)]
    (testing ".input directive present (no ground atoms)"
      (is (str/includes? text ".input zil_kind"))
      (is (not (str/includes? text "zil_kind(\"g:1\""))))
    (testing "rule present in schema"
      (is (str/includes? text "zil_is_group(G, \"value:true\") :-")))))

(deftest write-facts-dir-test
  (let [facts [{:object "a:1" :relation :rel1 :subject "value:x" :attrs {}}
               {:object "a:2" :relation :rel1 :subject "value:y" :attrs {}}
               {:object "b:1" :relation :rel2 :subject "value:z" :attrs {}}
               {:object "event:sign" :relation :vc_component :subject "actor:page"
                :attrs {:counter "counter:1"}}]
        dir (bs/write-facts-dir! facts)
        rel1-file (java.io.File. dir "zil_rel1.facts")
        rel2-file (java.io.File. dir "zil_rel2.facts")
        attrs-file (java.io.File. dir "zillang_attribute_input.facts")]
    (testing "fact files created"
      (is (.exists rel1-file))
      (is (.exists rel2-file)))
    (testing "rel1 has 2 rows"
      (let [lines (str/split-lines (slurp rel1-file))]
        (is (= 2 (count lines)))
        (is (some #(= "a:1\tvalue:x" %) lines))
        (is (some #(= "a:2\tvalue:y" %) lines))))
    (testing "rel2 has 1 row"
      (let [lines (str/split-lines (slurp rel2-file))]
        (is (= 1 (count lines)))
        (is (= "b:1\tvalue:z" (first lines)))))
    (testing "named attributes survive as normalized five-column rows"
      (is (= ["zil_vc_component\tevent:sign\tactor:page\tcounter\tcounter:1"]
             (str/split-lines (slurp attrs-file)))))
    ;; cleanup
    (doseq [f (.listFiles (java.io.File. dir))] (.delete f))
    (.delete (java.io.File. dir))))

(deftest parse-souffle-stdout-schema-test
  (let [compiled
        {:facts   []
         :rules   []
         :queries [{:name "q1" :find ["?P" "?G"] :where []}
                   {:name "q2" :find ["?X"]      :where []}]}
        text (bs/emit-souffle-schema compiled)]
    (is (str/includes? text ".decl q1(P:symbol, G:symbol)"))
    (is (str/includes? text ".decl q2(X:symbol)"))))

(deftest parse-souffle-output-ignores-compiler-underline-test
  (let [output (str "Warning: generated.dl at line 53\n"
                    "  derived(X) :- source(X).\n"
                    "---------------------^------------\n"
                    "---------------\n"
                    "reachable\nX\tY\n"
                    "===============\n"
                    "a\tb\n"
                    "===============\n")]
    (is (= {"reachable" [["a" "b"]]}
           (bs/parse-souffle-stdout output)))))

;; ---------------------------------------------------------------------------
;; Integration test — only runs when Souffle is on PATH
;; ---------------------------------------------------------------------------

(deftest souffle-integration-test
  (if-not (bs/souffle-available?)
    (println "  [skip] souffle binary not found — skipping integration test")
    (let [compiled
          {:facts   [{:object "g:1"  :relation :kind   :subject "value:group"  :attrs {}}
                     {:object "g:2"  :relation :kind   :subject "value:group"  :attrs {}}
                     {:object "p:1"  :relation :parent :subject "g:1"          :attrs {}}
                     {:object "p:2"  :relation :parent :subject "g:2"          :attrs {}}
                     {:object "p:3"  :relation :parent :subject "g:1"          :attrs {}}]
           :rules   [{:name "mem"
                      :if   [{:object "?P" :relation :parent :subject "?G" :attrs {}}
                             {:object "?G" :relation :kind   :subject "value:group" :attrs {}}]
                      :then [{:object "?P" :relation :member_of :subject "?G"}]}]
           :queries [{:name "members"
                      :find ["?P" "?G"]
                      :where [{:object "?P" :relation :member_of :subject "?G" :attrs {}}]}]}
          result (bs/execute-with-souffle compiled {})]
      (is (map? (:query-results result)))
      (let [rows (get-in result [:query-results "members" :rows])]
        (is (= 3 (count rows)))
        (is (some #(= ["p:1" "g:1"] %) rows))
        (is (some #(= ["p:3" "g:1"] %) rows))
        (is (some #(= ["p:2" "g:2"] %) rows))))))

(deftest souffle-attributed-vector-clock-integration-test
  (if-not (bs/souffle-available?)
    (println "  [skip] souffle binary not found — skipping attributed tuple integration test")
    (let [source (str "MODULE vector_clock.\n"
                      "event:sign#vc_component@actor:page [counter=c1].\n"
                      "event:sign#vc_component@actor:service [counter=c0].\n"
                      "event:click#vc_component@actor:page [counter=c2].\n"
                      "c0#lt@c1.\n"
                      "c1#lt@c2.\n\n"
                      "QUERY page_order:\n"
                      "FIND ?EARLIER ?LATER WHERE ?EARLIER#vc_component@actor:page [counter=?LOW] AND "
                      "?LATER#vc_component@actor:page [counter=?HIGH] AND ?LOW#lt@?HIGH.\n")
          compiled (core/compile-program source)
          direct (set (get-in (core/execute-compiled compiled)
                              [:queries "page_order" :rows]))
          souffle (set (get-in (bs/execute-with-souffle compiled {})
                               [:query-results "page_order" :rows]))]
      (is (= #{["event:sign" "event:click"]} direct))
      (is (= direct souffle)))))
