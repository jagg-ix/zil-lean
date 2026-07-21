(ns zil.preprocess
  "Tiny source preprocessor for import-like composition.
  Concatenates `lib/*.zc` before a model file without changing core semantics."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]))

(defn- parent-chain
  [^java.io.File dir]
  (take-while some? (iterate #(.getParentFile ^java.io.File %) dir)))

(defn- zc-file?
  [^java.io.File f]
  (and (.isFile f)
       (str/ends-with? (.getName f) ".zc")))

(defn- render-block
  [label text]
  (str "// ---- begin " label " ----\n"
       text
       (when-not (str/ends-with? text "\n") "\n")
       "// ---- end " label " ----\n"))

(defn resolve-lib-dir
  "Resolve lib dir.
  Priority:
  1) explicit `lib-dir`
  2) nearest ancestor of model path containing `lib/` directory."
  [model-path lib-dir]
  (if lib-dir
    (io/file lib-dir)
    (let [mf (-> model-path io/file .getAbsoluteFile)
          start (if (.isDirectory mf) mf (.getParentFile mf))]
      (some (fn [^java.io.File d]
              (let [cand (io/file d "lib")]
                (when (.isDirectory cand) cand)))
            (parent-chain start)))))

(defn collect-lib-zc-files
  "Collect `lib/*.zc` files (non-recursive), sorted by file name."
  [model-path lib-dir]
  (let [resolved (resolve-lib-dir model-path lib-dir)]
    (if (and resolved (.isDirectory ^java.io.File resolved))
      (->> (.listFiles ^java.io.File resolved)
           (filter zc-file?)
           (sort-by #(.getName ^java.io.File %))
           vec)
      [])))

(defn preprocess-model
  "Build preprocessed text from model path + optional lib dir.
  Options:
  - :lib-dir path to explicit lib directory (default: auto-discover)
  - :output-path where to write preprocessed text"
  [model-path {:keys [lib-dir output-path]}]
  (let [mf (io/file model-path)]
    (when-not (.exists mf)
      (throw (ex-info "Model path does not exist for preprocess" {:path model-path})))
    (when-not (.isFile mf)
      (throw (ex-info "Model path must be a file for preprocess" {:path model-path})))
    (let [lib-files (collect-lib-zc-files model-path lib-dir)
          libs-text (->> lib-files
                         (map (fn [^java.io.File f]
                                (render-block
                                 (str "lib/" (.getName f))
                                 (slurp f))))
                         (str/join "\n"))
          model-text (render-block (.getName mf) (slurp mf))
          text (if (str/blank? libs-text)
                 model-text
                 (str libs-text "\n" model-text))
          report {:ok true
                  :model (.getAbsolutePath mf)
                  :lib_dir (some-> (resolve-lib-dir model-path lib-dir) .getAbsolutePath)
                  :lib_files (mapv #(.getAbsolutePath ^java.io.File %) lib-files)
                  :text text}]
      (if output-path
        (do
          (spit output-path text)
          (assoc report :output_path output-path))
        report))))
