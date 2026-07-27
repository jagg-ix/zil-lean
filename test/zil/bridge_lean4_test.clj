(ns zil.bridge-lean4-test
  (:require [clojure.test :refer [deftest is]]
            [zil.bridge.lean4 :as bl]))

(defn- tmp-dir
  []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-bridge-lean4"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest export-lts-to-lean4-smoke-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bridge.zc")]
    (spit model-file "MODULE bridge.demo.
LTS_ATOM ssh_client [states=#{idle ready}, initial=idle, transitions={[idle connect] [ready], [ready disconnect] [idle]}].
")
    (let [report (bl/export-lts->lean4 (.getAbsolutePath model-file))
          text (:text report)]
      (is (:ok report))
      (is (= 1 (:actor_count report)))
      (is (re-find #"namespace Zil.Generated.Bridge.Demo" text))
      (is (re-find #"inductive SSHClientState where" text))
      (is (re-find #"inductive SSHClientEvent where" text))
      (is (re-find #"def stepSSHClient" text))
      (is (re-find #"\| \.idle, \.connect => \.ready" text))
      (is (re-find #"def SSHClientCanonicalTrace : List SSHClientEvent" text)))))

(deftest export-lts-to-lean4-supports-namespace-and-output-file-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bridge2.zc")
        out-file (java.io.File. dir "generated/bridge.lean")]
    (spit model-file "MODULE bridge.override.
LTS_ATOM gateway [actor=SSHServer, actor_key=sshServer, states=#{listening accepted}, initial=listening, transitions={[listening accept] [accepted]}].
")
    (let [report (bl/export-lts->lean4 (.getAbsolutePath model-file)
                                       {:namespace "Acme.Zil.OVERLAY"
                                        :output-path (.getAbsolutePath out-file)})
          content (slurp out-file)]
      (is (:ok report))
      (is (= "Acme.Zil.Overlay" (:namespace report)))
      (is (.exists out-file))
      (is (re-find #"namespace Acme.Zil.Overlay" content))
      (is (re-find #"inductive SSHServerState where" content))
      (is (re-find #"def stepSSHServer" content)))))

(deftest export-lts-to-lean4-fails-without-lts-atoms-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "no-lts.zc")]
    (spit model-file "MODULE no.lts.
SERVICE api [env=prod].
")
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"No LTS_ATOM declarations found"
         (bl/export-lts->lean4 (.getAbsolutePath model-file))))))
