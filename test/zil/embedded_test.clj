(ns zil.embedded-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [zil.core :as core]
            [zil.embedded :as embedded]))

(deftest lean-self-attachment-test
  (let [source "/-\n@zil target=self\nself#formalizes@claim:monotone.\nself#requires@assumption:positive.\n@endzil\n-/\ntheorem Analysis.monotone : True := by trivial\n"
        report (embedded/scan-text "Acme/Analysis.lean" source)
        block (first (:blocks report))]
    (is (= :lean4 (:language report)))
    (is (= "lean:Analysis.monotone" (:target block)))
    (is (= :asserted_annotation (:trust block)))
    (is (= ["lean:Analysis.monotone#formalizes@claim:monotone."
            "lean:Analysis.monotone#requires@assumption:positive."] (:statements block)))
    (is (str/starts-with? (:source_hash report) "sha256:"))))

(deftest portable-comment-prefixes-and-explicit-target-test
  (doseq [[path source expected]
          [["agent.py" "# @zil target=python:publish\n# self#purpose@operation:publish.\n# @endzil\ndef ignored(): pass\n" "python:publish"]
           ["agent.clj" ";; @zil\n;; self#purpose@operation:resolve.\n;; @endzil\n(defn resolve-context [] nil)\n" "clojure:resolve-context"]
           ["agent.rs" "// @zil\n// self#purpose@operation:run.\n// @endzil\npub fn run() {}\n" "rust:run"]]]
    (is (= expected (-> (embedded/scan-text path source) :blocks first :target)))))

(deftest rendered-output-is-canonical-zil-test
  (let [report (embedded/scan-text "Demo.lean"
                "/-\n@zil\nself#formalizes@claim:demo.\n@endzil\n-/\ntheorem Demo.answer : True := by trivial\n")
        compiled (core/compile-program (embedded/render-zil [report] "embedded.demo"))]
    (is (= "embedded.demo" (:module compiled)))
    (is (some #(and (= "lean:Demo.answer" (:object %)) (= :formalizes (:relation %))
                    (= "claim:demo" (:subject %))) (:facts compiled)))))

(deftest missing-declaration-is-rejected-test
  (is (thrown-with-msg? clojure.lang.ExceptionInfo #"no following host declaration"
        (embedded/scan-text "orphan.py"
          "# @zil\n# self#purpose@operation:none.\n# @endzil\n"))))

(deftest embedded-macro-reuses-standalone-expander-test
  (let [macro-text "MACRO LINK(owner, claim):\nEMIT {{owner}}#formalizes@{{claim}}.\nEMIT {{claim}}#formalized_by@{{owner}}.\nENDMACRO.\n"
        source "/-\n@zil\nUSE LINK(self, claim:demo).\n@endzil\n-/\ntheorem Demo.answer : True := by trivial\n"
        statements (-> (embedded/scan-text "Demo.lean" source {:macro-text macro-text})
                       :blocks first :statements)
        macro-revision (-> (embedded/scan-text "Demo.lean" source {:macro-text macro-text})
                           :blocks first :macro_revision)]
    (is (= ["lean:Demo.answer#formalizes@claim:demo."
            "claim:demo#formalized_by@lean:Demo.answer."] statements))
    (is (str/starts-with? macro-revision "sha256:"))))

(deftest embedded-drift-classifies-source-target-macro-and-expansion-test
  (let [source "/-\n@zil\nUSE LINK(self, claim:demo).\n@endzil\n-/\ntheorem Demo.answer : True := by trivial\n"
        macro-a "MACRO LINK(owner, claim):\nEMIT {{owner}}#formalizes@{{claim}}.\nENDMACRO.\n"
        macro-b "MACRO LINK(owner, claim):\nEMIT {{owner}}#supports@{{claim}}.\nENDMACRO.\n"
        block-a (-> (embedded/scan-text "Demo.lean" source {:macro-text macro-a}) :blocks first)
        block-b (-> (embedded/scan-text "Demo.lean" (str "\n" source) {:macro-text macro-b}) :blocks first)
        report (embedded/drift-between
                {:format embedded/snapshot-format :blocks [block-a]}
                {:format embedded/snapshot-format :blocks [block-b]})
        kinds (set (map :kind (:differences report)))]
    (is (= (:block_id block-a) (:block_id block-b)))
    (is (:drift report))
    (is (contains? kinds :source_changed))
    (is (contains? kinds :macro_changed))
    (is (contains? kinds :expansion_changed))))

(deftest host-aware-macro-context-test
  (let [macro-text (str "MACRO CONTEXT(owner, file, module, namespace, project, revision, declaration_kind, source_span):\n"
                        "EMIT {{owner}}#source_file@{{file}}.\n"
                        "EMIT {{owner}}#defined_in@{{module}}.\n"
                        "EMIT {{owner}}#namespace@{{namespace}}.\n"
                        "EMIT {{owner}}#project@{{project}}.\n"
                        "EMIT {{owner}}#revision@{{revision}}.\n"
                        "EMIT {{owner}}#declaration_kind@{{declaration_kind}}.\n"
                        "EMIT {{owner}}#source_span@{{source_span}}.\nENDMACRO.\n")
        source "/-\n@zil\nUSE CONTEXT(self, file, module, namespace, project, revision, declaration_kind, source_span).\n@endzil\n-/\ntheorem Demo.answer : True := by trivial\n"
        block (-> (embedded/scan-text "Acme/Demo.lean" source
                                      {:macro-text macro-text :project "acme"})
                  :blocks first)
        text (str/join "\n" (:statements block))]
    (is (= "theorem" (:declaration_kind block)))
    (is (str/includes? text "file:Acme/Demo.lean"))
    (is (str/includes? text "lean_module:Acme.Demo"))
    (is (str/includes? text "lean_namespace:Demo"))
    (is (str/includes? text "project:acme"))
    (is (str/includes? text "lean4_kind:theorem"))
    (is (str/includes? text "source_span:Acme/Demo.lean:2-4"))))

(deftest lean-named-namespace-self-resolution-test
  (let [source "namespace Demo\n\n/-\n@zil\nself#documents@concept:test.\n@endzil\n-/\ntheorem answer : True := by trivial\n\nend Demo\n"]
    (is (= "lean:Demo.answer"
           (-> (embedded/scan-text "Demo.lean" source) :blocks first :target)))))
