-- Generated from an immutable ZIL snapshot. Do not edit.
module

public import Zil

@[expose] public section

namespace Zil.Generated.KnowledgeCore

open Zil

zil_snapshot "sha256:e10f2f58da95b2bc7d40c78f68ace30b6d24000922192ab967c6c95d9ce295da" completeness complete

zil_fact "quantity:entropy" # derived_from @ "quantity:pressure"
zil_fact "quantity:entropy" # derived_from @ "quantity:temperature"
zil_fact "quantity:pressure" # measured_by @ "instrument:manometer"
zil_fact "quantity:temperature" # measured_by @ "instrument:thermocouple"
zil_fact "instrument:manometer" # calibrated @ "value:true" [method = "deadweight", year = 2025]
zil_fact "instrument:thermocouple" # calibrated @ "value:true" [method = "fixed_point", year = 2026]

zil_rule derived_trusted:
  ?q # input_trusted @ ?base IF
  ?q # derived_from @ ?base AND
  ?base # trusted @ "value:true"

zil_rule trusted_when_calibrated:
  ?q # trusted @ "value:true" IF
  ?q # measured_by @ ?inst AND
  ?inst # calibrated @ "value:true"

def snapshotRevision : String := "sha256:e10f2f58da95b2bc7d40c78f68ace30b6d24000922192ab967c6c95d9ce295da"
def snapshotSourceSha256 : String := "e10f2f58da95b2bc7d40c78f68ace30b6d24000922192ab967c6c95d9ce295da"
def snapshotCompleteness : String := "complete"

def program : Program := {
  facts := [{ object := (.symbol "quantity:entropy"), relation := "derived_from", subject := (.symbol "quantity:pressure"), attrs := [] },
    { object := (.symbol "quantity:entropy"), relation := "derived_from", subject := (.symbol "quantity:temperature"), attrs := [] },
    { object := (.symbol "quantity:pressure"), relation := "measured_by", subject := (.symbol "instrument:manometer"), attrs := [] },
    { object := (.symbol "quantity:temperature"), relation := "measured_by", subject := (.symbol "instrument:thermocouple"), attrs := [] },
    { object := (.symbol "instrument:manometer"), relation := "calibrated", subject := (.symbol "value:true"), attrs := [("method", (.symbol "deadweight")), ("year", (.integer 2025))] },
    { object := (.symbol "instrument:thermocouple"), relation := "calibrated", subject := (.symbol "value:true"), attrs := [("method", (.symbol "fixed_point")), ("year", (.integer 2026))] }],
  rules := [{ name := "derived_trusted", head := { object := .variable "q", relation := "input_trusted", subject := .variable "base", attrs := [] }, literals := [.positive { object := .variable "q", relation := "derived_from", subject := .variable "base", attrs := [] }, .positive { object := .variable "base", relation := "trusted", subject := .value (.symbol "value:true"), attrs := [] }] },
    { name := "trusted_when_calibrated", head := { object := .variable "q", relation := "trusted", subject := .value (.symbol "value:true"), attrs := [] }, literals := [.positive { object := .variable "q", relation := "measured_by", subject := .variable "inst", attrs := [] }, .positive { object := .variable "inst", relation := "calibrated", subject := .value (.symbol "value:true"), attrs := [] }] }]
}

end Zil.Generated.KnowledgeCore
