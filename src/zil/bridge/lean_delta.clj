(ns zil.bridge.lean-delta
  "Content-addressed assertion/retraction deltas for Lean declaration batches."
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.set :as set]
            [zil.bridge.lean-events :as events])
  (:import [java.nio.charset StandardCharsets]
           [java.nio.file Files StandardCopyOption]
           [java.security MessageDigest]))

(def format-version "zil.lean-delta.v0.1")

(defn- canonicalize [value]
  (cond
    (map? value) (into (sorted-map) (map (fn [[k v]] [k (canonicalize v)]) value))
    (vector? value) (mapv canonicalize value)
    (sequential? value) (mapv canonicalize value)
    :else value))

(defn- canonical-json [value]
  (json/write-str (canonicalize value) :escape-slash false))

(defn- sha256 [text]
  (let [digest (.digest (MessageDigest/getInstance "SHA-256")
                        (.getBytes text StandardCharsets/UTF_8))]
    (apply str (map #(format "%02x" (bit-and % 0xff)) digest))))

(defn batch-revision [batch]
  (str "sha256:" (sha256 (canonical-json batch))))

(defn- events-by-declaration [batch]
  (into (sorted-map) (map (juxt #(get % "declaration") identity)
                           (get batch "events"))))

(defn- fact-key [fact]
  [(get fact "object") (get fact "relation") (get fact "subject")])

(defn- operation [op cause declaration fact]
  (sorted-map "cause" cause
              "declaration" declaration
              "fact" (canonicalize fact)
              "op" op))

(defn diff-batches [previous current]
  (events/validate-batch! current)
  (when previous (events/validate-batch! previous))
  (when (and previous (not= (get previous "module") (get current "module")))
    (throw (ex-info "Cannot diff Lean event batches from different modules"
                    {:code :revision-conflict
                     :previous-module (get previous "module")
                     :current-module (get current "module")})))
  (let [old-events (events-by-declaration (or previous {"events" []}))
        new-events (events-by-declaration current)
        declarations (sort (set (concat (keys old-events) (keys new-events))))
        operations
        (mapcat
         (fn [declaration]
           (let [old-event (get old-events declaration)
                 new-event (get new-events declaration)]
             (cond
               (nil? old-event)
               (map #(operation "assert" "declaration_added" declaration %)
                    (sort-by fact-key (events/event-records new-event)))

               (nil? new-event)
               (map #(operation "retract" "declaration_removed" declaration %)
                    (sort-by fact-key (events/event-records old-event)))

               (= (canonicalize old-event) (canonicalize new-event)) []

               :else
               (let [old-facts (into {} (map (juxt fact-key identity)
                                             (events/event-records old-event)))
                     new-facts (into {} (map (juxt fact-key identity)
                                             (events/event-records new-event)))
                     removed (sort (set/difference (set (keys old-facts))
                                                   (set (keys new-facts))))
                     added (sort (set/difference (set (keys new-facts))
                                                 (set (keys old-facts))))]
                 (concat
                  (map #(operation "retract" "declaration_changed" declaration
                                   (get old-facts %)) removed)
                  (map #(operation "assert" "declaration_changed" declaration
                                   (get new-facts %)) added))))))
         declarations)]
    (sorted-map
     "base_revision" (when previous (batch-revision previous))
     "complete" true
     "format" format-version
     "module" (get current "module")
     "operation_count" (count operations)
     "operations" (vec operations)
     "profile" "lean-declaration-delta-v0.1"
     "revision" (batch-revision current))))

(defn read-optional-batch [path]
  (when (and path (not= path "-")) (events/read-batch path)))

(defn- atomic-spit! [path text]
  (let [target (.toPath (io/file path))
        parent (.getParent target)]
    (when parent (Files/createDirectories parent (make-array java.nio.file.attribute.FileAttribute 0)))
    (let [tmp (Files/createTempFile parent ".zil-lean-delta-" ".tmp"
                                    (make-array java.nio.file.attribute.FileAttribute 0))]
      (spit (.toFile tmp) text)
      (Files/move tmp target
                  (into-array StandardCopyOption
                              [StandardCopyOption/ATOMIC_MOVE
                               StandardCopyOption/REPLACE_EXISTING])))))

(defn write-delta! [previous-path current-path output-path]
  (let [delta (diff-batches (read-optional-batch previous-path)
                            (events/read-batch current-path))]
    (atomic-spit! output-path (str (canonical-json delta) "\n"))
    {:ok true
     :output output-path
     :base_revision (get delta "base_revision")
     :revision (get delta "revision")
     :operation_count (get delta "operation_count")}))

(defn delta->versioned-facts [delta revision]
  (mapv (fn [entry]
          (let [fact (get entry "fact")]
            {:object (get fact "object")
             :relation (keyword (get fact "relation"))
             :subject (get fact "subject")
             :revision revision
             :op (keyword (get entry "op"))
             :attrs {:cause (get entry "cause")
                     :declaration (get entry "declaration")}}))
        (get delta "operations")))
