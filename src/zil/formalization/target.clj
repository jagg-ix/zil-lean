(ns zil.formalization.target
  "Bounded Lean formalization targets declared directly in ZIL."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.core :as core]
            [zil.lower :as lower]))

(def accepted-statuses #{:verified :reviewed :proved})
(def selectable-statuses #{:ready :in_progress})

(defn- values [value]
  (cond
    (nil? value) []
    (and (coll? value) (not (map? value))) (vec value)
    :else [value]))

(defn- validate-target-graph! [targets]
  (let [by-name (into {} (map (juxt :name identity)) targets)
        dependencies (into {}
                           (map (fn [{:keys [name attrs]}]
                                  [name (mapv str (values (:dependencies attrs)))])
                                targets))]
    (doseq [{:keys [name attrs]} targets]
      (when-not (and (integer? (:priority attrs)) (<= 0 (:priority attrs)))
        (throw (ex-info "Formalization target priority must be a nonnegative integer"
                        {:target name :priority (:priority attrs)})))
      (doseq [key [:module :file :declaration]]
        (when (str/blank? (str (get attrs key)))
          (throw (ex-info "Formalization target metadata must be non-empty"
                          {:target name :attribute key}))))
      (doseq [dependency (get dependencies name)]
        (when-not (contains? by-name dependency)
          (throw (ex-info "Formalization target dependency does not exist"
                          {:target name :dependency dependency})))))
    (letfn [(visit [name visiting visited]
              (when (contains? visiting name)
                (throw (ex-info "Formalization target dependency graph has a cycle"
                                {:target name :path (vec visiting)})))
              (if (contains? visited name)
                visited
                (reduce #(visit %2 (conj visiting name) %1)
                        (conj visited name)
                        (get dependencies name))))]
      (reduce #(visit %2 #{} %1) #{} (keys dependencies)))
    targets))

(defn load-targets [model-path]
  (let [compiled (core/compile-program (slurp model-path))
        targets (->> (:declarations compiled)
                     (filter #(= :formalization_target (:kind %)))
                     (mapv lower/normalized-declaration))
        _ (validate-target-graph! targets)]
    targets))

(defn next-target [model-path]
  (let [targets (load-targets model-path)
        by-name (into {} (map (juxt :name identity)) targets)
        ready (for [{:keys [name attrs] :as target} targets
                    :let [dependencies (mapv str (values (:dependencies attrs)))]
                    :when (and (selectable-statuses (:status attrs))
                               (every? #(accepted-statuses (get-in by-name [% :attrs :status]))
                                       dependencies))]
                {:id name
                 :module (:module attrs)
                 :file (:file attrs)
                 :declaration (:declaration attrs)
                 :priority (:priority attrs)
                 :status (:status attrs)
                 :dependencies dependencies
                 :verification_command (str "lake env lean " (:file attrs))})]
    (first (sort-by (juxt (comp - long :priority) :id) ready))))

(defn- contained-file [project-root relative-path]
  (let [root (.getCanonicalFile (io/file project-root))
        file (.getCanonicalFile (io/file root relative-path))
        root-prefix (str (.getPath root) java.io.File/separator)]
    (when-not (str/starts-with? (.getPath file) root-prefix)
      (throw (ex-info "Formalization target escapes the project root"
                      {:file relative-path :project_root (.getPath root)})))
    file))

(defn- default-runner [root relative-path]
  (let [process (-> (ProcessBuilder. ["lake" "env" "lean" relative-path])
                    (.directory root)
                    (.inheritIO)
                    (.start))]
    (.waitFor process)))

(defn check-target
  ([model-path target-id project-root]
   (check-target model-path target-id project-root default-runner))
  ([model-path target-id project-root runner]
   (let [target (some #(when (= target-id (:name %)) %) (load-targets model-path))]
     (when-not target
       (throw (ex-info "Unknown formalization target" {:target target-id})))
     (let [{:keys [file declaration module]} (:attrs target)
           root (.getCanonicalFile (io/file project-root))
           source-file (contained-file root file)]
       (when-not (.isFile source-file)
         (throw (ex-info "Formalization target file does not exist" {:file file})))
       (let [source (slurp source-file)
             short-name (last (str/split declaration #"\."))
             declaration-pattern (re-pattern
                                  (str "(?m)^\\s*(?:public\\s+)?(?:theorem|lemma|def|noncomputable\\s+def)\\s+"
                                       (java.util.regex.Pattern/quote short-name) "\\b"))
             violations (cond-> []
                          (re-find #"(?m)^\s*(?:axiom|unsafe)\b" source) (conj :forbidden-declaration)
                          (re-find #"\b(?:sorry|admit)\b" source) (conj :incomplete-proof)
                          (not (re-find declaration-pattern source)) (conj :missing-declaration))]
         (when (seq violations)
           (throw (ex-info "Formalization target failed source checks"
                           {:target target-id :violations violations})))
         (let [exit-code (runner root file)]
           {:ok (zero? exit-code) :target target-id :module module :file file
            :declaration declaration :exit_code exit-code :violations []}))))))
