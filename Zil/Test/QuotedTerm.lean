import Zil.Native

open Zil Lean

/-!
# Quoted strings as terms

A ground token that contains a double quote keeps exactly the name it has today whenever today's rules accept it. Only a
token those rules reject (a quoted run that holds `//`, as in a URL, gives an empty name segment) falls back to a
quote-aware split. These tests pin both halves.
-/

private def nameOf (token : String) : Option Name :=
  match Zil.Parser.termFromToken token with
  | .ok (.node node) => some node.name
  | _ => none

/-- The token parses the same way as before: `termFromToken` gives the name `nameFromToken` gives. -/
private def sameAsToday (token : String) : Bool :=
  match Zil.Parser.nameFromToken token with
  | .ok name => nameOf token == some name
  | .error _ => false

/-! ## Unchanged: tokens that parse today -/

#guard sameAsToday "doc:readme"
#guard sameAsToday "value:\"degraded\""
#guard sameAsToday "value:\"4456\""
#guard sameAsToday "value:\"1.5\""
#guard sameAsToday "value:\"a:b\""
#guard sameAsToday "value:\"a-b\""
#guard sameAsToday "\"x\""

-- and the names themselves are pinned, so a change to both sides at once is caught
#guard nameOf "value:\"4456\"" == some (Name.str (Name.mkSimple "value") "\"4456\"")
#guard nameOf "value:\"a-b\"" == some (Name.str (Name.mkSimple "value") "\"a_b\"")

/-! ## New: tokens that were rejected -/

#guard nameOf "\"https://api.example.test/v1?x=1\"" ==
  some (Name.mkSimple "\"https://api.example.test/v1?x=1\"")
#guard nameOf "value:\"http://127.0.0.1:8096\"" ==
  some (Name.str (Name.mkSimple "value") "\"http://127.0.0.1:8096\"")
-- namespaces outside the quotes still split
#guard nameOf "cfg:origins:\"http://a.test\"" ==
  some (Name.str (Name.str (Name.mkSimple "cfg") "origins") "\"http://a.test\"")
-- text inside the quotes is kept exactly: no hyphen rewriting, no collisions
#guard nameOf "\"https://a-b/c\"" == some (Name.mkSimple "\"https://a-b/c\"")
#guard nameOf "\"https://a/b\"" != nameOf "\"https://a//b\""
-- a backslash escapes the next character inside the quotes
#guard nameOf "\"a\\\"b//\"" == some (Name.mkSimple "\"a\"b//\"")

/-! ## Unchanged: what stays an error -/

-- an unterminated quote gives the message it gives today
#guard match Zil.Parser.termFromToken "\"https://a", Zil.Parser.nameFromToken "\"https://a" with
  | .error fromTerm, .error fromName => fromTerm == fromName
  | _, _ => false
-- an empty segment outside quotes is still an error
#guard match Zil.Parser.termFromToken "a::b" with
  | .error message => message == "empty name segment"
  | .ok _ => false
-- a token without a quote is never routed through the fallback
#guard (nameOf "a//b").isNone
#guard match Zil.Parser.termFromToken "?x" with
  | .ok (.var name) => name == `x
  | _ => false

/-! ## Whole programs -/

private def urlModel : String :=
  "cfg:item#origin@value:\"http://127.0.0.1:8096\".\n" ++
  "cfg:other#origin@value:\"http://127.0.0.1:9000\".\n" ++
  "QUERY first:\n" ++
  "FIND ?x WHERE ?x#origin@value:\"http://127.0.0.1:8096\".\n"

#guard match Zil.Parser.Program.parseText urlModel with
  | .ok program =>
      program.tuples.size == 2 &&
      match program.queries[0]? with
      | some query =>
          (Zil.Engine.solve (Zil.Engine.closure program.facts program.allRules) query).size == 1
      | none => false
  | .error _ => false


/-! ## Separators inside quotes: tuple lines -/

private def renderedLike (parse : Nat → String → Except Zil.Parser.ParseError TupleExpr) (line : String) : Option String :=
  match parse 1 line with
  | .ok tuple => (Zil.Parser.renderTupleDefinition 0 tuple).toOption
  | .error _ => none

/-- A line that parses today parses to exactly the same tuple through the public entry point. -/
private def likeToday (line : String) : Bool :=
  (renderedLike (Zil.Parser.parseTupleLineWith false) line).isSome &&
  renderedLike (Zil.Parser.parseTupleLineWith false) line == renderedLike Zil.Parser.parseTupleLine line

#guard likeToday "doc:readme#viewer@user:10."
#guard likeToday "doc:readme#viewer@group:eng#member."
#guard likeToday "a:b#r@value:\"4456\"."
#guard likeToday "a#r@value:\"1.5\"."
#guard likeToday "a:b#r@c [note=\"x\"]."
#guard likeToday "a:b#r@c [note=\"a=b\", k=v]."

private def subjectName (tuple : TupleExpr) : Name :=
  match tuple.subject with
  | .direct (.node node) => node.name
  | _ => Name.anonymous

-- a regular expression as the object: brackets inside quotes are text. Its name is the name today's rules give the token,
-- so the same string has the same name in a fact and in a query whichever way the line had to be read.
#guard (Zil.Parser.parseTupleLine 1 "api:p#pattern@\"^projects/[^/]+/x$\".").toOption.isSome
#guard (Zil.Parser.parseTupleLine 1 "api:p#pattern@\"^projects/[^/]+/x$\".").toOption.map subjectName ==
  (Zil.Parser.nameFromToken "\"^projects/[^/]+/x$\"").toOption
-- where today's rules reject the token, the name is exact: brackets and a URL together
#guard (Zil.Parser.parseTupleLine 1 "api:p#pattern@\"https://x/[a]\".").toOption.map subjectName ==
  some (Name.mkSimple "\"https://x/[a]\"")
-- '@' and '#' inside quotes
#guard (Zil.Parser.parseTupleLine 1 "a:b#email@\"x@y#z\".").toOption.isSome
-- a real attribute list after a quoted string that holds brackets
#guard (Zil.Parser.parseTupleLine 1 "a:b#r@\"p[1]\" [k=\"v\"].").toOption.isSome
-- a quoted attribute value that holds brackets is one attribute
#guard match Zil.Parser.parseTupleLine 1 "a:b#r@c [pattern=\"^x[0-9]+$\"]." with
  | .ok tuple => tuple.attrs.size == 1 && tuple.attrs[0]!.value == .text "^x[0-9]+$"
  | .error _ => false

-- when the retry fails too, today's error is the one reported
private def errorOf (parse : Nat → String → Except Zil.Parser.ParseError TupleExpr) (line : String) : Option String :=
  match parse 1 line with
  | .error error => some error.render
  | .ok _ => none
#guard (errorOf Zil.Parser.parseTupleLine "a:b#r@\"https://x.").isSome
#guard errorOf Zil.Parser.parseTupleLine "a:b#r@\"https://x." ==
  errorOf (Zil.Parser.parseTupleLineWith false) "a:b#r@\"https://x."
-- a line the two attempts reject for different reasons reports today's reason
#guard errorOf (Zil.Parser.parseTupleLineWith false) "a:b#@\"x@y\"." !=
  errorOf (Zil.Parser.parseTupleLineWith true) "a:b#@\"x@y\"."
#guard (errorOf Zil.Parser.parseTupleLine "a:b#@\"x@y\".").isSome
#guard errorOf Zil.Parser.parseTupleLine "a:b#@\"x@y\"." ==
  errorOf (Zil.Parser.parseTupleLineWith false) "a:b#@\"x@y\"."
#guard errorOf Zil.Parser.parseTupleLine "a:b#r@c \"x\" \"y\"." ==
  errorOf (Zil.Parser.parseTupleLineWith false) "a:b#r@c \"x\" \"y\"."

/-! ## Separators inside quotes: rules and queries -/

private def bracketModel : String :=
  "api:p#pattern@\"^projects/[^/]+/x$\".\n" ++
  "api:q#pattern@\"^zones/[^/]+$\".\n" ++
  "RULE hit:\n" ++
  "IF ?a#pattern@\"^projects/[^/]+/x$\"\n" ++
  "THEN ?a#hit@value:true.\n" ++
  "QUERY hits:\n" ++
  "FIND ?a WHERE ?a#hit@value:true.\n" ++
  "QUERY direct:\n" ++
  "FIND ?a WHERE ?a#pattern@\"^zones/[^/]+$\".\n"

#guard match Zil.Parser.Program.parseText bracketModel with
  | .ok program =>
      program.tuples.size == 2 && program.queries.size == 2 &&
      program.queries.all fun query =>
        (Zil.Engine.solve (Zil.Engine.closure program.facts program.allRules) query).size == 1
  | .error _ => false

/-! ## Generated Lean -/

-- every name that was writable before is written exactly as before
#guard Zil.Parser.leanNameLiteral (Name.str (Name.mkSimple "value") "\"4456\"") == "`value.«\"4456\"»"
#guard Zil.Parser.leanNameLiteral (Name.mkSimple "doc.readme") == "`«doc.readme»"
-- a name with a character the literal cannot hold is built from its parts
#guard Zil.Parser.leanNameLiteral (Name.mkSimple "a»b") ==
  "(Lean.Name.str Lean.Name.anonymous \"a»b\")"
#guard Zil.Parser.leanNameLiteral (Name.str (Name.mkSimple "v") "x\ny") ==
  "(Lean.Name.str (Lean.Name.str Lean.Name.anonymous \"v\") \"x\\ny\")"

#guard match Zil.Parser.parseText "cfg:item#origin@value:\"http://127.0.0.1:8096\".\n" with
  | .ok program =>
      match Zil.Parser.renderLeanModule program (Zil.Parser.defaultNamespace program) with
      | .ok rendered => (rendered.splitOn "`value.«\"http://127.0.0.1:8096\"»").length > 1
      | .error _ => false
  | .error _ => false
