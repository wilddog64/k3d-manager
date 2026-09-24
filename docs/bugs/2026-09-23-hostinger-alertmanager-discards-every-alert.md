# `ubuntu-hostinger` Alertmanager discards every alert — a missing `configSecret`, and a warning allowlist that must be edited per rule

**Filed:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Status:** OPEN
**Severity:** high — the cluster the public edge serves has had **zero** alert delivery, and nothing detected it for 64 days

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.37.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/observability.sh` — `deploy_observability` (the hub renderer, body at
    `:48-90`) and `deploy_observability_acg` (the app-cluster twin, body at `:611-652`). The two
    are near-duplicates; this spec adds the same guard call to both.
  - `scripts/etc/prometheus/alertmanager.yaml.tmpl` — the whole `route:` block.
  - `scripts/lib/hermes/sensors.py` — `_debounced`, and `kine` at `:226` as the model for a
    `run`-injected sensor.
  - `bin/k3dm-hermes` — the `from hermes.sensors import (...)` block at `:22-25`, the
    `_datastore_run` runner at `:82`, and the `records = [...]` list at `:122-129`.
  - `docs/bugs/2026-09-23-alertmanager-null-root-route-silently-drops-warning-alerts.md` — the
    hub half of this bug. Its fix `a7135966` is committed but **not deployed**, and as §Problem
    shows it is also **not sufficient**. Do NOT revert it.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`istio-cni-node-vgr6m` on `ubuntu-hostinger` has been `0/1 Running` for 17 days. The alert that
exists for exactly this condition has been firing the whole time and nobody was told.

Detection works. Delivery is dead. Three independent layers each break it, and any one of them
alone is a total blackout.

### Layer 1 — the referenced `configSecret` does not exist

```
$ kubectl --context ubuntu-hostinger -n monitoring get alertmanager \
    acg-kube-prometheus-stack-alertmanager -o jsonpath='{.spec.configSecret}'
alertmanager-smtp-secret

$ kubectl --context ubuntu-hostinger -n monitoring get secret alertmanager-smtp-secret
Error from server (NotFound): secrets "alertmanager-smtp-secret" not found
```

When the referenced Secret is absent the Prometheus Operator does not fail, does not warn on the
CR, and does not leave Alertmanager unconfigured. It generates its **default** configuration:

```yaml
route:
  receiver: "null"
receivers:
- name: "null"
templates: []
```

That is the live content of `alertmanager-acg-kube-prometheus-stack-alertmanager-generated`
today. The root receiver is a null sink and there are **no child routes**, so all 114 rules on
that cluster discard into it. Confirmed firing and discarded:

```
ALERTS{alertstate="firing"} =>
  Watchdog                     severity=none
  KubeDaemonSetRolloutStuck    severity=warning  daemonset=istio-cni-node
```

### Layer 2 — the renderer treats total alert loss as a warning

`deploy_observability_acg` reads the credentials from hub Vault and, on any failure:

```bash
  if [[ -z "${_am_creds}" ]]; then
    _warn "[observability] Alertmanager Vault secret not found — skipping SMS config on ACG"
    _warn "[observability] Run: make alertmanager-secret to configure"
  else
```

It skips creating the Secret and returns success. The CR keeps pointing at the name. A skipped
render is indistinguishable from a successful one in the exit code, and the two `_warn` lines
scroll past in a multi-minute deploy. `deploy_observability` has the same shape for the hub.

Warn-and-skip is the correct behaviour when the Secret **already exists** — it preserves a
working config across a transient Vault outage. It is the wrong behaviour when the Secret does
not exist, because then the outcome is guaranteed silence.

### Layer 3 — the warning route is an allowlist, so a new rule is silent by default

Even with `a7135966` deployed, `KubeDaemonSetRolloutStuck` would **still** be dropped. The root
receiver is `'null'` and the only exits are `severity = critical` and a five-name allowlist:

```yaml
    - matchers:
        - alertname =~ "KubeJobFailed|KubeJobNotCompleted|E2EVerificationFailing|E2EVerificationStale|PrometheusDuplicateTimestamps"
      receiver: platform-warning
```

Every `severity: warning` rule not named in that regex is discarded. There are 114 rules and 5
names. The allowlist has to be edited by hand for each new alert anyone wants to receive, and
forgetting to is silent — which is how 17 days passed.

### Why nothing noticed

Hermes has sensors for ESO, ArgoCD, reachability, node pressure, Kine, CI and token expiry. It
has no sensor for *the alerting path itself*. The component whose entire job is to tell us things
are broken is the one component nothing checks.

---

## Root cause

Three defects, fixed in order S1 → S2 → S3:

| | Defect | Fix |
|---|---|---|
| S1 | Warning alerts reach a receiver only via a hand-maintained allowlist | a `severity = warning` catch-all route |
| S2 | A `configSecret` that does not exist is a silent success | a post-deploy guard that fails the deploy |
| S3 | Nothing monitors the monitor | a Hermes `alert_delivery` sensor + read-only probe |

---

## S1 — route all warnings, not an allowlist

In `scripts/etc/prometheus/alertmanager.yaml.tmpl`, keep the named-allowlist route (it carries
its own timing) and append a catch-all **after** it. Order matters: Alertmanager takes the first
matching child route, so the catch-all must be last.

Replace this:

```yaml
    - matchers:
        - alertname =~ "KubeJobFailed|KubeJobNotCompleted|E2EVerificationFailing|E2EVerificationStale|PrometheusDuplicateTimestamps"
      receiver: platform-warning
      group_wait: 5m
      group_interval: 2h
      repeat_interval: 24h
```

with this:

```yaml
    - matchers:
        - alertname =~ "KubeJobFailed|KubeJobNotCompleted|E2EVerificationFailing|E2EVerificationStale|PrometheusDuplicateTimestamps"
      receiver: platform-warning
      group_wait: 5m
      group_interval: 2h
      repeat_interval: 24h
    - matchers:
        - severity = warning
      receiver: platform-warning
      group_wait: 10m
      group_interval: 6h
      repeat_interval: 72h
```

The catch-all is deliberately slower than the allowlist (`10m` / `6h` / `72h`): a named rule is
one we chose to watch closely, an unnamed warning is one we want to know about without being
paged repeatedly. `KubeHpaMaxedOut` is excluded as noise by the inhibit rules and the
`TrivyCriticalVulnerabilityDetected` route above, which both still match first.

Do NOT change the root `receiver: 'null'`. A default-drop root with explicit exits is the
intended design; the bug was that the only warning exit was an allowlist.

---

## S2 — refuse to finish a deploy that cannot deliver

Add one new private function to `scripts/plugins/observability.sh`. Place it immediately before
`deploy_observability_acg`:

```bash
function _observability_assert_alertmanager_delivery() {
  local _context="$1"
  local _cr _configured
  _cr="$(_kubectl --no-exit get alertmanager -n monitoring --context "${_context}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${_cr}" ]]; then
    return 0
  fi
  _configured="$(_kubectl --no-exit get alertmanager "${_cr}" -n monitoring --context "${_context}" \
    -o jsonpath='{.spec.configSecret}' 2>/dev/null || true)"
  if [[ -z "${_configured}" ]]; then
    return 0
  fi
  if _kubectl --no-exit get secret "${_configured}" -n monitoring --context "${_context}" \
      >/dev/null 2>&1; then
    _info "[observability] Alertmanager ${_cr} config secret ${_configured} present on ${_context}"
    return 0
  fi
  _err "[observability] Alertmanager ${_cr} on ${_context} references configSecret ${_configured}, which does not exist"
  _err "[observability] The Prometheus Operator falls back to route.receiver=null and DISCARDS EVERY ALERT"
  _err "[observability] Seed the credentials first: make alertmanager-secret"
  return 1
}
```

Then call it at the end of both renderers.

In `deploy_observability_acg`, the last lines currently are:

```bash
  if ! (set +e; _observability_refresh_prometheus_auth_proxy); then
    _warn "[observability] Prometheus auth proxy refresh failed; continuing with the generated web config"
  fi
}
```

Make them:

```bash
  if ! (set +e; _observability_refresh_prometheus_auth_proxy); then
    _warn "[observability] Prometheus auth proxy refresh failed; continuing with the generated web config"
  fi
  _observability_assert_alertmanager_delivery "${_app_context}"
}
```

Add the equivalent call as the final statement of `deploy_observability`, passing the hub context
that function already resolves (`k3d-k3d-cluster` unless it holds it in a local — use the local
it already has; do NOT hardcode a second copy of the context string).

**Why this is safe to make fatal.** The guard returns 0 in every state except one: the CR
references a Secret name and that Secret is absent. In that state delivery is not degraded, it is
zero, and the cluster cannot report its own failure. A rebuild that reaches this state has not
succeeded. The guard returns 0 when the CR does not exist yet (first deploy, before Helm creates
it) and when the Secret exists from a previous run, so a transient Vault outage still leaves the
previous working config in place and the deploy still passes.

---

## S3 — a Hermes sensor for the delivery path

### S3a — the probe

New file `bin/k3dm-alert-delivery-status`, mode `0755`, `set -euo pipefail`. It is **read-only**:
it gets the Alertmanager CR and the generated Secret, and prints JSON on stdout. It must never
mutate anything and must never print the Secret's contents — only the parsed shape.

Contract, and the sensor depends on every key:

```json
{
  "available": true,
  "clusters": [
    {
      "context": "k3d-k3d-cluster",
      "alertmanager": "kube-prometheus-stack-alertmanager",
      "config_secret": "alertmanager-smtp-secret",
      "config_secret_missing": false,
      "root_receiver": "null",
      "root_receiver_is_null": true,
      "child_routes": 4
    }
  ]
}
```

- Iterate the contexts in `scripts/etc/argocd/app-clusters.tsv` plus the hub context, skipping any
  context absent from the local kubeconfig (a laptop without the VPS context must not fail).
- `config_secret_missing` — the CR names a `configSecret` and `kubectl get secret` on it fails.
- `root_receiver` / `child_routes` — parsed from the **generated** Secret
  (`alertmanager-<cr-name>-generated`, key `alertmanager.yaml`, base64), because that is what
  Alertmanager actually loads. Parse it in Python via `python3 -c`, not with `grep`.
- `"null"` detection is on the receiver **name** resolving to a receiver with no
  `email_configs`, `webhook_configs` or any other `*_configs` key — not on the literal string
  `null`, so a receiver renamed to `blackhole` is still caught.
- On any failure to reach a cluster at all, emit `{"available": false}` and exit 1. Partial
  results are acceptable only when a context is absent from the kubeconfig; a context that exists
  but cannot be read is `available: false`.

### S3b — the sensor

Append to `scripts/lib/hermes/sensors.py`, after `kine`:

```python
def alert_delivery(run, state, threshold=1):
    """Report clusters whose Alertmanager cannot deliver any alert at all.

    Two independent blackout modes are checked, because either one alone silences
    every rule: a referenced configSecret that does not exist (the Prometheus
    Operator then generates route.receiver=null), and a live route tree whose root
    receiver is a null sink with no child routes to escape through.
    """
    try:
        code, output = run(["bin/k3dm-alert-delivery-status", "--json"], {})
        payload = json.loads(output) if code == 0 and output else {}
        clusters = payload.get("clusters")
        if not payload.get("available") or not isinstance(clusters, list) or not clusters:
            raise ValueError("invalid alert delivery probe")
        blackout = []
        for item in clusters:
            if not isinstance(item, dict) or "context" not in item:
                raise ValueError("invalid cluster entry")
            name = item["context"]
            if item.get("config_secret_missing"):
                blackout.append(
                    f"{name}: configSecret {item.get('config_secret', 'unset')} absent")
            elif item.get("root_receiver_is_null") and not item.get("child_routes"):
                blackout.append(f"{name}: root receiver is a null sink with no child routes")
        data = {"clusters": len(clusters), "blackout": blackout}
        if blackout:
            status = ("degraded" if _debounced("alert_delivery", True, threshold, state)
                      else "healthy")
            return record("alert_delivery", status, "; ".join(blackout[:3]), data=data)
        _debounced("alert_delivery", False, threshold, state)
        return record("alert_delivery", "healthy",
                      f"{len(clusters)} Alertmanager route tree(s) can deliver", data=data)
    except Exception:
        return record("alert_delivery", "unknown", "alert delivery probe unavailable")
```

`threshold=1` — a blackout is a static configuration state, not a flapping metric, so one
confirming cycle is enough. Follow `ci`, which uses the same value.

### S3c — wiring

In `bin/k3dm-hermes`, add `alert_delivery` to the import (keep alphabetical order within the
existing parenthesised list) and add one runner plus one record.

Runner, placed next to `_datastore_run`:

```python
def _alert_delivery_run(command, _additions):
    """Read Alertmanager delivery shape from the read-only probe."""
    result = subprocess.run([str(ROOT / command[0]), *command[1:]],
                            capture_output=True, text=True, timeout=60, check=False)
    return result.returncode, result.stdout
```

Record, appended to the `records = [...]` list after `kine(_datastore_run, state)`:

```python
        alert_delivery(_alert_delivery_run, state),
```

Do NOT add an enrichment hook, an LLM call, or a repair proposal for this sensor. Hermes'
`repairs` module must not learn to re-render a Secret — that is the operator's `make
observability`, and an automatic credential re-render is out of scope.

---

## Tests

All tests are pure logic. No cluster, no mocks of `kubectl` beyond a stub on `PATH`.

New file `scripts/tests/hermes/test_alert_delivery.py` — 8 cases:

1. a single healthy cluster → `status == "healthy"`, evidence names the count
2. `config_secret_missing: true` → degraded on the second cycle, evidence contains the
   secret name and the context
3. first cycle with a blackout → `healthy` (debounce not yet satisfied), and
   `state["debounce"]["alert_delivery"] == 1`
4. `root_receiver_is_null: true` with `child_routes: 4` → healthy (there is an escape route)
5. `root_receiver_is_null: true` with `child_routes: 0` → degraded on the second cycle
6. `available: false` → `status == "unknown"`
7. a cluster entry that is not a dict, and one missing `context` → `status == "unknown"`
8. a healthy cycle after a blackout resets the debounce counter to 0

New file `scripts/tests/plugins/observability_alertmanager_delivery_guard.bats` — 5 cases over
`_observability_assert_alertmanager_delivery` with a stubbed `_kubectl`:

1. no Alertmanager CR → returns 0
2. CR with an empty `configSecret` → returns 0
3. CR + `configSecret` + the Secret exists → returns 0, logs the `_info` line
4. CR + `configSecret` + the Secret is absent → returns **1**, and the output contains
   `DISCARDS EVERY ALERT`
5. the failure message names both the CR and the secret

Extend `scripts/tests/plugins/e2e_observability.bats` (or the nearest existing template test —
do not create a second template suite) with 2 cases over
`scripts/etc/prometheus/alertmanager.yaml.tmpl`:

1. a route matching `severity = warning` exists and its receiver is not `'null'`
2. the `severity = warning` route appears **after** the `alertname =~` allowlist route

Assert on meaningful tokens, never on a whole source line — whole-line assertions rot.

---

## Mutations — prove each guard can fail

Run one at a time. After each: confirm the named test goes red, paste the red, restore the file,
and confirm `git diff --quiet` before the next.

- **M1** — in `_observability_assert_alertmanager_delivery`, change the final `return 1` to
  `return 0`. Expect: `observability_alertmanager_delivery_guard.bats` case 4 red on the exit
  status, not on the message.
- **M2** — in `alert_delivery`, delete the `if item.get("config_secret_missing"):` branch.
  Expect: `test_alert_delivery.py` case 2 red. It must red because the status is `healthy`, NOT
  because of a `KeyError`.
- **M3** — in `alertmanager.yaml.tmpl`, delete the `severity = warning` catch-all route.
  Expect: the new template test case 1 red.

If a mutation does not turn its test red, the **test** is wrong. Fix the test, not the mutation.

---

## Docs

- New `docs/guides/alert-delivery.md` — the three layers, the route-tree shape Alertmanager
  actually loads vs. the template that produced it, how to confirm delivery end to end, and a
  triage table keyed on the symptom "an alert is firing in Prometheus but no mail arrived".
  Include the `configSecret`-absent case as the first row, because it is the one that looks
  healthy from every direction.
- `README.md` — one link line beside the existing Alerting guide line.
- `CHANGELOG.md` — `[Unreleased]` → `### Fixed`.
- `docs/guides/grafana-dashboards.md` — add a triage row: *Alertmanager delivers nothing on one
  cluster → the CR references a `configSecret` that does not exist → `kubectl -n monitoring get
  alertmanager -o jsonpath='{.items[0].spec.configSecret}'` then `get secret` on that name.*
- `memory-bank/activeContext.md` and `memory-bank/progress.md` — status and the commit SHA.

---

## Operator runbook (NOT Codex)

Codex must not run any of this. It needs the Vault port-forward, hub credentials and a live
mutation.

1. Confirm the credentials are still in Vault (the port-forward on `127.0.0.1:18200` must be up).
   If the read fails, `make alertmanager-secret` first.
2. `make observability` — re-renders the hub secret and picks up both `a7135966` and the S1
   catch-all.
3. `./scripts/k3d-manager deploy_observability_acg --confirm` against `ubuntu-hostinger` — creates
   the missing `alertmanager-smtp-secret` there.
4. Confirm the **generated** Secret, not the template:
   `kubectl --context ubuntu-hostinger -n monitoring get secret \
   alertmanager-acg-kube-prometheus-stack-alertmanager-generated -o jsonpath='{.data.alertmanager\.yaml}' \
   | base64 -d | head -40` — the root route must have child routes and `platform-warning` must
   appear.
5. Confirm delivery, not configuration: wait for the `KubeDaemonSetRolloutStuck` group and check
   that mail arrives. `notifications_total` counts **attempts**; read the `notify.go` log lines.

---

## Definition of Done

- [ ] S1 catch-all route added, allowlist route kept, root receiver unchanged
- [ ] S2 guard added and called as the final statement of **both** renderers
- [ ] S3 probe, sensor and wiring added; probe is read-only and prints no secret material
- [ ] 8 pytest cases + 5 BATS guard cases + 2 template cases, all green
- [ ] M1, M2, M3 each proven red, then restored
- [ ] `make test` green; bare `pytest` green (`make test` alone is not the CI gate)
- [ ] `make check-doc-links` green
- [ ] Docs written; memory-bank updated with the commit SHA

Commit message (verbatim):

```
fix(alerting): deliver warnings by default and refuse a deploy that cannot alert

ubuntu-hostinger's Alertmanager CR referenced a configSecret that was never
created, so the Prometheus Operator generated route.receiver=null and all 114
rules discarded into it, including a KubeDaemonSetRolloutStuck that had been
firing for 17 days. The renderer treated the missing secret as a warning and
exited 0, and warning alerts only escaped the null root via a five-name
allowlist. Routes every severity=warning alert, fails the deploy when the CR
references a secret that does not exist, and adds a Hermes alert_delivery
sensor so the alerting path itself is monitored.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

---

## What NOT to Do

- Do NOT create a pull request, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT touch the live cluster: no `kubectl`, no `helm`, no `docker`, no `make up`, no `make
  refresh`, no `make observability`. Code, tests and docs only.
- Do NOT change the root route's `receiver: 'null'`.
- Do NOT read, print, log or echo any Alertmanager credential. The probe prints shape only.
- Do NOT add a repair action, an LLM enrichment hook, or an auto re-render for this sensor.
  Hermes' LLM knob is dead code; leave it dead.
- Do NOT enable Hermes or set `K3DM_HERMES_STATUS_ENABLED=1`. Hermes stays down until a live run
  confirms the outstanding e2e fixes.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — subtrees, fixed upstream.
- Do NOT delete any file outside the target list. If a scope check flags an unrelated file,
  report it and leave it alone.

---

## Cross-references

- `docs/bugs/2026-09-23-alertmanager-null-root-route-silently-drops-warning-alerts.md` — the hub
  half; fix `a7135966`, committed and still undeployed
- `docs/bugs/2026-09-14-alertmanager-configsecret-wrong-values-path.md`
- `docs/bugs/2026-09-14-alertmanager-secret-accepts-empty-credentials.md`
- `docs/bugs/2026-09-20-alertmanager-cpu-limit-throttles-notifications.md`
- `docs/bugs/2026-09-23-appset-live-overrides-lock-in-stale-cni-dirs.md` — the istio-cni
  DaemonSet that this blackout hid
- `memory/reference_alertmanager_notifications_total_counts_attempts.md`
- `memory/reference_alertmanager_inline_templates_no_sprig.md`
