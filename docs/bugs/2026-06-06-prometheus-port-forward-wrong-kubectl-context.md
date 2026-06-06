# Bug: Prometheus port-forward LaunchAgent targets wrong kubectl context

**Branch:** `k3d-manager-v1.6.3`
**Files:** `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`

---

## Problem

The Prometheus port-forward LaunchAgent continuously exits with:

```
Error from server (NotFound): namespaces "monitoring" not found
```

The plist template hardcodes `--context ubuntu-k3s`, but the `monitoring` namespace
(kube-prometheus-stack) is deployed on the local hub cluster (`k3d-k3d-cluster`), not on
the remote ACG k3s node.

**Root cause:** `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`
has `<string>ubuntu-k3s</string>` as the `--context` argument. Prometheus is a hub-cluster
service, not a workload cluster service.

---

## Reproduction

```bash
make install-prometheus-port-forward
# LaunchAgent immediately exits with exit code 1
tail ~/Library/Logs/k3dm-prometheus-port-forward.log
# Error from server (NotFound): namespaces "monitoring" not found
```

---

## Fix

### Change 1 — `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`

**Exact old block:**

```xml
    <string>--context</string>
    <string>ubuntu-k3s</string>
```

**Exact new block:**

```xml
    <string>--context</string>
    <string>k3d-k3d-cluster</string>
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl` | Change `--context ubuntu-k3s` to `--context k3d-k3d-cluster` |

---

## Rules

- No other files touched
- After committing, user must run `make install-prometheus-port-forward` to reinstall the live plist

---

## Definition of Done

- [ ] `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`: `--context` value changed from `ubuntu-k3s` to `k3d-k3d-cluster`
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(launchd): prometheus port-forward plist targets k3d-k3d-cluster not ubuntu-k3s
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
- Do NOT reinstall the LaunchAgent — that is a manual step the user runs after the commit
