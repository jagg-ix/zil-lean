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

(defn- fake-runner [calls]
  (fn [command]
    (let [source-path (nth command (- (count command) 3))
          namespace (last command)
          source (slurp source-path)]
      (swap! calls conj {:command command :source source :namespace namespace})
      {:exit 0
       :out (str "import Zil\nnamespace " namespace "\nend " namespace "\n")
       :err ""
       :command command})))

(deftest compiles-blocks-from-all-supported-host-languages-test
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
                 :runner (fake-runner calls)
                 :require-blocks true})
        languages (set (map :language (:entries report)))
        targets (set (map :target (:entries report)))]
    (is (:ok report))
    (is (= 5 (:block-count report)))
    (is (= #{"lean4" "python" "clojure" "rust" "markdown"} languages))
    (is (contains? targets "lean:Demo.answer"))
    (is (contains? targets "python:work"))
    (is (contains? targets "clojure:resolve-item"))
    (is (contains? targets "rust:run"))
    (is (contains? targets "markdown:guide"))
    (is (every? #(= :compiled (:status %)) (:entries report)))
    (is (every? #(.exists (io/file (:output %))) (:entries report)))
    (is (= 5 (count @calls)))
    (is (every? #(str/starts-with? (:source %) "MODULE embedded.block.") @calls))
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
    (is (str/includes? (:lean-namespace entry) "Nested.Model.Block0"))))

(deftest native-failure-is-recorded-without-writing-output-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "Model.lean" (get host-fixtures "Model.lean"))
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :runner (fn [command]
                           {:exit 1 :out "" :err "native parse error" :command command})})
        entry (first (:entries report))]
    (is (false? (:ok report)))
    (is (= :failed (:status entry)))
    (is (= "native parse error" (:error entry)))
    (is (not (.exists (io/file (:output entry)))))))

(deftest check-only-validates-without-writing-output-test
  (let [workspace (temp-dir)
        root (io/file workspace "src")
        _ (write! root "worker.py" (get host-fixtures "worker.py"))
        report (native/compile-embedded!
                {:roots [(.getPath root)]
                 :output-root (.getPath (io/file workspace "generated"))
                 :manifest (.getPath (io/file workspace "manifest.edn"))
                 :check-only true
                 :runner (fake-runner (atom []))})
        entry (first (:entries report))]
    (is (:ok report))
    (is (= :checked (:status entry)))
    (is (not (.exists (io/file (:output entry)))))))

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
