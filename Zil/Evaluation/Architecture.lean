import Zil.Json.Ordered

/-!
# Evidence-driven placement evaluation (`ZIL-RUNTIME-EVALUATION/1`)

Scores where each component of a system is best implemented from measurements, and recommends keeping or changing the
placement. It never changes anything: a recommended change always requires human approval. All arithmetic is exact
(rational numbers read from the decimals in the model and measurements), so a decision margin can never be decided by
rounding.
-/

namespace Zil.Evaluation

open Zil.Json

def schema : String := "ZIL-RUNTIME-EVALUATION/1"
def reportSchema : String := "ZIL-ARCHITECTURE-EVALUATION/1"

/-! ## Exact numbers -/

/-- A rational number in lowest terms. -/
structure Q where
  num : Int
  den : Nat := 1
  deriving Inhabited, BEq

namespace Q

def make (num : Int) (den : Nat) : Q :=
  if den == 0 then ⟨0, 1⟩
  else
    let g := Nat.gcd num.natAbs den
    ⟨num / (g : Int), den / g⟩

def ofNat (n : Nat) : Q := ⟨n, 1⟩
def zero : Q := ⟨0, 1⟩
def one : Q := ⟨1, 1⟩

instance : Add Q := ⟨fun a b => make (a.num * b.den + b.num * a.den) (a.den * b.den)⟩
instance : Sub Q := ⟨fun a b => make (a.num * b.den - b.num * a.den) (a.den * b.den)⟩
instance : Mul Q := ⟨fun a b => make (a.num * b.num) (a.den * b.den)⟩

def div (a b : Q) : Q :=
  if b.num == 0 then zero
  else
    let sign : Int := if b.num < 0 then -1 else 1
    make (a.num * b.den * sign) (a.den * b.num.natAbs)

def lt (a b : Q) : Bool := a.num * b.den < b.num * a.den
def le (a b : Q) : Bool := a.num * b.den ≤ b.num * a.den
def isPositive (a : Q) : Bool := a.num > 0

/-- A decimal such as `0.98`, `3`, `-1.5` or `2e-3`. -/
def ofDecimal? (text : String) : Option Q := do
  let (mantissa, exponent) ← match text.splitOn "e" |>.length, text.splitOn "E" |>.length with
    | 1, 1 => some (text, (0 : Int))
    | 2, _ =>
        let parts := text.splitOn "e"
        some (parts[0]!, ← parts[1]!.toInt?)
    | _, 2 =>
        let parts := text.splitOn "E"
        some (parts[0]!, ← parts[1]!.toInt?)
    | _, _ => none
  let negative := mantissa.startsWith "-"
  let body := if negative || mantissa.startsWith "+" then String.ofList mantissa.toList.tail! else mantissa
  let (whole, fraction) ← match body.splitOn "." with
    | [w] => some (w, "")
    | [w, f] => some (w, f)
    | _ => none
  let digits := whole ++ fraction
  if digits.isEmpty || !digits.all Char.isDigit then none
  else
    let n ← digits.toNat?
    let scale := fraction.length
    let signed : Int := if negative then -(n : Int) else n
    if exponent ≥ 0 then some (make (signed * (10 ^ exponent.toNat : Nat)) (10 ^ scale))
    else some (make signed (10 ^ (scale + exponent.natAbs)))

/-- Decimal text with up to `digits` fractional digits (rounded half up), at least one. -/
def toDecimal (q : Q) (digits : Nat := 12) : String :=
  let scale := 10 ^ digits
  let negative := q.num < 0
  let magnitude := q.num.natAbs
  let scaled := (magnitude * scale * 2 + q.den) / (2 * q.den)
  let whole := scaled / scale
  let fraction := scaled % scale
  let fractionText := (toString fraction).pushn '0' 0
  let padded := "".pushn '0' (digits - fractionText.length) ++ fractionText
  let trimmed := String.ofList (padded.toList.reverse.dropWhile (· == '0')).reverse
  let sign := if negative && scaled != 0 then "-" else ""
  sign ++ toString whole ++ "." ++ (if trimmed.isEmpty then "0" else trimmed)

def toJson (q : Q) : J := .number (toDecimal q)

end Q

/-! ## The model -/

def candidates : List String := ["lean", "clojure", "hybrid"]

def metrics : List String :=
  ["correctness", "latency", "throughput", "maintenance", "extensibility", "proof-coverage", "reliability",
   "deployment-simplicity"]

private def q (num : Int) (den : Nat) : Q := Q.make num den

def defaultWeights : List (String × Q) :=
  [("correctness", q 20 100), ("latency", q 10 100), ("throughput", q 10 100), ("maintenance", q 15 100),
   ("extensibility", q 15 100), ("proof-coverage", q 15 100), ("reliability", q 10 100),
   ("deployment-simplicity", q 5 100)]

structure Policy where
  minimumMetrics : Nat := 6
  minimumConfidence : Q := q 60 100
  minimumSamples : Nat := 1
  decisionMargin : Q := q 5 100

structure Component where
  id : String
  description : String
  current : String
  candidates : Array String
  requiresKernelEvidence : Bool := false
  requiresDynamicPlugins : Bool := false
  requiresLeanOnlyProfile : Bool := false
  constraints : J := .obj #[]

structure Model where
  weights : Array (String × Q)
  policy : Policy
  components : Array Component

structure Measurement where
  component : String
  candidate : String
  metric : String
  value : Q
  confidence : Q
  samples : Nat
  source : String

private def bad (message : String) : Except String α := throw message

private def numberOf (value : J) : Option Q :=
  match value with
  | .int n => some ⟨n, 1⟩
  | .number text => Q.ofDecimal? text
  | _ => none

private def inUnit (x : Q) : Bool := !x.lt Q.zero && x.le Q.one

private def duplicates (values : List String) : List String :=
  (values.filter fun v => (values.filter (· == v)).length > 1).eraseDups

private def boolField (value : J) (key : String) : Bool :=
  match value.get? key with
  | some (.bool true) => true
  | _ => false

/-- Read and validate a model. -/
def parseModel (document : J) : Except String Model := do
  unless document.getStr? "schema" == some schema do bad "unsupported runtime evaluation schema"
  -- weights
  let mut weights : Array (String × Q) := defaultWeights.toArray
  if let some (.obj given) := document.get? "weights" then
    for (metric, value) in given do
      let some w := numberOf value | bad "runtime evaluation weights must be in [0,1]"
      match weights.findIdx? (·.1 == metric) with
      | some i => weights := weights.set! i (metric, w)
      | none => weights := weights.push (metric, w)
  unless (weights.map (·.1)).toList.mergeSort == metrics.mergeSort do
    bad "runtime evaluation weights must cover every metric"
  unless weights.all (fun (_, w) => inUnit w) do bad "runtime evaluation weights must be in [0,1]"
  let total := weights.foldl (fun acc (_, w) => acc + w) Q.zero
  unless total == Q.one do bad "runtime evaluation weights must sum to 1.0"
  -- policy
  let mut policy : Policy := {}
  if let some p := document.get? "policy" then
    if let some (.int n) := p.get? "minimum-metrics" then policy := { policy with minimumMetrics := n.toNat }
    if let some v := (p.get? "minimum-confidence").bind numberOf then policy := { policy with minimumConfidence := v }
    if let some (.int n) := p.get? "minimum-samples" then policy := { policy with minimumSamples := n.toNat }
    if let some v := (p.get? "decision-margin").bind numberOf then policy := { policy with decisionMargin := v }
  unless 1 ≤ policy.minimumMetrics && policy.minimumMetrics ≤ metrics.length do
    bad "minimum-metrics must be between 1 and the metric count"
  unless inUnit policy.minimumConfidence do bad "minimum-confidence must be in [0,1]"
  unless policy.minimumSamples > 0 do bad "minimum-samples must be a positive integer"
  unless inUnit policy.decisionMargin do bad "decision-margin must be in [0,1]"
  -- components
  let some (.arr rawComponents) := document.get? "components" | bad "runtime evaluation requires at least one component"
  if rawComponents.isEmpty then bad "runtime evaluation requires at least one component"
  let mut components : Array Component := #[]
  for raw in rawComponents do
    let id := (raw.getStr? "id").getD ""
    if id.isEmpty then bad "component id must be a keyword"
    if (raw.getStr? "description").getD "" |>.all Char.isWhitespace then bad s!"component description must be nonempty ({id})"
    let current := (raw.getStr? "current").getD ""
    unless candidates.contains current do bad s!"component current runtime is invalid ({id})"
    let cands := ((raw.get? "candidates").bind J.asArr?).getD #[] |>.filterMap J.asStr?
    if cands.isEmpty then bad s!"component requires at least one candidate ({id})"
    unless (duplicates cands.toList).isEmpty do bad s!"component candidates must be unique ({id})"
    unless cands.all candidates.contains do bad s!"component declares an invalid candidate ({id})"
    unless cands.contains current do bad s!"component current runtime must be an evaluated candidate ({id})"
    let constraints := (raw.get? "constraints").getD (.obj #[])
    let component : Component :=
      { id, description := (raw.getStr? "description").getD "", current, candidates := cands,
        requiresKernelEvidence := boolField constraints "requires-kernel-evidence",
        requiresDynamicPlugins := boolField constraints "requires-dynamic-plugins",
        requiresLeanOnlyProfile := boolField constraints "requires-lean-only-profile", constraints }
    if component.requiresKernelEvidence && !(cands.contains "lean" || cands.contains "hybrid") then
      bad s!"kernel-evidence component requires Lean participation ({id})"
    components := components.push component
  unless (duplicates (components.map (·.id)).toList).isEmpty do bad "runtime evaluation has duplicate component ids"
  return { weights, policy, components }

/-- Read and validate the measurements against a model. -/
def parseMeasurements (model : Model) (document : J) : Except String (Array Measurement) := do
  let some (.arr rows) := some document | bad "measurements must be an array"
  let mut out : Array Measurement := #[]
  for row in rows do
    let component := (row.getStr? "component").getD ""
    let candidate := (row.getStr? "candidate").getD ""
    let metric := (row.getStr? "metric").getD ""
    let some declared := model.components.find? (·.id == component) | bad s!"measurement references an unknown component ({component})"
    unless candidates.contains candidate do bad "measurement candidate is invalid"
    unless declared.candidates.contains candidate do bad "measurement candidate is not declared for the component"
    unless metrics.contains metric do bad "measurement metric is invalid"
    let some value := (row.get? "value").bind numberOf | bad "measurement value must be in [0,1]"
    unless inUnit value do bad "measurement value must be in [0,1]"
    let some confidence := (row.get? "confidence").bind numberOf | bad "measurement confidence must be in [0,1]"
    unless inUnit confidence do bad "measurement confidence must be in [0,1]"
    let samples ← match row.get? "samples" with
      | some (.int n) => if n > 0 then pure n.toNat else bad "measurement samples must be a positive integer"
      | _ => bad "measurement samples must be a positive integer"
    let source := (row.getStr? "source").getD ""
    if source.all Char.isWhitespace then bad "measurement source must be nonempty"
    out := out.push { component, candidate, metric, value, confidence, samples, source }
  return out

/-! ## Scoring -/

private structure Aggregate where
  value : Q
  confidence : Q
  samples : Nat
  sources : Array String

private def aggregate (values : Array Measurement) : Option Aggregate :=
  let weightTotal := values.foldl (fun acc m => acc + m.confidence * Q.ofNat m.samples) Q.zero
  if !weightTotal.isPositive then none
  else
    let numerator := values.foldl (fun acc m => acc + m.value * m.confidence * Q.ofNat m.samples) Q.zero
    let samples := values.foldl (fun acc m => acc + m.samples) 0
    let sources := (values.map (·.source)).toList.eraseDups.toArray.qsort (· < ·)
    some { value := numerator.div weightTotal, confidence := weightTotal.div (Q.ofNat samples), samples, sources }

private structure Scored where
  candidate : String
  eligible : Bool
  metricCount : Nat := 0
  coveredWeight : Q := Q.zero
  score : Option Q := none
  metrics : Array (String × Aggregate) := #[]
  accepted : Array (String × Aggregate) := #[]

private def eligible (component : Component) (candidate : String) : Bool :=
  component.candidates.contains candidate &&
    !(component.requiresKernelEvidence && candidate == "clojure") &&
    !(component.requiresDynamicPlugins && candidate == "lean") &&
    !(component.requiresLeanOnlyProfile && candidate == "clojure")

private def weightOf (model : Model) (metric : String) : Q :=
  (model.weights.find? (·.1 == metric)).map (·.2) |>.getD Q.zero

private def scoreCandidate (model : Model) (component : Component) (measurements : Array Measurement)
    (candidate : String) : Scored := Id.run do
  if !eligible component candidate then return { candidate, eligible := false }
  let mine := measurements.filter fun m => m.component == component.id && m.candidate == candidate
  let mut results : Array (String × Aggregate) := #[]
  for metric in metrics.mergeSort do
    if let some a := aggregate (mine.filter (·.metric == metric)) then results := results.push (metric, a)
  let accepted := results.filter fun (_, a) =>
    model.policy.minimumConfidence.le a.confidence && model.policy.minimumSamples ≤ a.samples
  let covered := accepted.foldl (fun acc (metric, _) => acc + weightOf model metric) Q.zero
  let score :=
    if covered.isPositive then
      some ((accepted.foldl (fun acc (metric, a) => acc + weightOf model metric * a.value) Q.zero).div covered)
    else none
  return { candidate, eligible := true, metricCount := accepted.size, coveredWeight := covered, score,
           metrics := results, accepted }

private def aggregateJson (a : Aggregate) : J :=
  .obj #[("confidence", a.confidence.toJson), ("samples", .int a.samples), ("sources", .arr (a.sources.map .str)),
         ("value", a.value.toJson)]

private def scoredJson (s : Scored) : J :=
  if !s.eligible then .obj #[("candidate", .str s.candidate), ("eligible", .bool false), ("reason", .str "constraint")]
  else
    .obj #[("candidate", .str s.candidate), ("eligible", .bool true), ("metric-count", .int s.metricCount),
           ("covered-weight", s.coveredWeight.toJson), ("score", match s.score with | some x => x.toJson | none => .null),
           ("metrics", .obj (s.metrics.map fun (m, a) => (m, aggregateJson a))),
           ("accepted-metrics", .obj (s.accepted.map fun (m, a) => (m, aggregateJson a)))]

/-- The decision for one component, as a JSON object and its status. -/
private def decide (model : Model) (component : Component) (scored : Array Scored) : String × J :=
  let candidatesWithScore := scored.filter fun s => s.eligible && s.metricCount ≥ model.policy.minimumMetrics && s.score.isSome
  -- best first: higher score, then the candidate name
  let ordered := candidatesWithScore.qsort fun a b =>
    match a.score, b.score with
    | some x, some y => if x == y then a.candidate < b.candidate else y.lt x
    | _, _ => false
  match ordered[0]? with
  | none =>
      ("insufficient-evidence", .obj #[("status", .str "insufficient-evidence"), ("current", .str component.current),
        ("recommended", .null), ("reason", .str "coverage")])
  | some best =>
      let bestScore := best.score.getD Q.zero
      let second := ordered[1]?
      let margin := bestScore - ((second.bind (·.score)).getD Q.zero)
      let enough := second.isNone || model.policy.decisionMargin.le margin
      if !enough then
        ("review-required", .obj #[("status", .str "review-required"), ("current", .str component.current),
          ("recommended", .str best.candidate), ("score", bestScore.toJson), ("margin", margin.toJson),
          ("reason", .str "close-scores")])
      else if best.candidate == component.current then
        ("retain-current", .obj #[("status", .str "retain-current"), ("current", .str component.current),
          ("recommended", .str best.candidate), ("score", bestScore.toJson), ("margin", margin.toJson)])
      else
        ("candidate-change", .obj #[("status", .str "candidate-change"), ("current", .str component.current),
          ("recommended", .str best.candidate), ("score", bestScore.toJson), ("margin", margin.toJson),
          ("requires-human-approval", .bool true)])

/-- The evaluation report and the number of recommended changes. -/
def evaluate (model : Model) (measurements : Array Measurement) : J × Nat := Id.run do
  let mut componentJson : Array J := #[]
  let mut counts : Array (String × Nat) :=
    #[("retain-current", 0), ("candidate-change", 0), ("review-required", 0), ("insufficient-evidence", 0)]
  for component in model.components do
    let scored := component.candidates.map (scoreCandidate model component measurements)
    let (status, decision) := decide model component scored
    counts := counts.map fun (k, n) => if k == status then (k, n + 1) else (k, n)
    componentJson := componentJson.push <| .obj #[("id", .str component.id), ("description", .str component.description),
      ("constraints", component.constraints), ("scores", .arr (scored.map scoredJson)), ("decision", decision)]
  let report : J := .obj #[("schema", .str reportSchema), ("model-schema", .str schema),
    ("policy", .obj #[("minimum-metrics", .int model.policy.minimumMetrics),
                      ("minimum-confidence", model.policy.minimumConfidence.toJson),
                      ("minimum-samples", .int model.policy.minimumSamples),
                      ("decision-margin", model.policy.decisionMargin.toJson)]),
    ("weights", .obj (model.weights.qsort (fun a b => a.1 < b.1) |>.map fun (m, w) => (m, w.toJson))),
    ("measurement-count", .int measurements.size), ("components", .arr componentJson),
    ("summary", .obj (counts.map fun (k, n) => (k, J.int n)))]
  return (report, (counts.find? (·.1 == "candidate-change")).map (·.2) |>.getD 0)

end Zil.Evaluation
