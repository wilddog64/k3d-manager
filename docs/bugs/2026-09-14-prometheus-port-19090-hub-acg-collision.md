# Bug: hub and app-cluster Prometheus port-forwards both claim `localhost:19090`

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** FIXED `31e69c56` (Codex; Claude verified) — operator follow-up pending
**Files:** `bin/cluster-up`, `bin/cluster-refresh`, `bin/k3dm-webhook`, `scripts/plugins/loadtest.sh`, `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, `docs/howto/slack-slash-commands.md`, `scripts/tests/bin/prometheus_port_split.bats` (new), `CHANGELOG.md`
**Related:** `docs/bugs/2026-09-13-hub-federate-acg-self-scrape-duplicates-series.md` (symptom fixed; this is the cause)

## Problem

Two forwards want the same local port.

| Owner | Forward | Consumers |
|---|---|---|
| **Hub** — LaunchAgent `com.k3d-manager.prometheus-port-forward` (`KeepAlive`), `scripts/etc/launchd/…prometheus-port-forward.plist.tmpl` | `19090 → k3d-k3d-cluster monitoring/prometheus-operated:9090` | cloudflared `prometheus.3ai-talk.org → 127.0.0.1:19090` (`scripts/etc/cloudflared/config.yml`); Hermes `repairs.py` `PORT_FORWARD_LABELS`; `docs/howto/launchd-daemons.md` |
| **App cluster** — `bin/cluster-up` Step 14b (`19090 + _acg_provider_port_offset`) and `bin/cluster-refresh` `_pf_ensure "ACG Prometheus port-forward"` (a hard-coded `19090`, which **ignores the offset**) | `19090(+offset) → <app ctx> monitoring/prometheus-operated:9090` | hub `federate-acg` target `host.internal:19090`; Grafana datasource `acg-prometheus` `http://host.internal:19090`; webhook non-hostinger smoke `http://localhost:19090/-/ready`; `loadtest.sh` `LOADTEST_PROM_URL` default (k6 remote-write to the app cluster) |

Live on 2026-09-14, read-only `lsof`: only the hub LaunchAgent listens on `:19090`. `:19190` is free.

Effects:
- Whichever forward starts first wins the port. The KeepAlive agent nearly always wins.
- Every app-cluster consumer then silently reads **hub** data:
  - federation duplicated 81.5k hub series as `cluster="acg"` (dropped since `22feff51`, but still scraped);
  - the `acg-prometheus` Grafana datasource shows the hub;
  - the webhook's ACG Prometheus smoke passes against the hub;
  - k6 once remote-wrote load-test metrics into the hub (progress log 2026-08).
- For `k3s-hostinger`, `cluster-refresh` re-forwards the app cluster on `19090` instead of `19100`, which fights the hub agent.

## Decision

- The hub keeps `19090`. It is the always-on, publicly routed side (cloudflared, Hermes R2, the launchd docs), so nothing there changes.
- App-cluster Prometheus forwards move to base **`19190`** plus the existing per-provider offset: `k3s-aws` 19190, `k3s-hostinger` 19200, `k3s-az` 19210, `k3s-gcp` 19220.

## Fix

### S1 — `bin/cluster-up`

Old:

```bash
_acg_prom_local_port=$((19090 + $(_acg_provider_port_offset "${_cluster_provider}")))
```

New:

```bash
_acg_prom_local_port=$((19190 + $(_acg_provider_port_offset "${_cluster_provider}")))
```

### S2 — `bin/cluster-refresh`

Old:

```bash
_pf_ensure "ACG Prometheus port-forward" \
  "${_ACG_STATE_DIR}/run/acg-prom-pf.pid" \
  "${_ACG_STATE_DIR}/logs/acg-prom-pf.log" \
  port-forward svc/prometheus-operated 19090:9090 \
  -n monitoring --context "${_app_context}" --address 0.0.0.0
```

New:

```bash
_acg_prom_local_port=$((19190 + $(_acg_provider_port_offset "${_cluster_provider}")))
_pf_ensure "ACG Prometheus port-forward" \
  "${_ACG_STATE_DIR}/run/acg-prom-pf.pid" \
  "${_ACG_STATE_DIR}/logs/acg-prom-pf.log" \
  port-forward svc/prometheus-operated "${_acg_prom_local_port}:9090" \
  -n monitoring --context "${_app_context}" --address 0.0.0.0
```

(`bin/cluster-refresh` already sources `scripts/lib/provider.sh` and sets `_cluster_provider` before this block. Confirm both; if either is missing, stop and report.)

### S3 — `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`

Old (federate target):

```yaml
              - 'host.internal:19090'
```

New:

```yaml
              - 'host.internal:19190'
```

Old (Grafana datasource):

```yaml
      url: http://host.internal:19090
```

New:

```yaml
      url: http://host.internal:19190
```

Keep the `metric_relabel_configs` drop rule from `22feff51`. It still guards against a mis-bound port.

### S4 — `bin/k3dm-webhook`

Old:

```python
        prometheus_ready_url = "http://localhost:19090/-/ready"
```

New:

```python
        prometheus_ready_url = "http://localhost:19190/-/ready"
```

Old (system-prompt text):

```
  - Prometheus: localhost:19090 → monitoring/prometheus-operated:9090 (NOT on ubuntu-k3s ingress)
```

New:

```
  - Prometheus: hub localhost:19090 (prometheus.3ai-talk.org); app cluster localhost:19190+provider offset → monitoring/prometheus-operated:9090 (NOT on ubuntu-k3s ingress)
```

### S5 — `scripts/plugins/loadtest.sh`

Old:

```bash
LOADTEST_PROM_URL="${LOADTEST_PROM_URL:-http://localhost:19090}"
```

New:

```bash
LOADTEST_PROM_URL="${LOADTEST_PROM_URL:-http://localhost:19190}"
```

### S6 — `docs/howto/slack-slash-commands.md`

Old:

```
| Prometheus | `http://localhost:19090/-/ready` | 200 |
```

New:

```
| Prometheus | `http://localhost:19190/-/ready` (app cluster; hostinger uses `https://prometheus.3ai-talk.org/-/ready`) | 200 |
```

### S7 — tests: `scripts/tests/bin/prometheus_port_split.bats` (new)

Assert tokens, never whole lines:

1. `bin/cluster-up` contains `19190 + $(_acg_provider_port_offset` and does not contain `19090 + $(_acg_provider_port_offset`.
2. `bin/cluster-refresh`:
   - contains `"${_acg_prom_local_port}:9090"`;
   - `run grep -c 'prometheus-operated 19090:9090' bin/cluster-refresh` outputs `0`.
3. `yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .static_configs[0].targets[0]'` = `host.internal:19190`.
4. `yq -r '.grafana.additionalDataSources[] | select(.name == "acg-prometheus") | .url'` = `http://host.internal:19190`.
5. Hub side unchanged:
   - the plist template contains `19090:9090` and `k3d-k3d-cluster`;
   - `scripts/etc/cloudflared/config.yml` contains `127.0.0.1:19090`.
6. `scripts/plugins/loadtest.sh` contains `localhost:19190`; `bin/k3dm-webhook` contains `localhost:19190/-/ready`.

Use `run grep …; [ "$status" -ne 0 ]` for negatives. No bare `!`.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet:

```
- App-cluster Prometheus port-forwards moved from `localhost:19090` to `19190` + provider offset, so they no longer collide with the hub's KeepAlive `prometheus-port-forward` agent (which keeps `19090` for `prometheus.3ai-talk.org`); hub federation, the `acg-prometheus` Grafana datasource, the webhook ACG smoke check and the load-test Prometheus default follow the new port, and `bin/cluster-refresh` now applies the per-provider offset it previously ignored
```

## Definition of Done

- [ ] S1–S7 applied; `git diff --stat` shows only the listed files.
- [ ] `shellcheck -x bin/cluster-up bin/cluster-refresh scripts/plugins/loadtest.sh`: no new warnings (paste the before/after counts).
- [ ] `python3 -m py_compile bin/k3dm-webhook` exits 0; `yq -e . scripts/etc/helm/observability/kube-prometheus-stack-values.yaml >/dev/null` exits 0.
- [ ] `bats scripts/tests/bin/prometheus_port_split.bats scripts/tests/bin/cluster_refresh.bats scripts/tests/plugins/observability_federate_self_scrape.bats scripts/tests/lib/webhook.bats`: all pass (paste the summary).
- [ ] `grep -rn '19090' bin scripts/plugins scripts/etc --include='*' | grep -v node_modules` lists only the plist template, cloudflared `config.yml`, and the webhook system-prompt line naming the hub.
- [ ] Commit message, verbatim: `fix(observability): move app-cluster Prometheus forwards off the hub's 19090`

## Operator follow-up (NOT for Codex)

- **Hub values:** reapply only the `observability` ApplicationSet at release close-out, then confirm that the `federate-acg` target and the `acg-prometheus` datasource show `19190`.
- **Webhook:** `make restart-webhook`.
- **Next ACG/hostinger bring-up or refresh:** confirm `lsof -iTCP:19190` (k3s-aws) or `:19200` (hostinger) is held by the app-cluster forward.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT change the hub LaunchAgent template, `Makefile` install targets, `scripts/etc/cloudflared/`, `scripts/lib/hermes/`, or `docs/howto/launchd-daemons.md`.
- Do NOT run `kubectl`, `launchctl`, `bin/cluster-up`, `bin/cluster-refresh`, or `make` targets against live systems.
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, `scripts/lib/provider.sh`, or memory-bank.
