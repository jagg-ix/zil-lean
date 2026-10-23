import Zil.Runtime.Interop

open Zil.Json Zil.Runtime.Codec Zil.Runtime.Ingest

/-! # Datasource ingest: vector clocks, records to facts, scalar typing (the expected values come from the earlier tools) -/

private def clock (fields : List (String × Int)) : Array (String × Int) := fields.toArray

-- vector-clock ordering
#guard vectorClockBefore (clock [("a", 1), ("b", 0)]) (clock [("a", 2), ("b", 0)])
#guard vectorClockBefore (clock [("a", 1), ("b", 2)]) (clock [("a", 2), ("b", 3)])
#guard !vectorClockBefore (clock [("a", 2)]) (clock [("a", 2)])
#guard !vectorClockBefore (clock [("a", 3)]) (clock [("a", 2)])
#guard vectorClockConcurrent (clock [("a", 2), ("b", 0)]) (clock [("a", 1), ("b", 3)])
#guard !vectorClockConcurrent (clock [("a", 1)]) (clock [("a", 2)])

-- edges derived from the clocks of four events
private def derived : Array Edge := deriveBeforeEdges #[
  ("evt_a1", clock [("A", 1)]), ("evt_a2", clock [("A", 2)]), ("evt_b1", clock [("B", 1)]),
  ("evt_join", clock [("A", 2), ("B", 1)])]
#guard derived.contains { left := "evt_a1", right := "evt_a2" }
#guard derived.contains { left := "evt_a2", right := "evt_join" }
#guard derived.contains { left := "evt_b1", right := "evt_join" }
#guard !derived.contains { left := "evt_a1", right := "evt_b1" }
#guard !derived.contains { left := "evt_b1", right := "evt_a2" }

-- counters may be numbers or numeric text; anything else is refused
#guard (normalizeVectorClock (.obj #[("a", .int 2), ("b", .str " 3 "), ("c", .number "2.7")])).toOption ==
  some #[("a", (2 : Int)), ("b", 3), ("c", 2)]
#guard (normalizeVectorClock (.obj #[("a", .str "many")])).toOption.isNone
#guard (normalizeVectorClock (.arr #[])).toOption.isNone

-- scalar typing of a token
private def scalar (text : String) : Option J := (parseScalarToken text).toOption
#guard scalar " true " == some (.bool true)
#guard scalar "FALSE" == some (.bool false)
#guard scalar "-12" == some (.int (-12))
#guard scalar "2.50" == some (.number "2.5")
#guard scalar "1.0" == some (.number "1.0")
#guard scalar "0.0001" == some (.number "1.0E-4")
#guard scalar "\"a\\tb\"" == some (.str "a\tb")
#guard scalar "plain words" == some (.str "plain words")
#guard scalar "   " == some (.str "")
#guard scalar "9223372036854775807" == some (.int 9223372036854775807)
#guard (scalar "9223372036854775808").isNone
#guard (scalar "\"bad \\q escape\"").isNone

-- subjects of facts
#guard subjectValue (.str "plain") == "value:plain"
#guard subjectValue (.str "a:b") == "a:b"
#guard subjectValue (.str "?x") == "?x"
#guard subjectValue (.int 7) == "value:7"
#guard subjectValue (.number "1e3") == "value:1000.0"
#guard subjectValue .null == "value:nil"
#guard subjectValue (.arr #[.int 1, .str "x"]) == "value:[1 \"x\"]"
#guard subjectValue (.obj #[("k", .arr #[.null, .bool true])]) == "value:{:k [nil true]}"

-- a record with an event, a clock and a metric
private def sampleFacts : Array String :=
  match recordFacts "datasource:d" (.obj #[("event_id", .str "e1"), ("vector_clock", .obj #[("A", .int 1)]),
      ("metric", .str "latency"), ("value", .int 9), ("host", .str "web")]) 5 with
  | .ok facts => facts.map fun (o, r, s, _, e) => s!"{o} {r} {s} {e.getD "-"}"
  | .error m => #[m]
#guard sampleFacts == #[
  "datasource:d ingested_record value:record event:e1",
  "metric:latency observed_from datasource:d event:e1",
  "event:e1 vc_component actor:A event:e1",
  "datasource:d host value:web event:e1"]

-- the earlier tools' text rules
#guard Zil.JavaText.splitLines "a\r\nb\n\n" == #["a", "b"]
#guard Zil.JavaText.splitLines "" == #[""]
#guard Zil.JavaText.splitLines "\n\n" == #[]
