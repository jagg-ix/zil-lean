(ns build
  "Build helpers for producing a standalone ZIL uberjar.

  Output:
  - dist/zil-standalone.jar

  Runtime:
  - `java -jar dist/zil-standalone.jar ...`
  "
  (:require [clojure.tools.build.api :as b]))

(def lib 'zil/zil)
(def class-dir "target/classes")
(def uber-file "dist/zil-standalone.jar")

(defn clean
  "Remove generated build outputs."
  [_]
  (b/delete {:path "target"})
  (b/delete {:path "dist"})
  {:ok true
   :cleaned ["target" "dist"]})

(defn uber
  "Build a standalone uberjar with `zil.cli` as the entrypoint."
  [_]
  (let [basis (b/create-basis {:project "deps.edn"})
        version (format "0.1.%s" (b/git-count-revs nil))
        jar-type "uber"]
    (b/delete {:path "target"})
    (b/delete {:path "dist"})
    (b/copy-dir {:src-dirs ["src"]
                 :target-dir class-dir})
    (b/compile-clj {:basis basis
                    :src-dirs ["src"]
                    :class-dir class-dir
                    :ns-compile '[zil.cli]})
    (b/uber {:class-dir class-dir
             :uber-file uber-file
             :basis basis
             :main 'zil.cli})
    (b/write-pom {:class-dir class-dir
                  :lib lib
                  :version version
                  :basis basis
                  :src-dirs ["src"]})
    {:ok true
     :jar-type jar-type
     :version version
     :uber-file uber-file}))
