-- Generated from an immutable ZIL snapshot. Do not edit.
module

public import Zil

@[expose] public section

namespace Zil.Generated.AttributeNegation

open Zil

zil_snapshot "sha256:927b80450b51150e02c1fbd87bb0440f7940bbfe8dc2a835ec3202390608bc75" completeness complete

zil_fact "claim:c2" # candidate @ "value:true" [quality = "draft", score = 1]
zil_fact "claim:c1" # candidate @ "value:true" [quality = "reviewed", score = 5]
zil_fact "claim:c2" # blocked @ "value:true" [reason = "policy"]

zil_rule acceptedWhenUnblocked:
  ?claim # accepted @ "value:true" [quality = ?quality] IF
  ?claim # candidate @ "value:true" [quality = ?quality] AND
  NOT ?claim # blocked @ "value:true"

def snapshotRevision : String := "sha256:927b80450b51150e02c1fbd87bb0440f7940bbfe8dc2a835ec3202390608bc75"
def snapshotSourceSha256 : String := "927b80450b51150e02c1fbd87bb0440f7940bbfe8dc2a835ec3202390608bc75"
def snapshotCompleteness : String := "complete"

def program : Program := {
  facts := [{ object := (.symbol "claim:c2"), relation := "candidate", subject := (.symbol "value:true"), attrs := [("quality", (.symbol "draft")), ("score", (.integer 1))] },
    { object := (.symbol "claim:c1"), relation := "candidate", subject := (.symbol "value:true"), attrs := [("quality", (.symbol "reviewed")), ("score", (.integer 5))] },
    { object := (.symbol "claim:c2"), relation := "blocked", subject := (.symbol "value:true"), attrs := [("reason", (.symbol "policy"))] }],
  rules := [{ name := "acceptedWhenUnblocked", head := { object := .variable "claim", relation := "accepted", subject := .value (.symbol "value:true"), attrs := [("quality", .variable "quality")] }, literals := [.positive { object := .variable "claim", relation := "candidate", subject := .value (.symbol "value:true"), attrs := [("quality", .variable "quality")] }, .negative { object := .variable "claim", relation := "blocked", subject := .value (.symbol "value:true"), attrs := [] }] }]
}

end Zil.Generated.AttributeNegation
