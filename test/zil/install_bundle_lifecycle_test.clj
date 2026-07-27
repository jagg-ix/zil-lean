(ns zil.install-bundle-lifecycle-test
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]))

(def required-files
  ["scripts/package.sh"
   "scripts/install.sh"
   "scripts/verify-install.sh"
   "scripts/uninstall.sh"
   "scripts/install-lifecycle-test.sh"
   "INSTALL-BUNDLES.md"
   "spec/install-bundle-lifecycle-v1.md"])

(defn- text [path]
  (slurp (io/file path)))

(deftest lifecycle-files-are-present
  (doseq [path required-files]
    (is (.isFile (io/file path)) (str path " should exist"))))

(deftest public-launcher-routes-lifecycle-commands
  (let [launcher (text "bin/zil")]
    (doseq [command ["package" "install" "verify-install" "uninstall" "test-install"]]
      (is (str/includes? launcher (str "  bin/zil " command))))
    (doseq [script ["scripts/package.sh" "scripts/install.sh"
                    "scripts/verify-install.sh" "scripts/uninstall.sh"
                    "scripts/install-lifecycle-test.sh"]]
      (is (str/includes? launcher script)))))

(deftest packager-is-commit-bound-and-hash-manifested
  (let [script (text "scripts/package.sh")]
    (is (str/includes? script "git archive --format=tar"))
    (is (str/includes? script "git rev-parse --verify"))
    (is (str/includes? script "ZIL-SOURCE-BUNDLE/1"))
    (is (str/includes? script "ZIL-BUNDLE-MANIFEST/1"))
    (is (str/includes? script "SHA256SUMS"))
    (is (str/includes? script "zil_sha256_file"))
    (is (str/includes? script "gzip -n"))))

(deftest copied-installs-are-immutable-and-atomically-activated
  (let [script (text "scripts/install.sh")
        common (text "scripts/lib/common.sh")]
    (is (str/includes? script "versions/$install_id"))
    (is (str/includes? script ".installing.$$"))
    (is (str/includes? script "mv \"$candidate\" \"$final_root\""))
    (is (str/includes? script "zil_replace_symlink \"$link_tmp\" \"$current\""))
    (is (str/includes? script "activation_started=true"))
    (is (str/includes? script "activation_complete=true"))
    (is (str/includes? script "failed to restore previous current pointer"))
    (is (str/includes? common "--no-target-directory"))
    (is (str/includes? common "mv -h"))
    (is (str/includes? script "ZIL-INSTALL-WRAPPER/1"))
    (is (str/includes? script "ZIL-INSTALL-STATE/1"))
    (is (str/includes? script "ZIL-INSTALL-ROOT/1"))
    (is (str/includes? script "source_id"))
    (is (str/includes? script "verify_bundle_manifest"))
    (is (str/includes? script "--prefix \"$prefix\""))))

(deftest installer-protects-unowned-wrapper-and-worktree-commits
  (let [script (text "scripts/install.sh")]
    (is (str/includes? script "git -C \"$source_root\" rev-parse HEAD"))
    (is (str/includes? script "refusing to replace launcher without installer ownership marker"))
    (is (str/includes? script "install_id=\"$install_id-$(zil_epoch)-$$\""))))

(deftest installed-wrapper-retains-management-path
  (let [script (text "scripts/install.sh")]
    (is (str/includes? script "verify-install)"))
    (is (str/includes? script "uninstall)"))
    (is (str/includes? script "ZIL_INSTALL_PREFIX"))
    (is (str/includes? script "scripts/verify-install.sh"))
    (is (str/includes? script "scripts/uninstall.sh"))))

(deftest verifier-checks-state-root-and-bundle-bytes
  (let [script (text "scripts/verify-install.sh")]
    (doseq [token ["ZIL-INSTALL-VERIFY/1"
                   "ZIL-INSTALL-STATE/1"
                   "ZIL-INSTALL-WRAPPER/1"
                   "ZIL-BUNDLE-MANIFEST.tsv"
                   "root-install-id"
                   "zil_sha256_file"
                   "scripts/self-check.sh"]]
      (is (str/includes? script token)))))

(deftest uninstaller-protects-unowned-and-linked-paths
  (let [script (text "scripts/uninstall.sh")]
    (is (str/includes? script "Preflight every path before deleting anything"))
    (is (str/includes? script "refusing to remove launcher without installer ownership marker"))
    (is (str/includes? script "refusing to remove non-symlink current path"))
    (is (str/includes? script "linked_source_deleted\\tfalse"))
    (is (str/includes? script "case \"$install_root\" in"))
    (is (str/includes? script "\"$versions\"/*"))))

(deftest lifecycle-test-is-dependency-light-and-isolated
  (let [script (text "scripts/install-lifecycle-test.sh")]
    (is (str/includes? script "ZIL-INSTALL-LIFECYCLE-TEST/1"))
    (is (str/includes? script "zil_temp_dir"))
    (is (str/includes? script "--no-build"))
    (is (str/includes? script "--no-verify"))
    (is (str/includes? script "--force"))
    (is (str/includes? script "inactive-retained"))
    (is (str/includes? script "purge-absence"))
    (is (str/includes? script "scripts/uninstall.sh"))
    (is (not (str/includes? script "lake build")))
    (is (not (str/includes? script "clojure -M:test")))))

(deftest makefile-exposes-lifecycle-targets
  (let [makefile (text "Makefile")]
    (doseq [target ["package:" "package-dir:" "install:" "install-link:"
                    "verify-install:" "uninstall:" "test-install:"]]
      (is (str/includes? makefile target)))))

(deftest specification-preserves-authority-boundaries
  (let [specification (text "spec/install-bundle-lifecycle-v1.md")]
    (is (str/includes? specification "MUST NOT delete the linked source tree"))
    (is (str/includes? specification "A preparation failure MUST leave the prior `current` pointer unchanged"))
    (is (str/includes? specification "Lean remains authoritative"))
    (is (str/includes? specification "Clojure remains authoritative"))))
