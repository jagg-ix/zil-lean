(ns zil.interop
  "Interop helpers for consuming and producing JSON/YAML/CSV around ZIL models."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.core :as core]
            [zil.lower :as zl]
            [zil.runtime.codec :as rc]))

(defn infer-format
  [path]
  (let [name (-> (io/file path) .getName str/lower-case)]
    (cond
      (str/ends-with? name ".json") :json
      (or (str/ends-with? name ".yaml")
          (str/ends-with? name ".yml")) :yaml
      (str/ends-with? name ".csv") :csv
      (str/ends-with? name ".edn") :edn
      (str/ends-with? name ".kv") :kv
      (str/ends-with? name ".txt") :text
      :else nil)))

(defn- ensure-format
  [path fmt]
  (or (rc/normalize-format fmt)
      (infer-format path)
      (throw (ex-info "Could not infer interop format from file extension; pass format explicitly."
                      {:path path}))))

(defn- sanitize-token
  [x]
  (-> (str x)
      str/lower-case
      (str/replace #"[^a-z0-9_:\-\.]+" "_")
      (str/replace #"^_+|_+$" "")
      (#(if (str/blank? %) "value" %))))

(defn- relation-key
  [k]
  (cond
    (keyword? k) (keyword (sanitize-token (name k)))
    :else (keyword (sanitize-token k))))

(defn- render-fact-line
  [object relation subject]
  (str object "#" (name relation) "@" subject "."))

(defn- record-fact-lines
  [record-prefix idx record]
  (let [object (str record-prefix ":" (inc idx))
        record* (if (map? record) record {:value record})]
    (vec
     (concat
      [(render-fact-line object :kind "entity:interop_record")]
      (for [[k v] record*]
        (render-fact-line object
                          (relation-key k)
                          (zl/subject-value v)))))))

(defn import-data->zil
  "Import one JSON/YAML/CSV/EDN/KV/TEXT payload as generated ZIL facts.

  Options:
  - :format       explicit format keyword/string (default: infer from input path)
  - :module-name  output module name (default: interop.import)
  - :record-prefix object prefix for generated records (default: interop:record)
  - :output-path  optional file path for writing generated ZIL text"
  ([input-path] (import-data->zil input-path {}))
  ([input-path {:keys [format module-name record-prefix output-path]
                :or {module-name "interop.import"
                     record-prefix "interop:record"}}]
   (let [fmt (ensure-format input-path format)
         payload (rc/parse-string fmt (slurp input-path) {:path input-path})
         records (rc/records-from-decoded payload)
         fact-lines (mapcat #(record-fact-lines record-prefix %1 %2)
                            (range)
                            records)
         text (str (str "MODULE " module-name ".\n\n")
                   (str/join "\n" fact-lines)
                   "\n")
         report {:ok true
                 :input (.getAbsolutePath (io/file input-path))
                 :format fmt
                 :module module-name
                 :records (count records)
                 :facts (count fact-lines)
                 :text text}]
     (if output-path
       (do
         (spit output-path text)
         (assoc report :output_path output-path))
       report))))

(defn- query-var->key
  [v]
  (-> (str v)
      (str/replace #"^\?" "")
      sanitize-token
      keyword))

(defn- query-rows->maps
  [{:keys [vars rows]}]
  (let [keys* (mapv query-var->key vars)]
    (mapv (fn [row] (zipmap keys* row)) rows)))

(defn- select-export-payload
  [result source]
  (let [queries (:queries result)
        source* (or source "queries")]
    (cond
      (= source* "facts")
      (:facts result)

      (= source* "queries")
      (into {}
            (for [[q qres] queries]
              [q (query-rows->maps qres)]))

      :else
      (if-let [qres (get queries source*)]
        (query-rows->maps qres)
        (throw (ex-info "Unknown export source. Use `facts`, `queries`, or a query name."
                        {:source source*
                         :queries (-> queries keys sort vec)}))))))

(defn export-model-data
  "Execute a ZIL model and export selected payload in interop format.

  Options:
  - :format       json|yaml|yml|csv|edn|kv|text (default: json)
  - :source       facts|queries|<query-name> (default: queries)
  - :output-path  optional target file path"
  ([model-path] (export-model-data model-path {}))
  ([model-path {:keys [format source output-path]
                :or {format :json
                     source "queries"}}]
   (let [fmt (rc/normalize-format format)
         result (core/execute-file model-path)
         payload (select-export-payload result source)]
     (when (and (= fmt :csv) (map? payload))
       (throw (ex-info "CSV export requires a single tabular source. Use :source <query-name>."
                       {:source source})))
     (let [text (rc/emit-string fmt payload {:source source})
           report {:ok true
                   :model (.getAbsolutePath (io/file model-path))
                   :format fmt
                   :source source
                   :bytes (count (.getBytes ^String text "UTF-8"))
                   :text text}]
       (if output-path
         (do
           (spit output-path text)
           (assoc report :output_path output-path))
         report)))))
