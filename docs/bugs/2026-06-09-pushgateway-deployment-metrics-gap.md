# Bug: Pushgateway deployment metrics are intermittently missing

**Filed:** 2026-06-09

## Description

`bin/k3dm-webhook` pushes deployment metrics to Prometheus Pushgateway only once,
at job finish. When the Pushgateway port-forward or pod is still warming up, that
single best-effort push can fail and be logged as a non-fatal skip. The Grafana
dashboard then shows no fresh deployment data until a later run succeeds.

This matches the observed behavior where `k3dm_deployment_duration_seconds`,
`k3dm_deployment_success`, and `k3dm_deployment_last_timestamp_seconds` appear
intermittently: the data exists only when the one-shot push lands after
Pushgateway is reachable.

## Why this matters

- Grafana deployment panels look flaky even when the underlying deployment
  completed successfully.
- The last successful metric sample can be stale or missing if Pushgateway was
  briefly unavailable at job completion.
- The current best-effort push path has no retry window, so transient readiness
  gaps turn into lost metrics.

## Proposed follow-up

1. Add a bounded retry window around the Pushgateway metric push.
2. Prefer a healthy/reachable Pushgateway before sending the POST.
3. Keep the push non-fatal, but avoid dropping metrics on short-lived readiness
   gaps.

---

## Update 2026-09-24 — the proposed follow-up above is ALREADY IMPLEMENTED; the real cause is different

Do not re-implement items 1–3. They shipped. `bin/k3dm-webhook:1717-1741` already has a bounded
retry loop (`_PUSHGATEWAY_PUSH_RETRIES`, `_PUSHGATEWAY_PUSH_SLEEP_SECS`) and already prechecks
`${PUSHGATEWAY_URL}/-/healthy` before POSTing, and the push is already non-fatal.

**Measured today:** the symptom is not intermittent, it is total.

- `pushgateway` on `ubuntu-hostinger` is up and being scraped — hostinger Prometheus has
  `pushgateway_build_info` and `pushgateway_http_requests_total`.
- That same Prometheus has **zero** `k3dm_*` series. No push has ever landed.
- The hub (`k3d-k3d-cluster`) has **no pushgateway pod at all**.
- `PUSHGATEWAY_URL` defaults to `http://localhost:9091` (`scripts/lib/webhook/config.py:33`), i.e. a
  launchd port-forward on the laptop (`com.k3d-manager.pushgateway-port-forward`,
  `bin/cluster-up:1873-1890`).
- **That launchd agent is not loaded** (`launchctl list | grep pushgateway` → nothing), and
  `curl http://localhost:9091/-/healthy` returns `000` — connection refused.

So every push retries against a dead local socket, exhausts its retries, and logs a non-fatal skip.
The retry window cannot help: there is nothing listening to retry against.

### Real remaining defects

1. **The sink is absent, not slow.** A bounded retry against a closed port is pure latency. The push
   path needs to distinguish "Pushgateway not reachable at all" from "not ready yet" and say so once,
   loudly, rather than degrading into a silent skip that nobody sees for months.
2. **Silent failure has no operator surface.** `k3dm_deployment_*` being absent for an extended period
   is indistinguishable from "no deployments ran". There is no alert and no `make status` row for
   "deployment metrics have not been published since X".
3. **`_provider_supports_pushgateway` is inconsistent with the push path.**
   `bin/k3dm-webhook:1793` returns `False` for `k3s-hostinger`, so the smoke check skips Pushgateway
   on that provider — but `_push_metrics` (line 1698) gates only on `PUSHGATEWAY_URL` being non-empty
   and attempts the push regardless of provider. One of the two is wrong; decide which and make them
   agree.
4. **Topology is unstated.** The dashboard ships to both the hub and hostinger, but only hostinger has
   a Pushgateway. Which Prometheus is supposed to hold these metrics should be written down before
   any code changes, or the fix will chase the wrong cluster.

### Note on how this was nearly misdiagnosed

An initial producer search used `grep -r --include='*.yaml' --include='*.sh' --include='*.py'` and
concluded **no producer existed**. That was wrong: `bin/k3dm-webhook` has **no file extension**, so
the include filters skipped it. When searching this repo for producers, never restrict by extension —
`bin/` holds extensionless executables.

---

## Update 2026-09-24 (second) — ROOT CAUSE FOUND. This section is the implementation spec.

The first 2026-09-24 update left four open items and said the topology had to be decided before any
code changed. Both are now settled by measurement. **Implement this section; do not re-derive it.**

### The one-sentence cause

`_deploy_pushgateway_acg` installs the helm release as **`prometheus-pushgateway`**
(`scripts/plugins/observability.sh:692`), but `_hostinger_refresh_access_layer` probes for a service
named **`pushgateway`** (`scripts/lib/providers/k3s-hostinger.sh:661`). The probe therefore always
fails, the `else` branch fires, and
`rm -f "${_pushgateway_pf_plist}"` **deletes the port-forward agent on every access-layer refresh**.

### Measured evidence (2026-09-24, live `ubuntu-hostinger`)

| Link in the chain | Measured | Verdict |
|---|---|---|
| Helm release / service name | `monitoring/prometheus-pushgateway`, ClusterIP, 9091, age 64d | present |
| `kubectl -n monitoring get svc pushgateway` | not found | **probe is wrong** |
| `~/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist` | absent | deleted by `rm -f` |
| `lsof -iTCP:9091 -sTCP:LISTEN` | nothing | no local sink |
| `~/Library/Logs/k3dm-webhook.log` | `metrics push attempt 5/6 failed: <urlopen error [Errno 61] Connection refused>` then `metrics push skipped (non-fatal)` | producer is healthy and trying |
| Prometheus target `job="pushgateway"` | `up = 1`, instance `prometheus-pushgateway.monitoring:9091` | **sink and scrape are fine** |
| `k3dm_deployment_success` in hostinger Prometheus | zero series | nothing has ever landed |

The producer works. The sink works. The scrape works. Only the laptop→cluster hop was missing, and it
was missing because our own code removed it.

**Round-trip proof.** The plist and wrapper were regenerated by calling
`_hostinger_write_monitoring_port_forward_plist` with `svc/prometheus-pushgateway`, the agent was
bootstrapped, and then: `localhost:9091/-/healthy` → `200`; a `POST` of a throwaway gauge →
`200`; the same series queryable in hostinger Prometheus ~45s later; the group then `DELETE`d
(`202`). **The corrected service name is the entire fix.** The live agent is a manual stopgap and
will be `rm -f`'d again by the next refresh until S1 lands.

### Item 4 from the previous update — topology, now DECIDED

**`ubuntu-hostinger`'s Prometheus is the intended home for `k3dm_deployment_*`.** Not a guess:
the dashboard's every panel targets datasource uid `P5A1115AEDF367D43`
(`scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml`), and that uid is defined in
`scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml:26` — the ACG/app-cluster
stack. The hub (`k3d-k3d-cluster`) has no pushgateway and is not supposed to have one.
**Do not add a pushgateway to the hub. Do not repoint the dashboard.**

---

## S1 — correct the service name, and stop it drifting again

`scripts/lib/providers/k3s-hostinger.sh`, inside `_hostinger_refresh_access_layer`.

The name currently appears twice as a bare literal, which is exactly how it drifted away from
`bin/cluster-up`. Bind it once. Add this beside the existing `_pushgateway_pf_*` locals:

```bash
  local _pushgateway_svc="prometheus-pushgateway"
```

Then replace the block at lines 661-671 so both uses read from it:

```bash
  if kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" -n monitoring get svc "${_pushgateway_svc}" >/dev/null 2>&1; then
    _hostinger_write_monitoring_port_forward_plist \
      "${_pushgateway_pf_plist}" \
      "${_pushgateway_pf_log}" \
      "svc/${_pushgateway_svc}" \
      "${_HOSTINGER_KUBE_CONTEXT}" \
      "9091" \
      "9091"
  else
    rm -f "${_pushgateway_pf_plist}"
  fi
```

Nothing else in that function changes. Keep the `else rm -f` — removing a stale agent when the
service genuinely is absent is correct behaviour.

**Do NOT** touch `bin/cluster-up:1890`. It already says `svc/prometheus-pushgateway` and has always
been right; it is the reference, not the bug.

## S2 — `_provider_supports_pushgateway` is inverted

`bin/k3dm-webhook:1793-1794` currently reads:

```python
def _provider_supports_pushgateway(provider):
    return provider != "k3s-hostinger"
```

This excludes the **only** provider that provably has a Pushgateway, and includes the hub, which
provably does not. `_deploy_pushgateway_acg` is the sole installer and it installs onto the
app-cluster observability context — `ubuntu-hostinger` in this deployment, hence the 64-day-old
release. `provider == "hub"` is a real value in this file (see line 406). Replace with:

```python
def _provider_supports_pushgateway(provider):
    """The Pushgateway is installed on app-cluster observability stacks only
    (_deploy_pushgateway_acg). The hub has none by design."""
    return provider != "hub"
```

This predicate gates only the `make status` smoke surface (lines 2242 and 2297), never
`_push_metrics`. Fixing it does not change what is pushed — it changes whether a dead sink is
**visible**. That invisibility is why this went unnoticed for 64 days.

If you find a provider string reaching this function that contradicts the above, **stop and report
it** rather than widening the predicate on a guess.

## S3 — make a dead Pushgateway an error, not a shrug

`bin/cluster-status-summary:61` contains `optional={"pushgateway"}`, which downgrades a failed
Pushgateway probe from `error` to `warning`. With S2 also skipping the probe entirely on hostinger,
the two together produced total silence. Remove `pushgateway` from that set so the row reports
`error`.

Removing it is safe **because** of S2: on the hub the probe is now skipped, so no spurious error
appears where no Pushgateway is expected.

Keep the change to that one set literal. Do not restructure the inline `python3` heredoc.

---

## Explicitly OUT of scope

- **Checkout Load Test.** The other half of the "no data" report has its own spec at
  `docs/bugs/2026-08-29-loadtest-slice-f-generator.md` (Slice F, k6 generator + auth token recipe).
  It needs a live cluster and a Keycloak password grant. **Do not start it here and do not duplicate
  that spec.**
- **A metric-staleness alert.** Worth doing, deliberately deferred: it needs a PrometheusRule plus a
  decision on the staleness window, and S1+S2+S3 already restore both the data and its visibility.
  Recorded here as the remaining follow-up rather than filed as a second document.
- The hub. No Pushgateway there. See the topology decision above.

## Tests

All four are new. There is no existing suite covering the hostinger port-forward plists or this
predicate, so do not hunt for one to extend.

**`scripts/tests/lib/hostinger_pushgateway_port_forward.bats`** (new)

1. **"the pushgateway probe uses the installed service name"** — assert the `get svc` probe in
   `_hostinger_refresh_access_layer` resolves to `prometheus-pushgateway`, and that the
   `_hostinger_write_monitoring_port_forward_plist` call passes `svc/prometheus-pushgateway`.
2. **"no producer refers to the bare pushgateway service name"** — a **disappearance gate**: the
   forms `get svc pushgateway` and `svc/pushgateway` (as whole tokens, not as substrings of
   `prometheus-pushgateway`) must appear **zero** times across
   `scripts/lib/providers/k3s-hostinger.sh`, `bin/cluster-up` and `scripts/plugins/observability.sh`.
   Use a disappearance assertion, not a count comparison — `grep -c` exits 1 on zero matches.
3. **"all three sites agree on the pushgateway service name"** — assert the helm release name in
   `observability.sh`, the `svc/` argument in `bin/cluster-up`, and the name in
   `k3s-hostinger.sh` are the **same** string. This is the guard that would have caught the original
   drift; test 1 alone would not.

**`scripts/tests/bin/test_webhook_pushgateway_provider.py`** (new)

4. **A table test over `_provider_supports_pushgateway`** — `"hub"` → `False`; each of
   `"k3s-hostinger"`, `"k3s-aws"`, `"k3s-gcp"`, `"k3s-az"` → `True`.
   Import `bin/k3dm-webhook` with the **existing** `SourceFileLoader` pattern from
   `scripts/tests/bin/test_smoke_logins.py:12-16`. Do not invent a second import mechanism and do
   not add an `__init__.py`.

No test may stub the thing it measures. These assert against real repo files and the real imported
function — keep it that way. `scripts/tests/hermes/test_alert_delivery.py` was 8/8 green while the
probe it claimed to cover was never executed, because it injected a stubbed `run`.

## Mutations — prove each test can fail

One at a time. Reintroduce the defect, run the suite, **paste the red**, restore, and confirm
`git diff --quiet` before the next one.

- **M1** — revert S1's probe to `get svc pushgateway`. Test 1 must go red **on the asserted service
  name**, not on a stub or harness error. If it reds for any other reason the test is wrong: fix the
  test, not the mutation.
- **M2** — revert only the `svc/${_pushgateway_svc}` argument, leaving the probe correct. Test 1 must
  still go red. This proves test 1 checks both uses; a test that only reads the probe would pass here
  and that is the failure mode to rule out.
- **M3** — change the helm release name in `observability.sh` to `pushgateway`. Test 3 must go red.
  Test 2 must **also** red. Restore carefully — this one edits a third file.
- **M4** — restore `return provider != "k3s-hostinger"`. Test 4 must go red on both the `hub` case
  and the `k3s-hostinger` case; paste both failures.

## Gates — paste the real output of each

1. `bats scripts/tests/lib/hostinger_pushgateway_port_forward.bats` — green, with counts.
   BATS numbers tests per-invocation, not per-file, so **quote test NAMES, not numbers**.
2. `bats scripts/tests/lib/provider_contract.bats` — still green. It is the one existing suite that
   touches `_hostinger_refresh_access_layer`; S1 must not regress it.
3. `shellcheck -x scripts/lib/providers/k3s-hostinger.sh` — **zero new** warnings vs `HEAD~`. Paste
   BOTH counts. Count with `grep -cE '\^-*\^ SC'`, **not** `grep -c 'SC[0-9]'` — the latter
   double-counts, because the "For more information" wiki URL line also contains the code.
4. `make test` — green. It takes ~15 minutes; **that is not a hang, let it finish.** Paste the final
   summary line.
5. Bare `pytest` — green. `make test` alone is not the CI gate. `pytest` is **not** on
   `/opt/homebrew/bin/python3`; invoke bare `pytest` so the pyenv shim resolves it.
6. `make check-doc-links` — the pre-commit hook runs it on staged `.md`.

## Docs — required in this same commit

A feature or fix is not done until the page a reader would actually open is updated. CHANGELOG,
`docs/releases.md` and memory-bank **do not count**, and neither does this spec.

- `docs/guides/grafana-dashboards.md` — it already carries the "No data" triage table. Add the
  Pushgateway row: symptom (`k3dm Deployment Metrics` empty), the three things that must be true
  (release installed on the app cluster, local 9091 agent loaded, `job="pushgateway"` target up),
  and the one-line check `curl -s -o /dev/null -w '%{http_code}' http://localhost:9091/-/healthy`.
  State plainly that these metrics live in the **app-cluster** Prometheus, not the hub's.
- `CHANGELOG.md` under `[Unreleased]` → `### Fixed`.
- `memory-bank/activeContext.md` and `memory-bank/progress.md` with the commit SHA and status.

## Definition of Done

- [ ] S1, S2, S3 applied exactly as written above.
- [ ] Four tests added and green; `provider_contract.bats` still green.
- [ ] M1-M4 each mutation-proved red and restored, with the red pasted.
- [ ] shellcheck before/after counts pasted, zero new.
- [ ] `make test` and bare `pytest` green, summary lines pasted.
- [ ] `docs/guides/grafana-dashboards.md` updated in this commit.
- [ ] Pushed; `git rev-parse HEAD` and `git rev-parse origin/k3d-manager-v1.37.0` print the same SHA.

Commit message, verbatim:

```
fix(observability): correct the Pushgateway service name so deployment metrics land

_hostinger_refresh_access_layer probed for a service named "pushgateway" while
_deploy_pushgateway_acg installs the helm release as "prometheus-pushgateway". The
probe always failed, so the else branch rm -f'd the port-forward LaunchAgent on
every access-layer refresh. Nothing listened on localhost:9091, every webhook
metric push exhausted its retries against a closed socket, and the k3dm Deployment
Metrics dashboard held zero series while the Pushgateway pod, its scrape target and
the retry logic were all healthy.

Bind the service name to one local so it cannot drift from bin/cluster-up again, and
add a cross-file agreement test — the drift, not the typo, is the reusable defect.

_provider_supports_pushgateway was inverted: it returned False for k3s-hostinger,
the only provider that has a Pushgateway, and True for the hub, which has none. That
is why a dead sink produced no operator signal for 64 days. Gate on the hub instead,
and stop cluster-status-summary treating a failed Pushgateway probe as optional.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## What NOT to do

- Do NOT create a pull request. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify` or otherwise skip the pre-commit hooks.
- Do NOT modify `bin/cluster-up:1890` — it is already correct.
- Do NOT add a Pushgateway to the hub, and do NOT repoint the dashboard datasource.
- Do NOT touch the live cluster: no `kubectl`, `helm`, `docker`, `launchctl`, `make up`,
  `make refresh`, `make refresh-registration`, or ApplicationSet reapply. The agent is already
  loaded on the host by the operator. Code, tests and docs only.
- Do NOT start the Checkout Load Test work or duplicate its spec.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — subtrees, fixed upstream.
- Do NOT delete, move or rename any file outside the target list, for any reason, including a
  hygiene or scope check. `scratchpad/` is untracked and is the operator's. A previous run deleted
  an untracked spec file it judged to be test-generated; it was not, and the work had to be
  rebuilt from a log. If a check flags something, leave it and report it.
