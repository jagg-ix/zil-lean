(ns zil.evaluation.architecture
  "Evidence-driven Lean, Clojure, and hybrid architecture evaluation."
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [clojure.string :as str]))

(def schema "ZIL-RUNTIME-EVALUATION/1")
(def report-schema "ZIL-ARCHITECTURE-EVALUATION/1")
(def candidates #{:lean :clojure :hybrid})
(def metrics
  #{:correctness :latency :throughput :maintenance :extensibility
    :proof-coverage :reliability :deployment-simplicity})

(def default-weights
  {:correctness 0.20
   :latency 0.10
   :throughput 0.10
   :maintenance 0.15
   :extensibility 0.15
   :proof-coverage 0.15
   :reliability 0.10
   :deployment-simplicity 0.05})

(def default-policy
  {:minimum-metrics 6
   :minimum-confidence 0.60
   :minimum-samples 1
   :decision-margin 0.05})

(defn load-edn [path]
  (edn/read-string (slurp (io/file path))))

(defn- duplicates [values]
  (->> values frequencies (keep (fn [[value n]] (when (> n 1) value))) sort vec))

(defn validate-model! [model]
  (when-not (= schema (:schema model))
    (throw (ex-info "unsupported runtime evaluation schema"
                    {:kind :evaluation-error :schema (:schema model)})))
  (let [components (vec (:components model))
        ids (mapv :id components)
        duplicate-ids (duplicates ids)
        weights (merge default-weights (:weights model))
        policy (merge default-policy (:policy model))]
    (when (seq duplicate-ids)
      (throw (ex-info "runtime evaluation has duplicate component ids"
                      {:kind :evaluation-error :ids duplicate-ids})))
    (when-not (= metrics (set (keys weights)))
      (throw (ex-info "runtime evaluation weights must cover every metric"
                      {:kind :evaluation-error
                       :expected metrics :actual (set (keys weights))})))
    (when-not (< (Math/abs (- 1.0 (reduce + 0.0 (vals weights)))) 1.0e-9)
      (throw (ex-info "runtime evaluation weights must sum to 1.0"
                      {:kind :evaluation-error :weights weights})))
    (doseq [{:keys [id current candidates constraints]} components]
      (when-not (keyword? id)
        (throw (ex-info "component id must be a keyword"
                        {:kind :evaluation-error :component id})))
      (when-not (contains? zil.evaluation.architecture/candidates current)
        (throw (ex-info "component current runtime is invalid"
                        {:kind :evaluation-error :component id :current current})))
      (when-not (seq candidates)
        (throw (ex-info "component requires at least one candidate"
                        {:kind :evaluation-error :component id})))
      (when-not (set/subset? (set candidates) zil.evaluation.architecture/candidates)
        (throw (ex-info "component declares an invalid candidate"
                        {:kind :evaluation-error :component id :candidates candidates})))
      (when (and (:requires-kernel-evidence constraints)
                 (not (some #{:lean :hybrid} candidates)))
        (throw (ex-info "kernel-evidence component requires Lean participation"
                        {:kind :evaluation-error :component id}))))
    (assoc model :weights weights :policy policy :components components)))

(defn validate-measurement! [component-ids measurement]
  (let [{:keys [component candidate metric value confidence samples source]} measurement]
    (when-not (contains? component-ids component)
      (throw (ex-info "measurement references an unknown component"
                      {:kind :measurement-error :measurement measurement})))
    (when-not (contains? candidates candidate)
      (throw (ex-info "measurement candidate is invalid"
                      {:kind :measurement-error :measurement measurement})))
    (when-not (contains? metrics metric)
      (throw (ex-info "measurement metric is invalid"
                      {:kind :measurement-error :measurement measurement})))
    (when-not (and (number? value) (<= 0.0 (double value) 1.0))
      (throw (ex-info "measurement value must be in [0,1]"
                      {:kind :measurement-error :measurement measurement})))
    (when-not (and (number? confidence) (<= 0.0 (double confidence) 1.0))
      (throw (ex-info "measurement confidence must be in [0,1]"
                      {:kind :measurement-error :measurement measurement})))
    (when-not (and (integer? samples) (pos? samples))
      (throw (ex-info "measurement samples must be a positive integer"
                      {:kind :measurement-error :measurement measurement})))
    (when (str/blank? (str source))
      (throw (ex-info "measurement source must be nonempty"
                      {:kind :measurement-error :measurement measurement})))
    measurement))

(defn normalize-measurements [model measurements]
  (let [component-ids (set (map :id (:components model)))]
    (mapv #(validate-measurement! component-ids %) measurements)))

(defn- candidate-eligible? [component candidate]
  (let [constraints (:constraints component)]
    (and (some #{candidate} (:candidates component))
         (not (and (:requires-kernel-evidence constraints)
                   (= candidate :clojure)))
         (not (and (:requires-dynamic-plugins constraints)
                   (= candidate :lean)))
         (not (and (:requires-lean-only-profile constraints)
                   (= candidate :clojure))))))

(defn- aggregate-metric [values]
  (let [weight-total (reduce + 0.0 (map #(* (:confidence %) (:samples %)) values))]
    (when (pos? weight-total)
      {:value (/ (reduce + 0.0
                         (map #(* (:value %) (:confidence %) (:samples %)) values))
                 weight-total)
       :confidence (/ (reduce + 0.0 (map #(* (:confidence %) (:samples %)) values))
                      (reduce + 0.0 (map :samples values)))
       :samples (reduce + 0 (map :samples values))
       :sources (vec (sort (distinct (map :source values))))})))

(defn- candidate-score [model component candidate measurements]
  (if-not (candidate-eligible? component candidate)
    {:candidate candidate :eligible false :reason :constraint}
    (let [grouped (group-by :metric
                            (filter #(and (= (:id component) (:component %))
                                          (= candidate (:candidate %)))
                                    measurements))
          metric-results
          (into (sorted-map)
                (keep (fn [metric]
                        (when-let [value (aggregate-metric (get grouped metric))]
                          [metric value])))
                metrics)
          policy (:policy model)
          accepted
          (into (sorted-map)
                (filter (fn [[_ value]]
                          (and (>= (:confidence value) (:minimum-confidence policy))
                               (>= (:samples value) (:minimum-samples policy)))))
                metric-results)
          covered-weight (reduce + 0.0 (map #(get-in model [:weights %]) (keys accepted)))
          score (when (pos? covered-weight)
                  (/ (reduce + 0.0
                             (map (fn [[metric value]]
                                    (* (get-in model [:weights metric]) (:value value)))
                                  accepted))
                     covered-weight))]
      {:candidate candidate
       :eligible true
       :metric-count (count accepted)
       :covered-weight covered-weight
       :score score
       :metrics metric-results
       :accepted-metrics accepted})))

(defn- decision [model component scored]
  (let [eligible (->> scored
                      (filter :eligible)
                      (filter #(>= (:metric-count % 0)
                                   (get-in model [:policy :minimum-metrics])))
                      (filter :score)
                      (sort-by (juxt (comp - :score) :candidate))
                      vec)
        best (first eligible)
        second-best (second eligible)
        margin (when best
                 (- (:score best) (or (:score second-best) 0.0)))
        enough-margin (and best
                           (or (nil? second-best)
                               (>= margin (get-in model [:policy :decision-margin]))))]
    (cond
      (nil? best)
      {:status :insufficient-evidence
       :current (:current component)
       :recommended nil
       :reason :coverage}

      (not enough-margin)
      {:status :review-required
       :current (:current component)
       :recommended (:candidate best)
       :score (:score best)
       :margin margin
       :reason :close-scores}

      (= (:candidate best) (:current component))
      {:status :retain-current
       :current (:current component)
       :recommended (:candidate best)
       :score (:score best)
       :margin margin}

      :else
      {:status :candidate-change
       :current (:current component)
       :recommended (:candidate best)
       :score (:score best)
       :margin margin
       :requires-human-approval true})))

(defn evaluate
  [model measurements]
  (let [model (validate-model! model)
        measurements (normalize-measurements model measurements)
        components
        (mapv
         (fn [component]
           (let [scored (mapv #(candidate-score model component % measurements)
                              (:candidates component))]
             {:id (:id component)
              :description (:description component)
              :constraints (:constraints component)
              :scores scored
              :decision (decision model component scored)}))
         (:components model))]
    {:schema report-schema
     :model-schema schema
     :policy (:policy model)
     :weights (:weights model)
     :measurement-count (count measurements)
     :components components
     :summary
     {:retain-current (count (filter #(= :retain-current
                                         (get-in % [:decision :status])) components))
      :candidate-change (count (filter #(= :candidate-change
                                           (get-in % [:decision :status])) components))
      :review-required (count (filter #(= :review-required
                                          (get-in % [:decision :status])) components))
      :insufficient-evidence (count (filter #(= :insufficient-evidence
                                                (get-in % [:decision :status])) components))}}))
