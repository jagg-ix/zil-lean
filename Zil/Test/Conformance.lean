import Zil.Codec.Conformance

private def source : String :=
  "MODULE conformance.demo.\n" ++
  "doc:a#parent@doc:b.\n" ++
  "RULE inherit:\n" ++
  "IF ?x#parent@?y\n" ++
  "THEN ?x#ancestor@?y.\n" ++
  "QUERY ancestors:\n" ++
  "FIND ?y WHERE doc:a#ancestor@?y.\n"

private def hasLinePrefix (report prefix : String) : Bool :=
  (report.splitOn "\n").any fun line => line.startsWith prefix

#guard match Zil.Codec.Conformance.renderSource source with
  | .ok report =>
      report.startsWith "ZILC\t1\nmodule\tconformance.demo\n" &&
      hasLinePrefix report "fact\t" &&
      hasLinePrefix report "closed\t" &&
      hasLinePrefix report "rule\t" &&
      hasLinePrefix report "query-row\tancestors\t"
  | .error _ => false

run_cmd do
  match Zil.Codec.Conformance.renderSource source with
  | .error error => throwError error
  | .ok report =>
      unless hasLinePrefix report "query-row\tancestors\t" do
        throwError "conformance report omitted query bindings"
