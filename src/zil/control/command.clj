(ns zil.control.command
  "Command descriptors for the formal control-plane boundary."
  (:require [zil.control.capability :as capability]
            [zil.control.runtime :as runtime]
            [zil.worker.protocol :as worker-protocol]))

(defn command-table
  "Build the immutable built-in command table from the validated ownership inventory."
  [inventory]
  (into
   (sorted-map)
   (for [[operation required-capability] worker-protocol/operation-capabilities
         :let [owned (capability/require-lean-operation! inventory operation)]]
     [operation
      {:id (keyword operation)
       :operation operation
       :authority :lean
       :capability required-capability
       :arity (get worker-protocol/operation-arities operation)
       :assurance (:assurance owned)
       :replaceable false}])))

(defn resolve-command!
  [inventory command]
  (let [command (name command)
        descriptor (get (command-table inventory) command)]
    (or descriptor
        (throw (ex-info "unknown control-plane command"
                        {:kind :unknown-command :command command})))))

(defn execute!
  "Execute one built-in command through the authoritative exchange path."
  ([control-plane command input-path arguments]
   (execute! control-plane command input-path arguments {}))
  ([control-plane command input-path arguments options]
   (let [descriptor (resolve-command! (:inventory control-plane) command)]
     (runtime/invoke!
      control-plane
      {:operation (:operation descriptor)
       :input-path input-path
       :arguments (vec arguments)
       :base-revision (or (:base-revision options) "-")
       :request-id (:request-id options)
       :capabilities [(:capability descriptor)]}
      (or (:timeout-ms options) runtime/default-timeout-ms)))))

(defn execute-payload!
  ([control-plane command input-path arguments]
   (runtime/payload! (execute! control-plane command input-path arguments)))
  ([control-plane command input-path arguments options]
   (runtime/payload! (execute! control-plane command input-path arguments options))))
