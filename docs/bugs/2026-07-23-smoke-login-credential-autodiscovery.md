# Bugfix: v1.17.0 — smoke-login credential auto-discovery (no operator env setup)

**Branch:** `k3d-manager-v1.17.0`
**Files:** `bin/k3dm-webhook`

---

## Problem

The login smoke test added in `843e643a` (`_smoke_test_logins`) verifies real logins only
when `K3DM_SMOKE_*` credentials are pre-set in the webhook environment. In practice they are
not, so `make status` / Slack `/cluster-status` shows four `⚪` skips:

```
⚪ Keycloak login: no credentials (set K3DM_SMOKE_KC_USER/PASS)
⚪ Frontend login: skipped (no Keycloak token)
⚪ ArgoCD login: no credentials (set K3DM_SMOKE_ARGOCD_PASS)
⚪ Grafana login: no credentials (set K3DM_SMOKE_GRAFANA_PASS)
```

Two of these credentials **already exist in-cluster** as plain Kubernetes Secrets, so the
webhook can discover them at smoke time instead of requiring operator setup:

| Login | Secret (verified live 2026-07-23) | Context | Keys |
|-------|-----------------------------------|---------|------|
| **ArgoCD** | `cicd/argocd-initial-admin-secret` | hub (default) | `.data.password` (base64), user `admin` |
| **Grafana** | `monitoring/acg-kube-prometheus-stack-grafana` | app (`app_context`) | `.data.admin-user` + `.data.admin-password` (base64) |

**Root cause:** the check hard-requires env credentials and has no fallback to the admin
Secrets that already live in-cluster.

**Scope note — Keycloak + Frontend are deliberately NOT auto-discovered here.** The
`Keycloak login` and `Frontend login` checks authenticate a **shopping-cart realm end-user**
(`grant_type=password`, client `frontend`), and Keycloak stores user passwords as one-way
hashes — no plaintext end-user password exists in any Secret to discover. (`identity/keycloak-secrets`
holds only `KEYCLOAK_ADMIN`/`KEYCLOAK_ADMIN_PASSWORD` — the master-realm admin, a different
identity than the frontend user the check exercises.) Those two stay env-driven and `⚪` until
the owner picks a direction (see **Owner decision** below). This spec closes the two
unambiguous wins where the admin login *is* the correct semantic check.

---

## Reproduction

```bash
make status CLUSTER_PROVIDER=k3s-hostinger   # ArgoCD login / Grafana login show ⚪ despite the admin secrets existing
```

---

## Fix

All edits are inside `_smoke_test_logins(provider, app_context)` in `bin/k3dm-webhook`, plus one
new module-level helper directly above it. Do NOT change the Keycloak or Frontend blocks.

### Change 1 — new helper `_smoke_secret`, inserted directly above `def _smoke_test_logins`

**Exact old block (lines 1512–1513):**

```python


def _smoke_test_logins(provider, app_context):
```

**Exact new block:**

```python


def _smoke_secret(namespace, key, secret_name, context=None):
    """Read one key from a k8s Secret and base64-decode it. Returns str or None.

    Lets the login smoke test auto-discover admin credentials that already live
    in-cluster instead of requiring K3DM_SMOKE_* env vars. Returns None on any
    failure (secret/key absent, timeout, decode error) so the caller degrades to a
    ⚪ skip rather than a false red."""
    import base64 as _b64
    cmd = ["kubectl", "get", "secret", secret_name, "-n", namespace,
           "-o", "jsonpath={.data." + key + "}", "--request-timeout=5s"]
    if context:
        cmd += ["--context", context]
    out, timed_out = _posix_spawn_capture(cmd, timeout=8)
    if timed_out or not out.strip():
        return None
    try:
        return _b64.b64decode(out.strip()).decode("utf-8", "replace")
    except Exception:
        return None


def _smoke_test_logins(provider, app_context):
```

### Change 2 — ArgoCD: fall back to the in-cluster admin secret

**Exact old block (lines 1586–1589):**

```python
    argo_user = os.environ.get("K3DM_SMOKE_ARGOCD_USER", "admin")
    argo_pass = os.environ.get("K3DM_SMOKE_ARGOCD_PASS")
    if not argo_pass:
        results.append(("ArgoCD login", None, "no credentials (set K3DM_SMOKE_ARGOCD_PASS)"))
```

**Exact new block:**

```python
    argo_user = os.environ.get("K3DM_SMOKE_ARGOCD_USER", "admin")
    argo_pass = os.environ.get("K3DM_SMOKE_ARGOCD_PASS") or _smoke_secret(
        "cicd", "password", "argocd-initial-admin-secret")
    if not argo_pass:
        results.append(("ArgoCD login", None, "no credentials (argocd-initial-admin-secret absent; set K3DM_SMOKE_ARGOCD_PASS)"))
```

### Change 3 — Grafana: fall back to the in-cluster admin secret

**Exact old block (lines 1604–1607):**

```python
    graf_user = os.environ.get("K3DM_SMOKE_GRAFANA_USER", "admin")
    graf_pass = os.environ.get("K3DM_SMOKE_GRAFANA_PASS")
    if not graf_pass:
        results.append(("Grafana login", None, "no credentials (set K3DM_SMOKE_GRAFANA_PASS)"))
```

**Exact new block:**

```python
    graf_user = (os.environ.get("K3DM_SMOKE_GRAFANA_USER")
                 or _smoke_secret("monitoring", "admin-user",
                                  "acg-kube-prometheus-stack-grafana", context=app_context)
                 or "admin")
    graf_pass = os.environ.get("K3DM_SMOKE_GRAFANA_PASS") or _smoke_secret(
        "monitoring", "admin-password", "acg-kube-prometheus-stack-grafana", context=app_context)
    if not graf_pass:
        results.append(("Grafana login", None, "no credentials (acg-kube-prometheus-stack-grafana absent; set K3DM_SMOKE_GRAFANA_PASS)"))
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | add `_smoke_secret` helper; ArgoCD + Grafana login checks fall back to in-cluster admin Secrets when `K3DM_SMOKE_*` env vars are unset |

---

## Rules

- Env vars still win — `_smoke_secret` is only a fallback (`os.environ.get(...) or _smoke_secret(...)`).
- Discovery failure must degrade to `⚪` (ok=None), never a false red — `_smoke_secret` returns `None` on any error and the existing `if not <pass>:` skip branch handles it.
- ArgoCD secret is on the **hub** → no `--context` (matches `_current_label`, which reads `cicd` on the default context). Grafana secret is on the **app cluster** → `context=app_context`.
- Do NOT touch the Keycloak or Frontend blocks, `_smoke_test_services`, or any other function.
- `python3 -m py_compile bin/k3dm-webhook` — clean.
- Run `make restart-webhook` after the change (webhook code changed).
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `_smoke_secret` helper present directly above `_smoke_test_logins`, uses `_posix_spawn_capture`
- [ ] ArgoCD + Grafana blocks use `os.environ.get(...) or _smoke_secret(...)` fallback
- [ ] `python3 -m py_compile bin/k3dm-webhook` passes
- [ ] `grep -c '_smoke_secret' bin/k3dm-webhook` → **4** (1 def + 3 call sites: argo pass, grafana user, grafana pass)
- [ ] `make restart-webhook` exits 0
- [ ] `git show --stat` shows exactly one file changed (`bin/k3dm-webhook`)
- [ ] Committed and pushed to `k3d-manager-v1.17.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit from the code)

**Commit message (exact):**
```
feat(webhook): auto-discover argocd + grafana admin creds in login smoke test
```

---

## Owner decision — Keycloak + Frontend (NOT in this spec's scope)

The remaining two `⚪` need a **realm end-user** password that is not stored in plaintext
anywhere. Options for a later spec (owner picks):

- **(A) Re-point `Keycloak login` to the master-realm admin** (`identity/keycloak-secrets`,
  client `admin-cli`, realm `master`) — fully auto-discoverable, but changes the check's meaning
  from "a frontend user can log in" to "Keycloak admin auth works." May mask the exact
  user-login symptom the owner originally reported.
- **(B) Seed a dedicated smoke user** in the `shopping-cart` realm and store its credential in a
  Secret/Vault — keeps the real user-login signal and becomes zero-setup once seeded. Recommended
  for `Frontend login`, which inherently needs a real user.
- **(C) Leave Keycloak + Frontend env-driven** (`K3DM_SMOKE_KC_USER/PASS`), `⚪` until set.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/k3dm-webhook`
- Do NOT change the Keycloak or Frontend login blocks in this spec
- Do NOT commit to `main` — work on `k3d-manager-v1.17.0`
