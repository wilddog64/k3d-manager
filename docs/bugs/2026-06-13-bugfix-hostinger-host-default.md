# Bugfix: v1.7.0 — default HOSTINGER_HOST via config vars (no more per-command export)

**Branch:** `k3d-manager-v1.7.0`
**Files:** `scripts/etc/hostinger/vars.sh` (NEW), `scripts/lib/providers/k3s-hostinger.sh`

---

## Problem

`make up CLUSTER_PROVIDER=k3s-hostinger` fails unless the operator prepends
`HOSTINGER_HOST=srv1754834.hstgr.cloud` on every invocation:

```
ERROR: [k3s-hostinger] HOSTINGER_HOST is not set — export HOSTINGER_HOST=<vps-ip>
```

The Hostinger box is **permanent** (one fixed host), so requiring the long hostname on every
command is needless friction. Every other provider/component ships a default in
`scripts/etc/<component>/vars.sh` (e.g. `scripts/etc/oci/vars.sh`:
`OCI_REGION="${OCI_REGION:-us-ashburn-1}"`; ACG defaults `host.k3d.internal`). k3s-hostinger has
no such file, so `HOSTINGER_HOST` has no default.

**Root cause:** no `scripts/etc/hostinger/vars.sh`, and the provider never sources one — so
`HOSTINGER_HOST` is only ever read from the live environment.

---

## Reproduction

```bash
make up CLUSTER_PROVIDER=k3s-hostinger
# actual:   ERROR ... HOSTINGER_HOST is not set
# expected: provider runs against the default host; still overridable via env
```

---

## Fix

Mirror the OCI provider: add a `scripts/etc/hostinger/vars.sh` with env-overridable defaults and
source it at provider load (exactly as `k3s-oci.sh` sources `etc/oci/vars.sh`). The default host
is a **hostname in the config layer** (overridable), consistent with how ACG defaults
`host.k3d.internal` — no IP is hardcoded in script logic.

### Change 1 — NEW `scripts/etc/hostinger/vars.sh`

**Exact new file contents:**

```bash
# shellcheck shell=bash
# Hostinger KVM VPS — CLUSTER_PROVIDER=k3s-hostinger
# Permanent single-node app-cluster host, provisioned out-of-band via the Hostinger panel.
# All values are env-overridable; override here or export before running.

HOSTINGER_HOST="${HOSTINGER_HOST:-srv1754834.hstgr.cloud}"
HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
HOSTINGER_SSH_KEY="${HOSTINGER_SSH_KEY:-${HOME}/.ssh/hostinger}"
```

### Change 2 — `scripts/lib/providers/k3s-hostinger.sh`: source the vars file

**Exact old block:**

```bash
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"

_HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
```

**Exact new block:**

```bash
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/etc/hostinger/vars.sh"

_HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
```

### Change 3 — `scripts/lib/providers/k3s-hostinger.sh`: correct the deploy help text

**Exact old block:**

```bash
Config (env overrides):
  HOSTINGER_HOST       VPS public IP (REQUIRED)
  HOSTINGER_SSH_USER   SSH user (default: ubuntu)
  HOSTINGER_SSH_KEY    SSH private key path (default: ~/.ssh/hostinger)
```

**Exact new block:**

```bash
Config (env overrides; defaults in scripts/etc/hostinger/vars.sh):
  HOSTINGER_HOST       VPS host (default: srv1754834.hstgr.cloud)
  HOSTINGER_SSH_USER   SSH user (default: ubuntu)
  HOSTINGER_SSH_KEY    SSH private key path (default: ~/.ssh/hostinger)
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/hostinger/vars.sh` | NEW — env-overridable `HOSTINGER_HOST`/`HOSTINGER_SSH_USER`/`HOSTINGER_SSH_KEY` defaults |
| `scripts/lib/providers/k3s-hostinger.sh` | source the vars file at load; correct deploy help text |

---

## Rules

- `shellcheck -S warning scripts/etc/hostinger/vars.sh scripts/lib/providers/k3s-hostinger.sh` — zero warnings
- `bash -n scripts/lib/providers/k3s-hostinger.sh` — parses clean
- `./scripts/k3d-manager _agent_audit` — passes
- `make -n up CLUSTER_PROVIDER=k3s-hostinger` — still expands to `deploy_cluster --confirm`
- Env override still wins: `HOSTINGER_HOST=foo` must take precedence over the default
- No other files touched

---

## Definition of Done

- [ ] `scripts/etc/hostinger/vars.sh` defines `HOSTINGER_HOST` (default `srv1754834.hstgr.cloud`),
      `HOSTINGER_SSH_USER`, `HOSTINGER_SSH_KEY`, all env-overridable (`${VAR:-default}`)
- [ ] provider sources the vars file (after the `shopping_cart.sh` source) with a
      `# shellcheck source=/dev/null` directive
- [ ] deploy help text no longer says `REQUIRED` for `HOSTINGER_HOST`
- [ ] `make up CLUSTER_PROVIDER=k3s-hostinger` runs without exporting `HOSTINGER_HOST`
- [ ] an explicit `HOSTINGER_HOST=<other>` still overrides the default
- [ ] `shellcheck -S warning`, `bash -n`, `_agent_audit` all clean
- [ ] Committed and pushed to `k3d-manager-v1.7.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
feat(k3s-hostinger): default HOSTINGER_HOST via scripts/etc/hostinger/vars.sh
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT hardcode the host in `k3s-hostinger.sh` logic — the default belongs in the vars file only
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.7.0`
