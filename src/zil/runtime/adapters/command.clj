(ns zil.runtime.adapters.command
  "Command adapter.

  If :format is present on datasource attrs, stdout is parsed with interop codecs
  (json|yaml|yml|csv|edn|kv|text). Without :format, legacy stdout/stderr payload
  is returned as one record."
  (:require [clojure.java.shell :as sh]
            [clojure.string :as str]
            [zil.runtime.codec :as rc]
            [zil.runtime.adapters.core :as ac]))

(defn read-command
  [datasource _opts]
  (let [attrs (:attrs datasource)
        cmd (or (:command attrs) (:command_path attrs))
        format (rc/normalize-format (:format attrs))]
    (when-not (and (string? cmd) (not (str/blank? cmd)))
      (throw (ex-info "COMMAND datasource requires :command or :command_path"
                      {:datasource datasource})))
    (let [{:keys [out err exit]} (sh/sh "bash" "-lc" cmd)]
      (if (nil? format)
        [{:exit exit
          :stdout out
          :stderr err}]
        (->> (rc/parse-string format out attrs)
             rc/records-from-decoded
             (mapv (fn [record]
                     (if (map? record)
                       (cond-> record
                         true (assoc :command_exit exit)
                         (not (str/blank? err)) (assoc :command_stderr err))
                       {:value record
                        :command_exit exit
                        :command_stderr err}))))))))

(ac/register-adapter! :command read-command)
