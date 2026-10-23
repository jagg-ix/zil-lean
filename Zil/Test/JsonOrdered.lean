import Zil.Json.Ordered

open Zil.Json

/-! # Ordered JSON: bytes as `clojure.data.json/write-str` writes them (expected strings come from that writer) -/

private def sample := "é/\"\\ \u0001\u001f\n\r\t\u0008\u000c \u007f \u2028 😀 ~"

#guard writeString sample == "\"\\u00e9\\/\\\"\\\\ \\u0001\\u001f\\n\\r\\t\\b\\f \u007f \\u2028 \\ud83d\\ude00 ~\""
#guard writeString sample (escapeSlash := false) == "\"\\u00e9/\\\"\\\\ \\u0001\\u001f\\n\\r\\t\\b\\f \u007f \\u2028 \\ud83d\\ude00 ~\""
#guard writeString ("a" ++ String.ofList [Char.ofNat 128] ++ "c" ++ String.ofList [Char.ofNat 0x9f]) == "\"a\\u0080c\\u009f\""
#guard write (.obj #[("b", .int 1), ("a", .arr #[.bool true, .null, .number "1.5", .int (-3), .int 10000000000, .str "x"])]) ==
  "{\"b\":1,\"a\":[true,null,1.5,-3,10000000000,\"x\"]}"

-- parse then write returns the bytes (with the slash escape the writer uses by default)
private def roundTrips (text : String) : Bool :=
  match parse text with
  | .ok value => write value == text
  | .error _ => false
#guard roundTrips "{\"b\":1,\"a\":[true,null,-3,\"x\\/y\",{\"k\":\"\\u00e9\\ud83d\\ude00\"}]}"
#guard roundTrips "[]"
#guard roundTrips "{}"
#guard roundTrips "{\"a\":{\"b\":[]}}"

-- surrogate pairs decode to one character
#guard match parse "\"\\ud83d\\ude00\"" with | .ok (.str s) => s == "😀" | _ => false
-- bad input is an error
#guard (parse "{\"a\":").toOption.isNone
#guard (parse "[1,]").toOption.isNone
#guard (parse "\"\\ud83d\"").toOption.isNone
#guard (parse "{} x").toOption.isNone

-- canonical form sorts keys at every depth, in JVM string order, and rejects duplicates
#guard match parse "{\"b\":{\"z\":1,\"a\":2},\"a\":[{\"y\":1,\"x\":2}]}" with
  | .ok v => (match canonical v with
      | .ok c => write c == "{\"a\":[{\"x\":2,\"y\":1}],\"b\":{\"a\":2,\"z\":1}}"
      | .error _ => false)
  | .error _ => false
#guard (match parse "{\"a\":1,\"a\":2}" with | .ok v => (canonical v).toOption.isNone | .error _ => false)
-- a supplementary character sorts after U+FFFF-range characters below U+E000 in UTF-16 order
#guard compareKeys "😀" "\uFFFD" == .lt
#guard compareKeys "a" "b" == .lt
#guard compareKeys "ab" "a" == .gt
