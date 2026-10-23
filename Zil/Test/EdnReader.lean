import Zil.Edn.Reader

open Zil.Json Zil.Edn

private def canon (text : String) : Option String :=
  match readCanonical text with
  | .ok j => some (write j)
  | .error _ => none

-- keywords and symbols give their names; maps are sorted; vectors and lists are arrays
#guard canon "{:b 1 :a [:x y \"z\"]}" == some "{\"a\":[\"x\",\"y\",\"z\"],\"b\":1}"
#guard canon "{:workflow_id \"workflow:demo\", :n -3, :ok true, :none nil}" ==
  some "{\"n\":-3,\"none\":null,\"ok\":true,\"workflow_id\":\"workflow:demo\"}"
-- namespaced keywords give their name only
#guard canon "{:a/b 1}" == some "{\"b\":1}"
-- sets are ordered by the text of their elements, as the earlier tool ordered them
#guard canon "#{:b :a \"c\"}" == some "[\"a\",\"b\",\"c\"]"
#guard canon "#{3 1 2}" == some "[1,2,3]"
-- comments, commas and discards are trivia
#guard canon "; note\n{:a 1, ; trailing\n :b #_ :skipped 2}" == some "{\"a\":1,\"b\":2}"
-- string escapes
#guard canon "\"a\\nb\\\"c\\u00e9\"" == some "\"a\\nb\\\"c\\u00e9\""
-- decimals keep their text; big-int and big-decimal suffixes are dropped
#guard canon "[1.5 10N 2M]" == some "[1.5,10,2]"
-- errors
#guard canon "{:a}" == none
#guard canon "#inst \"2026\"" == none
#guard canon "[1 2" == none
#guard canon "{1 2}" == none
#guard canon "1 2" == none
#guard canon "#{:a :a}" == none
