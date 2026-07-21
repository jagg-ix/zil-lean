(ns zil.bridge-lean-events-test
  (:require [clojure.data.json :as json]
            [clojure.test :refer [deftest is]]
            [zil.bridge.lean-events :as events]
            [zil.core :as core]))

(def valid-batch
  {"format" "zil.lean-events.v0.1"
   "profile" "lean-declarations-v0.1"
   "complete" true
   "lean_version" "4.32.0"
   "module" "Demo"
   "event_count" 1
   "events" [{"operation" "linkLeanDecl"
               "declaration" "Demo.answer"
               "module" "Demo"
               "kind" "theorem"
               "kernel_present" true
               "trust" "kernel_checked_term"
               "uses_sorry" false
               "zil_claim" "demo.answer"
               "zil_concept" "demo.concept"
               "zil_requires" "demo.foundation"
               "zil_export" true
               "zil_attachments" [{"object" {"symbol" "lean:Demo.answer"}
                                    "relation" "requires"
                                    "subject" {"symbol" "assumption:demo"}
                                    "module" "Demo"
                                    "declaration_kind" "theorem"
                                    "trust" "elaboration_validated"
                                    "source_span" {"file" "Demo.lean"
                                                   "start_line" 10 "start_column" 0
                                                   "end_line" 11 "end_column" 30}}]
               "proved_claim" false
               "type_fingerprint" "lean-hash:1"
               "dependencies" ["Nat"]}]})

(deftest lean-events-lower-to-compilable-zil-test
  (let [text (events/render-zil (events/validate-batch! valid-batch) "lean.events.demo")
        compiled (core/compile-program text)]
    (is (= "lean.events.demo" (:module compiled)))
    (is (some #(and (= :proved_claim (:relation %))
                    (= "value:false" (:subject %))) (:facts compiled)))
    (is (some #(and (= "lean:Demo.answer" (:object %))
                    (= :formalizes (:relation %))
                    (= "claim:demo.answer" (:subject %))) (:facts compiled)))
    (is (some #(and (= "claim:demo.answer" (:object %))
                    (= :formalized_by (:relation %))
                    (= "lean:Demo.answer" (:subject %))) (:facts compiled)))
    (is (some #(and (= "lean:Demo.answer" (:object %))
                    (= :mentions (:relation %))
                    (= "concept:demo.concept" (:subject %))) (:facts compiled)))
    (is (some #(and (= :export_selected (:relation %))
                    (= "value:true" (:subject %))) (:facts compiled)))
    (is (some #(and (= "lean:Demo.answer" (:object %))
                    (= :requires (:relation %))
                    (= "assumption:demo.foundation" (:subject %))) (:facts compiled)))
    (is (some #(and (= "assumption:demo.foundation" (:object %))
                    (= :required_by (:relation %))
                    (= "lean:Demo.answer" (:subject %))) (:facts compiled)))
    (is (some #(and (= "lean:Demo.answer" (:object %))
                    (= :requires (:relation %))
                    (= "assumption:demo" (:subject %))) (:facts compiled)))
    (is (some #(= :depends_on (:relation %)) (:facts compiled)))))

(deftest proved-claim-escalation-is-rejected-test
  (let [bad (assoc-in valid-batch ["events" 0 "proved_claim"] true)]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"must not directly assert"
                          (events/validate-batch! bad)))))
