(ns zil.port-verify-test
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [zil.port.library :as library]
            [zil.port.verify :as verify]))

(defn- temp-dir []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-generated-verify-test"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(defn- write! [file content]
  (when-let [parent (.getParentFile (io/file file))] (.mkdirs parent))
  (spit file content)
  (io/file file))

(defn- entry [source output namespace status]
  {:source (.getCanonicalPath (io/file source))
   :root (.getCanonicalPath (.getParentFile (io/file source)))
   :relative (.getName (io/file source))
   :output (.getCanonicalPath (io/file output))
   :namespace namespace
   :source-sha256 (library/file-sha256 source)
   :output-sha256 (library/file-sha256 output)
   :status status})

(defn- manifest! [workspace output-root entries]
  (let [file (io/file workspace "manifest.edn")
        data {:schema "ZIL-LIBRARY-MANIFEST/1"
              :roots [(.getCanonicalPath workspace)]
              :output-root (.getCanonicalPath output-root)
              :entries (vec entries)}]
    (spit file (str (pr-str data) "\n"))
    file))

(deftest verifies-each-module-and-sorted-aggregate-test
  (let [workspace (temp-dir)
        source-a (write! (io/file workspace "a.zc") "doc:a#owner@user:1.\n")
        source-b (write! (io/file workspace "b.zc") "doc:b#owner@user:2.\n")
        output-root (io/file workspace "generated")
        output-a (write! (io/file output-root "A.lean") "import Zil\nnamespace Demo.A\nend Demo.A\n")
        output-b (write! (io/file output-root "B.lean") "import Zil\nnamespace Demo.B\nend Demo.B\n")
        manifest (manifest! workspace output-root
                            [(entry source-b output-b "Demo.B" :compiled)
                             (entry source-a output-a "Demo.A" :compiled)])
        calls (atom [])
        runner (fn [request]
                 (swap! calls conj request)
                 {:exit 0 :out "" :err "" :command (:command request)})
        report-file (io/file workspace "verification.edn")
        aggregate (io/file output-root "All.lean")
        report (verify/verify-manifest!
                {:manifest (.getPath manifest)
                 :output (.getPath report-file)
                 :aggregate (.getPath aggregate)
                 :command ["fake-lean"]
                 :runner runner})]
    (is (:ok report))
    (is (= 2 (:verified report)))
    (is (= :verified (get-in report [:aggregate :status])))
    (is (= "import Demo.A\nimport Demo.B\n" (slurp aggregate)))
    (is (= 3 (count @calls)))
    (is (= (.getCanonicalPath aggregate)
           (last (:command (last @calls)))))
    (is (str/includes? (get-in (last @calls) [:environment "LEAN_PATH"])
                       (.getCanonicalPath output-root)))
    (is (= "ZIL-LEAN-VERIFY/1"
           (:schema (edn/read-string (slurp report-file)))))))

(deftest hash-drift-blocks-processes-and-aggregate-test
  (let [workspace (temp-dir)
        source (write! (io/file workspace "model.zc") "doc:a#owner@user:1.\n")
        output-root (io/file workspace "generated")
        output (write! (io/file output-root "Model.lean") "import Zil\n")
        stale-entry (assoc (entry source output "Demo.Model" :compiled)
                           :output-sha256 (apply str (repeat 64 "0")))
        manifest (manifest! workspace output-root [stale-entry])
        calls (atom [])
        report (verify/verify-manifest!
                {:manifest (.getPath manifest)
                 :output (.getPath (io/file workspace "verification.edn"))
                 :aggregate (.getPath (io/file output-root "All.lean"))
                 :runner (fn [request]
                           (swap! calls conj request)
                           {:exit 0 :out "" :err "" :command (:command request)})})]
    (is (false? (:ok report)))
    (is (= :hash-mismatch (get-in report [:entries 0 :status])))
    (is (= :blocked (get-in report [:aggregate :status])))
    (is (empty? @calls))))

(deftest module-failure-blocks-aggregate-test
  (let [workspace (temp-dir)
        source-a (write! (io/file workspace "a.zc") "doc:a#owner@user:1.\n")
        source-b (write! (io/file workspace "b.zc") "doc:b#owner@user:2.\n")
        output-root (io/file workspace "generated")
        output-a (write! (io/file output-root "A.lean") "import Zil\n")
        output-b (write! (io/file output-root "B.lean") "import Zil\n")
        manifest (manifest! workspace output-root
                            [(entry source-a output-a "Demo.A" :compiled)
                             (entry source-b output-b "Demo.B" :compiled)])
        calls (atom [])
        runner (fn [request]
                 (swap! calls conj request)
                 (if (str/ends-with? (last (:command request)) "A.lean")
                   {:exit 1 :out "" :err "type error" :command (:command request)}
                   {:exit 0 :out "" :err "" :command (:command request)}))
        report (verify/verify-manifest!
                {:manifest (.getPath manifest)
                 :output (.getPath (io/file workspace "verification.edn"))
                 :aggregate (.getPath (io/file output-root "All.lean"))
                 :runner runner})]
    (is (false? (:ok report)))
    (is (= :failed (get-in report [:entries 0 :status])))
    (is (= "type error" (get-in report [:entries 0 :error])))
    (is (= :blocked (get-in report [:aggregate :status])))
    (is (= 2 (count @calls)))))

(deftest no-aggregate-mode-still-verifies-modules-test
  (let [workspace (temp-dir)
        source (write! (io/file workspace "model.zc") "doc:a#owner@user:1.\n")
        output-root (io/file workspace "generated")
        output (write! (io/file output-root "Model.lean") "import Zil\n")
        manifest (manifest! workspace output-root
                            [(entry source output "Demo.Model" :compiled)])
        calls (atom [])
        report (verify/verify-manifest!
                {:manifest (.getPath manifest)
                 :output (.getPath (io/file workspace "verification.edn"))
                 :aggregate (.getPath (io/file output-root "All.lean"))
                 :write-aggregate false
                 :runner (fn [request]
                           (swap! calls conj request)
                           {:exit 0 :out "" :err "" :command (:command request)})})]
    (is (:ok report))
    (is (= :skipped (get-in report [:aggregate :status])))
    (is (= :disabled (get-in report [:aggregate :reason])))
    (is (= 1 (count @calls)))))

(deftest rejects-duplicate-or-empty-manifests-test
  (let [workspace (temp-dir)
        output-root (io/file workspace "generated")
        empty-manifest (io/file workspace "empty.edn")]
    (spit empty-manifest
          (pr-str {:schema "ZIL-LIBRARY-MANIFEST/1"
                   :output-root (.getCanonicalPath output-root)
                   :entries []}))
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"contains no generated modules"
                          (verify/read-manifest! empty-manifest))))
  (let [workspace (temp-dir)
        source-a (write! (io/file workspace "a.zc") "doc:a#owner@user:1.\n")
        source-b (write! (io/file workspace "b.zc") "doc:b#owner@user:2.\n")
        output-root (io/file workspace "generated")
        output-a (write! (io/file output-root "A.lean") "import Zil\n")
        output-b (write! (io/file output-root "B.lean") "import Zil\n")
        duplicate (manifest! workspace output-root
                             [(entry source-a output-a "Demo.Same" :compiled)
                              (entry source-b output-b "Demo.Same" :compiled)])]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"duplicate generated identities"
                          (verify/read-manifest! duplicate)))))
