# Bug: OCI vars in global vars.sh instead of scripts/etc/oci/vars.sh

**Branch:** `k3d-manager-v1.5.0`
**Introduced by:** commit `bda61dde`
**Severity:** P3 — wrong file layout; OCI vars loaded on every invocation regardless of CLUSTER_PROVIDER

---

## Symptom

`scripts/etc/vars.sh` (a new global file) was created containing only OCI-specific env var
defaults. This file is unconditionally sourced from `scripts/k3d-manager` for all invocations,
not just when `CLUSTER_PROVIDER=k3s-oci`.

---

## Root Cause

The spec said to add OCI vars to `scripts/etc/vars.sh`. The convention in this project is to
keep provider vars in a provider-scoped file and source it from within the provider file itself:

| Provider | Vars file | Sourced from |
|----------|-----------|--------------|
| k3s | `scripts/etc/k3s/vars.sh` | `scripts/lib/providers/k3s.sh:4–8` |
| azure | `scripts/etc/azure/azure-vars.sh` | `scripts/plugins/azure.sh:4` |
| **oci (current — wrong)** | `scripts/etc/vars.sh` (global) | `scripts/k3d-manager:69–73` |
| **oci (correct)** | `scripts/etc/oci/vars.sh` | `scripts/lib/providers/k3s-oci.sh:top` |

---

## Fix

### File 1 — CREATE `scripts/etc/oci/vars.sh`

```bash
# shellcheck shell=bash
# OCI Always Free (ARM64) — CLUSTER_PROVIDER=k3s-oci

OCI_COMPARTMENT_ID="${OCI_COMPARTMENT_ID:-}"
OCI_REGION="${OCI_REGION:-us-ashburn-1}"
OCI_AVAILABILITY_DOMAIN="${OCI_AVAILABILITY_DOMAIN:-}"
OCI_IMAGE_ID="${OCI_IMAGE_ID:-}"
OCI_INSTANCE_SHAPE="${OCI_INSTANCE_SHAPE:-VM.Standard.A1.Flex}"
OCI_OCPUS="${OCI_OCPUS:-2}"
OCI_MEMORY_GB="${OCI_MEMORY_GB:-12}"
OCI_SSH_KEY_FILE="${OCI_SSH_KEY_FILE:-${HOME}/.ssh/oci-k3s}"
OCI_K3S_VERSION="${OCI_K3S_VERSION:-v1.32.0+k3s1}"
OCI_CONTEXT="${OCI_CONTEXT:-k3s-oci}"
```

### File 2 — DELETE `scripts/etc/vars.sh`

This file only contains OCI vars (added in `bda61dde`). Delete it entirely — content
moves to `scripts/etc/oci/vars.sh`.

```bash
git rm scripts/etc/vars.sh
```

### File 3 — MODIFY `scripts/k3d-manager` — remove global vars.sh source block

Remove lines 69–73 exactly:

```bash
# Shared variable defaults (including OCI provider config).
if [[ -r "${SCRIPT_DIR}/etc/vars.sh" ]]; then
   # shellcheck disable=SC1091
   source "${SCRIPT_DIR}/etc/vars.sh"
fi
```

After removal, line 68 (`source "${SCRIPT_DIR}/lib/provider.sh"`) is followed directly
by the lib-foundation block (currently line 74).

### File 4 — MODIFY `scripts/lib/providers/k3s-oci.sh` — source vars at top

After line 9 (the comment block), add the vars sourcing following the k3s.sh pattern:

```bash
# load k3s-oci variables
_OCI_VARS="${SCRIPT_DIR}/etc/oci/vars.sh"
if [[ ! -r "${_OCI_VARS}" ]]; then
  _err "OCI vars file not found: ${_OCI_VARS}"
fi
# shellcheck source=/dev/null
source "${_OCI_VARS}"
```

This replaces the inline variable assignments at lines 10–20 of `k3s-oci.sh` that duplicate
the defaults. Those duplicate assignments should be removed since vars.sh now owns them.

Wait — on re-read: the inline assignments in `k3s-oci.sh` (lines 10–20) are the module-level
`_OCI_VCN_NAME`, `_OCI_SUBNET_NAME` etc. — those are **private** internal constants, not env
var defaults. Only the env var defaults (OCI_COMPARTMENT_ID, OCI_REGION, etc.) move to vars.sh.
Do NOT remove the private `_OCI_*` constant assignments at lines 10–20.

So the correct addition to `k3s-oci.sh` is after line 9, before line 10:

```bash
# shellcheck shell=bash
# scripts/lib/providers/k3s-oci.sh — k3s on OCI Always Free (Ampere A1, ARM64)
#
# Provider actions:
#   deploy_cluster  — provision OCI infra (idempotent) → install k3s
#                     → kubeconfig merge → register with hub ArgoCD
#                     → deploy stable stack → smoke test
#   destroy_cluster — deregister from ArgoCD; --destroy-infra also deletes OCI resources

# load OCI variables
_OCI_VARS="${SCRIPT_DIR}/etc/oci/vars.sh"
if [[ ! -r "${_OCI_VARS}" ]]; then
  _err "OCI vars file not found: ${_OCI_VARS}"
fi
# shellcheck source=/dev/null
source "${_OCI_VARS}"

_OCI_VCN_NAME="k3s-oci-vcn"
... (rest of file unchanged)
```

---

## Behaviour After Fix

| Scenario | Before | After |
|----------|--------|-------|
| `./scripts/k3d-manager` with any provider | Loads OCI defaults unconditionally | No OCI vars loaded |
| `CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager deploy_cluster` | OCI vars from global file | OCI vars from `scripts/etc/oci/vars.sh` |
| `scripts/etc/` layout | Lone `vars.sh` with OCI content | `oci/vars.sh` consistent with k3s/azure pattern |

---

## Before You Start

1. `git pull origin k3d-manager-v1.5.0`
2. Read `scripts/lib/providers/k3s.sh` lines 1–8 — this is the exact pattern to follow
3. Read `scripts/lib/providers/k3s-oci.sh` lines 1–25 — understand what is private constants vs env defaults

## What NOT to Do

- Do NOT remove the `_OCI_VCN_NAME`, `_OCI_SUBNET_NAME` etc. assignments — those are private
  constants, not env var defaults
- Do NOT modify any other files
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main` — work on `k3d-manager-v1.5.0`

## Definition of Done

- [ ] `scripts/etc/oci/vars.sh` created with all 11 OCI env var defaults
- [ ] `scripts/etc/vars.sh` deleted (`git rm`)
- [ ] `scripts/k3d-manager` lines 69–73 removed (the `vars.sh` source block)
- [ ] `scripts/lib/providers/k3s-oci.sh` — OCI vars sourcing block added after comment header, before `_OCI_VCN_NAME`
- [ ] `shellcheck scripts/lib/providers/k3s-oci.sh` — zero new warnings
- [ ] `shellcheck scripts/k3d-manager` — zero new warnings
- [ ] Commit message: `fix(provider): move OCI vars to scripts/etc/oci/vars.sh — follow k3s/azure provider convention`
- [ ] `git push origin k3d-manager-v1.5.0` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA
- [ ] Report back: commit SHA + paste memory-bank lines updated
