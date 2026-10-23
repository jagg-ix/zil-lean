(ns zil.bridge-souffle-ci-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.souffle-ci :as ci]))

(deftest compare-query-results-requires-exact-names-vars-and-rows-test
  (let [zil {"reachable" {:vars ["?x" "?y"] :rows [["a" "b"] ["a" "c"]]}}
        same {"reachable" {:vars ["?x" "?y"] :rows [["a" "c"] ["a" "b"]]}}
        missing {"reachable" {:vars ["?x" "?y"] :rows [["a" "b"]]}}
        report (ci/compare-query-results zil same)
        mismatch (ci/compare-query-results zil missing)]
    (is (:ok report))
    (is (= 1 (:query_count report)))
    (is (false? (:ok mismatch)))
    (is (= [["a" "c"]] (get-in mismatch [:queries 0 :zil_only])))))
