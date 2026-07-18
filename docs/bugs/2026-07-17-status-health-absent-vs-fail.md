# Bugfix: v1.16.0 — status health: distinguish "not deployed" from "failing"

**Branch:** `k3d-manager-v1.16.0`
**Files:** `bin/k3dm-webhook`, `bin/cluster-status`, `bin/smoke-test-webhook`

---

## Problem

`make status` against a provider whose cluster does **not** have the full app stack (e.g.
`CLUSTER_PROVIDER=k3s-aws` → the `ubuntu-k3s` istio-ambient sandbox, which only has `secrets` +
`shopping-cart-apps` namespaces) reports absent services as hard failures, including a raw
`json.loads` traceback:

```
❌ Pushgateway: <urlopen error [Errno 61] Connection refused>
❌ ESO ClusterSecretStore: Expecting value: line 1 column 1 (char 0)
✅ ESO ExternalSecrets: 0/0 synced
❌ Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

These are not failures — the resources were never deployed on that cluster. The `❌` +
`Expecting value: line 1 column 1 (char 0)` is alarming and wrong: it's `json.loads("")` /
`json.loads("Error from server (NotFound)...")` on the ClusterSecretStore check when the object /
CRD is absent.

**Root cause:** the health checks in `_smoke_test_services` (`bin/k3dm-webhook`) are strictly
binary (`ok` = True/False). There is no representation for "this resource legitimately does not
exist on this cluster," so absence collapses to `❌` (and, for the ClusterSecretStore check,
crashes into the `except` branch that surfaces the parse error).

**Fix approach:** introduce a **third, neutral state** — `ok = None` — meaning "not deployed /
not installed on this provider." It renders as `⚪` and does **not** count as a failure in
`all_ok` / smoke gates. Absence is detected from kubectl's combined stdout+stderr, which
`_posix_spawn_capture` already merges (`POSIX_SPAWN_DUP2 1→2`), so `NotFound` / `No resources
found` / `doesn't have a resource type` text is present in the returned string.

---

## Reproduction

```
make status CLUSTER_PROVIDER=k3s-aws        # ubuntu-k3s ambient sandbox — no app stack
```

Actual (Service Health block):
```
❌ Pushgateway: <urlopen error [Errno 61] Connection refused>
❌ ESO ClusterSecretStore: Expecting value: line 1 column 1 (char 0)
✅ ESO ExternalSecrets: 0/0 synced
❌ Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

Expected:
```
⚪ Pushgateway: not deployed (no pushgateway pod on ubuntu-k3s)
⚪ ESO ClusterSecretStore: not installed (no ClusterSecretStore on ubuntu-k3s)
✅ ESO ExternalSecrets: 0/0 synced
⚪ Data layer: not deployed (namespace shopping-cart-data absent on ubuntu-k3s)
```

`make status CLUSTER_PROVIDER=k3s-hostinger` (fully-deployed cluster) must remain **all `✅`** —
no service may flip to `⚪` on a cluster where it is actually deployed and healthy.

---

## Tri-state contract

- Internal result tuples stay `(name, ok, detail)` with `ok ∈ {True, False, None}`.
  - `True` → healthy → `✅`
  - `None` → not deployed / not installed → `⚪` (neutral; NOT a failure)
  - `False` → deployed but unhealthy/unreachable → `❌`
- Wire JSON keeps the `ok` field; a neutral service serializes as `"ok": null`.
- `all_ok` and every gate treat `None` as passing: only `ok is False` counts against them.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: add `_kubectl_absent` helper (before `def _smoke_test_services`)

**Exact old block (line 1497):**

```python
def _smoke_test_services(retries=None, provider=None):
```

**Exact new block:**

```python
def _kubectl_absent(output):
    """True when combined kubectl stdout+stderr indicates the resource, CRD, or
    namespace does not exist (as opposed to existing-but-unhealthy). Relies on
    _posix_spawn_capture merging stderr into the returned text."""
    if not output or not output.strip():
        return False
    _low = output.lower()
    return any(sig in _low for sig in (
        "notfound",
        "not found",
        "no resources found",
        "doesn't have a resource type",
        "could not find the requested resource",
    ))


def _smoke_test_services(retries=None, provider=None):
```

---

### Change 2 — `bin/k3dm-webhook`: Pushgateway — reclassify absence as neutral (after the smoke loop)

**Exact old block (lines 1543–1545):**

```python
        results.append((name, passed, last_err))

    # Product catalog: verify at least one product has a non-empty imageUrl
```

**Exact new block:**

```python
        results.append((name, passed, last_err))

    if _provider_supports_pushgateway(provider):
        for _i, (_pn, _pok, _pd) in enumerate(results):
            if _pn == "Pushgateway" and _pok is False:
                _pg_out, _pg_to = _posix_spawn_capture(
                    ["kubectl", "get", "pods", "-n", "monitoring",
                     "-l", "app.kubernetes.io/name=prometheus-pushgateway",
                     "--context", app_context, "-o", "name", "--request-timeout=5s"],
                    timeout=8,
                )
                if not _pg_to and (_kubectl_absent(_pg_out) or not _pg_out.strip()):
                    results[_i] = ("Pushgateway", None,
                                   f"not deployed (no pushgateway pod on {app_context})")
                break

    # Product catalog: verify at least one product has a non-empty imageUrl
```

---

### Change 3 — `bin/k3dm-webhook`: ESO ClusterSecretStore — neutral when absent

**Exact old block (lines 1567–1581):**

```python
    try:
        _css_out, _css_timeout = _posix_spawn_capture(
            ["kubectl", "get", "clustersecretstore", "vault-backend",
             "--context", app_context, "-o", "json"],
            timeout=8,
        )
        if _css_timeout:
            raise RuntimeError("kubectl clustersecretstore timed out")
        _data = json.loads(_css_out)
        _conds = _data.get("status", {}).get("conditions", [])
        _ready = next((c for c in _conds if c.get("type") == "Ready"), None)
        _val = f"Ready={_ready.get('status', 'Unknown')}" if _ready else "no conditions"
        results.append(("ESO ClusterSecretStore", _val == "Ready=True", _val))
    except Exception as _exc:
        results.append(("ESO ClusterSecretStore", False, str(_exc)[:200]))
```

**Exact new block:**

```python
    try:
        _css_out, _css_timeout = _posix_spawn_capture(
            ["kubectl", "get", "clustersecretstore", "vault-backend",
             "--context", app_context, "-o", "json"],
            timeout=8,
        )
        if _css_timeout:
            raise RuntimeError("kubectl clustersecretstore timed out")
        if _kubectl_absent(_css_out):
            results.append(("ESO ClusterSecretStore", None,
                            f"not installed (no ClusterSecretStore on {app_context})"))
        else:
            _data = json.loads(_css_out)
            _conds = _data.get("status", {}).get("conditions", [])
            _ready = next((c for c in _conds if c.get("type") == "Ready"), None)
            _val = f"Ready={_ready.get('status', 'Unknown')}" if _ready else "no conditions"
            results.append(("ESO ClusterSecretStore", _val == "Ready=True", _val))
    except Exception as _exc:
        results.append(("ESO ClusterSecretStore", False, str(_exc)[:200]))
```

---

### Change 4 — `bin/k3dm-webhook`: ESO ExternalSecrets — neutral when CRD absent

**Exact old block (lines 1583–1591):**

```python
    try:
        _es_out, _es_timeout = _posix_spawn_capture(
            ["kubectl", "get", "externalsecret", "-A",
             "--context", app_context, "-o", "json"],
            timeout=10,
        )
        if _es_timeout:
            raise RuntimeError("kubectl externalsecret timed out")
        _es_data = json.loads(_es_out)
```

**Exact new block:**

```python
    try:
        _es_out, _es_timeout = _posix_spawn_capture(
            ["kubectl", "get", "externalsecret", "-A",
             "--context", app_context, "-o", "json"],
            timeout=10,
        )
        if _es_timeout:
            raise RuntimeError("kubectl externalsecret timed out")
        if _kubectl_absent(_es_out):
            results.append(("ESO ExternalSecrets", None,
                            f"not installed (no ExternalSecret CRD on {app_context})"))
            _es_data = None
        else:
            _es_data = json.loads(_es_out)
```

> Note: the existing body that consumes `_es_data` (the `_items`/`_not_ready`/`_total` block and
> its `results.append(...)`) must run **only when `_es_data is not None`**. Wrap the existing
> lines 1592–1606 in `if _es_data is not None:` (indent them one level). Do not change their
> logic. The `except Exception as _exc:` handler at line 1607–1608 stays as-is. The `0/0 synced`
> ✅ case (CRD present, no items) is unchanged — only a genuinely absent CRD becomes `⚪`.

---

### Change 5 — `bin/k3dm-webhook`: Data layer — neutral when namespace absent

**Exact old block (lines 1610–1632):**

```python
    # Data-layer StatefulSet readiness for the active app cluster — uses posix_spawn, safe after NEF load
    _dl_names = ["postgresql-orders", "postgresql-payment", "postgresql-products", "minio"]
    _dl_ready = 0
    _dl_not_ready = []
    for _ss in _dl_names:
        _dl_out, _dl_timeout = _posix_spawn_capture(
            ["kubectl", "get", "statefulset", _ss,
             "-n", "shopping-cart-data", "--context", app_context,
             "-o", "jsonpath={.status.readyReplicas}",
             "--request-timeout=5s"],
            timeout=8,
        )
        if not _dl_timeout and _dl_out.strip().isdigit() and int(_dl_out.strip()) >= 1:
            _dl_ready += 1
        else:
            _dl_not_ready.append(_ss)
    _dl_ok = _dl_ready == len(_dl_names)
    _dl_detail = (
        f"{_dl_ready}/{len(_dl_names)} ready"
        if _dl_ok
        else f"{len(_dl_not_ready)} not ready: {', '.join(_dl_not_ready[:2])}"
    )
    results.append(("Data layer", _dl_ok, _dl_detail))
```

**Exact new block:**

```python
    # Data-layer StatefulSet readiness for the active app cluster — uses posix_spawn, safe after NEF load
    _dl_ns_out, _dl_ns_timeout = _posix_spawn_capture(
        ["kubectl", "get", "namespace", "shopping-cart-data",
         "--context", app_context, "-o", "name", "--request-timeout=5s"],
        timeout=8,
    )
    if not _dl_ns_timeout and _kubectl_absent(_dl_ns_out):
        results.append(("Data layer", None,
                        f"not deployed (namespace shopping-cart-data absent on {app_context})"))
    else:
        _dl_names = ["postgresql-orders", "postgresql-payment", "postgresql-products", "minio"]
        _dl_ready = 0
        _dl_not_ready = []
        for _ss in _dl_names:
            _dl_out, _dl_timeout = _posix_spawn_capture(
                ["kubectl", "get", "statefulset", _ss,
                 "-n", "shopping-cart-data", "--context", app_context,
                 "-o", "jsonpath={.status.readyReplicas}",
                 "--request-timeout=5s"],
                timeout=8,
            )
            if not _dl_timeout and _dl_out.strip().isdigit() and int(_dl_out.strip()) >= 1:
                _dl_ready += 1
            else:
                _dl_not_ready.append(_ss)
        _dl_ok = _dl_ready == len(_dl_names)
        _dl_detail = (
            f"{_dl_ready}/{len(_dl_names)} ready"
            if _dl_ok
            else f"{len(_dl_not_ready)} not ready: {', '.join(_dl_not_ready[:2])}"
        )
        results.append(("Data layer", _dl_ok, _dl_detail))
```

---

### Change 6 — `bin/k3dm-webhook`: post-provision render + gate (tri-state)

**Exact old block (lines 1678–1682):**

```python
    for svc_name, ok, detail in smoke:
        icon = "✅" if ok else "❌"
        lines.append(f"*{svc_name}:* {icon} {detail}")

    all_ok = not degraded and all(ok for _, ok, _ in smoke)
```

**Exact new block:**

```python
    for svc_name, ok, detail in smoke:
        icon = "✅" if ok is True else ("⚪" if ok is None else "❌")
        lines.append(f"*{svc_name}:* {icon} {detail}")

    all_ok = not degraded and all(ok is not False for _, ok, _ in smoke)
```

---

### Change 7 — `bin/k3dm-webhook`: Slack cluster-status render + gate + triage (tri-state)

**Exact old block (lines 1950–1958):**

```python
        all_smoke_ok = all(ok for _, ok, _ in smoke)
        _log(f"\n*Service smoke test:*{'  all clear ✅' if all_smoke_ok else ''}")
        for svc_name, ok, detail in smoke:
            icon = "✅" if ok else "❌"
            _log(f"  {icon} {svc_name}: {detail}")
        if all_smoke_ok and not tunnel_ok:
            _log("\nℹ️ _Hub/tunnel checks DOWN but service endpoints responding — port-forwards or Cloudflare tunnel still active. Run `/cluster-refresh` to restore kubectl access._")

        failed_smoke = [(name, detail) for name, ok, detail in smoke if not ok]
```

**Exact new block:**

```python
        all_smoke_ok = all(ok is not False for _, ok, _ in smoke)
        _log(f"\n*Service smoke test:*{'  all clear ✅' if all_smoke_ok else ''}")
        for svc_name, ok, detail in smoke:
            icon = "✅" if ok is True else ("⚪" if ok is None else "❌")
            _log(f"  {icon} {svc_name}: {detail}")
        if all_smoke_ok and not tunnel_ok:
            _log("\nℹ️ _Hub/tunnel checks DOWN but service endpoints responding — port-forwards or Cloudflare tunnel still active. Run `/cluster-refresh` to restore kubectl access._")

        failed_smoke = [(name, detail) for name, ok, detail in smoke if ok is False]
```

---

### Change 8 — `bin/k3dm-webhook`: `/api/v1/health` serialization — neutral passes `all_ok` (both handlers)

**Exact old block (lines 3011–3023):**

```python
        if self.path == "/api/v1/health":
            services = _smoke_test_services(retries=1)
            result = [{"name": n, "ok": ok, "detail": d} for n, ok, d in services]
            self._json(200, {"services": result, "all_ok": all(r["ok"] for r in result)})
            return
        if self.path.startswith("/api/v1/health?"):
            parsed = urllib.parse.urlsplit(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            provider = params.get("provider", [None])[0]
            services = _smoke_test_services(retries=1, provider=provider)
            result = [{"name": n, "ok": ok, "detail": d} for n, ok, d in services]
            self._json(200, {"services": result, "all_ok": all(r["ok"] for r in result)})
            return
```

**Exact new block:**

```python
        if self.path == "/api/v1/health":
            services = _smoke_test_services(retries=1)
            result = [{"name": n, "ok": ok, "detail": d} for n, ok, d in services]
            self._json(200, {"services": result,
                             "all_ok": all(r["ok"] is not False for r in result)})
            return
        if self.path.startswith("/api/v1/health?"):
            parsed = urllib.parse.urlsplit(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            provider = params.get("provider", [None])[0]
            services = _smoke_test_services(retries=1, provider=provider)
            result = [{"name": n, "ok": ok, "detail": d} for n, ok, d in services]
            self._json(200, {"services": result,
                             "all_ok": all(r["ok"] is not False for r in result)})
            return
```

---

### Change 9 — `bin/cluster-status`: render `⚪` for neutral (`ok == null`)

**Exact old block (lines 425–427):**

```python
for s in data.get('services', []):
    icon = '✅' if s['ok'] else '❌'
    print(f'  {icon} {s[\"name\"]}: {s[\"detail\"]}')
```

**Exact new block:**

```python
for s in data.get('services', []):
    _st = s.get('ok')
    icon = '✅' if _st is True else ('⚪' if _st is None else '❌')
    print(f'  {icon} {s[\"name\"]}: {s[\"detail\"]}')
```

---

### Change 10 — `bin/smoke-test-webhook`: neutral counts as pass (not `not_ok`)

**Exact old block (lines 113–117):**

```python
for svc in services:
    icon = "OK " if svc.get("ok") else "ERR"
    print(f"  [{icon}] {svc.get('name')}: {svc.get('detail')}")

not_ok = [svc.get("name") for svc in services if not svc.get("ok")]
```

**Exact new block:**

```python
for svc in services:
    _st = svc.get("ok")
    icon = "OK " if _st is True else ("--" if _st is None else "ERR")
    print(f"  [{icon}] {svc.get('name')}: {svc.get('detail')}")

not_ok = [svc.get("name") for svc in services if svc.get("ok") is False]
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | add `_kubectl_absent`; CSS / ExternalSecrets / Data layer / Pushgateway report `None` when absent; tri-state render + `all_ok` in post-provision, Slack status, and both `/api/v1/health` handlers |
| `bin/cluster-status` | render `⚪` when `ok` is `null` |
| `bin/smoke-test-webhook` | neutral (`ok: null`) counts as pass, renders `[--]` |

No other files. Do NOT deploy anything to any cluster (this is a reporting-only change).

---

## Rules

- `python3 -c "import ast; ast.parse(open('bin/k3dm-webhook').read())"` → exit 0.
- `bash -n bin/cluster-status` and `bash -n bin/smoke-test-webhook` → exit 0.
- `shellcheck -S warning bin/cluster-status bin/smoke-test-webhook` → zero new warnings.
- `grep -c 'def _kubectl_absent' bin/k3dm-webhook` → `1`.
- Old binary icon lines must be gone: `grep -c 'icon = "✅" if ok else "❌"' bin/k3dm-webhook` → `0`.
- `grep -c 'if s\[.ok.\] else' bin/cluster-status` → `0` (old renderer replaced).
- No new imports. No change to `_posix_spawn_capture`. No change to which services are checked
  (`smoke_endpoints` list unchanged) or to any HTTP endpoint URL.
- Do NOT touch any file other than the three listed.

---

## Definition of Done

- [ ] `_kubectl_absent` helper added; four checks (CSS, ExternalSecrets, Data layer, Pushgateway)
      emit `None` when the resource/CRD/namespace is absent.
- [ ] Tri-state render (`✅`/`⚪`/`❌`) in post-provision, Slack status, `bin/cluster-status`,
      and `bin/smoke-test-webhook`; `all_ok` / gates treat `None` as passing.
- [ ] `ast.parse` (webhook) exit 0; `bash -n` + `shellcheck -S warning` clean on both bash files.
- [ ] grep gates above all pass.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(status): report not-deployed services as neutral (⚪) instead of failing (❌)
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Claude will `make restart-webhook`, then:
- `make status CLUSTER_PROVIDER=k3s-aws` → the four absent services show `⚪ ... not deployed/not
  installed` (no `json.loads` traceback, no `❌`).
- `make status CLUSTER_PROVIDER=k3s-hostinger` → still **all `✅`** (no service flipped to `⚪`).
- `bin/smoke-test-webhook` gate still passes.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the three listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT deploy the app stack to any cluster — this is a **reporting-only** change.
- Do NOT change the `smoke_endpoints` set, any endpoint URL, or `_posix_spawn_capture`.
- Do NOT make the `0/0 synced` ExternalSecrets case neutral — it stays `✅` (CRD present, nothing
  to sync). Only a genuinely absent CRD/resource/namespace becomes `⚪`.
