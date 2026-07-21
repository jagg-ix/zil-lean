(ns zil.runtime-datascript-vector-clock-test
  (:require [clojure.test :refer [deftest is]]
            [zil.runtime.datascript :as zr]))

(deftest vector-clock-ordering-test
  (is (zr/vector-clock-before? {"a" 1 "b" 0} {"a" 2 "b" 0}))
  (is (zr/vector-clock-before? {:a 1 :b 2} {:a 2 :b 3}))
  (is (not (zr/vector-clock-before? {"a" 2} {"a" 2})))
  (is (not (zr/vector-clock-before? {"a" 3} {"a" 2}))))

(deftest vector-clock-concurrency-test
  (is (zr/vector-clock-concurrent? {"a" 2 "b" 0} {"a" 1 "b" 3}))
  (is (not (zr/vector-clock-concurrent? {"a" 1} {"a" 2}))))

(deftest derive-before-edges-from-vector-clocks-test
  (let [events [{:event :evt_a1 :vector_clock {"A" 1}}
                {:event :evt_a2 :vector_clock {"A" 2}}
                {:event :evt_b1 :vector_clock {"B" 1}}
                {:event :evt_join :vector_clock {"A" 2 "B" 1}}]
        edges (set (zr/derive-before-edges-from-vector-clocks events))]
    (is (contains? edges {:left :evt_a1 :right :evt_a2}))
    (is (contains? edges {:left :evt_a2 :right :evt_join}))
    (is (contains? edges {:left :evt_b1 :right :evt_join}))
    (is (not (contains? edges {:left :evt_a1 :right :evt_b1})))
    (is (not (contains? edges {:left :evt_b1 :right :evt_a2})))))
