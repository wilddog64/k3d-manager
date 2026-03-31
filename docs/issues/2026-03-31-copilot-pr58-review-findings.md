# Copilot PR #58 Review Findings

**PR:** #58 — feat(k3s-aws): multi-node cluster, CloudFormation provisioning, Playwright hardening
**Date:** 2026-03-31
**Fix commit:** `8889f6b`
**Findings:** 11

---

## Findings and Fixes

### 1. `acg.bats` — `_run_command` stub doesn't strip `--` separator (lines 97, 120)

**Finding:** Stub shifts off `mode` but `$*` then starts with `-- aws ...`; `describe-stacks` branch never matched.

**Fix:** Added `[[ "${1:-}" == "--" ]] && shift` after `local mode="$1"; shift` in both stubs.

**Root cause:** Stubs written before `_run_command` callers added `--` argument separator.

---

### 2. `k3s-aws.sh` — `ACG_AGENT_COUNT` inconsistent with hardcoded 2 agents

**Finding:** `ACG_AGENT_COUNT` env var used for `total_nodes` but `UBUNTU_K3S_AGENT_HOSTS` always hardcodes `ubuntu-1,ubuntu-2`; CF template always provisions 2 agents.

**Fix:** Removed `ACG_AGENT_COUNT`; hardcoded `local total_nodes=3`.

**Root cause:** Variable added before CF template was finalized; CF template hardcodes 2 agents.

---

### 3. `k3s_aws_provider.bats` — test name says "runs once" but doesn't assert count

**Finding:** Test `_provider_k3s_aws_deploy_cluster runs acg_provision once` only checked output contains the stub marker, not that it was called exactly once.

**Fix:** Added `[ "$(echo "$output" | grep -c "\[stub\] acg_provision")" -eq 1 ]`.

---

### 4. `acg_credentials.js` — logs actual email address (PII)

**Finding:** `console.error(\`INFO: Filled email (${email})\`)` logs the raw email to stderr, which can appear in CI logs or terminal transcripts.

**Fix:** Changed to `console.error('INFO: Filled email from PLURALSIGHT_EMAIL')`.

**Root cause:** Debug log added without considering PII exposure.

---

### 5. `shopping_cart.sh` — `_agent_hosts` array leaks into global scope

**Finding:** `IFS=',' read -ra _agent_hosts <<< ...` populates a global array in a sourced file.

**Fix:** Added `local -a _agent_hosts` declaration before the `read`.

---

### 6. `acg.sh` — help text describes old single-EC2 behavior

**Finding:** Both `acg_provision` and `acg_teardown` help blocks still described single EC2 instance provisioning/termination, not CloudFormation 3-node stack.

**Fix:** Updated both help blocks to describe CloudFormation stack semantics.

---

### 7. `agent_rigor.sh` — `grep -Fqx "$file"` without `--`

**Finding:** Repo-relative paths beginning with `-` would be interpreted as grep flags, silently breaking the allowlist check.

**Fix:** Changed to `grep -Fqx -- "$file"`. Also upstreamed to lib-foundation as PR #22 (v0.3.16).

---

### 8. `acg-cluster.yaml` — intra-VPC SG rule uses `/8` instead of `/16`

**Finding:** `CidrIp: 10.0.0.0/8` is broader than the VPC CIDR (`10.0.0.0/16`); allows traffic from any `10.x` network.

**Fix:** Changed to `10.0.0.0/16` to match VPC CIDR exactly.

**Root cause:** Added before VPC CIDR was finalized; `/8` was a conservative placeholder.

---

## Process Notes

- **`_run_command` stub pattern**: always strip `--` after `shift` when mocking `_run_command` in BATS tests.
- **PII in logs**: never log env var values; log the var name instead.
- **`grep` with user-controlled paths**: always use `--` before path arguments.
- **Help text drift**: when a function's behavior changes significantly, update help text in the same commit.
