(ns zil.runtime.adapters.file
  "File adapter.

  Supports:
  - mode=lines|text|edn (legacy)
  - format=json|yaml|yml|csv|kv (interop codecs)"
  (:require [clojure.edn :as edn]
            [clojure.string :as str]
            [zil.runtime.codec :as rc]
            [zil.runtime.adapters.core :as ac]))

(defn- parse-lines
  [path]
  (->> (slurp path)
       str/split-lines
       (map-indexed (fn [idx line]
                      {:line_number (inc idx)
                       :line line}))
       vec))

(defn read-file
  [datasource _opts]
  (let [attrs (:attrs datasource)
        path (or (:path attrs) (:file attrs))
        mode (some-> (:mode attrs) ac/normalize-type)
        format (rc/normalize-format (:format attrs))
        effective (or mode format :lines)]
    (when-not path
      (throw (ex-info "FILE datasource requires :path"
                      {:datasource datasource})))
    (case effective
      :lines (parse-lines path)
      :text [{:text (slurp path)}]
      :edn (let [v (edn/read-string (slurp path))]
             (if (sequential? v) (vec v) [v]))
      :json (rc/records-from-decoded (rc/parse-string :json (slurp path) attrs))
      :csv (rc/records-from-decoded (rc/parse-string :csv (slurp path) attrs))
      :yaml (rc/records-from-decoded (rc/parse-string :yaml (slurp path) attrs))
      :yml (rc/records-from-decoded (rc/parse-string :yml (slurp path) attrs))
      :kv (rc/records-from-decoded (rc/parse-string :kv (slurp path) attrs))
      (throw (ex-info "Unsupported FILE mode"
                      {:mode effective :datasource datasource})))))

(ac/register-adapter! :file read-file)
