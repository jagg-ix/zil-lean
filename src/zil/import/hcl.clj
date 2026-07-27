(ns zil.import.hcl
  "Import a practical subset of HCL/OpenTofu descriptions into ZIL source."
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(defn- hcl-file?
  [^java.io.File f]
  (and (.isFile f)
       (or (str/ends-with? (.getName f) ".tf")
           (str/ends-with? (.getName f) ".hcl"))))

(defn collect-hcl-files
  "Collect .tf/.hcl files from path (file or directory)."
  [path]
  (let [f (io/file path)]
    (cond
      (not (.exists f)) []
      (.isFile f) (if (hcl-file? f) [(.getPath f)] [])
      (.isDirectory f) (->> (file-seq f)
                            (filter hcl-file?)
                            (map #(.getPath ^java.io.File %))
                            sort
                            vec)
      :else [])))

(defn- strip-inline-comment
  [line]
  (loop [chs (seq line)
         out ""
         in-string? false
         escape? false]
    (if-let [c (first chs)]
      (cond
        escape?
        (recur (next chs) (str out c) in-string? false)

        in-string?
        (cond
          (= c \\) (recur (next chs) (str out c) in-string? true)
          (= c \") (recur (next chs) (str out c) false false)
          :else (recur (next chs) (str out c) in-string? false))

        (= c \")
        (recur (next chs) (str out c) true false)

        (= c \#)
        out

        (and (= c \/) (= (first (next chs)) \/))
        out

        :else
        (recur (next chs) (str out c) false false))
      out)))

(defn- line-brace-delta
  [line]
  (loop [chs (seq line)
         in-string? false
         escape? false
         depth 0]
    (if-let [c (first chs)]
      (cond
        escape?
        (recur (next chs) in-string? false depth)

        in-string?
        (cond
          (= c \\) (recur (next chs) in-string? true depth)
          (= c \") (recur (next chs) false false depth)
          :else (recur (next chs) in-string? false depth))

        (= c \")
        (recur (next chs) true false depth)

        (= c \{)
        (recur (next chs) false false (inc depth))

        (= c \})
        (recur (next chs) false false (dec depth))

        :else
        (recur (next chs) false false depth))
      depth)))

(defn- parse-hcl-scalar
  [raw]
  (let [t (-> raw str/trim (str/replace #",\s*$" ""))]
    (cond
      (str/blank? t) ""
      (re-matches #"(?s)\"(?:\\.|[^\"])*\"" t)
      (try
        (edn/read-string t)
        (catch Exception _
          (subs t 1 (dec (count t)))))

      (re-matches #"(?i)true|false" t)
      (Boolean/parseBoolean (str/lower-case t))

      (re-matches #"-?\d+" t)
      (Long/parseLong t)

      (re-matches #"-?\d+\.\d+" t)
      (Double/parseDouble t)

      :else t)))

(defn- parse-top-level-attrs
  "Parse simple top-level key=value assignments from a block body.
  Nested object/list assignments are intentionally skipped in this first pass."
  [body]
  (loop [lines (str/split-lines body)
         depth 0
         out {}]
    (if-let [line (first lines)]
      (let [clean (-> line strip-inline-comment str/trim)
            parse? (and (zero? depth)
                        (not (str/blank? clean))
                        (re-matches #"([A-Za-z0-9_\-]+)\s*=\s*(.+)" clean))
            [_ k raw-v] (when parse?
                          (re-matches #"([A-Za-z0-9_\-]+)\s*=\s*(.+)" clean))
            vtxt (str/trim (or raw-v ""))
            out* (if (and parse?
                          (not= vtxt "{")
                          (not (str/ends-with? vtxt "{")))
                   (assoc out (keyword k) (parse-hcl-scalar vtxt))
                   out)
            depth* (+ depth (line-brace-delta clean))]
        (recur (next lines) depth* out*))
      out)))

(defn- last-nonblank-line
  [s]
  (->> (str/split-lines (or s ""))
       (map strip-inline-comment)
       (map str/trim)
       (remove str/blank?)
       last))

(defn extract-top-level-blocks
  "Extract top-level HCL blocks with header/body by brace matching."
  [text]
  (let [n (count text)]
    (loop [i 0
           depth 0
           in-string? false
           escape? false
           segment-start 0
           block-open nil
           block-header nil
           out []]
      (if (>= i n)
        out
        (let [c (.charAt text i)]
          (cond
            escape?
            (recur (inc i) depth in-string? false segment-start block-open block-header out)

            in-string?
            (cond
              (= c \\)
              (recur (inc i) depth in-string? true segment-start block-open block-header out)

              (= c \")
              (recur (inc i) depth false false segment-start block-open block-header out)

              :else
              (recur (inc i) depth in-string? false segment-start block-open block-header out))

            (= c \")
            (recur (inc i) depth true false segment-start block-open block-header out)

            (= c \{)
            (if (zero? depth)
              (let [header (last-nonblank-line (subs text segment-start i))]
                (recur (inc i)
                       1
                       false
                       false
                       segment-start
                       i
                       header
                       out))
              (recur (inc i) (inc depth) false false segment-start block-open block-header out))

            (= c \})
            (let [depth* (dec depth)]
              (if (and (zero? depth*) (some? block-open))
                (let [body (subs text (inc block-open) i)
                      out* (if (str/blank? (or block-header ""))
                             out
                             (conj out {:header block-header :body body}))]
                  (recur (inc i)
                         0
                         false
                         false
                         (inc i)
                         nil
                         nil
                         out*))
                (recur (inc i) depth* false false segment-start block-open block-header out)))

            :else
            (recur (inc i) depth false false segment-start block-open block-header out)))))))

(defn- parse-header
  [header]
  (let [h (str/trim (or header ""))]
    (cond
      (re-matches #"(?i)^terraform$" h)
      {:type :terraform}

      (re-matches #"(?i)^required_providers$" h)
      {:type :required_providers}

      (re-matches #"(?i)^provider\s+\"([^\"]+)\"$" h)
      (let [[_ provider] (re-matches #"(?i)^provider\s+\"([^\"]+)\"$" h)]
        {:type :provider
         :provider provider})

      (re-matches #"(?i)^resource\s+\"([^\"]+)\"\s+\"([^\"]+)\"$" h)
      (let [[_ resource-type name] (re-matches #"(?i)^resource\s+\"([^\"]+)\"\s+\"([^\"]+)\"$" h)]
        {:type :resource
         :resource_type resource-type
         :name name})

      (re-matches #"(?i)^data\s+\"([^\"]+)\"\s+\"([^\"]+)\"$" h)
      (let [[_ data-type name] (re-matches #"(?i)^data\s+\"([^\"]+)\"\s+\"([^\"]+)\"$" h)]
        {:type :data
         :data_type data-type
         :name name})

      (re-matches #"(?i)^module\s+\"([^\"]+)\"$" h)
      (let [[_ name] (re-matches #"(?i)^module\s+\"([^\"]+)\"$" h)]
        {:type :module
         :name name})

      (re-matches #"(?i)^variable\s+\"([^\"]+)\"$" h)
      (let [[_ name] (re-matches #"(?i)^variable\s+\"([^\"]+)\"$" h)]
        {:type :variable
         :name name})

      (re-matches #"(?i)^output\s+\"([^\"]+)\"$" h)
      (let [[_ name] (re-matches #"(?i)^output\s+\"([^\"]+)\"$" h)]
        {:type :output
         :name name})

      :else
      nil)))

(defn- parse-required-provider-map
  [required-providers-body]
  (->> (re-seq #"(?s)([A-Za-z0-9_\-]+)\s*=\s*\{(.*?)\}" required-providers-body)
       (map (fn [[_ pname pbody]]
              [pname (parse-top-level-attrs pbody)]))
       (into {})))

(defn- parse-required-providers
  [terraform-body]
  (->> (extract-top-level-blocks terraform-body)
       (map (fn [{:keys [header body]}]
              (let [{:keys [type]} (parse-header header)]
                (when (= type :required_providers)
                  (parse-required-provider-map body)))))
       (remove nil?)
       (apply merge {})))

(defn- safe-ident
  [x]
  (-> (str x)
      (str/replace #"[^A-Za-z0-9_.:-]" "_")))

(defn- raw->string
  [v]
  (cond
    (string? v) v
    (keyword? v) (name v)
    :else (pr-str v)))

(defn- file-entity
  [path]
  (str "hcl:file:" (-> path io/file .getName (str/replace #"[^A-Za-z0-9]+" "_"))))

(defn- infer-provider-from-type
  [resource-or-data-type]
  (some-> (str resource-or-data-type)
          (str/split #"_" 2)
          first
          str/trim
          not-empty))

(defn- provider-local-from-attrs
  [attrs]
  (when-let [p (:provider attrs)]
    (let [pstr (raw->string p)]
      (some-> pstr
              (str/split #"\." 2)
              first
              str/trim
              not-empty))))

(defn- provider-source
  [local required-map]
  (let [source (get-in required-map [local :source])]
    (if (str/blank? (str source))
      (str "hashicorp/" local)
      (raw->string source))))

(defn- provider-version
  [local required-map]
  (some-> (get-in required-map [local :version]) raw->string not-empty))

(defn- render-scalar
  [v]
  (cond
    (string? v)
    (str "\"" (str/escape v {\\ "\\\\" \" "\\\""}) "\"")

    (keyword? v) (name v)
    (boolean? v) (if v "true" "false")
    (number? v) (str v)
    (nil? v) "nil"
    :else (render-scalar (raw->string v))))

(defn- render-provider-decl
  [provider-name attrs]
  (let [pairs (->> attrs
                   (remove (fn [[_ v]] (nil? v)))
                   (map (fn [[k v]]
                          (str (clojure.core/name k) "=" (render-scalar v))))
                   (str/join ", "))]
    (str "PROVIDER " provider-name " [" pairs "].")))

(defn- render-attr-facts
  [obj attrs]
  (mapcat
   (fn [[k v]]
     (let [k* (safe-ident (name k))
           raw (raw->string v)]
       [(str obj "#attr@value:present [key=value:" k* ", raw=" (render-scalar raw) "].")]))
   (sort-by (comp name key) attrs)))

(defn import-path->zil
  "Import HCL/OpenTofu descriptions into ZIL source text.

  Options:
  - :module-name  => ZIL module name (default: hcl.import)
  - :output-path  => when provided, writes generated ZIL file"
  ([path]
   (import-path->zil path {}))
  ([path {:keys [module-name output-path]
          :or {module-name "hcl.import"}}]
   (let [files (collect-hcl-files path)]
     (when (empty? files)
       (throw (ex-info "No .tf/.hcl files found for import"
                       {:path path})))
     (let [parsed
           (reduce
            (fn [acc fp]
              (let [text (slurp fp)
                    blocks (extract-top-level-blocks text)
                    fentity (file-entity fp)]
                (reduce
                 (fn [a {:keys [header body]}]
                   (if-let [{:keys [type provider resource_type data_type name]} (parse-header header)]
                     (case type
                       :terraform
                       (update a :required-providers merge (parse-required-providers body))

                       :provider
                       (update a :provider-configs conj {:provider provider
                                                         :attrs (parse-top-level-attrs body)
                                                         :file fentity})

                       :resource
                       (update a :resources conj {:resource_type resource_type
                                                  :name name
                                                  :attrs (parse-top-level-attrs body)
                                                  :file fentity})

                       :data
                       (update a :data conj {:data_type data_type
                                             :name name
                                             :attrs (parse-top-level-attrs body)
                                             :file fentity})

                       :module
                       (update a :modules conj {:name name
                                                :attrs (parse-top-level-attrs body)
                                                :file fentity})

                       :variable
                       (update a :variables conj {:name name
                                                  :attrs (parse-top-level-attrs body)
                                                  :file fentity})

                       :output
                       (update a :outputs conj {:name name
                                                :attrs (parse-top-level-attrs body)
                                                :file fentity})

                       a)
                     a))
                 (update acc :files conj fentity)
                 blocks)))
            {:required-providers {}
             :provider-configs []
             :resources []
             :data []
             :modules []
             :variables []
             :outputs []
             :files []}
            files)
           provider-locals
           (->> (concat
                 (keys (:required-providers parsed))
                 (map :provider (:provider-configs parsed))
                 (keep (fn [{:keys [resource_type attrs]}]
                         (or (provider-local-from-attrs attrs)
                             (infer-provider-from-type resource_type)))
                       (:resources parsed))
                 (keep (fn [{:keys [data_type attrs]}]
                         (or (provider-local-from-attrs attrs)
                             (infer-provider-from-type data_type)))
                       (:data parsed)))
                (remove str/blank?)
                (map safe-ident)
                distinct
                sort
                vec)
           provider-lines
           (map (fn [local]
                  (render-provider-decl
                   local
                   {:source (provider-source local (:required-providers parsed))
                    :version (provider-version local (:required-providers parsed))
                    :language :hcl
                    :engine :opentofu}))
                provider-locals)
           provider-config-lines
           (mapcat
            (fn [{:keys [provider attrs file]}]
              (let [pname (safe-ident provider)
                    pobj (str "provider:" pname)]
                (concat
                 [(str pobj "#configured_in@" file ".")]
                 (render-attr-facts pobj attrs))))
            (:provider-configs parsed))
           resource-lines
           (mapcat
            (fn [{:keys [resource_type name attrs file]}]
              (let [obj (str "hcl_resource:" (safe-ident resource_type) ":" (safe-ident name))
                    provider-local (or (some-> (provider-local-from-attrs attrs) safe-ident)
                                       (some-> (infer-provider-from-type resource_type) safe-ident))]
                (concat
                 [(str obj "#kind@entity:hcl_resource.")
                  (str obj "#resource_type@value:" (safe-ident resource_type) ".")
                  (str obj "#resource_name@value:" (safe-ident name) ".")
                  (str obj "#declared_in@" file ".")]
                 (when provider-local
                   [(str obj "#provider@provider:" provider-local ".")])
                 (render-attr-facts obj attrs))))
            (:resources parsed))
           data-lines
           (mapcat
            (fn [{:keys [data_type name attrs file]}]
              (let [obj (str "hcl_data:" (safe-ident data_type) ":" (safe-ident name))
                    provider-local (or (some-> (provider-local-from-attrs attrs) safe-ident)
                                       (some-> (infer-provider-from-type data_type) safe-ident))]
                (concat
                 [(str obj "#kind@entity:hcl_data.")
                  (str obj "#data_type@value:" (safe-ident data_type) ".")
                  (str obj "#data_name@value:" (safe-ident name) ".")
                  (str obj "#declared_in@" file ".")]
                 (when provider-local
                   [(str obj "#provider@provider:" provider-local ".")])
                 (render-attr-facts obj attrs))))
            (:data parsed))
           module-lines
           (mapcat
            (fn [{:keys [name attrs file]}]
              (let [obj (str "hcl_module:" (safe-ident name))]
                (concat
                 [(str obj "#kind@entity:hcl_module.")
                  (str obj "#module_name@value:" (safe-ident name) ".")
                  (str obj "#declared_in@" file ".")]
                 (render-attr-facts obj attrs))))
            (:modules parsed))
           variable-lines
           (mapcat
            (fn [{:keys [name attrs file]}]
              (let [obj (str "hcl_variable:" (safe-ident name))]
                (concat
                 [(str obj "#kind@entity:hcl_variable.")
                  (str obj "#variable_name@value:" (safe-ident name) ".")
                  (str obj "#declared_in@" file ".")]
                 (render-attr-facts obj attrs))))
            (:variables parsed))
           output-lines
           (mapcat
            (fn [{:keys [name attrs file]}]
              (let [obj (str "hcl_output:" (safe-ident name))]
                (concat
                 [(str obj "#kind@entity:hcl_output.")
                  (str obj "#output_name@value:" (safe-ident name) ".")
                  (str obj "#declared_in@" file ".")]
                 (render-attr-facts obj attrs))))
            (:outputs parsed))
           lines (vec (concat
                       [(str "MODULE " module-name ".") ""]
                       provider-lines
                       [""]
                       provider-config-lines
                       resource-lines
                       data-lines
                       module-lines
                       variable-lines
                       output-lines))
           text (str (str/join "\n" lines) "\n")
           report {:ok true
                   :path path
                   :files files
                   :module module-name
                   :providers (count provider-locals)
                   :resources (count (:resources parsed))
                   :data (count (:data parsed))
                   :modules (count (:modules parsed))
                   :variables (count (:variables parsed))
                   :outputs (count (:outputs parsed))
                   :text text}]
       (if output-path
         (do
           (spit output-path text)
           (assoc report :output_path output-path))
         report)))))
