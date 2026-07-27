(ns zil.extensions.report-exporter
  "Deterministic JSON and EDN report export reference extension."
  (:require [clojure.data.json :as json]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [zil.plugin.api :as api]
            [zil.plugin.evidence :as evidence]
            [zil.worker.client :as worker-client])
  (:import (java.nio.charset StandardCharsets)
           (java.nio.file Files Paths StandardCopyOption)))

(def report-schema "ZIL-REPORT-EXPORT/1")
(def capabilities ["evidence-producer" "report-exporter"])

(defn- canonicalize [value]
  (cond
    (map? value)
    (into (sorted-map-by #(compare (str %1) (str %2)))
          (map (fn [[key item]] [key (canonicalize item)]))
          value)

    (set? value)
    (mapv canonicalize (sort-by str value))

    (sequential? value)
    (mapv canonicalize value)

    :else value))

(defn- read-report [path]
  (let [text (slurp path)]
    (if (str/ends-with? (str/lower-case (str path)) ".json")
      (json/read-str text :key-fn keyword)
      (edn/read-string text))))

(defn- render-report [format value]
  (case (str/lower-case (str format))
    "json" (str (json/write-str (canonicalize value)) "\n")
    "edn" (str (pr-str (canonicalize value)) "\n")
    (throw (ex-info "report format must be json or edn"
                    {:kind :extension-input-error :format format}))))

(defn- atomic-write! [path text]
  (let [target (.normalize (.toAbsolutePath (Paths/get (str path) (make-array String 0))))
        parent (.getParent target)
        _ (when parent
            (Files/createDirectories parent
                                     (make-array java.nio.file.attribute.FileAttribute 0)))
        temporary (Files/createTempFile parent ".zil-report-" ".tmp"
                                        (make-array java.nio.file.attribute.FileAttribute 0))]
    (Files/writeString temporary (str text) StandardCharsets/UTF_8
                       (into-array java.nio.file.OpenOption []))
    (try
      (Files/move temporary target
                  (into-array StandardCopyOption
                              [StandardCopyOption/ATOMIC_MOVE
                               StandardCopyOption/REPLACE_EXISTING]))
      (catch java.nio.file.AtomicMoveNotSupportedException _
        (Files/move temporary target
                    (into-array StandardCopyOption
                                [StandardCopyOption/REPLACE_EXISTING]))))
    (str target)))

(defn export-report!
  [input-path output-path format]
  (let [value (read-report input-path)
        rendered (render-report format value)
        output (atomic-write! output-path rendered)]
    (array-map
     :schema report-schema
     :input (str input-path)
     :input-sha256 (worker-client/sha256-file input-path)
     :output output
     :output-sha256 (worker-client/sha256-file output)
     :format (str/lower-case (str format))
     :bytes (count (.getBytes rendered StandardCharsets/UTF_8)))))

(defrecord ReportExporter [extension-manifest config]
  api/Extension
  (extension-manifest [_] extension-manifest)
  (start-extension! [this _] this)
  (stop-extension! [_ _] nil)

  api/Capability
  (provided-capabilities [_] capabilities)

  api/CommandProvider
  (provided-commands [_]
    {"report-export"
     {:summary "Export a canonical JSON or EDN report"
      :arguments ["input-path" "output-path" "format"]
      :authority :clojure}})
  (invoke-extension-command! [_ command _ arguments]
    (when-not (= "report-export" command)
      (throw (ex-info "unsupported report exporter command"
                      {:kind :unknown-extension-command :command command})))
    (when-not (= 3 (count arguments))
      (throw (ex-info "report-export requires input, output, and format arguments"
                      {:kind :extension-input-error :arguments arguments})))
    (apply export-report! arguments))

  api/EvidenceProducer
  (produce-evidence! [_ context request]
    (let [report (export-report! (:input-path request)
                                 (:output-path request)
                                 (:format request))
          extension (or (:extension-manifest context) extension-manifest)]
      (evidence/make-envelope
       {:extension extension
        :role "report-export"
        :subject (or (:subject request) (str "artifact:" (:output report)))
        :input-sha256 (:input-sha256 report)
        :payload (json/write-str report)
        :metadata {:format (:format report)
                   :bytes (:bytes report)}}))))

(defn create [extension-manifest config]
  (->ReportExporter extension-manifest config))
