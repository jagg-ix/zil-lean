(ns zil.runtime.codec
  "Format codec registry used by adapters and interop tooling.

  Goals:
  - one expansion point for wire/file formats
  - parser + emitter pairing per format
  - lightweight defaults for json/yaml/csv interoperability"
  (:require [clojure.data.json :as json]
            [clojure.edn :as edn]
            [clojure.string :as str]))

(defonce ^:private codec-registry
  (atom {}))

(defn normalize-format
  [fmt]
  (cond
    (keyword? fmt) fmt
    (string? fmt) (-> fmt str/trim str/lower-case keyword)
    (nil? fmt) nil
    :else (-> fmt str str/trim str/lower-case keyword)))

(defn register-codec!
  [fmt {:keys [parse emit aliases]}]
  (let [k (normalize-format fmt)
        entry {:parse parse
               :emit emit}]
    (when-not (and k parse emit)
      (throw (ex-info "Invalid codec registration"
                      {:format fmt :has_parse (boolean parse) :has_emit (boolean emit)})))
    (swap! codec-registry assoc k entry)
    (doseq [a aliases]
      (swap! codec-registry assoc (normalize-format a) entry))
    k))

(defn supported-formats
  []
  (->> @codec-registry keys sort vec))

(defn codec-for
  [fmt]
  (get @codec-registry (normalize-format fmt)))

(defn parse-string
  [fmt text opts]
  (let [k (normalize-format fmt)
        {:keys [parse]} (codec-for k)]
    (when-not parse
      (throw (ex-info "Unsupported codec format for parse"
                      {:format fmt
                       :supported (supported-formats)})))
    (parse (or text "") (or opts {}))))

(defn emit-string
  [fmt value opts]
  (let [k (normalize-format fmt)
        {:keys [emit]} (codec-for k)]
    (when-not emit
      (throw (ex-info "Unsupported codec format for emit"
                      {:format fmt
                       :supported (supported-formats)})))
    (emit value (or opts {}))))

(defn records-from-decoded
  [payload]
  (cond
    (nil? payload) []
    (sequential? payload) (vec payload)
    :else [payload]))

(defn- parse-scalar-token
  [s]
  (let [t (str/trim (or s ""))]
    (cond
      (str/blank? t) ""
      (re-matches #"(?i)true|false" t) (Boolean/parseBoolean (str/lower-case t))
      (re-matches #"-?\d+" t) (Long/parseLong t)
      (re-matches #"-?\d+\.\d+" t) (Double/parseDouble t)
      (re-matches #"\"(?:\\.|[^\"])*\"" t)
      (try
        (edn/read-string t)
        (catch Exception e
          (throw (ex-info "Invalid escape sequence in quoted string token"
                          {:token t} e))))
      :else t)))

(defn- sanitize-header-key
  [x idx]
  (let [base (-> (str x)
                 str/trim
                 str/lower-case
                 (str/replace #"[^a-z0-9_:\-\.]+" "_")
                 (str/replace #"^_+|_+$" ""))]
    (keyword (if (str/blank? base)
               (str "col_" (inc idx))
               base))))

(defn- csv-split-line
  [line delimiter]
  (let [n (count (or line ""))]
    (loop [i 0
           in-quote? false
           token ""
           out []]
      (if (>= i n)
        (conj out token)
        (let [c (.charAt line i)
              next-c (when (< (inc i) n) (.charAt line (inc i)))]
          (cond
            in-quote?
            (cond
              (= c \")
              (if (= next-c \")
                (recur (+ i 2) true (str token "\"") out)
                (recur (inc i) false token out))
              :else
              (recur (inc i) true (str token c) out))

            (= c \")
            (recur (inc i) true token out)

            (= c delimiter)
            (recur (inc i) false "" (conj out token))

            :else
            (recur (inc i) false (str token c) out)))))))

(defn- parse-csv
  [text {:keys [csv-delimiter csv_header csv_typed]
         :or {csv_header true
              csv_typed true}}]
  (let [delimiter (or (when (and (string? csv-delimiter) (pos? (count csv-delimiter)))
                        (.charAt ^String csv-delimiter 0))
                      \,)
        lines (->> (str/split-lines (or text ""))
                   (remove str/blank?)
                   vec)
        rows (mapv #(csv-split-line % delimiter) lines)
        coerce (fn [v] (if csv_typed (parse-scalar-token v) v))]
    (if (empty? rows)
      []
      (let [max-cols (reduce max 0 (map count rows))
            row* (fn [r] (vec (concat r (repeat (- max-cols (count r)) ""))))
            rows* (mapv row* rows)]
        (if csv_header
          (let [header-row (first rows*)
                headers (mapv sanitize-header-key header-row (range))]
            (->> (rest rows*)
                 (mapv (fn [r]
                         (into {}
                               (map (fn [k v] [k (coerce v)]) headers r)))))
            )
          (mapv (fn [r]
                  (into {}
                        (map-indexed (fn [idx v]
                                       [(keyword (str "col_" (inc idx))) (coerce v)])
                                     r)))
                rows*))))))

(defn- csv-escape
  [v delimiter]
  (let [raw (cond
              (nil? v) ""
              (string? v) v
              :else (str v))
        needs-quote? (or (str/includes? raw (str delimiter))
                         (str/includes? raw "\"")
                         (str/includes? raw "\n")
                         (str/includes? raw "\r"))]
    (if needs-quote?
      (str "\"" (str/replace raw "\"" "\"\"") "\"")
      raw)))

(defn- emit-csv
  [value {:keys [csv-delimiter csv-columns]
          :or {csv-delimiter ","}}]
  (let [delimiter (or (when (and (string? csv-delimiter) (pos? (count csv-delimiter)))
                        (.charAt ^String csv-delimiter 0))
                      \,)
        rows (cond
               (nil? value) []
               (map? value) [value]
               (sequential? value)
               (if (every? map? value)
                 (vec value)
                 (mapv (fn [v] {:value v}) value))
               :else [{:value value}])
        columns (if (seq csv-columns)
                  (mapv #(if (keyword? %) % (keyword (str %))) csv-columns)
                  (->> rows
                       (mapcat keys)
                       distinct
                       (sort-by name)
                       vec))
        header (str/join delimiter (map #(csv-escape (name %) delimiter) columns))
        body (for [row rows]
               (str/join delimiter
                         (for [k columns]
                           (csv-escape (get row k "") delimiter))))]
    (if (empty? rows)
      ""
      (str/join "\n" (cons header body)))))

(defn- maybe-parse-json
  [text]
  (let [trimmed (str/triml text)]
    (if (or (str/starts-with? trimmed "{")
            (str/starts-with? trimmed "["))
      (try
        (json/read-str text :key-fn keyword)
        (catch Exception _ ::not-json))
      ::not-json)))

(defn- yaml-scalar->value
  [v]
  (let [t (str/trim (or v ""))]
    (cond
      (str/blank? t) nil
      (= t "null") nil
      :else (parse-scalar-token t))))

(defn- yaml-kv-line
  [line]
  (when-let [[_ k v] (re-matches #"\s*([A-Za-z0-9_:\-\.]+)\s*:\s*(.*?)\s*$" line)]
    [(keyword (str/lower-case k)) (yaml-scalar->value v)]))

(defn- parse-yaml-list
  [lines]
  (loop [remaining lines
         current nil
         out []]
    (if-let [line (first remaining)]
      (let [trimmed (str/trim line)]
        (cond
          (str/starts-with? trimmed "- ")
          (let [out* (if (some? current) (conj out current) out)
                item (subs trimmed 2)
                kv (yaml-kv-line item)]
            (if kv
              (recur (rest remaining) {(first kv) (second kv)} out*)
              (recur (rest remaining) (yaml-scalar->value item) out*)))

          (and (map? current) (yaml-kv-line trimmed))
          (let [[k v] (yaml-kv-line trimmed)]
            (recur (rest remaining) (assoc current k v) out))

          :else
          (recur (rest remaining) current out)))
      (if (some? current)
        (conj out current)
        out))))

(defn- parse-yaml-lite
  [text _opts]
  (let [raw (or text "")
        json* (maybe-parse-json raw)]
    (if (not= json* ::not-json)
      json*
      (let [lines (->> (str/split-lines raw)
                       (map #(str/replace % #"\s+#.*$" ""))
                       (map str/trimr)
                       (remove str/blank?)
                       vec)]
        (cond
          (empty? lines) []
          (str/starts-with? (str/trim (first lines)) "- ")
          (parse-yaml-list lines)
          :else
          (into {}
                (keep yaml-kv-line lines)))))))

(defn- yaml-escape
  [v]
  (let [s (cond
            (nil? v) "null"
            (boolean? v) (if v "true" "false")
            (number? v) (str v)
            (keyword? v) (name v)
            (string? v) v
            :else (pr-str v))]
    (if (or (str/blank? s)
            (re-find #"[#:\n\r\"]" s)
            (str/starts-with? s " ")
            (str/ends-with? s " "))
      (str "\"" (str/replace s "\"" "\\\"") "\"")
      s)))

(defn- emit-yaml-map
  [m indent-prefix]
  (->> (sort-by (comp name key) m)
       (map (fn [[k v]]
              (str indent-prefix (name (if (keyword? k) k (keyword (str k))))
                   ": "
                   (yaml-escape v))))
       (str/join "\n")))

(defn- emit-yaml-lite
  [value _opts]
  (cond
    (nil? value) "null"
    (map? value) (emit-yaml-map value "")
    (sequential? value)
    (->> value
         (map (fn [item]
                (cond
                  (map? item)
                  (let [entries (sort-by (comp name key) item)
                        [k0 v0] (first entries)
                        rest* (rest entries)
                        head (str "- " (name (if (keyword? k0) k0 (keyword (str k0))))
                                  ": "
                                  (yaml-escape v0))
                        tail (for [[k v] rest*]
                               (str "  " (name (if (keyword? k) k (keyword (str k))))
                                    ": "
                                    (yaml-escape v)))]
                    (str/join "\n" (cons head tail)))
                  :else
                  (str "- " (yaml-escape item)))))
         (str/join "\n"))
    :else (yaml-escape value)))

(defn- parse-kv
  [text {:keys [kv_typed] :or {kv_typed true}}]
  (let [parse-v (fn [v] (if kv_typed (parse-scalar-token v) v))]
    (into {}
          (keep (fn [line]
                  (let [trimmed (str/trim line)]
                    (when (and (not (str/blank? trimmed))
                               (not (str/starts-with? trimmed "#"))
                               (str/includes? trimmed "="))
                      (let [[k v] (str/split trimmed #"=" 2)]
                        [(keyword (str/lower-case (str/trim k)))
                         (parse-v (or v ""))])))))
          (str/split-lines (or text "")))))

(defn- emit-kv
  [value _opts]
  (let [m (cond
            (map? value) value
            :else {:value value})]
    (->> (sort-by (comp name key) m)
         (map (fn [[k v]]
                (str (name (if (keyword? k) k (keyword (str k))))
                     "="
                     (cond
                       (nil? v) ""
                       (string? v) v
                       :else (str v)))))
         (str/join "\n"))))

(register-codec! :json
                 {:parse (fn [text _opts] (json/read-str text :key-fn keyword))
                  :emit (fn [value _opts] (json/write-str value))})

(register-codec! :edn
                 {:parse (fn [text _opts] (edn/read-string text))
                  :emit (fn [value _opts] (pr-str value))})

(register-codec! :text
                 {:parse (fn [text _opts] text)
                  :emit (fn [value _opts]
                          (if (string? value) value (pr-str value)))})

(register-codec! :csv
                 {:parse parse-csv
                  :emit emit-csv})

(register-codec! :yaml
                 {:parse parse-yaml-lite
                  :emit emit-yaml-lite
                  :aliases [:yml]})

(register-codec! :kv
                 {:parse parse-kv
                  :emit emit-kv})
