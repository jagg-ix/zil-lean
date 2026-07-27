(ns zil.model-exchange-test
  (:require [clojure.test :refer [deftest is]]
            [zil.model-exchange :as mx]
            [zil.profile.z3 :as z3]))

(defn- tmp-dir
  []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-model-bundle"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(def tm-atom-minimal
  "TM_ATOM parity [states=#{q0 qa qr}, alphabet=#{0 _}, blank=_, initial=q0, accept=#{qa}, reject=#{qr}, transitions={[q0 0] [q0 0 :R], [q0 _] [qa _ :N]}].")

(def lts-atom-minimal
  "LTS_ATOM flow [states=#{idle running failed}, initial=idle, transitions={[idle start] [running], [running fail] [failed alert_ops]}].")

(def constraint-minimal
  "POLICY p1 [condition=\"latency > 120\", criticality=high].")

(defn- with-z3
  [f]
  (if (z3/z3-available?)
    (f)
    (is true "z3 unavailable; skipping SMT-backed assertions")))

(deftest bundle-check-validates-tm-atom-policy-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bundle.zc")]
    (spit model-file (str "MODULE bundle.ok.\n"
                          tm-atom-minimal
                          "\n"))
    (let [report (mx/check-bundle (.getAbsolutePath dir))]
      (is (:ok report))
      (is (= 1 (:tm_atoms report))))))

(deftest bundle-check-fails-without-profile-unit-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bundle.zc")]
    (spit model-file "MODULE bundle.bad.
SERVICE web [env=prod].
")
    (let [report (mx/check-bundle (.getAbsolutePath dir))]
      (is (false? (:ok report)))
      (is (= 0 (:tm_atoms report)))
      (is (some #(= :policy (:type %)) (:errors report))))))

(deftest bundle-check-supports-lts-and-constraint-profiles-test
  (let [dir (tmp-dir)
        lts-file (java.io.File. dir "bundle-lts.zc")
        constraint-file (java.io.File. dir "bundle-constraint.zc")]
    (spit lts-file (str "MODULE bundle.lts.\n" lts-atom-minimal "\n"))
    (spit constraint-file (str "MODULE bundle.constraint.\n" constraint-minimal "\n"))
    (let [lts-report (mx/check-bundle (.getAbsolutePath lts-file) {:profile "lts"})
          constraint-report (mx/check-bundle (.getAbsolutePath constraint-file) {:profile :constraint})]
      (is (:ok lts-report))
      (is (= :lts (:profile lts-report)))
      (is (= :lts_atom (:unit_kind lts-report)))
      (is (:ok constraint-report))
      (is (= :constraint (:profile constraint-report)))
      (is (= :policy (:unit_kind constraint-report))))))

(deftest auto-profile-infers-from-dsl-profile-test
  (let [dir (tmp-dir)
        file (java.io.File. dir "bundle-auto-lts.zc")]
    (spit file (str "MODULE bundle.auto.lts.\n"
                    "QUERY_PACK qp_main [queries=[q_health]].\n"
                    "DSL_PROFILE ops [query_pack=qp_main, verification_chain=[lts], planner_hint=high_selectivity_first].\n"
                    lts-atom-minimal
                    "\n"))
    (let [report (mx/check-bundle (.getAbsolutePath file) {:profile :auto})]
      (is (:ok report))
      (is (= :auto (:requested_profile report)))
      (is (= :lts (:profile report)))
      (is (= :lts_atom (:unit_kind report))))))

(deftest constraint-profile-solver-checks-sat-and-unsat-test
  (with-z3
   (fn []
     (let [dir (tmp-dir)
           sat-file (java.io.File. dir "sat.zc")
           unsat-file (java.io.File. dir "unsat.zc")]
       (spit sat-file "MODULE c.sat.
POLICY p1 [condition=\"latency > 120\", criticality=high].
")
       (spit unsat-file "MODULE c.unsat.
POLICY bad [condition=\"x > 0 AND x < 0\", criticality=high].
")
       (let [sat-report (mx/check-bundle (.getAbsolutePath sat-file) {:profile :constraint})
             unsat-report (mx/check-bundle (.getAbsolutePath unsat-file) {:profile :constraint})]
         (is (:ok sat-report))
         (is (false? (:ok unsat-report)))
         (is (some #(= :solver (:type %)) (:errors unsat-report))))))))

(deftest constraint-profile-solver-supports-implies-test
  (with-z3
   (fn []
     (let [dir (tmp-dir)
           sat-file (java.io.File. dir "implies-sat.zc")
           unsat-file (java.io.File. dir "implies-unsat.zc")]
       (spit sat-file "MODULE c.impl.sat.
POLICY p1 [condition=\"x > 0 IMPLIES y > 0\", criticality=high].
")
       (spit unsat-file "MODULE c.impl.unsat.
POLICY p1 [condition=\"x > 0 IMPLIES y > 0\", criticality=high].
POLICY p2 [condition=\"x > 0\", criticality=high].
POLICY p3 [condition=\"y < 0\", criticality=high].
")
       (let [sat-report (mx/check-bundle (.getAbsolutePath sat-file) {:profile :constraint})
             unsat-report (mx/check-bundle (.getAbsolutePath unsat-file) {:profile :constraint})]
         (is (:ok sat-report))
         (is (false? (:ok unsat-report)))
         (is (some #(= :solver (:type %)) (:errors unsat-report))))))))

(deftest constraint-profile-solver-detects-joint-conflicts-test
  (with-z3
   (fn []
     (let [dir (tmp-dir)
           file (java.io.File. dir "joint-unsat.zc")]
       (spit file "MODULE c.joint.
POLICY p1 [condition=\"x > 10\", criticality=high].
POLICY p2 [condition=\"x < 0\", criticality=high].
")
       (let [report (mx/check-bundle (.getAbsolutePath file) {:profile :constraint})]
         (is (false? (:ok report)))
         (is (some #(and (= :solver (:type %))
                         (= :bundle (:scope %)))
                   (:errors report))))))))

(deftest resolve-profile-rejects-unsupported-profile-test
  (is (thrown? clojure.lang.ExceptionInfo
               (mx/check-bundle "examples" {:profile "petri-net"}))))

(deftest commit-check-requires-single-tm-atom-per-file-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "unit.zc")]
    (spit model-file (str "MODULE commit.ok.\n"
                          tm-atom-minimal
                          "\n"))
    (let [report (mx/check-commit (.getAbsolutePath dir))]
      (is (:ok report))
      (is (= :tm_atom_commit (:policy report)))
      (is (= :tm.det (:profile report)))
      (is (= 1 (:tm_atoms report)))
      (is (= :tm_atom (:unit_kind report))))))

(deftest commit-check-rejects-non-tm-or-multi-tm-file-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bad-unit.zc")
        tm-atom-second (clojure.string/replace tm-atom-minimal "TM_ATOM parity" "TM_ATOM parity2")]
    (spit model-file (str "MODULE commit.bad.\n"
                          tm-atom-minimal
                          "\n"
                          "SERVICE web [env=prod].\n"
                          tm-atom-second
                          "\n"))
    (let [report (mx/check-commit (.getAbsolutePath dir))
          policy-errors (filter #(= :policy (:type %)) (:errors report))]
      (is (false? (:ok report)))
      (is (some #(re-find #"exactly one TM_ATOM" (:error %)) policy-errors))
      (is (some #(re-find #"only TM_ATOM declarations" (:error %)) policy-errors)))))

(deftest commit-check-lts-profile-strict-and-relaxed-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "lts-unit.zc")]
    (spit model-file (str "MODULE commit.lts.\n"
                          lts-atom-minimal
                          "\nSERVICE helper [env=prod].\n"))
    (let [strict-report (mx/check-commit (.getAbsolutePath dir) {:profile "lts"})
          relaxed-report (mx/check-commit (.getAbsolutePath dir)
                                          {:profile "lts"
                                           :strict-units-only? false})]
      (is (false? (:ok strict-report)))
      (is (some #(re-find #"only LTS_ATOM declarations" (:error %))
                (filter #(= :policy (:type %)) (:errors strict-report))))
      (is (:ok relaxed-report))
      (is (= :lts_atom_commit (:policy relaxed-report)))
      (is (= :lts_atom (:unit_kind relaxed-report))))))

(deftest commit-check-auto-profile-falls-back-to-tmdet-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "auto-tm.zc")]
    (spit model-file (str "MODULE commit.auto.tm.\n"
                          tm-atom-minimal
                          "\n"))
    (let [report (mx/check-commit (.getAbsolutePath dir) {:profile :auto})]
      (is (:ok report))
      (is (= :auto (:requested_profile report)))
      (is (= :tm.det (:profile report)))
      (is (= :tm_atom_commit (:policy report))))))

(deftest commit-check-constraint-unsat-fails-with-solver-error-test
  (with-z3
   (fn []
     (let [dir (tmp-dir)
           file (java.io.File. dir "constraint-bad.zc")]
       (spit file "MODULE c.commit.
POLICY bad [condition=\"x > 0 AND x < 0\", criticality=high].
")
       (let [report (mx/check-commit (.getAbsolutePath dir) {:profile :constraint})]
         (is (false? (:ok report)))
         (is (some #(= :solver (:type %)) (:errors report))))))))
