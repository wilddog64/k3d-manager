# Bug: fresh local hub fails istioctl precheck — pin the hub k3d k3s image

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/cluster.yaml.tmpl` (ONLY)
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "Hub k3d image unpinned → fresh hub fails istioctl 1.30 precheck" item on branch
  `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/cluster.yaml.tmpl` — the whole file (31 lines). It is a k3d
    `apiVersion: k3d.io/v1alpha5`, kind `Simple` config.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

A fresh local Hub cluster (`k3d-cluster`) silently comes up on whatever k3s image the
`k3d` binary defaults to. On this box that is `k3d version v5.8.3`, whose default k3s image
is **`rancher/k3s:v1.31.5-k3s1`** (Kubernetes reports it as `v1.31.5+k3s1`).

The box's `istioctl` is **v1.30.0**, and `istioctl x precheck` requires Kubernetes
**≥ 1.32**. So the hub Istio install aborts at `make up` Step 3.5/12:

```
Error [IST0142] The Kubernetes Version "v1.31.5+k3s1" is lower than the minimum version: 1.32
```

This kills the whole `make down` → `make up` end-to-end rebuild **before** ArgoCD and the
appsets are ever deployed. It was masked until now because prior rebuilds reused an
already-existing hub (`KEEP_LOCAL=1`); a true teardown that deletes the hub exposes the drift.

**Root cause:** `scripts/etc/cluster.yaml.tmpl` has **no `image:` field**, so the fresh hub
inherits the k3d binary's default k3s version, which is now below the istioctl precheck floor.

The OCI provider already pins its k3s version to `v1.32.0+k3s1`
(`scripts/etc/oci/vars.sh:12`, `scripts/lib/providers/k3s-oci.sh:39`). The local k3d hub is
the only cluster path with no pin.

---

## Fix

### Change 1 — add a top-level `image:` pin to the k3d Simple config

The k3d image tag uses a **dash** (`-k3s1`), not the plus sign Kubernetes reports.
Pin to `rancher/k3s:v1.32.0-k3s1` (the same Kubernetes version the OCI provider pins).

**Exact old block (lines 5–7):**

```yaml
servers: 1
agents: 3
kubeAPI:
```

**Exact new block:**

```yaml
servers: 1
agents: 3
image: rancher/k3s:v1.32.0-k3s1
kubeAPI:
```

Add nothing else. Do NOT touch `servers`, `agents`, `kubeAPI`, `ports`, `options`, the
`--disable=traefik` extraArg, `volumes`, or `hostAliases`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/cluster.yaml.tmpl` | add `image: rancher/k3s:v1.32.0-k3s1` top-level pin |

---

## Rules

- `yq eval '.' scripts/etc/cluster.yaml.tmpl >/dev/null` — parses clean (this box's
  `python3` has no PyYAML; use `yq`, which is installed).
- **Presence gate:** `grep -c 'image: rancher/k3s:v1.32.0-k3s1' scripts/etc/cluster.yaml.tmpl` → **`1`**
- **Unchanged gate:** `grep -c 'agents: 3' scripts/etc/cluster.yaml.tmpl` → **`1`** (before and after — record both)
- **Unchanged gate:** `grep -c 'kind: Simple' scripts/etc/cluster.yaml.tmpl` → **`1`** (before and after)
- **No new metachars:** the pinned value is a literal image ref — no `$`, no backticks, no
  quotes needed; it must NOT introduce any `${...}` expansion.
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] `image: rancher/k3s:v1.32.0-k3s1` present as a top-level key in the Simple config
- [ ] `agents: 3` and `kind: Simple` counts unchanged (gate recorded both counts)
- [ ] `yq eval` parses clean
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(cluster): pin hub k3d k3s image to v1.32.0-k3s1 for istioctl precheck floor
```

---

## What NOT to Do

- Do NOT change the k3s version to anything other than `v1.32.0-k3s1` — it must match the
  OCI provider's `v1.32.0+k3s1` (dash vs plus is the tag-vs-report difference).
- Do NOT add a registry prefix, digest, or `latest` tag — pin the exact tag as written.
- Do NOT touch any other field in the template.
- Do NOT modify the k3d/k3s provider shell files — this bug is the template pin ONLY.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live verify. After the commit lands, Claude runs the full `make down` → `make up`
end-to-end rebuild and confirms:

- the fresh hub reports Kubernetes `v1.32.0+k3s1` (`kubectl --context k3d-k3d-cluster version`).
- `make up` clears Step 3.5/12 (hub Istio precheck no longer aborts on `IST0142`).
- the rebuild proceeds to ArgoCD + appsets, at which point the separately-verified istiod/
  ztunnel CPU right-size (`1af15217`) finally gets exercised live.
