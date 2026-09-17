# Bug: `make status` never samples hub ESO, so a broken hub secret store reports green

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** FIXED `3eeaef5b` (Codex; Claude verified + committed) — operator: `make restart-webhook`
**Files:** `bin/k3dm-webhook`, `scripts/tests/lib/webhook_hub_eso.bats` (new), `CHANGELOG.md`
**Incident:** `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`

## Problem

- On 2026-09-11, `make status CLUSTER_PROVIDER=k3s-hostinger` printed `ESO ExternalSecrets: 20/20 synced ✓`.
- That was true for the app cluster only. On the hub, `ClusterSecretStore vault-backend` was `Ready=False` and **24 of 25 ExternalSecrets were failing**, because of a stale Vault `token_reviewer_jwt`.
- Hub-hosted credentials (Grafana, Keycloak, ArgoCD) come from that hub store, and the smoke logins use them.

How the status reaches the terminal:
- `make status` runs `bin/cluster-status --summary`.
- That calls the webhook `GET /api/v1/health`, which calls `_smoke_test_services(provider)` in `bin/k3dm-webhook`.
- The two ESO checks there query only `--context app_context` (`_provider_context(provider)`).
- No code path runs `kubectl get clustersecretstore/externalsecret --context k3d-k3d-cluster`.

Consumers of the existing check names must keep working unchanged:
- `scripts/lib/hermes/sensors.py:eso()` selects exactly `"ESO ClusterSecretStore"` and `"ESO ExternalSecrets"`.
- The two triage `ns_map` dicts in `bin/k3dm-webhook` key on the same names.

## Fix

### S1 — `bin/k3dm-webhook`: extract the ESO checks into a context-parameterised helper

Insert this function immediately **above** `def _smoke_test_services(`:

```python
def _eso_health_results(context, label_prefix=""):
    """ClusterSecretStore + ExternalSecret health on one kube context.
    Returns [(name, ok, detail), ...] named '<label_prefix>ESO ...'."""
    results = []
    css_name = f"{label_prefix}ESO ClusterSecretStore"
    es_name = f"{label_prefix}ESO ExternalSecrets"
    try:
        _css_out, _css_timeout = _posix_spawn_capture(
            ["kubectl", "get", "clustersecretstore", "vault-backend",
             "--context", context, "-o", "json"],
            timeout=8,
        )
        if _css_timeout:
            raise RuntimeError("kubectl clustersecretstore timed out")
        if _kubectl_absent(_css_out):
            results.append((css_name, None,
                            f"not installed (no ClusterSecretStore on {context})"))
        else:
            _data = json.loads(_css_out)
            _conds = _data.get("status", {}).get("conditions", [])
            _ready = next((c for c in _conds if c.get("type") == "Ready"), None)
            _val = f"Ready={_ready.get('status', 'Unknown')}" if _ready else "no conditions"
            results.append((css_name, _val == "Ready=True", _val))
    except Exception as _exc:
        results.append((css_name, False, str(_exc)[:200]))

    try:
        _es_out, _es_timeout = _posix_spawn_capture(
            ["kubectl", "get", "externalsecret", "-A",
             "--context", context, "-o", "json"],
            timeout=10,
        )
        if _es_timeout:
            raise RuntimeError("kubectl externalsecret timed out")
        if _kubectl_absent(_es_out):
            results.append((es_name, None,
                            f"not installed (no ExternalSecret CRD on {context})"))
            _es_data = None
        else:
            _es_data = json.loads(_es_out)
        if _es_data is not None:
            _items = _es_data.get("items", [])
            _not_ready = [
                it["metadata"]["name"]
                for it in _items
                if not any(
                    c.get("type") == "Ready" and c.get("status") == "True"
                    for c in it.get("status", {}).get("conditions", [])
                )
            ]
            _total = len(_items)
            if _not_ready:
                results.append((es_name, False,
                                 f"{len(_not_ready)}/{_total} not synced: {', '.join(_not_ready[:3])}"))
            else:
                results.append((es_name, True, f"{_total}/{_total} synced"))
    except Exception as _exc:
        results.append((es_name, False, str(_exc)[:200]))
    return results


```

### S2 — `_smoke_test_services`: call the helper for the app cluster and the hub

In `_smoke_test_services`, replace the whole block that starts with `    try:` / `        _css_out, _css_timeout = _posix_spawn_capture(` and ends with the second `        results.append(("ESO ExternalSecrets", False, str(_exc)[:200]))`. That is the two `try/except` blocks immediately before the comment `# Data-layer StatefulSet readiness for the active app cluster`. Replace it with:

```python
    results.extend(_eso_health_results(app_context))
    if app_context != "k3d-k3d-cluster":
        results.extend(_eso_health_results("k3d-k3d-cluster", "Hub "))
```

Keep the `# Data-layer StatefulSet readiness…` comment and everything after it unchanged.

- The app-cluster results keep their exact names, so Hermes `sensors.eso()` and both triage `ns_map`s are unaffected.
- The new `Hub ESO ClusterSecretStore` / `Hub ESO ExternalSecrets` rows are not in either `ns_map`, so failure triage skips their pod-state query. Do NOT add them to the maps: the maps query `app_context`, which is the wrong cluster for hub rows.

### S3 — tests: `scripts/tests/lib/webhook_hub_eso.bats` (new)

Follow the `SourceFileLoader` pattern in `scripts/tests/lib/webhook.bats` (the `run env K3DM_WEBHOOK_PATH=… python3 - <<'PY'` blocks, with the same `repo_root` resolution as that file's tests). Monkeypatch `webhook._posix_spawn_capture` with a fake that returns `(json_text, False)` keyed on the value after `--context` and on the resource kind (`clustersecretstore` / `externalsecret`). Assert on returned tuples; never `grep -F` a source line.

1. **Hub rows use the hub context and prefix.**
   - Fake hub data: CSS `Ready=False`; 25 ExternalSecrets, 24 not Ready.
   - `webhook._eso_health_results("k3d-k3d-cluster", "Hub ")` returns 2 tuples:
     - names `Hub ESO ClusterSecretStore` and `Hub ESO ExternalSecrets`;
     - `ok` is `False` for both;
     - the second detail starts with `24/25 not synced`.
   - Every captured call contains `k3d-k3d-cluster`.
2. **App rows keep legacy names.**
   - Fake app data: CSS `Ready=True`; 20 ExternalSecrets, all Ready.
   - `_eso_health_results("ubuntu-hostinger")` returns names `ESO ClusterSecretStore` and `ESO ExternalSecrets`, both `ok is True`, second detail `20/20 synced`.
3. **Absent CRD is `None`, not a failure.** The fake returns `error: the server doesn't have a resource type "externalsecret"` (make sure `_kubectl_absent` recognises it; otherwise use a `NotFound` message). The ExternalSecrets tuple has `ok is None` and a detail containing `not installed`.
4. **Wiring.** `inspect.getsource(webhook._smoke_test_services)` contains `_eso_health_results(app_context)` and `_eso_health_results("k3d-k3d-cluster", "Hub ")`, and no longer contains `"clustersecretstore"`.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet:

```
- `make status` (webhook `/api/v1/health`) now reports hub ESO health as `Hub ESO ClusterSecretStore` / `Hub ESO ExternalSecrets` alongside the app-cluster rows; previously only the app cluster was sampled, so a hub with 24/25 failing ExternalSecrets still printed `ESO ExternalSecrets: 20/20 synced`
```

## Definition of Done

- [ ] S1–S3 applied; `git diff --stat` shows only the three listed files.
- [ ] `python3 -m py_compile bin/k3dm-webhook` exits 0.
- [ ] `bats scripts/tests/lib/webhook_hub_eso.bats scripts/tests/lib/webhook.bats`: all pass (paste the summary).
- [ ] `python3 -m pytest -q scripts/tests/hermes`: all pass (paste the summary), which proves the Hermes `eso` sensor is unaffected.
- [ ] Disappearance gate: `grep -c '"clustersecretstore", "vault-backend"' bin/k3dm-webhook` prints `1` (only inside the helper).
- [ ] Commit message, verbatim: `fix(status): sample hub ESO store and ExternalSecrets in webhook health`

## Operator follow-up (NOT for Codex)

- `make restart-webhook`, then `make status` shows the two `Hub ESO` rows.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT rename the existing `ESO ClusterSecretStore` / `ESO ExternalSecrets` rows or change `scripts/lib/hermes/`.
- Do NOT run `kubectl`, restart the webhook, or run `launchctl`/`make restart-webhook`.
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `bin/cluster-status`, or memory-bank.
