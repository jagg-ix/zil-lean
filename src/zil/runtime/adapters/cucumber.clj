(ns zil.runtime.adapters.cucumber
  "Cucumber JSON adapter.

  Reads a standard Cucumber JSON report and emits normalized step-event records
  carrying:
  - event id
  - local vector-clock component (scenario actor counter)
  - explicit before edge to previous step in same scenario"
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [zil.runtime.adapters.core :as ac]))

(defn- slug
  [x]
  (-> (str x)
      str/lower-case
      (str/replace #"[^a-z0-9]+" "_")
      (str/replace #"^_+|_+$" "")
      (#(if (str/blank? %) "unnamed" %))))

(defn- parse-json
  [path]
  (json/read-str (slurp path) :key-fn keyword))

(defn- features-from-payload
  [payload]
  (cond
    (sequential? payload) (vec payload)
    (map? payload) [payload]
    :else
    (throw (ex-info "Unsupported cucumber payload root"
                    {:type (type payload)}))))

(defn- scenarios-of
  [feature]
  (or (:elements feature) (:scenarios feature) []))

(defn- scenario-type
  [scenario]
  (-> (or (:type scenario) "scenario")
      str
      str/lower-case))

(defn- allowed-scenario?
  [scenario]
  (contains? #{"scenario" "scenario_outline"} (scenario-type scenario)))

(defn- steps-of
  [scenario]
  (or (:steps scenario) []))

(defn- feature-id
  [feature idx]
  (or (:id feature)
      (str "feature_" (inc idx) "_" (slug (or (:name feature) "feature")))))

(defn- scenario-id
  [feature-id* scenario idx]
  (or (:id scenario)
      (str feature-id* "__scenario_" (inc idx) "_" (slug (or (:name scenario) "scenario")))))

(defn- step-id
  [scenario-id* step-idx]
  (str "evt:" (slug scenario-id*) "__step_" (format "%03d" (inc step-idx))))

(defn- step-status
  [step]
  (-> (or (get-in step [:result :status]) "unknown")
      str
      str/lower-case))

(defn- step-duration-ns
  [step]
  (let [v (get-in step [:result :duration])]
    (cond
      (integer? v) (long v)
      (number? v) (long v)
      (string? v) (Long/parseLong (str/trim v))
      :else 0)))

(defn- step-records
  [feature-idx feature]
  (let [fid (feature-id feature feature-idx)
        uri (or (:uri feature) "unknown")]
    (->> (scenarios-of feature)
         (map-indexed
          (fn [scenario-idx scenario]
            (if-not (allowed-scenario? scenario)
              []
              (let [sid (scenario-id fid scenario scenario-idx)
                    sname (or (:name scenario) "scenario")]
                (->> (steps-of scenario)
                     (map-indexed
                      (fn [step-idx step]
                        (let [eid (step-id sid step-idx)
                              prev-eid (when (pos? step-idx)
                                         (step-id sid (dec step-idx)))
                              step-name (or (:name step) "")
                              keyword* (or (:keyword step) "")]
                          {:record_kind :cucumber_step
                           :feature (or (:name feature) "feature")
                           :feature_id fid
                           :scenario sname
                           :scenario_id sid
                           :step step-name
                           :step_keyword (str/trim keyword*)
                           :step_index (inc step-idx)
                           :status (step-status step)
                           :duration_ns (step-duration-ns step)
                           :event_id eid
                           :actor sid
                           :vector_clock {sid (inc step-idx)}
                           :before (if prev-eid [prev-eid] [])
                           :uri uri})))
                     vec)))))
         (remove nil?)
         (mapcat identity)
         vec)))

(defn read-cucumber
  [datasource _opts]
  (let [attrs (:attrs datasource)
        path (or (:path attrs) (:file attrs))]
    (when-not (and (string? path) (not (str/blank? path)))
      (throw (ex-info "CUCUMBER datasource requires :path"
                      {:datasource datasource})))
    (->> (parse-json path)
         features-from-payload
         (map-indexed step-records)
         (mapcat identity)
         vec)))

(ac/register-adapter! :cucumber read-cucumber)
