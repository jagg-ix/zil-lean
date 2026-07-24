(ns zil.extensions.repository-scanner
  "Deterministic repository inventory reference extension."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [zil.plugin.api :as api]
            [zil.plugin.evidence :as evidence])
  (:import (java.nio.file Files LinkOption Path Paths)))

(def scan-schema "ZIL-REPOSITORY-SCAN/1")
(def capabilities ["evidence-producer" "repository-scanner"])

(defn- absolute-path ^Path [value]
  (.normalize (.toAbsolutePath (Paths/get (str value) (make-array String 0)))))

(defn- path-string [^Path value]
  (str/replace (.toString value) "\\" "/"))

(defn- hidden-internal? [^Path relative excluded]
  (let [text (path-string relative)]
    (or (= text ".git")
        (str/starts-with? text ".git/")
        (some #(or (= text %) (str/starts-with? text (str % "/"))) excluded))))

(defn scan-repository
  [root {:keys [exclude] :or {exclude [".lake" "target"]}}]
  (let [root (absolute-path root)
        excluded (set (map str exclude))]
    (when-not (Files/isDirectory root (make-array LinkOption 0))
      (throw (ex-info "repository scan root is not a directory"
                      {:kind :extension-input-error :root (path-string root)})))
    (let [entries
          (with-open [stream (Files/walk root (make-array java.nio.file.FileVisitOption 0))]
            (->> (.iterator stream)
                 iterator-seq
                 (filter #(Files/isRegularFile ^Path % (make-array LinkOption 0)))
                 (map (fn [^Path path]
                        [(.relativize root path) path]))
                 (remove (fn [[relative _]] (hidden-internal? relative excluded)))
                 (sort-by (comp path-string first))
                 (mapv (fn [[relative path]]
                         {:path (path-string relative)
                          :bytes (Files/size ^Path path)
                          :sha256 (str "sha256:"
                                       (subs (zil.worker.client/sha256-file
                                              (path-string path)) 7))}))))
          aggregate (str/join "\n" (map (juxt :path :bytes :sha256) entries))]
      (array-map
       :schema scan-schema
       :root-label (or (some-> root .getFileName str) ".")
       :file-count (count entries)
       :content-sha256 (evidence/sha256-text aggregate)
       :entries entries))))

(defrecord RepositoryScanner [extension-manifest config]
  api/Extension
  (extension-manifest [_] extension-manifest)
  (start-extension! [this _] this)
  (stop-extension! [_ _] nil)

  api/Capability
  (provided-capabilities [_] capabilities)

  api/CommandProvider
  (provided-commands [_]
    {"repository-scan"
     {:summary "Produce a deterministic repository file inventory"
      :arguments ["root"]
      :authority :clojure}})
  (invoke-extension-command! [_ command _ arguments]
    (when-not (= "repository-scan" command)
      (throw (ex-info "unsupported repository scanner command"
                      {:kind :unknown-extension-command :command command})))
    (when-not (= 1 (count arguments))
      (throw (ex-info "repository-scan requires one root argument"
                      {:kind :extension-input-error :arguments arguments})))
    (scan-repository (first arguments) config))

  api/EvidenceProducer
  (produce-evidence! [_ context request]
    (let [root (or (:root request) ".")
          report (scan-repository root config)
          payload (json/write-str report)
          extension (or (:extension-manifest context) extension-manifest)]
      (evidence/make-envelope
       {:extension extension
        :role "repository-scan"
        :subject (or (:subject request) (str "repository:" (:root-label report)))
        :input-sha256 (:content-sha256 report)
        :payload payload
        :metadata {:file-count (:file-count report)}}))))

(defn create [extension-manifest config]
  (->RepositoryScanner extension-manifest config))
