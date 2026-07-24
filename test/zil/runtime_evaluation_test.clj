(ns zil.runtime-evaluation-test
  (:require [clojure.test :refer [deftest is]]
            [zil.evaluation.architecture :as architecture]))

(def metric-order
  [:correctness :latency :throughput :maintenance :extensibility
   :proof-coverage :reliability :deployment-simplicity])

(defn- measurements-for [component candidate value]
  (mapv (fn [metric]
          {:component component
           :candidate candidate
           :metric metric
           :value value
           :confidence 0.9
           :samples 5
           :source (str "fixture:" (name component) ":" (name candidate)
                        ":" (name metric))})
        metric-order))

(deftest empty-evidence-does-not-change-architecture
  (let [model (architecture/load-edn "architecture/runtime-evaluation.edn")
        report (architecture/evaluate model [])]
    (is (= "ZIL-ARCHITECTURE-EVALUATION/1" (:schema report)))
    (is (= (count (:components model))
           (get-in report [:summary :insufficient-evidence])))
    (is (zero? (get-in report [:summary :candidate-change])))))

(deftest measured-candidate-change-requires-human-approval
  (let [model (architecture/load-edn "architecture/runtime-evaluation.edn")
        measurements
        (vec (concat
              (measurements-for :exchange-supervision :clojure 0.55)
              (measurements-for :exchange-supervision :hybrid 0.90)
              (measurements-for :exchange-supervision :lean 0.35)))
        report (architecture/evaluate model measurements)
        component (first (filter #(= :exchange-supervision (:id %))
                                 (:components report)))]
    (is (= :candidate-change (get-in component [:decision :status])))
    (is (= :hybrid (get-in component [:decision :recommended])))
    (is (true? (get-in component [:decision :requires-human-approval])))))

(deftest kernel-constraint-excludes-clojure-only-candidate
  (let [model (architecture/load-edn "architecture/runtime-evaluation.edn")
        measurements
        (vec (concat
              (measurements-for :semantic-kernel :lean 0.80)
              (measurements-for :semantic-kernel :hybrid 0.75)
              (measurements-for :semantic-kernel :clojure 1.00)))
        report (architecture/evaluate model measurements)
        component (first (filter #(= :semantic-kernel (:id %))
                                 (:components report)))
        clojure-score (first (filter #(= :clojure (:candidate %))
                                     (:scores component)))]
    (is (false? (:eligible clojure-score)))
    (is (= :retain-current (get-in component [:decision :status])))
    (is (= :lean (get-in component [:decision :recommended])))))

(deftest sparse-or-low-confidence-measurements-remain-insufficient
  (let [model (architecture/load-edn "architecture/runtime-evaluation.edn")
        measurements
        [{:component :extension-registry
          :candidate :clojure
          :metric :extensibility
          :value 0.95
          :confidence 0.4
          :samples 1
          :source "fixture:sparse"}]
        report (architecture/evaluate model measurements)
        component (first (filter #(= :extension-registry (:id %))
                                 (:components report)))]
    (is (= :insufficient-evidence (get-in component [:decision :status])))))

(deftest undeclared-measurement-candidates-fail-closed
  (let [model (-> (architecture/load-edn "architecture/runtime-evaluation.edn")
                  (update :components
                          (fn [components]
                            (mapv (fn [component]
                                    (if (= :exchange-supervision (:id component))
                                      (assoc component :candidates [:clojure :hybrid])
                                      component))
                                  components))))
        measurement {:component :exchange-supervision
                     :candidate :lean
                     :metric :correctness
                     :value 0.9
                     :confidence 0.9
                     :samples 3
                     :source "fixture:undeclared"}]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"not declared"
                          (architecture/evaluate model [measurement])))))

(deftest malformed-component-candidate-lists-fail-closed
  (let [model (architecture/load-edn "architecture/runtime-evaluation.edn")
        duplicate-model
        (update model :components
                (fn [components]
                  (mapv (fn [component]
                          (if (= :semantic-kernel (:id component))
                            (assoc component :candidates [:lean :lean :hybrid])
                            component))
                        components)))]
    (is (thrown-with-msg? clojure.lang.ExceptionInfo
                          #"candidates must be unique"
                          (architecture/evaluate duplicate-model [])))))
