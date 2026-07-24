(ns zil.control.runtime
  "Formal operational control plane for Lean-authoritative exchange capabilities."
  (:require [clojure.string :as str]
            [zil.control.capability :as capability]
            [zil.worker.client :as client]
            [zil.worker.pool :as worker-pool]))

(def default-pool-size 2)
(def default-timeout-ms 30000)

(defrecord ControlPlane
  [pool inventory closed? options])

(defn start!
  ([] (start! {}))
  ([{:keys [pool-size inventory inventory-path worker-options]
     :or {pool-size default-pool-size worker-options {}}
     :as options}]
   (let [inventory (if inventory
                     (capability/validate-inventory! inventory)
                     (capability/load-valid-inventory
                      (or inventory-path capability/default-inventory-path)))
         pool (worker-pool/start-pool!
               {:size pool-size
                :worker-options worker-options})]
     (->ControlPlane pool inventory (atom false) options))))

(defn closed? [^ControlPlane control-plane]
  @(:closed? control-plane))

(defn stop! [^ControlPlane control-plane]
  (when (compare-and-set! (:closed? control-plane) false true)
    (when-let [pool (:pool control-plane)]
      (worker-pool/stop-pool! pool)))
  {:closed true})

(defn invoke!
  "Invoke one Lean-authoritative operation and return the verified exchange response."
  ([control-plane request]
   (invoke! control-plane request default-timeout-ms))
  ([^ControlPlane control-plane
    {:keys [operation input-path arguments base-revision request-id capabilities]
     :or {arguments [] base-revision "-"}
     :as request}
    timeout-ms]
   (when (closed? control-plane)
     (throw (ex-info "control plane is closed" {:kind :control-plane-closed})))
   (when (str/blank? (str input-path))
     (throw (ex-info "control-plane operation requires an input path"
                     {:kind :invalid-request :request request})))
   (capability/require-lean-operation! (:inventory control-plane) operation)
   (let [exchange-request
         (client/request
          {:request-id request-id
           :operation operation
           :input-path input-path
           :base-revision base-revision
           :arguments arguments
           :capabilities capabilities})]
     (worker-pool/invoke! (:pool control-plane) exchange-request timeout-ms))))

(defn payload!
  "Return an authoritative payload or throw a semantic-operation error.

  Transport failures remain transport failures. A valid Lean response with status other
  than `ok` is represented separately so callers cannot confuse it with denial or an
  unsafe semantic payload."
  [response]
  (if (= "ok" (:status response))
    (:payload response)
    (throw (ex-info "Lean-authoritative operation failed"
                    {:kind :semantic-operation-error
                     :status (:status response)
                     :operation (:operation response)
                     :request-id (:request_id response)
                     :errors (:errors response)
                     :response response}))))

(defn invoke-payload!
  ([control-plane request]
   (payload! (invoke! control-plane request)))
  ([control-plane request timeout-ms]
   (payload! (invoke! control-plane request timeout-ms))))

(defn with-control-plane
  "Use an injected control plane or create and close one for the supplied function."
  [options function]
  (if-let [control-plane (:control-plane options)]
    (function control-plane)
    (let [control-plane
          (start! {:pool-size (or (:pool-size options) 1)
                   :inventory (:capability-inventory options)
                   :inventory-path (:capability-inventory-path options)
                   :worker-options (merge
                                    (select-keys options [:directory :environment])
                                    (:worker-options options))})]
      (try
        (function control-plane)
        (finally
          (stop! control-plane))))))
