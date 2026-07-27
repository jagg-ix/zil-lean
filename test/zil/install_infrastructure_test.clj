(ns zil.install-infrastructure-test
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]))

(def required-files
  ["scripts/lib/common.sh"
   "scripts/self-check.sh"
   "scripts/public-content-audit.sh"
   "scripts/doctor.sh"
   "scripts/setup.sh"
   "scripts/test.sh"
   "scripts/setup.ps1"
   "scripts/test.ps1"
   "config/test-profiles.edn"
   "Dockerfile.test"
   "compose.test.yml"
   ".dockerignore"
   "Makefile"
   "TESTING.md"
   "PUBLIC-CONTENT-POLICY.md"
   "spec/install-test-infrastructure-v1.md"])

(def expected-profiles
  #{:smoke :lean :clojure :hybrid :durable :all :container})

(defn- read-text [path]
  (slurp (io/file path)))

(deftest installation-files-are-present
  (doseq [path required-files]
    (is (.isFile (io/file path)) (str path " should exist"))))

(deftest test-profile-contract-is-complete
  (let [value (edn/read-string (read-text "config/test-profiles.edn"))
        profiles (:profiles value)
        ids (mapv :id profiles)]
    (is (= "ZIL-TEST-PROFILES/1" (:schema value)))
    (is (= expected-profiles (set ids)))
    (is (= (count ids) (count (distinct ids))))
    (is (contains? expected-profiles (:default-profile value)))
    (is (= "ZIL-TEST-REPORT/1" (:report-schema value)))
    (doseq [{:keys [id doctor-profile description requires]} profiles]
      (is (keyword? id))
      (is (keyword? doctor-profile))
      (is (not (str/blank? description)))
      (is (set? requires)))))

(deftest public-launcher-exposes-setup-and-tests
  (let [launcher (read-text "bin/zil")]
    (doseq [command ["self-check" "setup" "doctor" "test" "test-container"]]
      (is (str/includes? launcher (str "  bin/zil " command))))
    (is (str/includes? launcher "scripts/self-check.sh"))
    (is (str/includes? launcher "scripts/setup.sh"))
    (is (str/includes? launcher "scripts/doctor.sh"))
    (is (str/includes? launcher "scripts/test.sh"))
    (is (str/includes? launcher "compose.test.yml"))))

(deftest self-check-remains-build-independent
  (let [self-check (read-text "scripts/self-check.sh")]
    (is (str/includes? self-check "ZIL-INSTALL-SELF-CHECK/1"))
    (is (str/includes? self-check "bash -n"))
    (is (str/includes? self-check "scripts/public-content-audit.sh"))
    (is (str/includes? self-check "docker compose -f compose.test.yml config --quiet"))
    (is (not (str/includes? self-check "lake build")))
    (is (not (str/includes? self-check "clojure -M:test")))))

(deftest public-content-audit-is-generic
  (let [audit (read-text "scripts/public-content-audit.sh")
        policy (read-text "PUBLIC-CONTENT-POLICY.md")]
    (is (str/includes? audit "ZIL-PUBLIC-CONTENT-AUDIT/1"))
    (is (str/includes? audit "personal-home-path"))
    (is (str/includes? audit "private-repository-url"))
    (is (str/includes? audit "private-key-material"))
    (is (str/includes? audit "email-address"))
    (is (str/includes? audit "git ls-files"))
    (is (str/includes? policy "unpublished research notes"))
    (is (str/includes? policy "repository-relative source paths"))))

(deftest posix-runner-declares-every-host-profile
  (let [runner (read-text "scripts/test.sh")]
    (doseq [profile [:smoke :lean :clojure :hybrid :durable :all]]
      (is (str/includes? runner (name profile))))
    (is (str/includes? runner "ZIL-TEST-REPORT/1"))
    (is (str/includes? runner "--keep-workdir"))
    (is (str/includes? runner "control-store verify"))
    (is (str/includes? runner "macro-parity"))
    (is (str/includes? runner "${suite:+$suite-}"))
    (is (str/includes? runner "logs=\"${report}.logs\""))))

(deftest bootstrap-does-not-hide-privileged-installs
  (let [setup (read-text "scripts/setup.sh")]
    (is (not (re-find #"(?m)^\s*sudo\s" setup)))
    (is (str/includes? setup "--install-tools"))
    (is (str/includes? setup "--default-toolchain none"))
    (is (str/includes? setup "posix-install.sh"))))

(deftest container-is-versioned-and-runs-profile-runner
  (let [dockerfile (read-text "Dockerfile.test")
        compose (read-text "compose.test.yml")]
    (is (str/includes? dockerfile "ubuntu:24.04"))
    (is (re-find #"CLOJURE_TOOLS_VERSION=\d+\.\d+\.\d+\.\d+" dockerfile))
    (is (str/includes? dockerfile "scripts/test.sh"))
    (is (str/includes? compose "ZIL_TEST_PROFILE"))
    (is (str/includes? compose "/workspace/.zil/test-reports"))))

(deftest makefile-covers-all-supported-entry-points
  (let [makefile (read-text "Makefile")]
    (doseq [target ["self-check:" "setup:" "bootstrap:" "doctor:" "test:"
                    "test-all:" "container-build:" "container-test:" "clean-test:"]]
      (is (str/includes? makefile target)))))
