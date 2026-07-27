(ns zil.worker.pool
  "Bounded reusable pool for supervised Lean exchange workers."
  (:require [zil.worker.client :as client])
  (:import (java.util.concurrent ArrayBlockingQueue TimeUnit)))

(defrecord WorkerPool
  [^ArrayBlockingQueue available
   workers
   worker-options
   closed?])

(defn- start-workers! [size worker-options]
  (loop [remaining size
         workers []]
    (if (zero? remaining)
      workers
      (let [worker
            (try
              (client/start-worker! worker-options)
              (catch Exception error
                (doseq [started workers]
                  (try (client/stop-worker! started) (catch Exception _)))
                (throw error)))]
        (recur (dec remaining) (conj workers worker))))))

(defn start-pool!
  ([] (start-pool! {}))
  ([{:keys [size worker-options]
     :or {size 1 worker-options {}}}]
   (when-not (pos? size)
     (throw (ex-info "worker pool size must be positive" {:size size})))
   (let [workers (start-workers! size worker-options)
         queue (ArrayBlockingQueue. size)]
     (doseq [worker workers]
       (.put queue worker))
     (->WorkerPool queue (atom workers) worker-options (atom false)))))

(defn closed? [^WorkerPool pool]
  @(:closed? pool))

(defn- remove-worker! [^WorkerPool pool failed]
  (swap! (:workers pool)
         (fn [workers]
           (vec (remove #(identical? % failed) workers)))))

(defn- discard-worker! [^WorkerPool pool failed]
  (try (client/stop-worker! failed) (catch Exception _))
  (remove-worker! pool failed)
  (when-not (closed? pool)
    (try
      (let [replacement (client/start-worker! (:worker-options pool))]
        (swap! (:workers pool) conj replacement)
        (.put ^ArrayBlockingQueue (:available pool) replacement))
      (catch Exception _
        nil))))

(defn acquire!
  ([pool] (acquire! pool client/default-timeout-ms))
  ([^WorkerPool pool timeout-ms]
   (when (closed? pool)
     (throw (ex-info "worker pool is closed" {:kind :transport-error})))
   (or (.poll ^ArrayBlockingQueue (:available pool)
              (long timeout-ms) TimeUnit/MILLISECONDS)
       (throw (ex-info "timed out waiting for a Lean worker"
                       {:kind :transport-error :timeout-ms timeout-ms})))))

(defn release! [^WorkerPool pool worker]
  (cond
    (closed? pool)
    (try (client/stop-worker! worker) (catch Exception _))

    (client/alive? worker)
    (.put ^ArrayBlockingQueue (:available pool) worker)

    :else
    (discard-worker! pool worker)))

(defn invoke!
  ([pool request] (invoke! pool request client/default-timeout-ms))
  ([^WorkerPool pool request timeout-ms]
   (let [worker (acquire! pool timeout-ms)
         discard? (atom false)]
     (try
       (client/invoke! worker request timeout-ms)
       (catch Exception error
         (when (= :transport-error (:kind (ex-data error)))
           (reset! discard? true))
         (throw error))
       (finally
         (if @discard?
           (discard-worker! pool worker)
           (release! pool worker)))))))

(defn stop-pool! [^WorkerPool pool]
  (when (compare-and-set! (:closed? pool) false true)
    (doseq [worker @(:workers pool)]
      (try (client/stop-worker! worker) (catch Exception _)))
    (.clear ^ArrayBlockingQueue (:available pool)))
  {:closed true
   :workers (count @(:workers pool))})
