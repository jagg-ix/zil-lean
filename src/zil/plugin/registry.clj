(ns zil.plugin.registry
  "Manifest-driven extension registry with collision prevention and failure isolation."
  (:require [clojure.java.io :as io]
            [clojure.set :as set]
            [zil.control.capability :as ownership]
            [zil.control.command :as control-command]
            [zil.plugin.api :as api]
            [zil.plugin.evidence :as evidence]
            [zil.plugin.manifest :as manifest]
            [zil.worker.protocol :as worker-protocol]))

(defrecord Registry
  [control-plane extensions commands capabilities closed? lock])

(defn create-registry
  [{:keys [control-plane]}]
  (->Registry control-plane (atom (sorted-map)) (atom (sorted-map))
              (atom (sorted-map)) (atom false) (Object.)))

(defn closed? [^Registry registry]
  @(:closed? registry))

(defn- ensure-open! [^Registry registry]
  (when (closed? registry)
    (throw (ex-info "extension registry is closed" {:kind :registry-closed}))))

(defn- inventory-capabilities [^Registry registry]
  (or (some-> registry :control-plane :inventory :capabilities) []))

(defn- worker-available? [^Registry registry]
  (boolean (some-> registry :control-plane :pool)))

(defn- built-in-command-ids [^Registry registry]
  (let [inventory (some-> registry :control-plane :inventory)
        exchange-commands (if inventory
                            (set (keys (control-command/command-table inventory)))
                            #{})
        declared-commands (set (mapcat #(or (:commands %) [])
                                       (or (:capabilities inventory) [])))]
    (set/union exchange-commands declared-commands)))

(defn- built-in-capability-ids [^Registry registry]
  (set (map (comp name :id) (inventory-capabilities registry))))

(defn- runtime-capability-ids [^Registry registry]
  (set
   (for [{:keys [id operation]} (inventory-capabilities registry)
         :when (or (nil? operation) (worker-available? registry))]
     (name id))))

(defn- registered-output-schemas [^Registry registry]
  (set
   (mapcat (fn [[_ entry]]
             (if (= :active (:status entry))
               (or (get-in entry [:manifest :outputs]) [])
               []))
           @(:extensions registry))))

(defn- available-requirements [^Registry registry]
  (set/union
   #{manifest/schema evidence/schema ownership/schema}
   (if (worker-available? registry) #{worker-protocol/schema} #{})
   (runtime-capability-ids registry)
   (set (keys @(:capabilities registry)))
   (registered-output-schemas registry)))

(defn- normalize-command-map [commands]
  (into
   (sorted-map)
   (for [[command descriptor] (or commands {})
         :let [command (name command)]]
     [command (assoc (or descriptor {}) :id command)])))

(defn- extension-capabilities [extension]
  (if (satisfies? api/Capability extension)
    (vec (sort (distinct (map str (api/provided-capabilities extension)))))
    []))

(defn- extension-commands [extension]
  (if (satisfies? api/CommandProvider extension)
    (normalize-command-map (api/provided-commands extension))
    (sorted-map)))

(defn- quarantine! [^Registry registry extension-id error]
  (swap! (:extensions registry)
         update extension-id
         (fn [entry]
           (assoc entry
                  :status :quarantined
                  :error {:message (.getMessage ^Throwable error)
                          :data (ex-data error)})))
  nil)

(defn- guarded-call [registry extension-id function]
  (try
    (function)
    (catch Exception error
      (quarantine! registry extension-id error)
      (throw (ex-info "extension invocation failed"
                      {:kind :extension-failure
                       :extension-id extension-id
                       :cause-data (ex-data error)}
                      error)))))

(defn- validate-requirements! [registry extension-manifest]
  (let [declared (set (:requires extension-manifest))
        available (available-requirements registry)
        missing (vec (sort (set/difference declared available)))]
    (when (seq missing)
      (throw (ex-info "extension requirements are unavailable"
                      {:kind :extension-requirement-error
                       :extension-id (:id extension-manifest)
                       :missing missing
                       :available (vec (sort available))}))))
  extension-manifest)

(defn- validate-command-authority! [extension-manifest commands]
  (let [manifest-authority (keyword (:authority extension-manifest))]
    (doseq [[command descriptor] commands]
      (let [declared (or (:authority descriptor) manifest-authority)]
        (when-not (= manifest-authority declared)
          (throw (ex-info "extension command authority disagrees with manifest"
                          {:kind :extension-contract-error
                           :extension-id (:id extension-manifest)
                           :command command
                           :manifest-authority manifest-authority
                           :command-authority declared})))
        (when (contains? #{:lean :shared} declared)
          (throw (ex-info "dynamic Clojure commands cannot claim Lean or shared authority"
                          {:kind :extension-contract-error
                           :extension-id (:id extension-manifest)
                           :command command
                           :authority declared})))))
    commands))

(defn register!
  "Validate, start, and register one extension atomically.

  Authoritative built-in commands and capabilities cannot be shadowed. Extension
  startup failure leaves the extension quarantined and does not publish commands."
  ([registry extension] (register! registry extension {}))
  ([^Registry registry extension context]
   (ensure-open! registry)
   (when-not (satisfies? api/Extension extension)
     (throw (ex-info "extension does not implement zil.plugin.api/Extension"
                     {:kind :extension-contract-error})))
   (locking (:lock registry)
     (let [extension-manifest (manifest/with-fingerprint
                               (api/extension-manifest extension))
           _ (validate-requirements! registry extension-manifest)
           extension-id (:id extension-manifest)
           declared-capabilities (:capabilities extension-manifest)
           capabilities (extension-capabilities extension)
           commands (validate-command-authority!
                     extension-manifest
                     (extension-commands extension))
           command-ids (set (keys commands))
           capability-ids (set capabilities)
           built-in-commands (built-in-command-ids registry)
           built-in-capabilities (built-in-capability-ids registry)]
       (when (contains? @(:extensions registry) extension-id)
         (throw (ex-info "extension is already registered"
                         {:kind :extension-collision :extension-id extension-id})))
       (when-not (= declared-capabilities capabilities)
         (throw (ex-info "extension capabilities disagree with its manifest"
                         {:kind :extension-contract-error
                          :extension-id extension-id
                          :manifest-capabilities declared-capabilities
                          :runtime-capabilities capabilities})))
       (when-let [collision (first (sort (set/intersection command-ids built-in-commands)))]
         (throw (ex-info "extension command shadows a built-in command"
                         {:kind :command-shadowing
                          :extension-id extension-id
                          :command collision})))
       (when-let [collision (first (sort (set/intersection command-ids
                                                           (set (keys @(:commands registry))))))]
         (throw (ex-info "extension command is already registered"
                         {:kind :command-shadowing
                          :extension-id extension-id
                          :command collision})))
       (when-let [collision (first (sort (set/intersection capability-ids
                                                           built-in-capabilities)))]
         (throw (ex-info "extension capability shadows an authoritative capability"
                         {:kind :capability-shadowing
                          :extension-id extension-id
                          :capability collision})))
       (when-let [collision (first (sort (set/intersection capability-ids
                                                           (set (keys @(:capabilities registry))))))]
         (throw (ex-info "extension capability is already registered"
                         {:kind :capability-shadowing
                          :extension-id extension-id
                          :capability collision})))
       (swap! (:extensions registry)
              assoc extension-id
              {:manifest extension-manifest
               :instance extension
               :status :starting
               :error nil})
       (try
         (let [started (or (api/start-extension! extension
                                                  (assoc context
                                                         :registry registry
                                                         :control-plane (:control-plane registry)))
                           extension)
               started-capabilities (extension-capabilities started)
               started-commands (extension-commands started)]
           (when-not (satisfies? api/Extension started)
             (throw (ex-info "started extension lost the Extension contract"
                             {:kind :extension-contract-error
                              :extension-id extension-id})))
           (when-not (= capabilities started-capabilities)
             (throw (ex-info "extension capabilities changed during startup"
                             {:kind :extension-contract-error
                              :extension-id extension-id
                              :before capabilities
                              :after started-capabilities})))
           (when-not (= commands started-commands)
             (throw (ex-info "extension commands changed during startup"
                             {:kind :extension-contract-error
                              :extension-id extension-id
                              :before commands
                              :after started-commands})))
           (swap! (:extensions registry)
                  assoc extension-id
                  {:manifest extension-manifest
                   :instance started
                   :status :active
                   :error nil})
           (swap! (:commands registry)
                  into
                  (for [[command descriptor] commands]
                    [command {:extension-id extension-id
                              :descriptor descriptor}]))
           (swap! (:capabilities registry)
                  into
                  (for [provided capabilities]
                    [provided extension-id]))
           extension-manifest)
         (catch Exception error
           (quarantine! registry extension-id error)
           (throw (ex-info "extension startup failed"
                           {:kind :extension-startup-failure
                            :extension-id extension-id}
                           error))))))))

(defn extension-entry [registry extension-id]
  (get @(:extensions registry) (str extension-id)))

(defn extension-status [registry extension-id]
  (:status (extension-entry registry extension-id)))

(defn registered-extensions [registry]
  (mapv (fn [[extension-id entry]]
          {:id extension-id
           :version (get-in entry [:manifest :version])
           :status (:status entry)
           :fingerprint (get-in entry [:manifest :fingerprint])})
        @(:extensions registry)))

(defn invoke-command!
  [^Registry registry command context arguments]
  (ensure-open! registry)
  (let [command (name command)
        {:keys [extension-id descriptor]} (get @(:commands registry) command)
        entry (extension-entry registry extension-id)]
    (when-not extension-id
      (throw (ex-info "extension command was not found"
                      {:kind :unknown-extension-command :command command})))
    (when-not (= :active (:status entry))
      (throw (ex-info "extension command is unavailable"
                      {:kind :extension-unavailable
                       :command command
                       :extension-id extension-id
                       :status (:status entry)})))
    (guarded-call
     registry extension-id
     #(let [result (api/invoke-extension-command!
                    (:instance entry) command
                    (assoc context
                           :registry registry
                           :control-plane (:control-plane registry)
                           :extension-manifest (:manifest entry)
                           :command-descriptor descriptor)
                    (vec arguments))]
        {:extension_id extension-id
         :extension_version (get-in entry [:manifest :version])
         :command command
         :result result}))))

(defn produce-evidence!
  [^Registry registry extension-id context request]
  (ensure-open! registry)
  (let [extension-id (str extension-id)
        entry (extension-entry registry extension-id)
        registered-manifest (:manifest entry)]
    (when-not (= :active (:status entry))
      (throw (ex-info "extension evidence producer is unavailable"
                      {:kind :extension-unavailable
                       :extension-id extension-id
                       :status (:status entry)})))
    (when-not (satisfies? api/EvidenceProducer (:instance entry))
      (throw (ex-info "extension does not provide evidence"
                      {:kind :extension-contract-error :extension-id extension-id})))
    (guarded-call
     registry extension-id
     #(let [values (api/produce-evidence!
                    (:instance entry)
                    (assoc context
                           :registry registry
                           :control-plane (:control-plane registry)
                           :extension-manifest registered-manifest)
                    request)
            values (if (sequential? values) values [values])]
        (mapv
         (fn [value]
           (let [value (evidence/validate! value)]
             (when-not (= extension-id (:extension_id value))
               (throw (ex-info "extension returned evidence for another extension"
                               {:kind :evidence-error
                                :extension-id extension-id
                                :evidence value})))
             (when-not (= (:authority registered-manifest) (:authority value))
               (throw (ex-info "extension evidence authority disagrees with manifest"
                               {:kind :evidence-error
                                :extension-id extension-id
                                :manifest-authority (:authority registered-manifest)
                                :evidence-authority (:authority value)})))
             (when (and (= "clojure" (:runtime registered-manifest))
                        (contains? #{"validated" "kernel-backed"} (:assurance value)))
               (throw (ex-info "Clojure extension exceeded its assurance ceiling"
                               {:kind :evidence-error
                                :extension-id extension-id
                                :assurance (:assurance value)})))
             value))
         values)))))

(defn unregister!
  ([registry extension-id] (unregister! registry extension-id {}))
  ([^Registry registry extension-id context]
   (locking (:lock registry)
     (let [extension-id (str extension-id)
           entry (extension-entry registry extension-id)]
       (when entry
         (try
           (api/stop-extension! (:instance entry)
                                (assoc context
                                       :registry registry
                                       :control-plane (:control-plane registry)))
           (catch Exception error
             (quarantine! registry extension-id error)))
         (swap! (:commands registry)
                (fn [commands]
                  (into (sorted-map)
                        (remove (fn [[_ value]]
                                  (= extension-id (:extension-id value))))
                        commands)))
         (swap! (:capabilities registry)
                (fn [capabilities]
                  (into (sorted-map)
                        (remove (fn [[_ owner]] (= extension-id owner)))
                        capabilities)))
         (swap! (:extensions registry) dissoc extension-id))
       {:removed (boolean entry) :extension-id extension-id}))))

(defn close!
  [^Registry registry]
  (when (compare-and-set! (:closed? registry) false true)
    (doseq [extension-id (reverse (keys @(:extensions registry)))]
      (try (unregister! registry extension-id) (catch Exception _))))
  {:closed true})

(defn discover-manifests
  [roots]
  (->> roots
       (map io/file)
       (mapcat (fn [root]
                 (cond
                   (.isFile root) [root]
                   (.isDirectory root) (file-seq root)
                   :else [])))
       (filter #(.isFile %))
       (filter #(= "extension.json" (.getName %)))
       (sort-by #(.getCanonicalPath %))
       vec))

(defn load-extension
  [manifest-path config]
  (let [extension-manifest (manifest/read-manifest manifest-path)]
    (when-not (= "clojure" (:runtime extension-manifest))
      (throw (ex-info "dynamic registry loading supports Clojure runtime extensions only"
                      {:kind :extension-load-error
                       :runtime (:runtime extension-manifest)
                       :manifest manifest-path})))
    (let [entrypoint (symbol (:entrypoint extension-manifest))
          factory (requiring-resolve entrypoint)]
      (when-not factory
        (throw (ex-info "extension entrypoint could not be resolved"
                        {:kind :extension-load-error
                         :entrypoint entrypoint
                         :manifest manifest-path})))
      (factory extension-manifest config))))

(defn load-and-register!
  ([registry manifest-path] (load-and-register! registry manifest-path {} {}))
  ([registry manifest-path config context]
   (register! registry (load-extension manifest-path config) context)))
