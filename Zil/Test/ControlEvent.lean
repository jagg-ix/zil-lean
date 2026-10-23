import Zil.Control.Event

open Zil.Json Zil.Control.Event Zil.Crypto

/-! # Control events and receipts: every expected value below was produced by the earlier Clojure implementation -/

private def d1 : String := "sha256:86ae35d58a6aa3b5742df94ef9d7162219f0106a911ae1954c1f0604aaec805d"
private def aaaa : String := "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

#guard emptyChainSha256 == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
#guard Sha256.ofText "decision" == d1

private def parsed (text : String) : J := (parse text).toOption.getD .null

private def input0 : EventInput :=
  { stream := "workflow:demo", eventType := "semantic-decision", actor := "agent:tester", requestId := some "request:1",
    baseRevision := some "rev:42", contextBundleId := some aaaa, decisionSha256 := d1,
    payload := parsed "{\"workflow_id\":\"workflow:demo\",\"response\":{\"status\":\"ok\",\"errors\":[],\"warnings\":[\"w/x\",\"é\"]}}" }
private def input1 : EventInput :=
  { stream := "s", eventType := "t", actor := "a", decisionSha256 := emptyChainSha256 }
private def input2 : EventInput :=
  { stream := "stream/with/slash", eventType := "observation", actor := "人", requestId := some "  ",
    decisionSha256 := d1,
    payload := parsed "{\"z\":1,\"b\":{\"y\":[1,2,{\"k\":\"v\"}],\"x\":\"😀\\n\"},\"a\":null}" }

private def prepared (input : EventInput) : J := (prepare input).toOption.getD .null
private def jsonOf (input : EventInput) : String := (eventJson (prepared input)).toOption.getD ""
private def sha (input : EventInput) (previous : String) (revision : Nat) : String :=
  (eventSha256 (prepared input) previous revision).toOption.getD ""


#guard jsonOf input0 == "{\"event_id\":\"event:1d57bb461c9bc3fce6b053a1bf93023f47ad96a93a2c8d520956248530ff07e4\",\"stream\":\"workflow:demo\",\"request_id\":\"request:1\",\"schema\":\"ZIL-CONTROL-EVENT\\/1\",\"base_revision\":\"rev:42\",\"event_type\":\"semantic-decision\",\"context_bundle_id\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"decision_sha256\":\"sha256:86ae35d58a6aa3b5742df94ef9d7162219f0106a911ae1954c1f0604aaec805d\",\"plugin_id\":\"-\",\"payload_sha256\":\"sha256:786f9007e75afe489cdd129bd474ba721ea719c4c1e9c18ec369d4ffd63915db\",\"payload\":{\"response\":{\"errors\":[],\"status\":\"ok\",\"warnings\":[\"w\\/x\",\"\\u00e9\"]},\"workflow_id\":\"workflow:demo\"},\"actor\":\"agent:tester\"}"
#guard (prepared input0).getStr? "event_id" == some "event:1d57bb461c9bc3fce6b053a1bf93023f47ad96a93a2c8d520956248530ff07e4"
#guard (prepared input0).getStr? "payload_sha256" == some "sha256:786f9007e75afe489cdd129bd474ba721ea719c4c1e9c18ec369d4ffd63915db"
#guard sha input0 emptyChainSha256 1 == "sha256:9459794356ffc1201c549d3ca17db98afbc196090d2f232ebfc2b58439cce6cf"
#guard sha input0 "sha256:9459794356ffc1201c549d3ca17db98afbc196090d2f232ebfc2b58439cce6cf" 2 == "sha256:292cd1f74114770711fa4985a9b5d1cf988ba48472f46d2d6d6024241f0c894b"

#guard jsonOf input1 == "{\"event_id\":\"event:463692ff4c2689128d8fcaa0cacde5ddceb970f20787072a76247d35a5588eff\",\"stream\":\"s\",\"request_id\":\"-\",\"schema\":\"ZIL-CONTROL-EVENT\\/1\",\"base_revision\":\"-\",\"event_type\":\"t\",\"context_bundle_id\":\"-\",\"decision_sha256\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"plugin_id\":\"-\",\"payload_sha256\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"payload\":{},\"actor\":\"a\"}"
#guard (prepared input1).getStr? "event_id" == some "event:463692ff4c2689128d8fcaa0cacde5ddceb970f20787072a76247d35a5588eff"
#guard (prepared input1).getStr? "payload_sha256" == some "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
#guard sha input1 emptyChainSha256 1 == "sha256:550ef56e5b08bb97af47e77fd874d308c54871c3e8dc388f9e671be317e03739"
#guard sha input1 "sha256:550ef56e5b08bb97af47e77fd874d308c54871c3e8dc388f9e671be317e03739" 2 == "sha256:8c5f5a3c61965f422f403e09bee17d3cbd9c981a20ab6af68484870a96f3178f"

#guard jsonOf input2 == "{\"event_id\":\"event:c1f0825a992de64345daa22a6abf81f3d7ef55bfc376c3a69a4a01abee6ed09a\",\"stream\":\"stream\\/with\\/slash\",\"request_id\":\"-\",\"schema\":\"ZIL-CONTROL-EVENT\\/1\",\"base_revision\":\"-\",\"event_type\":\"observation\",\"context_bundle_id\":\"-\",\"decision_sha256\":\"sha256:86ae35d58a6aa3b5742df94ef9d7162219f0106a911ae1954c1f0604aaec805d\",\"plugin_id\":\"-\",\"payload_sha256\":\"sha256:0d5ee7febcf994f5c783694d9cacd3091342850ba13b2923dd96f38346ed1ce1\",\"payload\":{\"a\":null,\"b\":{\"x\":\"\\ud83d\\ude00\\n\",\"y\":[1,2,{\"k\":\"v\"}]},\"z\":1},\"actor\":\"\\u4eba\"}"
#guard (prepared input2).getStr? "event_id" == some "event:c1f0825a992de64345daa22a6abf81f3d7ef55bfc376c3a69a4a01abee6ed09a"
#guard (prepared input2).getStr? "payload_sha256" == some "sha256:0d5ee7febcf994f5c783694d9cacd3091342850ba13b2923dd96f38346ed1ce1"
#guard sha input2 emptyChainSha256 1 == "sha256:420c4435b67a0e1ec740bc4786205a97e5c7d06774c242e4fa8a59f18f298537"
#guard sha input2 "sha256:420c4435b67a0e1ec740bc4786205a97e5c7d06774c242e4fa8a59f18f298537" 2 == "sha256:fadc1b38008a3884e42adf7e745e9daf4f5bd0c640bfc60cc87f9d2570d36cb9"

private def receiptInput : ReceiptInput :=
  { stream := "workflow:demo", baseRevision := 0, finalRevision := 2, eventCount := 2,
    batchSha256 := Sha256.ofText "batch", committedAtEpochMs := 1790000000000 }
private def receipt : J := (prepareReceipt receiptInput).toOption.getD .null

#guard receiptJson receipt == "{\"schema\":\"ZIL-CONTROL-RECEIPT\\/1\",\"receipt_id\":\"receipt:eaf7cbf091dcc3158d3012b2ba37da6c0fecb07ff386e876dc84277d5bea727d\",\"stream\":\"workflow:demo\",\"base_revision\":0,\"final_revision\":2,\"event_count\":2,\"batch_sha256\":\"sha256:4bb24efc9641afc5ded1ca77eabb6e2fcf062d2112ccd61bd8bd6acd89180bae\",\"committed_at_epoch_ms\":1790000000000}"
#guard receipt.getStr? "receipt_id" == some "receipt:eaf7cbf091dcc3158d3012b2ba37da6c0fecb07ff386e876dc84277d5bea727d"
#guard receiptSha256 receipt == "sha256:fad89f338fce400db2c0cbe3392b551262bc31060f3984df043dd3aa562735f9"

-- refusals
#guard (prepare { input1 with stream := "  " }).toOption.isNone
#guard (prepare { input1 with eventType := "" }).toOption.isNone
#guard (prepare { input1 with actor := "" }).toOption.isNone
#guard (prepare { input1 with decisionSha256 := "sha256:xyz" }).toOption.isNone
#guard (eventSha256 (prepared input1) "not-a-digest" 1).toOption.isNone
#guard (prepareReceipt { receiptInput with batchSha256 := "x" }).toOption.isNone
-- an event given its own identity keeps it
#guard (prepared { input1 with eventId := some "event:custom" }).getStr? "event_id" == some "event:custom"
-- preparing a prepared event is the identity on its bytes
#guard match inputOfJson (prepared input0) with
  | .ok again => jsonOf again == jsonOf input0
  | .error _ => false
