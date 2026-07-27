-- Generated from an immutable ZIL snapshot. Do not edit.
module

public import Zil

@[expose] public section

namespace Zil.Generated.DependencyAvailability

open Zil

zil_snapshot "sha256:4d8b9ea6bcfa900519c6a2a244cb62b3f7bd89cb6c17ab3715be1f4ccb15cfc4" completeness complete

zil_fact "app:svc1" # depends_on @ "service:db1"
zil_fact "service:db1" # available @ true

zil_rule dependencyAvailability:
  ?app # dependency_available @ ?dep IF
  ?app # depends_on @ ?dep AND
  ?dep # available @ true

def snapshotRevision : String := "sha256:4d8b9ea6bcfa900519c6a2a244cb62b3f7bd89cb6c17ab3715be1f4ccb15cfc4"
def snapshotSourceSha256 : String := "4d8b9ea6bcfa900519c6a2a244cb62b3f7bd89cb6c17ab3715be1f4ccb15cfc4"
def snapshotCompleteness : String := "complete"

def program : Program := {
  facts := [{ object := (.symbol "app:svc1"), relation := "depends_on", subject := (.symbol "service:db1"), attrs := [] },
    { object := (.symbol "service:db1"), relation := "available", subject := (.boolean true), attrs := [] }],
  rules := [{ name := "dependencyAvailability", head := { object := .variable "app", relation := "dependency_available", subject := .variable "dep", attrs := [] }, literals := [.positive { object := .variable "app", relation := "depends_on", subject := .variable "dep", attrs := [] }, .positive { object := .variable "dep", relation := "available", subject := .value (.boolean true), attrs := [] }] }]
}

end Zil.Generated.DependencyAvailability
