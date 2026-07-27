-- Generated from an immutable ZIL snapshot. Do not edit.
module

public import Zil

@[expose] public section

namespace Zil.Generated.AccessControl

open Zil

zil_snapshot "sha256:aa08577f231e8756b32967850d7584ad4a9fc15d894b6602756245c4d2a874d0" completeness complete

zil_fact "dataset:run_2026_04" # kind @ "entity:object"
zil_fact "dataset:run_2026_04" # owner @ "subject:pi_alice"
zil_fact "dataset:sim_ensemble" # kind @ "entity:object"
zil_fact "dataset:sim_ensemble" # owner @ "subject:pi_bob"
zil_fact "grant:g1" # action @ "action:read"
zil_fact "grant:g1" # grantor @ "subject:pi_alice"
zil_fact "grant:g1" # kind @ "entity:dac_grant_subject"
zil_fact "grant:g1" # object @ "dataset:run_2026_04"
zil_fact "grant:g1" # subject @ "subject:postdoc_carol"
zil_fact "grant:g2" # action @ "action:write"
zil_fact "grant:g2" # grantor @ "subject:pi_alice"
zil_fact "grant:g2" # kind @ "entity:dac_grant_subject"
zil_fact "grant:g2" # object @ "dataset:sim_ensemble"
zil_fact "grant:g2" # subject @ "subject:postdoc_carol"
zil_fact "request:r1" # action @ "action:read"
zil_fact "request:r1" # kind @ "entity:access_request"
zil_fact "request:r1" # object @ "dataset:run_2026_04"
zil_fact "request:r1" # subject @ "subject:postdoc_carol"
zil_fact "request:r2" # action @ "action:write"
zil_fact "request:r2" # kind @ "entity:access_request"
zil_fact "request:r2" # object @ "dataset:sim_ensemble"
zil_fact "request:r2" # subject @ "subject:postdoc_carol"

zil_rule rbd_allow_via_dac_group:
  ?req # allowed_by @ "mechanism:dac_group" IF
  ?req # kind @ "entity:access_request" AND
  ?req # subject @ ?subject AND
  ?req # object @ ?obj AND
  ?req # action @ ?action AND
  ?g # kind @ "entity:dac_grant_group" AND
  ?g # valid @ "value:true" AND
  ?g # group @ ?group AND
  ?group # member @ ?subject AND
  ?g # object @ ?obj AND
  ?g # action @ ?action

zil_rule rbd_allow_via_dac_subject:
  ?req # allowed_by @ "mechanism:dac_subject" IF
  ?req # kind @ "entity:access_request" AND
  ?req # subject @ ?subject AND
  ?req # object @ ?obj AND
  ?req # action @ ?action AND
  ?g # kind @ "entity:dac_grant_subject" AND
  ?g # valid @ "value:true" AND
  ?g # subject @ ?subject AND
  ?g # object @ ?obj AND
  ?g # action @ ?action

zil_rule rbd_allow_via_rbac_assignment:
  ?req # allowed_by @ "mechanism:rbac_assignment" IF
  ?req # kind @ "entity:access_request" AND
  ?req # subject @ ?subject AND
  ?req # object @ ?obj AND
  ?req # action @ ?action AND
  ?rb # kind @ "entity:role_binding" AND
  ?rb # subject @ ?subject AND
  ?rb # role @ ?role AND
  ?rp # kind @ "entity:role_permission" AND
  ?rp # role @ ?role AND
  ?rp # object @ ?obj AND
  ?rp # action @ ?action

zil_rule rbd_allow_via_rbac_session:
  ?req # allowed_by @ "mechanism:rbac_session" IF
  ?req # kind @ "entity:access_request" AND
  ?req # subject @ ?subject AND
  ?req # object @ ?obj AND
  ?req # action @ ?action AND
  ?req # session @ ?session AND
  ?session # subject @ ?subject AND
  ?session # active_role @ ?role AND
  ?rp # kind @ "entity:role_permission" AND
  ?rp # role @ ?role AND
  ?rp # object @ ?obj AND
  ?rp # action @ ?action

zil_rule rbd_dac_group_grant_valid:
  ?g # valid @ "value:true" IF
  ?g # kind @ "entity:dac_grant_group" AND
  ?g # object @ ?obj AND
  ?g # grantor @ ?grantor AND
  ?obj # owner @ ?grantor

zil_rule rbd_dac_group_grantor_not_owner:
  ?g # policy_violation @ "value:grantor_not_owner" IF
  ?g # kind @ "entity:dac_grant_group" AND
  ?g # object @ ?obj AND
  ?g # grantor @ ?grantor AND
  NOT ?obj # owner @ ?grantor

zil_rule rbd_dac_subject_grant_valid:
  ?g # valid @ "value:true" IF
  ?g # kind @ "entity:dac_grant_subject" AND
  ?g # object @ ?obj AND
  ?g # grantor @ ?grantor AND
  ?obj # owner @ ?grantor

zil_rule rbd_dac_subject_grantor_not_owner:
  ?g # policy_violation @ "value:grantor_not_owner" IF
  ?g # kind @ "entity:dac_grant_subject" AND
  ?g # object @ ?obj AND
  ?g # grantor @ ?grantor AND
  NOT ?obj # owner @ ?grantor

zil_rule rbd_missing_audit_record:
  ?req # policy_violation @ "value:missing_audit_record" IF
  ?req # decision @ ?decision AND
  NOT ?req # audit_logged @ "value:true"

zil_rule rbd_policy_target_access_request:
  ?x # policy_target @ "value:access_request" IF
  ?x # kind @ "entity:access_request"

zil_rule rbd_policy_target_dac_grant_group:
  ?x # policy_target @ "value:dac_grant" IF
  ?x # kind @ "entity:dac_grant_group"

zil_rule rbd_policy_target_dac_grant_subject:
  ?x # policy_target @ "value:dac_grant" IF
  ?x # kind @ "entity:dac_grant_subject"

zil_rule rbd_policy_target_reuse_allocation:
  ?x # policy_target @ "value:reuse_allocation" IF
  ?x # kind @ "entity:reuse_allocation"

zil_rule rbd_request_allow_decision:
  ?req # decision @ "value:allow" IF
  ?req # allow_witness @ "value:true"

zil_rule rbd_request_allow_witness:
  ?req # allow_witness @ "value:true" IF
  ?req # allowed_by @ ?mechanism

zil_rule rbd_request_default_deny:
  ?req # decision @ "value:deny" IF
  ?req # kind @ "entity:access_request" AND
  NOT ?req # allow_witness @ "value:true"

zil_rule rbd_reuse_with_clear_ok:
  ?alloc # policy_ok @ "value:reuse_cleared_before_allocation" IF
  ?alloc # kind @ "entity:reuse_allocation" AND
  ?alloc # object @ ?obj AND
  ?obj # reuse_cleared @ "value:true"

zil_rule rbd_reuse_without_clear_violation:
  ?alloc # policy_violation @ "value:reuse_without_clear" IF
  ?alloc # kind @ "entity:reuse_allocation" AND
  ?alloc # object @ ?obj AND
  NOT ?obj # reuse_cleared @ "value:true"

def snapshotRevision : String := "sha256:aa08577f231e8756b32967850d7584ad4a9fc15d894b6602756245c4d2a874d0"
def snapshotSourceSha256 : String := "aa08577f231e8756b32967850d7584ad4a9fc15d894b6602756245c4d2a874d0"
def snapshotCompleteness : String := "complete"

def program : Program := {
  facts := [{ object := (.symbol "dataset:run_2026_04"), relation := "kind", subject := (.symbol "entity:object"), attrs := [] },
    { object := (.symbol "dataset:run_2026_04"), relation := "owner", subject := (.symbol "subject:pi_alice"), attrs := [] },
    { object := (.symbol "dataset:sim_ensemble"), relation := "kind", subject := (.symbol "entity:object"), attrs := [] },
    { object := (.symbol "dataset:sim_ensemble"), relation := "owner", subject := (.symbol "subject:pi_bob"), attrs := [] },
    { object := (.symbol "grant:g1"), relation := "action", subject := (.symbol "action:read"), attrs := [] },
    { object := (.symbol "grant:g1"), relation := "grantor", subject := (.symbol "subject:pi_alice"), attrs := [] },
    { object := (.symbol "grant:g1"), relation := "kind", subject := (.symbol "entity:dac_grant_subject"), attrs := [] },
    { object := (.symbol "grant:g1"), relation := "object", subject := (.symbol "dataset:run_2026_04"), attrs := [] },
    { object := (.symbol "grant:g1"), relation := "subject", subject := (.symbol "subject:postdoc_carol"), attrs := [] },
    { object := (.symbol "grant:g2"), relation := "action", subject := (.symbol "action:write"), attrs := [] },
    { object := (.symbol "grant:g2"), relation := "grantor", subject := (.symbol "subject:pi_alice"), attrs := [] },
    { object := (.symbol "grant:g2"), relation := "kind", subject := (.symbol "entity:dac_grant_subject"), attrs := [] },
    { object := (.symbol "grant:g2"), relation := "object", subject := (.symbol "dataset:sim_ensemble"), attrs := [] },
    { object := (.symbol "grant:g2"), relation := "subject", subject := (.symbol "subject:postdoc_carol"), attrs := [] },
    { object := (.symbol "request:r1"), relation := "action", subject := (.symbol "action:read"), attrs := [] },
    { object := (.symbol "request:r1"), relation := "kind", subject := (.symbol "entity:access_request"), attrs := [] },
    { object := (.symbol "request:r1"), relation := "object", subject := (.symbol "dataset:run_2026_04"), attrs := [] },
    { object := (.symbol "request:r1"), relation := "subject", subject := (.symbol "subject:postdoc_carol"), attrs := [] },
    { object := (.symbol "request:r2"), relation := "action", subject := (.symbol "action:write"), attrs := [] },
    { object := (.symbol "request:r2"), relation := "kind", subject := (.symbol "entity:access_request"), attrs := [] },
    { object := (.symbol "request:r2"), relation := "object", subject := (.symbol "dataset:sim_ensemble"), attrs := [] },
    { object := (.symbol "request:r2"), relation := "subject", subject := (.symbol "subject:postdoc_carol"), attrs := [] }],
  rules := [{ name := "rbd_allow_via_dac_group", head := { object := .variable "req", relation := "allowed_by", subject := .value (.symbol "mechanism:dac_group"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "kind", subject := .value (.symbol "entity:access_request"), attrs := [] }, .positive { object := .variable "req", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "req", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "req", relation := "action", subject := .variable "action", attrs := [] }, .positive { object := .variable "g", relation := "kind", subject := .value (.symbol "entity:dac_grant_group"), attrs := [] }, .positive { object := .variable "g", relation := "valid", subject := .value (.symbol "value:true"), attrs := [] }, .positive { object := .variable "g", relation := "group", subject := .variable "group", attrs := [] }, .positive { object := .variable "group", relation := "member", subject := .variable "subject", attrs := [] }, .positive { object := .variable "g", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "g", relation := "action", subject := .variable "action", attrs := [] }] },
    { name := "rbd_allow_via_dac_subject", head := { object := .variable "req", relation := "allowed_by", subject := .value (.symbol "mechanism:dac_subject"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "kind", subject := .value (.symbol "entity:access_request"), attrs := [] }, .positive { object := .variable "req", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "req", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "req", relation := "action", subject := .variable "action", attrs := [] }, .positive { object := .variable "g", relation := "kind", subject := .value (.symbol "entity:dac_grant_subject"), attrs := [] }, .positive { object := .variable "g", relation := "valid", subject := .value (.symbol "value:true"), attrs := [] }, .positive { object := .variable "g", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "g", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "g", relation := "action", subject := .variable "action", attrs := [] }] },
    { name := "rbd_allow_via_rbac_assignment", head := { object := .variable "req", relation := "allowed_by", subject := .value (.symbol "mechanism:rbac_assignment"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "kind", subject := .value (.symbol "entity:access_request"), attrs := [] }, .positive { object := .variable "req", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "req", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "req", relation := "action", subject := .variable "action", attrs := [] }, .positive { object := .variable "rb", relation := "kind", subject := .value (.symbol "entity:role_binding"), attrs := [] }, .positive { object := .variable "rb", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "rb", relation := "role", subject := .variable "role", attrs := [] }, .positive { object := .variable "rp", relation := "kind", subject := .value (.symbol "entity:role_permission"), attrs := [] }, .positive { object := .variable "rp", relation := "role", subject := .variable "role", attrs := [] }, .positive { object := .variable "rp", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "rp", relation := "action", subject := .variable "action", attrs := [] }] },
    { name := "rbd_allow_via_rbac_session", head := { object := .variable "req", relation := "allowed_by", subject := .value (.symbol "mechanism:rbac_session"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "kind", subject := .value (.symbol "entity:access_request"), attrs := [] }, .positive { object := .variable "req", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "req", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "req", relation := "action", subject := .variable "action", attrs := [] }, .positive { object := .variable "req", relation := "session", subject := .variable "session", attrs := [] }, .positive { object := .variable "session", relation := "subject", subject := .variable "subject", attrs := [] }, .positive { object := .variable "session", relation := "active_role", subject := .variable "role", attrs := [] }, .positive { object := .variable "rp", relation := "kind", subject := .value (.symbol "entity:role_permission"), attrs := [] }, .positive { object := .variable "rp", relation := "role", subject := .variable "role", attrs := [] }, .positive { object := .variable "rp", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "rp", relation := "action", subject := .variable "action", attrs := [] }] },
    { name := "rbd_dac_group_grant_valid", head := { object := .variable "g", relation := "valid", subject := .value (.symbol "value:true"), attrs := [] }, literals := [.positive { object := .variable "g", relation := "kind", subject := .value (.symbol "entity:dac_grant_group"), attrs := [] }, .positive { object := .variable "g", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "g", relation := "grantor", subject := .variable "grantor", attrs := [] }, .positive { object := .variable "obj", relation := "owner", subject := .variable "grantor", attrs := [] }] },
    { name := "rbd_dac_group_grantor_not_owner", head := { object := .variable "g", relation := "policy_violation", subject := .value (.symbol "value:grantor_not_owner"), attrs := [] }, literals := [.positive { object := .variable "g", relation := "kind", subject := .value (.symbol "entity:dac_grant_group"), attrs := [] }, .positive { object := .variable "g", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "g", relation := "grantor", subject := .variable "grantor", attrs := [] }, .negative { object := .variable "obj", relation := "owner", subject := .variable "grantor", attrs := [] }] },
    { name := "rbd_dac_subject_grant_valid", head := { object := .variable "g", relation := "valid", subject := .value (.symbol "value:true"), attrs := [] }, literals := [.positive { object := .variable "g", relation := "kind", subject := .value (.symbol "entity:dac_grant_subject"), attrs := [] }, .positive { object := .variable "g", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "g", relation := "grantor", subject := .variable "grantor", attrs := [] }, .positive { object := .variable "obj", relation := "owner", subject := .variable "grantor", attrs := [] }] },
    { name := "rbd_dac_subject_grantor_not_owner", head := { object := .variable "g", relation := "policy_violation", subject := .value (.symbol "value:grantor_not_owner"), attrs := [] }, literals := [.positive { object := .variable "g", relation := "kind", subject := .value (.symbol "entity:dac_grant_subject"), attrs := [] }, .positive { object := .variable "g", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "g", relation := "grantor", subject := .variable "grantor", attrs := [] }, .negative { object := .variable "obj", relation := "owner", subject := .variable "grantor", attrs := [] }] },
    { name := "rbd_missing_audit_record", head := { object := .variable "req", relation := "policy_violation", subject := .value (.symbol "value:missing_audit_record"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "decision", subject := .variable "decision", attrs := [] }, .negative { object := .variable "req", relation := "audit_logged", subject := .value (.symbol "value:true"), attrs := [] }] },
    { name := "rbd_policy_target_access_request", head := { object := .variable "x", relation := "policy_target", subject := .value (.symbol "value:access_request"), attrs := [] }, literals := [.positive { object := .variable "x", relation := "kind", subject := .value (.symbol "entity:access_request"), attrs := [] }] },
    { name := "rbd_policy_target_dac_grant_group", head := { object := .variable "x", relation := "policy_target", subject := .value (.symbol "value:dac_grant"), attrs := [] }, literals := [.positive { object := .variable "x", relation := "kind", subject := .value (.symbol "entity:dac_grant_group"), attrs := [] }] },
    { name := "rbd_policy_target_dac_grant_subject", head := { object := .variable "x", relation := "policy_target", subject := .value (.symbol "value:dac_grant"), attrs := [] }, literals := [.positive { object := .variable "x", relation := "kind", subject := .value (.symbol "entity:dac_grant_subject"), attrs := [] }] },
    { name := "rbd_policy_target_reuse_allocation", head := { object := .variable "x", relation := "policy_target", subject := .value (.symbol "value:reuse_allocation"), attrs := [] }, literals := [.positive { object := .variable "x", relation := "kind", subject := .value (.symbol "entity:reuse_allocation"), attrs := [] }] },
    { name := "rbd_request_allow_decision", head := { object := .variable "req", relation := "decision", subject := .value (.symbol "value:allow"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "allow_witness", subject := .value (.symbol "value:true"), attrs := [] }] },
    { name := "rbd_request_allow_witness", head := { object := .variable "req", relation := "allow_witness", subject := .value (.symbol "value:true"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "allowed_by", subject := .variable "mechanism", attrs := [] }] },
    { name := "rbd_request_default_deny", head := { object := .variable "req", relation := "decision", subject := .value (.symbol "value:deny"), attrs := [] }, literals := [.positive { object := .variable "req", relation := "kind", subject := .value (.symbol "entity:access_request"), attrs := [] }, .negative { object := .variable "req", relation := "allow_witness", subject := .value (.symbol "value:true"), attrs := [] }] },
    { name := "rbd_reuse_with_clear_ok", head := { object := .variable "alloc", relation := "policy_ok", subject := .value (.symbol "value:reuse_cleared_before_allocation"), attrs := [] }, literals := [.positive { object := .variable "alloc", relation := "kind", subject := .value (.symbol "entity:reuse_allocation"), attrs := [] }, .positive { object := .variable "alloc", relation := "object", subject := .variable "obj", attrs := [] }, .positive { object := .variable "obj", relation := "reuse_cleared", subject := .value (.symbol "value:true"), attrs := [] }] },
    { name := "rbd_reuse_without_clear_violation", head := { object := .variable "alloc", relation := "policy_violation", subject := .value (.symbol "value:reuse_without_clear"), attrs := [] }, literals := [.positive { object := .variable "alloc", relation := "kind", subject := .value (.symbol "entity:reuse_allocation"), attrs := [] }, .positive { object := .variable "alloc", relation := "object", subject := .variable "obj", attrs := [] }, .negative { object := .variable "obj", relation := "reuse_cleared", subject := .value (.symbol "value:true"), attrs := [] }] }]
}

end Zil.Generated.AccessControl
