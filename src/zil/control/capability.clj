(ns zil.control.capability
  "Validate and query the machine-readable capability ownership contract."
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [zil.worker.protocol :as worker-protocol]))

(def schema "ZIL-CAPABILITY-OWNERSHIP/1")
(def default-inventory-path "architecture/capability-ownership.edn")
(def authorities #{:lean :clojure :shared :external})
(def assurance-levels
  #{:exploratory :validated :kernel-backed :externally-attested :byte-attested})

(defn load-inventory
  ([] (load-inventory default-inventory-path))
  ([path]
   (let [file (io/file path)]
     (when-not (.isFile file)
       (throw (ex-info "capability ownership inventory was not found"
                       {:kind :configuration-error :path (.getPath file)})))
     (edn/read-string (slurp file)))))

(defn- duplicates [values]
  (->> values
       frequencies
       (keep (fn [[value count]] (when (> count 1) value)))
       sort
       vec))

(defn capability-index [inventory]
  (into (sorted-map)
        (map (juxt :id identity) (:capabilities inventory))))

(defn operation-index [inventory]
  (into (sorted-map)
        (keep (fn [capability]
                (when-let [operation (:operation capability)]
                  [operation capability])))
        (:capabilities inventory)))

(defn validate-inventory!
  "Fail closed when the ownership inventory is ambiguous or disagrees with the worker allowlist."
  [inventory]
  (when-not (= schema (:schema inventory))
    (throw (ex-info "unsupported capability ownership schema"
                    {:kind :configuration-error :schema (:schema inventory)})))
  (let [capabilities (vec (:capabilities inventory))
        ids (mapv :id capabilities)
        operations (vec (keep :operation capabilities))
        duplicate-ids (duplicates ids)
        duplicate-operations (duplicates operations)]
    (when (seq duplicate-ids)
      (throw (ex-info "duplicate capability identifiers"
                      {:kind :configuration-error :ids duplicate-ids})))
    (when (seq duplicate-operations)
      (throw (ex-info "duplicate operation ownership declarations"
                      {:kind :configuration-error :operations duplicate-operations})))
    (doseq [{:keys [id authority assurance operation] :as declared-capability} capabilities]
      (when-not (keyword? id)
        (throw (ex-info "capability id must be a keyword"
                        {:kind :configuration-error :capability declared-capability})))
      (when-not (contains? authorities authority)
        (throw (ex-info "capability authority is invalid"
                        {:kind :configuration-error :capability declared-capability})))
      (when (and assurance (not (contains? assurance-levels assurance)))
        (throw (ex-info "capability assurance level is invalid"
                        {:kind :configuration-error :capability declared-capability})))
      (when operation
        (let [worker-capability (get worker-protocol/operation-capabilities operation)]
          (when-not (= :lean authority)
            (throw (ex-info "exchange operations must remain Lean-authoritative"
                            {:kind :configuration-error :capability declared-capability})))
          (when-not worker-capability
            (throw (ex-info "ownership inventory declares an unknown worker operation"
                            {:kind :configuration-error :capability declared-capability})))
          (when-not (= (name id) worker-capability)
            (throw (ex-info "ownership capability disagrees with worker protocol"
                            {:kind :configuration-error
                             :capability declared-capability
                             :worker-capability worker-capability}))))))
    (doseq [[operation worker-capability] worker-protocol/operation-capabilities]
      (let [declared (get (operation-index inventory) operation)]
        (when-not declared
          (throw (ex-info "worker operation has no ownership declaration"
                          {:kind :configuration-error
                           :operation operation
                           :capability worker-capability})))))
    inventory))

(defn operation-capability
  [inventory operation]
  (get (operation-index inventory) (str operation)))

(defn require-lean-operation!
  [inventory operation]
  (let [operation (str operation)
        declared-capability (operation-capability inventory operation)]
    (when-not declared-capability
      (throw (ex-info "operation is not declared in the control-plane inventory"
                      {:kind :configuration-error :operation operation})))
    (when-not (= :lean (:authority declared-capability))
      (throw (ex-info "operation is not Lean-authoritative"
                      {:kind :authority-error
                       :operation operation
                       :authority (:authority declared-capability)})))
    declared-capability))

(defn load-valid-inventory
  ([] (load-valid-inventory default-inventory-path))
  ([path] (validate-inventory! (load-inventory path))))
