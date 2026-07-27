(ns zil.bridge-tla-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.bridge.tla :as bt]))

(defn- tmp-dir
  []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-bridge-tla"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest export-lts-to-tla-smoke-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bridge.zc")]
    (spit model-file "MODULE bridge.demo.
LTS_ATOM ssh_client [states=#{idle ready}, initial=idle, transitions={[idle connect] [ready], [ready disconnect] [idle]}].
")
    (let [report (bt/export-lts->tla (.getAbsolutePath model-file))]
      (is (:ok report))
      (is (= 1 (:actor_count report)))
      (is (re-find #"MODULE bridge_demo_LTSBridge" (:text report)))
      (is (re-find #"SSHClientStates == \{" (:text report)))
      (is (re-find #"<< \"idle\", \"connect\", \"ready\" >>" (:text report)))
      (is (re-find #"SSHClientCanonicalTrace == <<" (:text report)))
      (is (re-find #"CanonicalSystemTrace == <<" (:text report))))))

(deftest export-lts-respects-actor-overrides-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "bridge-overrides.zc")]
    (spit model-file "MODULE bridge.override.
LTS_ATOM gateway [actor=SSHServer, actor_key=sshServer, states=#{listening accepted}, initial=listening, transitions={[listening accept] [accepted]}].
")
    (let [report (bt/export-lts->tla (.getAbsolutePath model-file) {:module-name "CustomBridge"})
          text (:text report)]
      (is (re-find #"MODULE CustomBridge" text))
      (is (re-find #"SSHServerStates == \{" text))
      (is (re-find #"<< \"sshServer\", \"accept\" >>" text)))))

(deftest export-lts-supports-directory-input-and-output-file-test
  (let [dir (tmp-dir)
        model-a (java.io.File. dir "a.zc")
        model-b (java.io.File. dir "b.zc")
        out-file (java.io.File. dir "generated/out.tla")]
    (spit model-a "MODULE dir.demo.
LTS_ATOM bridge_server [states=#{listening ready}, initial=listening, transitions={[listening boot] [ready]}].
")
    (spit model-b "MODULE dir.demo.
LTS_ATOM bridge_client [states=#{idle ws_ready}, initial=idle, transitions={[idle upgrade_ws] [ws_ready]}].
")
    (let [report (bt/export-lts->tla (.getAbsolutePath dir)
                                     {:output-path (.getAbsolutePath out-file)
                                      :module-name "DirBridge"})]
      (is (:ok report))
      (is (= 2 (:actor_count report)))
      (is (= (.getAbsolutePath out-file) (:output_path report)))
      (is (.exists out-file))
      (let [content (slurp out-file)]
        (is (re-find #"MODULE DirBridge" content))
        (is (re-find #"BridgeServerStates == \{" content))
        (is (re-find #"BridgeClientStates == \{" content))))))

(deftest export-lts-fails-without-lts-atoms-test
  (let [dir (tmp-dir)
        model-file (java.io.File. dir "no-lts.zc")]
    (spit model-file "MODULE no.lts.
SERVICE api [env=prod].
")
    (is (thrown-with-msg?
         clojure.lang.ExceptionInfo
         #"No LTS_ATOM declarations found"
         (bt/export-lts->tla (.getAbsolutePath model-file))))))
