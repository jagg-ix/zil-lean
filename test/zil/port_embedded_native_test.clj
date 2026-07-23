(ns zil.port-embedded-native-test
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.port.embedded-native :as native]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-embedded-native-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [root relative content]
  (let [file (io/file root relative)]
    (when-let [parent (.getParentFile file)] (.mkdirs parent))
    (spit file content)
    file))

(def host-fixtures
  {"Model.lean"
   (str "namespace Demo\n\n/-\n@zil\n"
        "self#formalizes@claim:lean.\n"
        "@endzil\n-/\n"
        "theorem answer : True := by trivial\n\nend Demo\n")

   "worker.py"
   (str "# @zil\n"
        "# self#purpose@operation:python.\n"
        "# @endzil\n"
        "def work():\n    return True\n")

   "resolver.clj"
   (str ";; @zil\n"
        ";; self#purpose@operation:clojure.\n"
        ";; @endzil\n"
        "(defn resolve-item [] true)\n")

   "runner.rs"
   (str "// @zil\n"
        "// self#purpose@operation:rust.\n"
        "// @endzil\n"
        "pub fn run() {}\n")

   "guide.md"
   (str "@zil target=markdown:guide\n"
        "self#documents@concept:guide.\n"
        "@endzil\n")})

(defn- populate! [root]
  (doseq [[relative content] host-fixtures]
    (write! root relative content)))

(defn- compile-request? [request]
  (some #{"compile"} (:command request)))

(defn- fake-runner [calls]
  (fn [request]
    (if (compile-request? request)
      (let [command (:command request)
            source-path (nth command (- (count command) 3))
            namespace (last command)
            source (slurp source-path)]
        (swap! calls conj {:phase :compile
                           :command command
                           :source source
                           :namespace namespace
                           :environment (:environment request)})
        {:exit 0
         :out (str "import Zil\nnamespace " namespace "\nend " namespace "\n")
         :err ""
         :command command})
      (do
        (swap! calls conj {:phase :verify
                           :command (:command request)
                           :environment (:environment request)})
        {:exit 0 :out "" :err "" :command (:command request)}))))

(deftest compiles-and-verifies-blocks-from-all-supported-host-languages-test
  (let [workspace (temp-dir)
        root (io/file workspace "hosts")
        _ (populate! root)
        output (io/file workspace "generated")
        manifest (io/file workspace "manifest.edn")
        calls (atom [])
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath output)
                 :manifest (.getPath manifest)
                 :namespace-prefix "Project.Embedded"
                 :command ["fake-zil" "compile"]
                 :verify-command ["fake-lean"]
                 :runner (fake-runner calls)
                 :require-blocks true})
        languages (set (map :language (:entries report)))
        targets (set (map :target (:entries report)))
        compile-calls (filter #(= :compile (:phase %)) @calls)
        verify-calls (filter #(= :verify (:phase %)) @calls)]
    (is (:ok report))
    (is (= 5 (:block-count report)))
    (is (= 5 (:verified report)))
    (is (:verify-generated report))
    (is (= #{"lean4" "python" "clojure" "rust" "markdown"} languages))
    (is (contains? targets "lean:Demo.answer"))
    (is (contains? targets "python:work"))
    (is (contains? targets "clojure:resolve-item"))
    (is (contains? targets "rust:run"))
    (is (contains? targets "markdown:guide"))
    (is (every? #(= :verified (:status %)) (:entries report)))
    (is (every? #(.exists (io/file (:output %))) (:entries report)))
    (is (= 10 (count @calls)))
    (is (= 5 (count compile-calls)))
    (is (= 5 (count verify-calls)))
    (is (every? #(str/starts-with? (:source %) "MODULE embedded.block.") compile-calls))
    (is (every? #(str/includes? (get-in % [:environment "LEAN_PATH"])
                                (.getCanonicalPath output))
                verify-calls))
    (is (= "ZIL-EMBEDDED-MANIFEST/1"
           (:schema (edn/read-string (slurp manifest)))))))

(deftest manifest-retains-line-and-host-source-map-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        host (write! root "nested/Model.lean" (get host-fixtures "Model.lean"))
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :runner (fake-runner (atom []))})
        entry (first (:entries report))]
    (is (= (.getCanonicalPath host) (:host entry)))
    (is (= "nested/Model.lean" (:relative entry)))
    (is (= 4 (:start_line entry)))
    (is (= 6 (:end_line entry)))
    (is (str/starts-with? (:source_hash entry) "sha256:"))
    (is (str/starts-with? (:macro_revision entry) "sha256:"))
    (is (= 64 (count (:zc-sha256 entry))))
    (is (str/includes? (:lean-namespace entry) "Nested.Model.Block0"))
    (is (= :verified (:status entry)))))

(deftest native-compile-failure-is-recorded-without-writing-output-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "Model.lean" (get host-fixtures "Model.lean"))
        calls (atom [])
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :runner (fn [request]
                           (swap! calls conj request)
                           {:exit 1 :out "" :err "native parse error"
                            :command (:command request)})})
        entry (first (:entries report))]
    (is (false? (:ok report)))
    (is (= :failed (:status entry)))
    (is (= :compile (:phase entry)))
    (is (= "native parse error" (:error entry)))
    (is (not (.exists (io/file (:output entry)))))
    (is (= 1 (count @calls)))))

(deftest generated-elaboration-failure-is-recorded-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "Model.lean" (get host-fixtures "Model.lean"))
        calls (atom [])
        runner (fn [request]
                 (swap! calls conj request)
                 (if (compile-request? request)
                   {:exit 0 :out "import Missing.Module\n" :err ""
                    :command (:command request)}
                   {:exit 1 :out "" :err "unknown module Missing.Module"
                    :command (:command request)}))
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :runner runner})
        entry (first (:entries report))]
    (is (false? (:ok report)))
    (is (= :verification-failed (:status entry)))
    (is (= :verify (:phase entry)))
    (is (= "unknown module Missing.Module" (:error entry)))
    (is (.exists (io/file (:output entry))))
    (is (= 2 (count @calls)))))

(deftest check-only-validates-source-without-writing-or-elaborating-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "worker.py" (get host-fixtures "worker.py"))
        calls (atom [])
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :check-only true
                 :runner (fake-runner calls)})
        entry (first (:entries report))]
    (is (:ok report))
    (is (= :checked (:status entry)))
    (is (not (.exists (io/file (:output entry)))))
    (is (= 1 (count @calls)))
    (is (= :compile (:phase (first @calls))))))

(deftest no-verify-mode-generates-without-elaboration-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "worker.py" (get host-fixtures "worker.py"))
        calls (atom [])
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :verify-generated false
                 :runner (fake-runner calls)})
        entry (first (:entries report))]
    (is (:ok report))
    (is (false? (:verify-generated report)))
    (is (= :compiled (:status entry)))
    (is (.exists (io/file (:output entry))))
    (is (= 1 (count @calls)))))

(deftest scan-errors-and-required-empty-corpus-fail-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "orphan.py"
                  "# @zil\n# self#purpose@operation:none.\n# @endzil\n")
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :runner (fake-runner (atom []))})]
    (is (false? (:ok report)))
    (is (= 1 (count (:scan-errors report)))))
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "empty.py" "def no_annotation():\n    pass\n")
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :require-blocks true
                 :runner (fake-runner (atom []))})]
    (is (false? (:ok report)))
    (is (= :no-embedded-blocks (get-in report [:failures 0 :kind])))))

(deftest rejects-cross-root-block-identity-collisions-test
  (let [workspace (temp-dir)
        root-a (io/file workspace "one/src")
        root-b (io/file workspace "two/src")
        _ (write! root-a "Model.lean" (get host-fixtures "Model.lean"))
        _ (write! root-b "Model.lean" (get host-fixtures "Model.lean"))]
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"contains collisions"
         (native/plan {:roots [(.getPath root-a) (.getPath root-b)]
                       :output-root (.getPath (io/file workspace "generated"))}))))
