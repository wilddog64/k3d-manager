# Copilot PR #21 Review Findings

**PR:** #21 — fix(acg): restore acg-cluster.yaml removed in v0.2.0 without updating path reference
**Date:** 2026-05-21
**File flagged:** `scripts/etc/acg-cluster.yaml`

---

## Finding 1 — `AllowedCidr` defaults to `0.0.0.0/0`

**Location:** `scripts/etc/acg-cluster.yaml` line 9
**Copilot:** `AllowedCidr` defaults to `0.0.0.0/0`, exposing SSH (22) and the Kubernetes API (6443) to the internet by default.

**Fix:**
```yaml
# Before
  AllowedCidr:
    Type: String
    Default: 0.0.0.0/0

# After
  AllowedCidr:
    Type: String
```

**Root cause:** The default was added as a convenience shortcut. `acg.sh` always passes `ACG_ALLOWED_CIDR` explicitly via `--parameter-overrides`, so the template default was never used in practice — removing it makes the template safer without changing runtime behavior.

**Process note:** CloudFormation parameters that control security group ingress CIDRs must not have defaults of `0.0.0.0/0`. Require callers to provide the value explicitly.

---

## Finding 2 — Hard-coded IAM `RoleName` and `InstanceProfileName`

**Location:** `scripts/etc/acg-cluster.yaml` lines 68, 82
**Copilot:** IAM role names are account-global; hard-coding `k3d-manager-ssm-role` risks collision if the stack is re-created before IAM fully cleans up the previous role.

**Fix:**
```yaml
# Before
      RoleName: k3d-manager-ssm-role
      InstanceProfileName: k3d-manager-ssm-profile

# After
      RoleName: !Sub "${AWS::StackName}-ssm-role"
      InstanceProfileName: !Sub "${AWS::StackName}-ssm-profile"
```

**Root cause:** Names were hard-coded during initial template authoring without considering stack re-creation scenarios. Using `!Sub` with `AWS::StackName` makes them unique per stack and eliminates collision risk.

**Process note:** IAM resource names in CloudFormation templates must be derived from `${AWS::StackName}` via `!Sub`, not hard-coded strings.
