import Zil.Native

open Zil

/-!
# Continuation lines

A statement written over several physical lines parses to exactly what the same statement on one line parses to, and a
statement that is still unfinished when the next one starts is left alone, so it gives the error it gives today.
-/

/-- What a parsed program means, without line numbers: facts, rules, queries and declarations. -/
private def meaning (program : Zil.Program) : List String :=
  (program.facts.map Zil.Codec.encodeRelation).toList ++
  (program.allRules.map Zil.Codec.encodeRule).toList ++
  (program.queries.map fun query =>
    "query " ++ toString query.name ++ " " ++ reprStr query.select ++ " " ++
      String.intercalate "|" ((query.premises.map Zil.Codec.encodeRelation).toList ++
        (query.negativePremises.map Zil.Codec.encodeRelation).toList)).toList ++
  (program.declarations.map fun declaration =>
    "decl " ++ reprStr declaration.kind ++ " " ++ toString declaration.name ++ " " ++ reprStr declaration.attrs).toList

private def meaningOf (text : String) : Option (List String) :=
  match Zil.Parser.DeclarationProgram.parseText text with
  | .ok program => some (meaning program)
  | .error _ => none

/-- Both forms parse, and to the same thing. -/
private def sameMeaning (multi single : String) : Bool :=
  match meaningOf multi, meaningOf single with
  | some a, some b => !a.isEmpty && a == b
  | _, _ => false

private def errorLine (text : String) : Option Nat :=
  match Zil.Parser.DeclarationProgram.parseText text with
  | .error error => some error.line
  | .ok _ => none

/-! ## FIND -/

#guard sameMeaning
  "a#r@v.\nQUERY q:\nFIND ?x\nWHERE ?x#r@v.\n"
  "a#r@v.\nQUERY q:\nFIND ?x WHERE ?x#r@v.\n"
#guard sameMeaning
  "a#r@b.\nb#s@v.\nQUERY q:\nFIND ?x ?y\nWHERE ?x#r@?y\nAND ?y#s@v.\n"
  "a#r@b.\nb#s@v.\nQUERY q:\nFIND ?x ?y WHERE ?x#r@?y AND ?y#s@v.\n"

/-! ## Rules -/

#guard sameMeaning
  "RULE both:\nIF ?a#p@?b\nAND ?b#q@?c\nAND NOT ?c#blocked@value:true\nTHEN ?a#reach@?c.\n"
  "RULE both:\nIF ?a#p@?b AND ?b#q@?c AND NOT ?c#blocked@value:true\nTHEN ?a#reach@?c.\n"
#guard sameMeaning
  "RULE both:\nIF ?a#p@?b AND\n?b#q@?c\nTHEN ?a#reach@?c.\n"
  "RULE both:\nIF ?a#p@?b AND ?b#q@?c\nTHEN ?a#reach@?c.\n"
-- indentation is free
#guard sameMeaning
  "RULE both:\n  IF ?a#p@?b\n     AND ?b#q@?c\n  THEN ?a#reach@?c.\n"
  "RULE both:\nIF ?a#p@?b AND ?b#q@?c\nTHEN ?a#reach@?c.\n"

/-! ## Brackets: attribute lists and declarations -/

#guard sameMeaning
  "a:b#r@c [k=1,\n m=2].\n"
  "a:b#r@c [k=1, m=2].\n"
#guard sameMeaning
  "QUERY_PACK ops [\n  queries=[q1 q2],\n  must_return=[q1]\n].\n"
  "QUERY_PACK ops [queries=[q1 q2], must_return=[q1]].\n"
#guard sameMeaning
  "QUERY_PACK ops [queries=[q1]].\nDSL_PROFILE p [query_pack=ops,\n  planner_hint=high_selectivity_first].\n"
  "QUERY_PACK ops [queries=[q1]].\nDSL_PROFILE p [query_pack=ops, planner_hint=high_selectivity_first].\n"

/-! ## Macros that emit continuation lines -/

private def macroMulti : String :=
  "MACRO REACH(p, q, out):\n" ++
  "EMIT RULE reach_{{out}}:\n" ++
  "EMIT IF ?a#{{p}}@?b\n" ++
  "EMIT AND ?b#{{q}}@?c\n" ++
  "EMIT THEN ?a#{{out}}@?c.\n" ++
  "ENDMACRO.\n" ++
  "USE REACH(p, q, reach).\n"

#guard sameMeaning macroMulti
  "RULE reach_reach:\nIF ?a#p@?b AND ?b#q@?c\nTHEN ?a#reach@?c.\n"

/-! ## Evaluation -/

#guard match Zil.Parser.DeclarationProgram.parseText
    "a#p@b.\nb#q@c.\nRULE both:\nIF ?x#p@?y\nAND ?y#q@?z\nTHEN ?x#reach@?z.\nQUERY reached:\nFIND ?z\nWHERE a#reach@?z.\n" with
  | .ok program =>
      match program.queries[0]? with
      | some query => (Zil.Engine.solve (Zil.Engine.closure program.facts program.allRules) query).size == 1
      | none => false
  | .error _ => false

/-! ## An unfinished statement is left alone: the error is today's, on the line where it began -/

-- a FIND with no terminating period, then a new statement
#guard errorLine "a#r@v.\nQUERY q:\nFIND ?x WHERE ?x#r@v\nQUERY r:\nFIND ?y WHERE ?y#r@v.\n" == some 3
-- a bracket that never closes, then a new statement
#guard errorLine "a#r@v.\nb:c#r@d [k=1,\nRULE r:\nIF ?a#p@?b\nTHEN ?a#q@?b.\n" == some 2
-- a THEN is never continued
#guard (errorLine "RULE r:\nIF ?a#p@?b\nTHEN ?a#q@?b\nAND ?a#z@?b.\n").isSome
-- a stray AND at the start of a statement is still an error
#guard (errorLine "a#r@v.\nAND ?x#p@?y.\n").isSome

/-! ## The line-joining function itself -/

private def texts (lines : Array String) : List String := (Zil.Parser.Continuation.joinContinuations lines).toList.map (·.2)
private def starts (lines : Array String) : List Nat := (Zil.Parser.Continuation.joinContinuations lines).toList.map (·.1)

-- a line that continues nothing comes back exactly as it was read, indentation included
#guard texts #["  a#r@v.", "b#r@w."] == ["  a#r@v.", "b#r@w."]
-- the first physical line numbers each logical line
#guard starts #["RULE r:", "IF ?a#p@?b", "AND ?b#q@?c", "THEN ?a#z@?c.", "x#y@z."] == [0, 1, 3, 4]
-- idempotent: joining the joined lines changes nothing
#guard texts ((Zil.Parser.Continuation.joinContinuations
    #["IF ?a#p@?b", "AND ?b#q@?c", "FIND ?x", "WHERE ?x#r@v."]).map (·.2)) ==
  texts #["IF ?a#p@?b", "AND ?b#q@?c", "FIND ?x", "WHERE ?x#r@v."]
-- a quoted '//' is not a comment, and a trailing comment does not make a finished FIND unfinished
#guard (texts #["FIND ?x WHERE ?x#u@\"http://a.test/x\".", "QUERY b:"]).length == 2
#guard (texts #["FIND ?x WHERE ?x#r@v. // a note", "QUERY b:"]).length == 2
-- brackets inside quotes do not open a statement
#guard (texts #["a:b#r@\"x[\".", "c:d#r@e."]).length == 2
-- an unfinished statement is never joined across the start of the next one
#guard texts #["FIND ?x WHERE ?x#r@v", "QUERY r:", "FIND ?y WHERE ?y#r@v."] ==
  ["FIND ?x WHERE ?x#r@v", "QUERY r:", "FIND ?y WHERE ?y#r@v."]
#guard texts #["a:b#r@c [k=1,", "RULE r:", "IF ?a#p@?b", "THEN ?a#q@?b."] ==
  ["a:b#r@c [k=1,", "RULE r:", "IF ?a#p@?b", "THEN ?a#q@?b."]
-- a statement that absorbs lines and is still unfinished at the end of the input is returned as it was read
#guard texts #["a#r@b [k=1,", "m=2"] == ["a#r@b [k=1,", "m=2"]
#guard texts #["FIND ?x", "WHERE ?x#r@v"] == ["FIND ?x", "WHERE ?x#r@v"]
-- a quoted '//' on a continued line is kept exactly
#guard texts #["FIND ?x", "WHERE ?x#u@\"http://a.test/x\"."] == ["FIND ?x WHERE ?x#u@\"http://a.test/x\"."]
-- a comment on a continued line is dropped from the joined line, not left to swallow the rest
#guard texts #["FIND ?x // first", "WHERE ?x#r@v."] == ["FIND ?x WHERE ?x#r@v."]
