# Hermes correlator never re-pages once an incident latches; probe counts 401 as unhealthy

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** High — Hermes detected a total public-endpoint outage and sent nothing.

## Symptom

Grafana returned Cloudflare 502 for hours. The operator found it by hand, from a browser.
Hermes had been detecting it the whole time and never notified.

Every cycle in `/Users/cliang/Library/Logs/k3dm-hermes.log` shows two degraded sensors and
no event:

```json
{"sensor":"reachability","status":"degraded",
 "evidence":"single-service 4/7 hosts failing",
 "failed_hosts":["prometheus.3ai-talk.org","alertmanager.3ai-talk.org",
                 "grafana.3ai-talk.org","webhook.3ai-talk.org"]}
{"sensor":"kine","status":"degraded",
 "evidence":"state.db=2413629440B, slow_sql=898, compaction_recent=False"}
...
"event": null, "approvals": [], "pages": []
```

## Root cause — defect 1: the correlator is edge-triggered and latches forever

`scripts/lib/hermes/correlator.py`, `Correlator.process`:

```python
active = len(contributors) >= 2
was_active = state.get("incident_active", False)
if active and not was_active:
    state["incident_active"] = True
    ...return incident
```

An event is emitted **only** on the `False → True` transition of `incident_active`. The kine
compaction stall tripped that latch days ago (see
`docs/bugs/2026-09-09-hub-kine-compaction-stall.md`). From that moment the correlator is
permanently silent: when `reachability` went degraded and joined the incident, `was_active`
was already `True`, so the branch was skipped and `process` returned `None`.

The state is only cleared when the incident **fully** resolves. With a chronic contributor
that never resolves, every subsequent failure — of any severity, on any sensor — is absorbed
silently. The dedupe is correct in intent (don't re-page the same incident every 5 minutes)
but it dedupes on *incident existence* rather than on *incident content*.

## Root cause — defect 2: `bin/public-endpoint-probe` treats HTTP 401 as unhealthy

`bin/public-endpoint-probe`, sampling loop:

```bash
case "${_pep_code}" in
  2??|3??) _pep_host_ok[_pep_h_idx]=$((_pep_host_ok[_pep_h_idx] + 1)) ;;
esac
```

Only 2xx/3xx count. `prometheus`, `alertmanager` and `webhook` sit behind auth proxies that
correctly answer **401** to an unauthenticated probe. All three are permanently counted as
failing. Consequences:

- `reachability` is permanently degraded, so it is a standing contributor that helps keep
  `incident_active` latched — it is part of what causes defect 1 to bite.
- The verdict is skewed: three guaranteed-unhealthy hosts push a genuine single-service
  failure toward `edge-down`, which points the operator at the Cloudflare tunnel instead of
  the one broken backend. Observed this session: verdict `edge-down` while `argocd` returned
  200 and `keycloak` 302 to a direct curl seconds earlier.

A host answering 401 is **reachable** — the edge, the tunnel and the backend all worked. That
is what this probe measures.

## Non-issue, checked and deliberately not changed

`sensors.kine`'s `max_db_bytes` is 8 GiB against a live 2.4 GiB DB, so the size arm never
trips. This is **not** a defect here: the sensor correctly reported the stall through the
`slow_sql > 0 and not compacting` arm. Do not lower the threshold in this fix.

## Fix

### 1. `scripts/lib/hermes/correlator.py` — re-page when the contributor set grows

Track which sensors have been notified. While an incident is active, emit an `escalation`
event when a sensor joins that was not in the last notified set. Keep the set monotonic until
resolve so a flapping sensor cannot page repeatedly.

Replace the body of `process` from `active = ...` to the final `return None`:

```python
        active = len(contributors) >= 2
        was_active = state.get("incident_active", False)
        notified = state.get("incident_sensors", [])
        if active and not was_active:
            state["incident_active"] = True
            state["incident_sensors"] = contributors
            event = {"kind": "incident", "sensors": contributors,
                     "text": self._template(records, contributors, "incident")}
            return self._enrich(event, state, llm, today)
        if active and was_active:
            joined = [sensor for sensor in contributors if sensor not in notified]
            if not joined:
                return None
            state["incident_sensors"] = sorted(set(notified) | set(contributors))
            event = {"kind": "escalation", "sensors": contributors,
                     "text": self._template(records, contributors,
                                            f"escalation ({', '.join(joined)} joined)")}
            return self._enrich(event, state, llm, today)
        if not active and was_active:
            state["incident_active"] = False
            state["incident_sensors"] = []
            return {"kind": "resolved", "sensors": [], "text": "Hermes correlated incident resolved."}
        return None
```

`_template` needs no signature change — `kind` is already interpolated free-form.

### 1b. `bin/k3dm-hermes` — treat `escalation` as pageable

`_run_cycle` gates on `kind == "incident"` in two places. Both must accept `escalation`, or the
new event is emitted and then silently dropped. Line numbers are from `f661e72a`; match on the
code, not the number.

Line 138 — rotate the approval nonce for an escalation too:

```python
    if event and event["kind"] in ("incident", "escalation"):
        state["incident_nonce"] = secrets.token_hex(8)
```

Line 150 — attach pending repair proposals to an escalation too:

```python
    if event and event["kind"] in ("incident", "escalation") and proposals:
```

Leave line 140 (`kind == "resolved"`) alone. Leave the `automatic` Kine-guard fallback at line
148 alone — it synthesizes its own `incident` event when the correlator returned `None`, which
is still correct.

### 2. `bin/public-endpoint-probe` — 401/403 means reachable

```bash
case "${_pep_code}" in
  2??|3??|401|403) _pep_host_ok[_pep_h_idx]=$((_pep_host_ok[_pep_h_idx] + 1)) ;;
esac
```

Leave the reported `code` values untouched — the JSON and human output must still show the
real `401` so the operator sees what happened. Only the healthy/unhealthy tally changes.

Update the usage/comment block at the top (lines ~31–33, ~65–67) if it describes what counts
as healthy.

## Tests

Add to `scripts/tests/hermes/test_hermes.py`, alongside
`test_correlator_fire_silence_dedupe_resolved_and_unknown`:

```python
def test_correlator_re_pages_when_a_sensor_joins_an_active_incident():
    corr, state = Correlator(correlation_window=1), {}
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state)["kind"] == "incident"
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state) is None
    escalation = corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                               sensor("reachability", "degraded")], state)
    assert escalation["kind"] == "escalation"
    assert "reachability" in escalation["text"]
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                         sensor("reachability", "degraded")], state) is None
    assert corr.process([sensor("kine", "healthy"), sensor("eso", "healthy"),
                         sensor("reachability", "healthy")], state)["kind"] == "resolved"
    assert state["incident_sensors"] == []


def test_correlator_does_not_re_page_a_flapping_sensor_within_one_incident():
    corr, state = Correlator(correlation_window=1), {}
    corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state)
    corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                  sensor("reachability", "degraded")], state)
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state) is None
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                         sensor("reachability", "degraded")], state) is None
```

**There is no BATS suite for `bin/public-endpoint-probe`** — verified: no `.bats` file
references it. Do **not** create one for a one-line `case` change. Verify the probe instead by:

1. `shellcheck bin/public-endpoint-probe` — zero new warnings.
2. A read-only run against the live tunnel, which currently has three 401 hosts:
   `./bin/public-endpoint-probe --json`
   Paste the output. `prometheus.3ai-talk.org`, `alertmanager.3ai-talk.org` and
   `webhook.3ai-talk.org` must each still report code `401` **and** now be counted healthy
   (absent from the unhealthy host list). This run makes no changes.

Note the cluster's datastore is currently degraded, so the other four hosts may legitimately
report 502/503. Judge only the three 401 hosts.

## Definition of Done

- [ ] `scripts/lib/hermes/correlator.py` emits `escalation` as specified
- [ ] Both `kind == "incident"` gates in `bin/k3dm-hermes._run_cycle` accept `escalation`
- [ ] `bin/public-endpoint-probe` counts 401/403 as reachable, still reports the real code
- [ ] Both Python tests above pass: `python3 -m pytest scripts/tests/hermes/test_hermes.py`
- [ ] `shellcheck bin/public-endpoint-probe` — zero new warnings
- [ ] `./bin/public-endpoint-probe --json` output pasted, showing the three 401 hosts healthy
- [ ] `make test` green, or the failures shown to be pre-existing
- [ ] CHANGELOG `[Unreleased] → ### Fixed` entry
- [ ] Commit message exactly:
      `fix(hermes): re-page when a sensor joins an active incident; 401 is reachable`
- [ ] Pushed to `origin/k3d-manager-v1.36.0`, SHA reported
- [ ] `memory-bank/activeContext.md` + `progress.md` updated with the SHA

## What NOT to Do

- Do NOT create a PR
- Do NOT merge, and do NOT commit to `main`
- Do NOT use `--no-verify`
- Do NOT modify files outside: `scripts/lib/hermes/correlator.py`, `bin/k3dm-hermes`,
  `bin/public-endpoint-probe`, `scripts/tests/hermes/test_hermes.py`,
  `CHANGELOG.md`, `memory-bank/`
- Do NOT create a BATS suite for `bin/public-endpoint-probe`
- Do NOT lower `max_db_bytes` in `scripts/lib/hermes/sensors.py` — see "Non-issue" above
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees)
- Do NOT restart, patch or otherwise touch the live cluster, the port-forwards, cloudflared,
  or the running `com.k3d-manager.hermes` agent — this task is code + tests only
```
