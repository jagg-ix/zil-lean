(ns zil.plugin.registry
  "Manifest-driven extension registry with collision prevention and failure isolation."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.control.command :as control-command]
            [zil.plugin.api :as api]
            [zil.plugin.evidence :as evidence]
            [zil.plugin.manifest :as manifest]))

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

(defn- built-in-command-ids [^Registry registry]
  (if-let [control-plane (:control-plane registry)]
    (set (keys (control-command/command-table (:inventory control-plane))))
    #{}))

(defn- built-in-capability-ids [^Registry registry]
  (if-let [control-plane (:control-plane registry)]
    (set (map (comp name :id) (:capabilities (:inventory control-plane))))
    #{}))

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
           extension-id (:id extension-manifest)
           declared-capabilities (:capabilities extension-manifest)
           capabilities (extension-capabilities extension)
           commands (extension-commands extension)
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
       (when-let [collision (first (sort (clojure.set/intersection command-ids built-in-commands)))]
         (throw (ex-info "extension command shadows a built-in command"
                         {:kind :command-shadowing
                          :extension-id extension-id
                          :command collision})))
       (when-let [collision (first (sort (clojure.set/intersection command-ids
                                                                   (set (keys @(:commands registry))))))]
         (throw (ex-info "extension command is already registered"
                         {:kind :command-shadowing
                          :extension-id extension-id
                          :command collision})))
       (when-let [collision (first (sort (clojure.set/intersection capability-ids
                                                                   built-in-capabilities)))]
         (throw (ex-info "extension capability shadows an authoritative capability"
                         {:kind :capability-shadowing
                          :extension-id extension-id
                          :capability collision})))
       (when-let [collision (first (sort (clojure.set/intersection capability-ids
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
                           extension)]
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
                  (for [capability capabilities]
                    [capability extension-id]))
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
        entry (extension-entry registry extension-id)]
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
                           :extension-manifest (:manifest entry))
                    request)
            values (if (sequential? values) values [values])]
        (mapv
         (fn [value]
           (when-not (= evidence/schema (:schema value))
             (throw (ex-info "extension returned an invalid evidence schema"
                             {:kind :evidence-error
                              :extension-id extension-id
                              :evidence value})))
           (when-not (= extension-id (:extension_id value))
             (throw (ex-info "extension returned evidence for another extension"
                             {:kind :evidence-error
                              :extension-id extension-id
                              :evidence value})))
           value)
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
  (let [extension-manifest (manifest/read-manifest manifest-path)
        entrypoint (symbol (:entrypoint extension-manifest))
        factory (requiring-resolve entrypoint)]
    (when-not factory
      (throw (ex-info "extension entrypoint could not be resolved"
                      {:kind :extension-load-error
                       :entrypoint entrypoint
                       :manifest manifest-path})))
    (factory extension-manifest config)))

(defn load-and-register!
  ([registry manifest-path] (load-and-register! registry manifest-path {} {}))
  ([registry manifest-path config context]
   (register! registry (load-extension manifest-path config) context)))
