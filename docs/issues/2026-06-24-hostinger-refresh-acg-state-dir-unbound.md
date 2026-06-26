# Issue: Hostinger refresh crashed on `_ACG_STATE_DIR` being unset in the provider script

**Filed:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`

## What happened

Running the exact command:

```bash
make refresh CLUSTER_PROVIDER=k3s-hostinger
```

initially failed after the access-layer restart started:

```text
INFO: [k3s-hostinger] Refreshing local access layer listeners...
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/lib/providers/k3s-hostinger.sh: line 187: _ACG_STATE_DIR: unbound variable
make: *** [refresh] Error 1
```

## Root cause

`scripts/lib/providers/k3s-hostinger.sh` referenced `_ACG_STATE_DIR` directly while running with
`set -u`, but the provider script did not define that variable itself. The script only sourced the
shopping-cart and Hostinger vars helpers, so the value existed in some entrypoints and was missing
in others.

## Fix applied

- Defined `_ACG_STATE_DIR="${_ACG_STATE_DIR:-${HOME}/.local/share/k3d-manager}"` inside the
  Hostinger provider script before the refresh helpers use it.
- Re-ran `make refresh CLUSTER_PROVIDER=k3s-hostinger` successfully after the fix.

## Follow-up

- Keep provider scripts self-contained when they depend on shared state directories.
- Avoid relying on inherited shell variables in `set -u` entrypoints unless the script defines a
  default locally.
