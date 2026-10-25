# Bug: a pending or finished OrbStack update is invisible to monitoring

**Filed:** 2026-10-12
**Branch:** `k3d-manager-v1.43.7` (moved from v1.44.0 to v1.43.9 on 2026-10-25, then to v1.43.7 the same day by Claude: it is a bug, so it does not count toward the cap, and landing it now clears the prerequisite of `docs/plans/v1.43.9-orbstack-upgrade-coordinated.md` before that branch exists. Phase 2 below is replaced by that plan's operator-run upgrade.)
**Status:** DISPATCHED to Luna 2026-10-25 (phase 1 only)
**Priority:** P3 — a visibility gap; an update restarts the whole hub, and nothing warns before or labels it after
**Approval:** explicit 2026-10-12 "go ahead" (operator, to "file it for v1.44.0, alert only first, scheduled install as a later phase"); dispatch go 2026-10-25 ("go ahead", for the OrbStack work). Not critical: read-only probe, alert and dashboard.
**Severity:** low

## Symptom

On 2026-10-12 the operator clicked **Upgrade** in the OrbStack app (2.2.x → 2.2.4). OrbStack
restarted every hub container at about 11:35Z: Vault came back sealed for one watchdog interval,
and Keycloak, Prometheus and Vault each restarted once
(`docs/bugs/2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md`).

- **Before:** nothing reported that an update was waiting. The only signal is the app's own window.
- **After:** the restart spike on every dashboard has no label. It reads like an outage until
  someone remembers the upgrade.

The monitoring stack runs inside OrbStack, so it cannot alert *during* the upgrade. It can report
the pending update before, and the version change after.

## Root cause

No producer publishes OrbStack's state. The data is available from the CLI, with no GUI and no
AppleScript:

- `orbctl version`: first line is `Version: 2.2.4 (2020400)`.
- `orbctl update --check`: "Check for updates, but don't install. Returns exit status 3 if
  outdated and 0 if not."

`orbctl` is at `/opt/homebrew/bin/orbctl`, already on the Hermes launchd `PATH`.

## Fix — phase 1: detect and alert (this bug)

Shaped like `bin/k3dm-disk-metrics`, which Hermes already runs every cycle.

### 1. New `bin/k3dm-orbstack-metrics` (Python 3, executable)

- Run `orbctl version` (timeout 30 s). Parse the version from the first line with
  `^Version:\s*(\S+)`.
- Run `orbctl update --check` (timeout 60 s). Exit 3 → update available; exit 0 → up to date; any
  other exit, a timeout, or a missing `orbctl` → probe failed.
- Emit:

  ```
  k3dm_orbstack_info{version="2.2.4"} 1
  k3dm_orbstack_update_available 0
  k3dm_orbstack_probe_success 1
  ```

  - On a failed probe, emit only `k3dm_orbstack_probe_success 0`. Still emit `k3dm_orbstack_info`
    if the version was read.
  - Escape label values the same way as `_label` in `bin/k3dm-disk-metrics`.
- `PUT` to `${K3DM_ORBSTACK_PUSHGATEWAY_URL:-http://localhost:19094}/metrics/job/k3dm-orbstack`.
  Use the same retry and non-fatal skip as `publish` in `bin/k3dm-disk-metrics`. `PUT` replaces
  the job, so the old `version` series disappears after an upgrade.
- `--dry-run` prints the body and pushes nothing.
- The script never runs `orbctl update` without `--check`. It never starts, stops or restarts
  OrbStack.

### 2. `bin/k3dm-hermes`

- Add `_publish_orbstack_metrics(state, now)` next to `_publish_disk_metrics`, with the same
  try/except shape.
- Run the script only when `now - state.get("orbstack_last_run", 0) >= 3600`, then set
  `state["orbstack_last_run"] = now`. An update check every Hermes cycle (5 min) is too often.
- Call it in `_poll_cycle` right after `_publish_disk_metrics()`.

### 3. New `scripts/etc/prometheus/rules/host-orbstack.yaml`

A PrometheusRule shaped like `host-disk.yaml` (`namespace: monitoring`,
`release: kube-prometheus-stack`, group `host.orbstack`, `interval: 60s`), labels
`severity: warning`, `cluster: hub`:

- **`OrbStackUpdateAvailable`**
  - `expr: k3dm_orbstack_update_available == 1`, `for: 1h`.
  - summary: "OrbStack update available".
  - description: "OrbStack {{ $labels.version }} is installed and an update is waiting. Updating restarts every hub container: run `orbctl update` when a short hub restart is acceptable, then check Vault is unsealed."
  - Include `version` by writing the expr as
    `k3dm_orbstack_update_available == 1 and on() group_left(version) k3dm_orbstack_info`, or an
    equivalent that carries the label. Prove it in the test.
- **`OrbStackMetricsStale`**
  - `expr: k3dm_orbstack_probe_success == 0 or (time() - max(push_time_seconds{job="k3dm-orbstack"}) > 10800) or absent(k3dm_orbstack_probe_success)`,
    `for: 1h`.
  - description: "OrbStack update metrics are stale; check Hermes, `orbctl` and the Pushgateway port-forward."

### 4. `scripts/etc/prometheus/alertmanager.yaml.tmpl`

Add `OrbStackUpdateAvailable` to the `platform-warning` alertname allowlist (line 26). This sends
email only, never SMS. Do not add `OrbStackMetricsStale`.

### 5. `scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml`

- Add one stat panel **OrbStack**: `k3dm_orbstack_info` with legend `{{version}}`, plus
  `k3dm_orbstack_update_available` mapped `0` → "up to date" (green), `1` → "update available"
  (orange).
  - Place it in a new row below the existing panels.
  - Do not move or resize existing panels.
- Add a dashboard annotation **OrbStack upgraded**:
  - `expr: k3dm_orbstack_info unless on(version) (k3dm_orbstack_info offset 1h)`.
  - title "OrbStack upgraded to {{version}}".
  - It marks the hour after a new version first appears.
- Keep the uid `k3dm-host-disk`.

### 6. Docs

- `docs/guides/alerting.md`: add `OrbStackUpdateAvailable` to the `platform-warning` allowlist
  sentence.
  - While there, add the two allowlisted names the sentence already misses: `DRDrillFailed` and
    `DRDrillStale` (they are in the template).
- `docs/guides/grafana-dashboards.md`, k3dm Host Disk: the OrbStack panel and annotation.
- `docs/providers/orbstack.md`, a short
  section "Updating OrbStack":
  - `orbctl update --check` and `orbctl update`;
  - an update restarts every hub container;
  - check Vault is unsealed afterwards.
- `CHANGELOG.md` `[Unreleased]` → `### Added`.

## Files

| File | Change |
|---|---|
| `bin/k3dm-orbstack-metrics` | new producer |
| `bin/k3dm-hermes` | hourly call |
| `scripts/etc/prometheus/rules/host-orbstack.yaml` | new rules |
| `scripts/etc/prometheus/alertmanager.yaml.tmpl` | allowlist entry |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml` | panel + annotation |
| `scripts/tests/bin/test_orbstack_metrics.py` | new tests |
| `scripts/tests/hermes/test_hermes.py` | cadence test |
| `docs/guides/alerting.md`, `docs/guides/grafana-dashboards.md`, `docs/providers/orbstack.md` | sections above |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Tests

Python. Use a stub `orbctl` on a temp `PATH`. Run the producer with `--dry-run` only. No test may
push to the real Pushgateway: add an autouse fixture setting `K3DM_ORBSTACK_PUSHGATEWAY_URL` to
`http://127.0.0.1:9`.

1. Stub version `Version: 2.2.4 (2020400)`, check exit 0 →
   - `k3dm_orbstack_info{version="2.2.4"} 1`
   - `k3dm_orbstack_update_available 0`
   - `k3dm_orbstack_probe_success 1`
2. Check exit 3 → `k3dm_orbstack_update_available 1`.
3. Check exit 1 → `k3dm_orbstack_probe_success 0` and no `update_available` line.
4. No `orbctl` on `PATH` → `k3dm_orbstack_probe_success 0`, exit 0.
5. The stub records its argv. Across tests 1–4 it never receives `update` without `--check`, nor
   `start`, `stop` or `restart`.
6. Rules file: both alerts exist with `severity: warning`, `cluster: hub`.
   - `OrbStackUpdateAvailable`'s expr references `k3dm_orbstack_update_available` and
     `k3dm_orbstack_info`.
   - Its description contains `orbctl update`.
7. The Alertmanager template's `platform-warning` matcher contains `OrbStackUpdateAvailable`. The
   `sms-critical` route is unchanged.
8. The dashboard JSON parses, and the uid is still `k3dm-host-disk`. It has a panel titled
   `OrbStack` and an annotation whose expr contains `offset 1h`.
9. Hermes (`test_hermes.py`):
   - With `orbstack_last_run` 10 minutes ago, `_publish_orbstack_metrics` does not run the
     script.
   - With it 61 minutes ago, it runs the script and updates the stamp.
   - Stub `subprocess.run`.

Mutations (each must turn a test red; restore with `cmp` against a snapshot):
- treat exit 3 as up to date (test 2);
- drop `--check` from the update call (test 5);
- remove the 3600 s guard (test 9).

Gates:
- `pytest scripts/tests/bin/test_orbstack_metrics.py scripts/tests/hermes/test_hermes.py`
- `make test-pytest`
- `make test` (read the per-suite counts)
- `make validate-manifests`

## Proof it works

After landing, the operator runs `make prometheus-rules`,
re-renders Alertmanager and restarts Hermes.

- Within an hour, the Host Disk dashboard shows **OrbStack 2.2.4 — up to date**.
- When OrbStack next publishes an update, `OrbStackUpdateAvailable` emails within about 2 h:
  1 h until the next check, plus 1 h `for:`.
- After the operator runs `orbctl update`, the dashboard shows an **OrbStack upgraded to x.y.z**
  annotation over the restart spike.

## Acceptance

`orbctl update --help` (OrbStack 2.2.5, checked 2026-10-25): `-c, --check   Check for updates, but don't install. Returns exit status 3 if outdated and 0 if not.`

```yaml
must:
  - id: M1
    text: bin/k3dm-orbstack-metrics emits k3dm_orbstack_info{version}, k3dm_orbstack_update_available (1 on check exit 3, 0 on exit 0) and k3dm_orbstack_probe_success 1.
  - id: M2
    text: A failed probe (other exit, timeout, orbctl missing) emits k3dm_orbstack_probe_success 0, no update_available line, and the script still exits 0.
  - id: M3
    text: Hermes runs the producer at most once per 3600 s, right after the disk metrics.
  - id: M4
    text: OrbStackUpdateAvailable (warning, cluster hub, carries version, description names orbctl update) and OrbStackMetricsStale exist; OrbStackUpdateAvailable is in the platform-warning allowlist.
  - id: M5
    text: The Host Disk dashboard (uid k3dm-host-disk) has an OrbStack stat and an "OrbStack upgraded" annotation using offset 1h; existing panels keep their gridPos.
  - id: M6
    text: alerting.md, grafana-dashboards.md and providers/orbstack.md describe the alert, panel and update procedure.
must_not:
  - id: N1
    text: The producer never runs orbctl update without --check, and never start, stop or restart.
  - id: N2
    text: OrbStack alerts never route to sms-critical; OrbStackMetricsStale is not allowlisted.
  - id: N3
    text: Tests never push to the real Pushgateway.
  - id: N4
    text: Exit 3 must not be read as up to date, and a failed probe must not emit update_available 0.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    text: pytest scripts/tests/bin/test_orbstack_metrics.py scripts/tests/hermes/test_hermes.py green with K3DM_ORBSTACK_PUSHGATEWAY_URL=http://127.0.0.1:9; the three listed mutations each turn a test red on a temp copy; ruff 0.15.8 clean; make validate-manifests passes.
  - id: E2
    kind: offline
    proves: [M6]
    text: make check-doc-links passes on the three docs.
  - id: E3
    kind: live
    proves: [M1, M3, M5]
    text: After landing and the operator's Hermes restart, Claude confirms the Host Disk dashboard shows OrbStack 2.2.5 and its update state within an hour.
interface:
  - bin/k3dm-orbstack-metrics [--dry-run] (env K3DM_ORBSTACK_PUSHGATEWAY_URL; orbctl on PATH)
  - _publish_orbstack_metrics(state, now) in bin/k3dm-hermes
  - scripts/etc/prometheus/rules/host-orbstack.yaml
  - scripts/etc/prometheus/alertmanager.yaml.tmpl (platform-warning matcher)
  - Grafana uid k3dm-host-disk
```

## Later — phase 2: scheduled install (not in this bug)

A weekly launchd job runs `orbctl update` in a fixed window (e.g. Sunday 03:00 local). The aim is
that a person never has to click **Upgrade**.

Do not start phase 2 until all three of these hold:

- `2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md` has landed and been proven on a
  real restart, so Vault unseals itself in the same watchdog run.
- `2026-10-12-hermes-has-no-vault-sealed-sensor.md` has landed, so a failed unseal is visible.
- The operator approves an unattended hub restart window.
- The job runs the host-network drift fix (`bin/k3dm-hostnet-drift --fix`) after the update, because an outside restart leaves host-network pods on stale IPs (recurrence 2026-10-12 in `2026-09-29-hostnetwork-pods-keep-stale-ip-after-node-restart.md`).

File phase 2 as its own bug then.

## What NOT to Do

- Do NOT run `orbctl update` (without `--check`), `orbctl stop`, `orbctl restart` or restart
  OrbStack from any code, test or verification step.
- Do NOT add an SMS route; this alert is email-only.
- Do NOT use AppleScript, GUI scripting or Accessibility automation.
- Do NOT apply rules, Alertmanager config or dashboards to the live hub; the operator does that.
- Do NOT commit, push or create a PR. Claude verifies and commits.
- Do NOT modify files outside the Files list.
