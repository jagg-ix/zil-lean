(ns zil.plugin.api
  "Stable extension SDK protocols for ZIL operational integrations.")

(defprotocol Extension
  (extension-manifest [extension]
    "Return the validated ZIL-EXTENSION/1 manifest map.")
  (start-extension! [extension context]
    "Start operational resources and return an updated extension value or state.")
  (stop-extension! [extension context]
    "Release operational resources. Must be safe to call after partial startup."))

(defprotocol Capability
  (provided-capabilities [extension]
    "Return sorted unique capability identifiers provided by the extension."))

(defprotocol EvidenceProducer
  (produce-evidence! [extension context request]
    "Produce a ZIL-EVIDENCE/1 envelope or a sequence of envelopes."))

(defprotocol CommandProvider
  (provided-commands [extension]
    "Return a map of command identifier to command descriptor.")
  (invoke-extension-command! [extension command context arguments]
    "Invoke one declared extension command."))

(defprotocol StoreBackend
  (open-store! [extension context options]
    "Open a store handle.")
  (close-store! [extension context handle]
    "Close one store handle.")
  (append-events! [extension context handle expected-revision events]
    "Append events atomically at the expected revision.")
  (read-events [extension context handle from-revision to-revision]
    "Read an ordered event range."))

(defn implements?
  [protocol extension]
  (satisfies? protocol extension))
