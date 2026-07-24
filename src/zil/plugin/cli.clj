(ns zil.plugin.cli
  "CLI for extension discovery, inspection, invocation, and evidence production."
  (:gen-class)
  (:require [clojure.data.json :as json]
            [clojure.edn :as edn]
            [clojure.set :as set]
            [clojure.string :as str]
            [zil.control.capability :as capability]
            [zil.control.runtime :as control]
            [zil.plugin.manifest :as manifest]
            [zil.plugin.registry :as registry]
            [zil.worker.protocol :as worker-protocol]))

(def default-root "extensions")

(def usage
  (str "zil-plugin list [ROOT...]\n"
       "zil-plugin inspect <extension.json>\n"
       "zil-plugin run <extension.json> <command> [arguments...] [--config FILE]\n"
       "zil-plugin evidence <extension.json> <request.edn> [--config FILE]"))

(defn- extract-config [arguments]
  (loop [remaining (seq arguments)
         positional []
         config {}]
    (if-not remaining
      {:arguments positional :config config}
      (if (= "--config" (first remaining))
        (let [path (second remaining)]
          (when (str/blank? path)
            (throw (ex-info "--config requires an EDN file"
                            {:kind :invalid-command})))
          (recur (nnext remaining)
                 positional
                 (edn/read-string (slurp path))))
        (recur (next remaining) (conj positional (first remaining)) config)))))

(defn- requires-lean-worker? [extension-manifest]
  (let [requirements (set (:requires extension-manifest))
        worker-requirements
        (conj (set (vals worker-protocol/operation-capabilities))
              worker-protocol/schema)]
    (boolean (seq (set/intersection requirements worker-requirements)))))

(defn- control-plane-for [extension-manifest]
  (let [inventory (capability/load-valid-inventory)]
    (if (requires-lean-worker? extension-manifest)
      (control/start! {:pool-size 1 :inventory inventory})
      (control/->ControlPlane nil inventory (atom false)
                              {:profile :exploratory-extension})))))

(defn- with-registry [manifest-path function]
  (let [extension-manifest (manifest/read-manifest manifest-path)
        control-plane (control-plane-for extension-manifest)
        extension-registry (registry/create-registry {:control-plane control-plane})]
    (try
      (function extension-manifest control-plane extension-registry)
      (finally
        (registry/close! extension-registry)
        (control/stop! control-plane)))))

(defn- list-extensions [roots]
  (mapv (fn [file]
          (let [value (manifest/with-fingerprint
                       (manifest/read-manifest (.getPath file)))]
            {:path (.getCanonicalPath file)
             :id (:id value)
             :version (:version value)
             :runtime (:runtime value)
             :authority (:authority value)
             :capabilities (:capabilities value)
             :fingerprint (:fingerprint value)}))
        (registry/discover-manifests (if (seq roots) roots [default-root]))))

(defn -main [& args]
  (try
    (let [[command & tail] args]
      (case command
        "list"
        (println (json/write-str (list-extensions tail)))

        "inspect"
        (let [[path & extra] tail]
          (when (or (str/blank? path) (seq extra))
            (throw (ex-info usage {:kind :invalid-command})))
          (println (json/write-str
                    (manifest/with-fingerprint (manifest/read-manifest path)))))

        "run"
        (let [[manifest-path extension-command & remaining] tail
              {:keys [arguments config]} (extract-config remaining)]
          (when (or (str/blank? manifest-path) (str/blank? extension-command))
            (throw (ex-info usage {:kind :invalid-command})))
          (with-registry
            manifest-path
            (fn [_ _ extension-registry]
              (registry/load-and-register! extension-registry manifest-path config {})
              (println
               (json/write-str
                (registry/invoke-command! extension-registry
                                          extension-command
                                          {}
                                          arguments))))))

        "evidence"
        (let [[manifest-path request-path & remaining] tail
              {:keys [arguments config]} (extract-config remaining)]
          (when (or (str/blank? manifest-path)
                    (str/blank? request-path)
                    (seq arguments))
            (throw (ex-info usage {:kind :invalid-command})))
          (let [request (edn/read-string (slurp request-path))]
            (with-registry
              manifest-path
              (fn [_ _ extension-registry]
                (let [registered
                      (registry/load-and-register! extension-registry
                                                   manifest-path config {})]
                  (println
                   (json/write-str
                    (registry/produce-evidence! extension-registry
                                                (:id registered)
                                                {}
                                                request))))))))

        (throw (ex-info usage {:kind :invalid-command :command command}))))
    (catch Exception error
      (binding [*out* *err*]
        (println (.getMessage error))
        (when-let [data (ex-data error)]
          (println (pr-str data))))
      (System/exit 2))))
