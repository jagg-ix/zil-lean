import Zil.Core.Userset

namespace Zil

/-- Higher-level values used by standard-library declarations. This remains
separate from tuple attributes so collection-valued declarations do not change
the canonical tuple codec. -/
inductive DeclValue where
  | scalar : AttrValue → DeclValue
  | list : Array DeclValue → DeclValue
  | set : Array DeclValue → DeclValue
  | map : Array (DeclValue × DeclValue) → DeclValue
  deriving Repr, BEq, Inhabited

namespace DeclValue

/-- True when every nested scalar is ground. -/
def isGround : DeclValue → Bool
  | .scalar value => value.isGround
  | .list values | .set values => values.all isGround
  | .map entries => entries.all fun entry => isGround entry.1 && isGround entry.2

/-- Flatten a scalar, list, or set into scalar values. Maps remain structural. -/
def scalarValues : DeclValue → Array AttrValue
  | .scalar value => #[value]
  | .list values | .set values => values.foldl (init := #[]) fun out value => out ++ scalarValues value
  | .map _ => #[]

/-- Return list/set members without flattening nested values. -/
def members : DeclValue → Array DeclValue
  | .list values | .set values => values
  | value => #[value]

/-- Obtain a stable token for validation and generated attribute values. -/
def token? : DeclValue → Option String
  | .scalar (.text value) => some value
  | .scalar (.integer value) => some (toString value)
  | .scalar (.decimal value) => some value
  | .scalar (.boolean value) => some (if value then "true" else "false")
  | .scalar (.term (.node node)) => some node.name.toString
  | .scalar (.term (.var _)) => none
  | _ => none

end DeclValue

/-- One supported higher-level declaration kind from the original ZIL runtime. -/
inductive DeclarationKind where
  | service
  | host
  | datasource
  | metric
  | policy
  | event
  | provider
  | tmAtom
  | ltsAtom
  | refines
  | corresponds
  | proofObligation
  | formalizationTarget
  | languageProfile
  | grammarProfile
  | parserAdapter
  | dslProfile
  | queryPack
  deriving Repr, BEq, Inhabited

namespace DeclarationKind

def keyword : DeclarationKind → String
  | .service => "SERVICE"
  | .host => "HOST"
  | .datasource => "DATASOURCE"
  | .metric => "METRIC"
  | .policy => "POLICY"
  | .event => "EVENT"
  | .provider => "PROVIDER"
  | .tmAtom => "TM_ATOM"
  | .ltsAtom => "LTS_ATOM"
  | .refines => "REFINES"
  | .corresponds => "CORRESPONDS"
  | .proofObligation => "PROOF_OBLIGATION"
  | .formalizationTarget => "FORMALIZATION_TARGET"
  | .languageProfile => "LANGUAGE_PROFILE"
  | .grammarProfile => "GRAMMAR_PROFILE"
  | .parserAdapter => "PARSER_ADAPTER"
  | .dslProfile => "DSL_PROFILE"
  | .queryPack => "QUERY_PACK"

def prefix : DeclarationKind → String
  | .service => "service"
  | .host => "host"
  | .datasource => "datasource"
  | .metric => "metric"
  | .policy => "policy"
  | .event => "event"
  | .provider => "provider"
  | .tmAtom => "tm_atom"
  | .ltsAtom => "lts_atom"
  | .refines => "refines"
  | .corresponds => "corresponds"
  | .proofObligation => "proof_obligation"
  | .formalizationTarget => "formalization_target"
  | .languageProfile => "language_profile"
  | .grammarProfile => "grammar_profile"
  | .parserAdapter => "parser_adapter"
  | .dslProfile => "dsl_profile"
  | .queryPack => "query_pack"

def ofKeyword? : String → Option DeclarationKind
  | "SERVICE" => some .service
  | "HOST" => some .host
  | "DATASOURCE" => some .datasource
  | "METRIC" => some .metric
  | "POLICY" => some .policy
  | "EVENT" => some .event
  | "PROVIDER" => some .provider
  | "TM_ATOM" => some .tmAtom
  | "LTS_ATOM" => some .ltsAtom
  | "REFINES" => some .refines
  | "CORRESPONDS" => some .corresponds
  | "PROOF_OBLIGATION" => some .proofObligation
  | "FORMALIZATION_TARGET" => some .formalizationTarget
  | "LANGUAGE_PROFILE" => some .languageProfile
  | "GRAMMAR_PROFILE" => some .grammarProfile
  | "PARSER_ADAPTER" => some .parserAdapter
  | "DSL_PROFILE" => some .dslProfile
  | "QUERY_PACK" => some .queryPack
  | _ => none

end DeclarationKind

structure DeclAttribute where
  key : Name
  value : DeclValue
  deriving Repr, BEq, Inhabited

/-- A validated source declaration before deterministic lowering to relations. -/
structure Declaration where
  kind : DeclarationKind
  name : Name
  attrs : Array DeclAttribute := #[]
  source : Source := {}
  deriving Repr, Inhabited

inductive DeclarationIssueKind where
  | duplicateKey
  | missingRequired
  | invalidEnum
  | invalidStructure
  | invalidReference
  | duplicateDeclaration
  | dependencyCycle
  deriving Repr, BEq, Inhabited

structure DeclarationIssue where
  kind : DeclarationIssueKind
  declaration : Name
  key : Option Name := none
  message : String
  deriving Repr, Inhabited

namespace Declaration

private def nameFromString (value : String) : Name :=
  value.splitOn "." |>.foldl (init := Name.anonymous) fun current segment =>
    if current == Name.anonymous then Name.mkSimple segment else Name.str current segment

private def hasNamespace (name : Name) : Bool :=
  name.toString.splitOn "." |>.length > 1

private def relationName (key : Name) : Name :=
  if key.toString.startsWith "zil." then key else Name.str `zil key.toString

private def normalizeKey (kind : DeclarationKind) (key : Name) : Name :=
  if kind == .service && key == `depends then `uses
  else if kind == .service && key == `depended_by then `used_by
  else key

private def normalizedAttrs (declaration : Declaration) : Array DeclAttribute :=
  declaration.attrs.map fun attr => { attr with key := normalizeKey declaration.kind attr.key }

/-- Stable entity name. Explicitly qualified declaration names remain unchanged. -/
def entityName (declaration : Declaration) : Name :=
  if hasNamespace declaration.name then declaration.name
  else nameFromString (declaration.kind.prefix ++ "." ++ declaration.name.toString)

/-- Find a normalized attribute. -/
def attr? (declaration : Declaration) (key : Name) : Option DeclAttribute :=
  (normalizedAttrs declaration).find? fun attr => attr.key == key

private def requiredKeys : DeclarationKind → Array Name
  | .datasource => #[`type]
  | .provider => #[`source]
  | .metric => #[`source]
  | .tmAtom => #[`states, `alphabet, `blank, `initial, `accept, `reject, `transitions]
  | .ltsAtom => #[`states, `initial, `transitions]
  | .refines => #[`spec, `impl]
  | .corresponds => #[`left, `right]
  | .proofObligation => #[`relation, `statement, `tool]
  | .formalizationTarget => #[`module, `file, `declaration, `status, `priority]
  | .languageProfile => #[`family, `module_system]
  | .grammarProfile => #[`language, `notation, `entrypoints]
  | .parserAdapter => #[`language, `input_profile, `output_profile, `runtime]
  | .dslProfile => #[`query_pack]
  | .queryPack => #[`queries]
  | _ => #[]

private def allowedEnums (kind : DeclarationKind) (key : Name) : Array String :=
  match kind, key with
  | .service, `criticality => #["low", "medium", "high", "critical"]
  | .service, `environment | .service, `env => #["dev", "qa", "prod", "dr", "cqa"]
  | .host, `environment => #["dev", "qa", "prod", "dr", "cqa"]
  | .host, `type => #["physical", "vm", "container", "pod", "process"]
  | .datasource, `type => #["rest", "file", "command", "socket", "websocket", "pipe", "cucumber"]
  | .datasource, `format => #["json", "text", "csv", "edn", "kv", "yaml", "yml"]
  | .datasource, `poll_mode => #["event", "interval"]
  | .provider, `language => #["hcl", "opentofu", "terraform", "native"]
  | .provider, `engine => #["opentofu", "terraform", "hcl_native", "custom"]
  | .event, `criticality | .policy, `criticality => #["low", "medium", "high", "critical"]
  | .proofObligation, `criticality => #["low", "medium", "high", "critical"]
  | .proofObligation, `status => #["open", "pending", "proved", "failed", "waived"]
  | .proofObligation, `tool => #["z3", "tlaps", "lean4", "acl2", "manual"]
  | .proofObligation, `logic => #["all", "qf_lia", "qf_lra", "qf_nia", "qf_nra", "qf_uf"]
  | .proofObligation, `expectation => #["sat", "unsat"]
  | .formalizationTarget, `status => #["draft", "blocked", "ready", "in_progress", "implemented", "verified", "reviewed", "proved", "rejected", "superseded"]
  | .languageProfile, `family => #["ocaml", "sml", "antlr", "ebnf", "hybrid"]
  | .languageProfile, `module_system => #["ml_module", "sml_structure_signature", "none"]
  | .grammarProfile, `notation => #["ebnf", "antlr4", "menhir", "ocamlyacc", "mlyacc", "custom"]
  | .grammarProfile, `status => #["draft", "stable", "deprecated"]
  | .parserAdapter, `runtime => #["native", "jvm", "python", "node", "external"]
  | .parserAdapter, `input_profile => #["source_text", "grammar_spec", "typed_ast", "ast"]
  | .parserAdapter, `output_profile => #["vetc_ir", "core_tuples", "lean_plan"]
  | .parserAdapter, `determinism => #["deterministic", "best_effort"]
  | .dslProfile, `planner_hint => #["as_is", "bound_first", "high_selectivity_first"]
  | .dslProfile, `default_profile => #["auto", "tm.det", "lts", "constraint"]
  | .dslProfile, `verification_chain => #["tm.det", "lts", "constraint", "proof_obligation", "theorem_ci", "vstack_ci", "query_ci"]
  | _, _ => #[]

private def pushIssue
    (issues : Array DeclarationIssue)
    (declaration : Declaration)
    (kind : DeclarationIssueKind)
    (message : String)
    (key : Option Name := none) : Array DeclarationIssue :=
  issues.push { kind, declaration := declaration.entityName, key, message }

private def tokenSet (value : DeclValue) : Array String :=
  value.members.filterMap DeclValue.token?

private def keysUnique (attrs : Array DeclAttribute) : Bool :=
  attrs.all fun attr => (attrs.filter fun candidate => candidate.key == attr.key).size == 1

private def validateTm (declaration : Declaration) (issues : Array DeclarationIssue) : Array DeclarationIssue :=
  let states := (declaration.attr? `states).map (tokenSet ·.value) |>.getD #[]
  let alphabet := (declaration.attr? `alphabet).map (tokenSet ·.value) |>.getD #[]
  let accept := (declaration.attr? `accept).map (tokenSet ·.value) |>.getD #[]
  let reject := (declaration.attr? `reject).map (tokenSet ·.value) |>.getD #[]
  let blank := (declaration.attr? `blank).bind (DeclValue.token? ·.value)
  let initial := (declaration.attr? `initial).bind (DeclValue.token? ·.value)
  let issues := if states.isEmpty then pushIssue issues declaration .invalidStructure "TM_ATOM states must be nonempty" else issues
  let issues := if alphabet.isEmpty then pushIssue issues declaration .invalidStructure "TM_ATOM alphabet must be nonempty" else issues
  let issues := match blank with
    | some value => if alphabet.contains value then issues else pushIssue issues declaration .invalidStructure "TM_ATOM blank must belong to alphabet" (some `blank)
    | none => issues
  let issues := match initial with
    | some value => if states.contains value then issues else pushIssue issues declaration .invalidStructure "TM_ATOM initial state is unknown" (some `initial)
    | none => issues
  let issues := accept.foldl (init := issues) fun out state =>
    if states.contains state then out else pushIssue out declaration .invalidStructure s!"unknown accept state {state}" (some `accept)
  let issues := reject.foldl (init := issues) fun out state =>
    if states.contains state then out else pushIssue out declaration .invalidStructure s!"unknown reject state {state}" (some `reject)
  accept.foldl (init := issues) fun out state =>
    if reject.contains state then pushIssue out declaration .invalidStructure s!"state {state} is both accepting and rejecting" else out

private def validateLts (declaration : Declaration) (issues : Array DeclarationIssue) : Array DeclarationIssue :=
  let states := (declaration.attr? `states).map (tokenSet ·.value) |>.getD #[]
  let initial := (declaration.attr? `initial).bind (DeclValue.token? ·.value)
  let issues := if states.isEmpty then pushIssue issues declaration .invalidStructure "LTS_ATOM states must be nonempty" else issues
  match initial with
  | some value => if states.contains value then issues else pushIssue issues declaration .invalidStructure "LTS_ATOM initial state is unknown" (some `initial)
  | none => issues

/-- Validate required fields, enum domains, groundness, and TM/LTS structure. -/
def issues (declaration : Declaration) : Array DeclarationIssue :=
  let attrs := normalizedAttrs declaration
  let issues := if keysUnique attrs then #[] else pushIssue #[] declaration .duplicateKey "duplicate declaration attribute key"
  let issues := requiredKeys declaration.kind |>.foldl (init := issues) fun out key =>
    if attrs.any (fun attr => attr.key == key) then out
    else pushIssue out declaration .missingRequired s!"missing required attribute {key}" (some key)
  let issues := attrs.foldl (init := issues) fun out attr =>
    let out := if attr.value.isGround then out else pushIssue out declaration .invalidStructure s!"attribute {attr.key} contains a variable" (some attr.key)
    let allowed := allowedEnums declaration.kind attr.key
    if allowed.isEmpty then out
    else attr.value.members.foldl (init := out) fun current value =>
      match value.token? with
      | some token => if allowed.contains token then current else pushIssue current declaration .invalidEnum s!"invalid value {token} for {attr.key}" (some attr.key)
      | none => pushIssue current declaration .invalidEnum s!"attribute {attr.key} requires a named enum value" (some attr.key)
  match declaration.kind with
  | .tmAtom => validateTm declaration issues
  | .ltsAtom => validateLts declaration issues
  | _ => issues

/-- True when local declaration validation succeeds. -/
def valid (declaration : Declaration) : Bool := declaration.issues.isEmpty

private def sanitizeValue (value : String) : String :=
  value.replace ":" "." |>.replace "/" "." |>.replace " " "_" |>.replace "-" "_" |>.replace "\"" ""

private def scalarTerm? : AttrValue → Option Term
  | .term term => some term
  | .text value => some (.ground (nameFromString ("value." ++ sanitizeValue value)))
  | .integer value => some (.ground (nameFromString ("value." ++ sanitizeValue (toString value))))
  | .decimal value => some (.ground (nameFromString ("value." ++ sanitizeValue value)))
  | .boolean value => some (.ground (if value then `value.true else `value.false))

private def referenceTerm? (defaultPrefix : String) (value : DeclValue) : Option Term :=
  match value with
  | .scalar (.term term) => some term
  | _ => value.token?.map fun token => .ground (nameFromString (defaultPrefix ++ "." ++ sanitizeValue token))

private def fact
    (declaration : Declaration)
    (relation : Name)
    (object : Term)
    (attrs : Array Attribute := #[]) : RelExpr :=
  { subject := .ground declaration.entityName, relation, object, attrs, source := declaration.source }

private def genericFacts (declaration : Declaration) (attr : DeclAttribute) : Array RelExpr :=
  attr.value.scalarValues.filterMap fun scalar =>
    (scalarTerm? scalar).map fun term => fact declaration (relationName attr.key) term

private def dependencyFacts (declaration : Declaration) (key : Name) (value : DeclValue) : Array RelExpr :=
  let refs := value.members.filterMap (referenceTerm? "service")
  refs.foldl (init := #[]) fun out reference =>
    let relation := if key == `used_by then `zil.usedBy else `zil.uses
    let inverse := if key == `used_by then `zil.uses else `zil.usedBy
    let direct := fact declaration relation reference
    let inverseFact : RelExpr := {
      subject := reference
      relation := inverse
      object := .ground declaration.entityName
      source := declaration.source
    }
    let out := out.push direct |>.push inverseFact
    if key == `uses then out.push (fact declaration `zil.dependsOn reference) else out

private def providerFacts (declaration : Declaration) (key : Name) (value : DeclValue) : Array RelExpr :=
  value.members.filterMap (referenceTerm? "provider") |>.foldl (init := #[]) fun out reference =>
    let direct := fact declaration (if key == `providers then `zil.providers else `zil.provider) reference
    let inverse : RelExpr := {
      subject := reference
      relation := `zil.providesFor
      object := .ground declaration.entityName
      source := declaration.source
    }
    out.push direct |>.push inverse

private def transitionAttrs
    (fromState readSymbol toState writeSymbol move : String) : Array Attribute := #[
  { key := `from_state, value := .text fromState },
  { key := `read_symbol, value := .text readSymbol },
  { key := `to_state, value := .text toState },
  { key := `write_symbol, value := .text writeSymbol },
  { key := `move, value := .text move }
]

private def tmTransitionFacts (declaration : Declaration) (value : DeclValue) : Array RelExpr :=
  match value with
  | .map entries =>
      entries.foldl (init := #[]) fun out entry =>
        let index := out.size
        match entry.1, entry.2 with
        | .list key, .list target =>
            if key.size == 2 && target.size == 3 then
              match key[0]!.token?, key[1]!.token?, target[0]!.token?, target[1]!.token?, target[2]!.token? with
              | some fromState, some readSymbol, some toState, some writeSymbol, some move =>
                  out.push (fact declaration `zil.transition (.ground (nameFromString s!"tmtr.n{index}"))
                    (transitionAttrs fromState readSymbol toState writeSymbol move))
              | _, _, _, _, _ => out
            else out
        | _, _ => out
  | _ => #[]

private def ltsTransitionFacts (declaration : Declaration) (value : DeclValue) : Array RelExpr :=
  match value with
  | .map entries =>
      entries.foldl (init := #[]) fun out entry =>
        let index := out.size
        match entry.1, entry.2 with
        | .list key, .list target =>
            if key.size == 2 && target.size >= 1 then
              match key[0]!.token?, key[1]!.token?, target[0]!.token? with
              | some fromState, some label, some toState =>
                  let attrs : Array Attribute := #[
                    { key := `from_state, value := .text fromState },
                    { key := `label, value := .text label },
                    { key := `to_state, value := .text toState }
                  ]
                  let attrs := match target[1]? >>= DeclValue.token? with
                    | some effect => attrs.push { key := `effect, value := .text effect }
                    | none => attrs
                  out.push (fact declaration `zil.edge (.ground (nameFromString s!"ltsedge.n{index}")) attrs)
              | _, _, _ => out
            else out
        | _, _ => out
  | _ => #[]

/-- Deterministically lower one validated declaration into canonical relations. -/
def lower (declaration : Declaration) : Array RelExpr :=
  let kindFact := fact declaration `zil.kind (.ground (nameFromString ("entity." ++ declaration.kind.prefix)))
  let facts := (normalizedAttrs declaration).foldl (init := #[kindFact]) fun out attr =>
    if declaration.kind == .service && (attr.key == `uses || attr.key == `used_by) then
      out ++ dependencyFacts declaration attr.key attr.value
    else if attr.key == `provider || attr.key == `providers then
      out ++ providerFacts declaration attr.key attr.value
    else if declaration.kind == .tmAtom && attr.key == `transitions then
      out ++ tmTransitionFacts declaration attr.value
    else if declaration.kind == .ltsAtom && attr.key == `transitions then
      out ++ ltsTransitionFacts declaration attr.value
    else
      out ++ genericFacts declaration attr
  facts.foldl (init := #[]) fun unique relation =>
    if unique.any (fun existing => existing.semanticallyEqual relation) then unique else unique.push relation

end Declaration

end Zil
