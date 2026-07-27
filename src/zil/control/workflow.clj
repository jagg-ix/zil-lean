(ns zil.control.workflow
  "Project agent workflow observations without redefining Lean safety semantics."
  (:require [clojure.string :as str]))

(def reducer-id "zil.control.workflow/v1")

(def workflow-event-types
  #{"context-generated"
    "action-token-issued"
    "checkpoint-created"
    "action-consumed"
    "postcondition-observed"
    "recovery-started"
    "recovery-completed"
    "semantic-decision"
    "external-evidence-recorded"})

(defn workflow-event?
  [event]
  (contains? workflow-event-types (get-in event [:event :event_type])))

(defn- workflow-id [event]
  (or (get-in event [:event :payload "workflow_id"])
      (get-in event [:event :payload :workflow_id])
      (get-in event [:event :payload "action_id"])
      (get-in event [:event :payload :action_id])
      (get-in event [:event :payload "token_id"])
      (get-in event [:event :payload :token_id])
      (get-in event [:event :request_id])))

(defn- observation [stored-event]
  (let [value (:event stored-event)]
    {:revision (:revision stored-event)
     :event-id (:event_id value)
     :event-type (:event_type value)
     :actor (:actor value)
     :request-id (:request_id value)
     :decision-sha256 (:decision_sha256 value)
     :payload (:payload value)}))

(defn reduce-events
  "Reduce stored events into an operational projection.

  The projection records observed order and Lean decision hashes. It does not infer
  that an action is authorized, verified, recovered, or safe unless the exact Lean
  result in the event payload states that result."
  [stored-events]
  (reduce
   (fn [state stored-event]
     (if-not (workflow-event? stored-event)
       state
       (let [id (str (or (workflow-id stored-event) "workflow:unbound"))
             observed (observation stored-event)]
         (-> state
             (update :event-count inc)
             (assoc :revision (:revision stored-event))
             (update-in [:workflows id :observations] (fnil conj []) observed)
             (assoc-in [:workflows id :last-event] observed)
             (update-in [:workflows id :actors]
                        (fnil (fn [actors] (vec (sort (distinct (conj actors (:actor observed)))))) []))))))
   {:schema "ZIL-WORKFLOW-PROJECTION/1"
    :reducer reducer-id
    :revision 0
    :event-count 0
    :workflows (sorted-map)}
   stored-events))

(defn workflow-summary [projection]
  {:schema (:schema projection)
   :revision (:revision projection)
   :event-count (:event-count projection)
   :workflow-count (count (:workflows projection))
   :workflows
   (mapv (fn [[id value]]
           {:workflow-id id
            :observation-count (count (:observations value))
            :last-event-type (get-in value [:last-event :event-type])
            :last-decision-sha256 (get-in value [:last-event :decision-sha256])
            :actors (:actors value)})
         (:workflows projection))})

(defn validate-workflow-event! [value]
  (when-not (contains? workflow-event-types (str (:event-type value)))
    (throw (ex-info "unsupported workflow observation type"
                    {:kind :workflow-event-error
                     :event-type (:event-type value)})))
  (when (str/blank? (str (or (get-in value [:payload :workflow_id])
                             (get-in value [:payload "workflow_id"])
                             (:request-id value))))
    (throw (ex-info "workflow event requires workflow_id or request_id"
                    {:kind :workflow-event-error})))
  value)
