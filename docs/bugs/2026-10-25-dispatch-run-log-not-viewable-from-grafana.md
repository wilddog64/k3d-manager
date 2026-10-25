# Bug: Agent Dispatch Log column gives a local path, not a log you can open from Grafana

**Status:** FIXED 2026-10-25 — offline E1 green (pytest 109/109, BATS dashboard + port-forward green, ruff clean, validate-manifests 85/85; Luna's mutations of redaction, codex_exit exclusion, failed-push state guard and dashboard link red; Claude's two new tests red under mutation); live E2 pending
**Fix commit:** `fa0d780a`
**Review note:** Claude changed four things before landing. (1) The run directory keeps one `land-test.log` per slug, so shipping it under every run (and re-shipping on change, as F2 said) put a later attempt's log under an earlier run; only the latest run of a slug is shipped now. (2) Loki's default `max_entries_limit_per_query` is 5,000 and Grafana's Loki default is 1,000 lines, so the panel would have shown only the last 1,000; the panel asks for `maxLines` 5000 and the shipper keeps 4,998 lines plus a `[shipped <time> sha256:<prefix>]` header and the truncation notice. (3) The metrics script's call to the shipper now has a 300 s timeout. (4) `884062ef`'s path test assumed the temp dir is outside `$HOME`; the land runs pytest with a temp dir under it, so the test now sets `HOME`.
**Priority:** P3
**Severity:** low — the run log is reachable by copying a path into a terminal on the operator's Mac; it cannot be opened from the dashboard
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's review of panel 47 (screenshot 252)
**Approval:** explicit 2026-10-25 ("go ahead to do what you recommend", after Claude proposed shipping `land-test.log` only to the hub's Loki and linking the Log cell to it). Not critical (no hub workload changes; one new local port-forward agent and one dashboard).
**Component:** new `bin/k3dm-dispatch-logs`, `bin/k3dm-dispatch-metrics` (call site), `scripts/etc/launchd/com.k3d-manager.hub-loki-port-forward.plist.tmpl`, `Makefile`, `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (panel 47), new `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-run-log.yaml`
**Related:** `docs/bugs/2026-10-25-dispatch-run-evidence-column-names-a-file-you-cannot-open.md` (the Result and Log columns, `b63fe8da`; home-free paths `884062ef`)

## Problem

Panel 47 (Per run evidence) now shows each run's test result and a `~/…/<slug>.run/land-test.log` path.
To read the log the operator copies the path and runs `less` on the Mac. The dashboard cannot open it.

The hub already runs Loki (`monitoring/loki-gateway`, port 80, `auth_enabled: false`) with a Grafana
datasource `uid: loki`. Shipping the test log there gives a click-through behind the existing Grafana
login, with no new public exposure.

### What may be shipped

Claude scanned every run log on 2026-10-25 (counts only, no values printed):

- `land-test.log` (130 files, 418 KB): test output. No tokens, keys or webhook URLs; the home path in
  6 lines.
- `codex.log` (164 files, 89 MB): the agent's full transcript, including every file it read and every
  command it ran. Token-shaped strings in it were all test fixtures already in the repo, but a pattern
  scan cannot prove a transcript clean.

**Only `land-test.log` is shipped. `codex.log` and every other run file stay on the Mac.**

## Fix

### F1. Port-forward to the hub's Loki

New `scripts/etc/launchd/com.k3d-manager.hub-loki-port-forward.plist.tmpl`, modelled exactly on
`com.k3d-manager.hub-pushgateway-port-forward.plist.tmpl`:
`kubectl port-forward svc/loki-gateway 19100:80 -n monitoring --context k3d-k3d-cluster`.
New Makefile target `install-hub-loki-port-forward`, modelled on `install-hub-pushgateway-port-forward`.
Add it next to that target's call in `bin/hub-restore` (`_local_agents_ok=0` on failure, like its
neighbour).

### F2. `bin/k3dm-dispatch-logs`

A Python script (style of `bin/k3dm-orbstack-metrics`), always exits 0 unless `--strict`:

- Reads the dispatch ledger the same way `bin/k3dm-dispatch-metrics` does, and for every run row whose
  `evidence` is `land-test.log` or `land_refused.tests` takes
  `<worktree root>/<version>/<slug>.run/land-test.log`.
- Skips a log whose SHA-256 is already recorded for that `version`/`slug`/`run` in the state file
  `<worktree root>/dispatch-logs-shipped.json`; ships it again when the content changed.
- Before shipping, each line is:
  1. rewritten so the home directory reads `~` (same rule as `_display_path` in
     `bin/k3dm-dispatch-metrics`);
  2. passed through `redact()` from `scripts/lib/hermes/e2e_triage.py`, plus these patterns replaced by
     `<redacted>`: `hvs\.[A-Za-z0-9]{20,}`, `gh[pousr]_[A-Za-z0-9]{30,}`, `github_pat_[A-Za-z0-9_]{20,}`,
     `sk_(test|live)_[A-Za-z0-9]{10,}`, `xox[abpr]-[A-Za-z0-9-]{6,}`,
     `hooks\.slack\.com/services/\S+`, `AKIA[0-9A-Z]{16}`, `-----BEGIN [A-Z ]*PRIVATE KEY-----`;
  3. cut to 2,000 characters.
- Keeps the **last** 5,000 lines of a log (the summary is at the end) and prepends one line
  `[truncated: <n> earlier lines]` when it cut.
- Pushes one stream per run to `${K3DM_DISPATCH_LOKI_URL:-http://localhost:19100}/loki/api/v1/push`
  with labels exactly `job="k3dm-dispatch-run"`, `version`, `slug`, `run`. Entry timestamps are the
  push time in nanoseconds, incremented by 1 per line so order is kept.
- Records the SHA-256 only after Loki answers 2xx. A failed push is retried on the next run.
- `--dry-run` prints the streams it would push (labels and line counts, not the lines) and pushes
  nothing.

### F3. Run it after each metrics push

At the end of a successful, non-dry-run push in `bin/k3dm-dispatch-metrics`, run
`bin/k3dm-dispatch-logs` as a subprocess; ignore its exit code and output. Add `make dispatch-logs`
(`DRY_RUN=1` passes `--dry-run`).

### F4. Run log dashboard and link

- New dashboard `k3dm Agent Run Log` (uid `k3dm-agent-run-log`) in
  `grafana-dashboard-agent-run-log.yaml`, built like the other agent dashboards (same ConfigMap shape,
  labels and tag-based Agents link). Variables `version`, `slug`, `run` (textbox or query over
  `{job="k3dm-dispatch-run"}` label values). One logs panel, datasource `{"type":"loki","uid":"loki"}`,
  query `{job="k3dm-dispatch-run", version="$version", slug="$slug", run="$run"}`, sorted ascending,
  full width and height. Default time range `now-30d`.
- Panel 47: the **Log** column gets a data link titled `Open log`, URL
  `/d/k3dm-agent-run-log?var-version=${__data.fields.version}&var-slug=${__data.fields.slug}&var-run=${__data.fields.run}&from=now-30d&to=now`.
  Keep `custom.inspect` so the path can still be copied. No `file://` link.

### F5. Docs

`docs/guides/grafana-dashboards.md`, Agent Dispatch Per run: the Log link, what is shipped (test log
only, redacted, last 5,000 lines), what is never shipped (`codex.log`), and that `make
install-hub-loki-port-forward` must have been run once. Add the run log dashboard to the dashboards
list.

## Tests

`scripts/tests/bin/test_dispatch_logs.py` (new). Point `K3DM_DISPATCH_LOKI_URL` at an in-process
`http.server` on `127.0.0.1` that records request bodies, or at `http://127.0.0.1:9` for the
unreachable case; set `HOME` and `K3DM_WORKTREE_ROOT` under `tmp_path`:

1. An accepted run with a `land-test.log` is pushed once with labels exactly `job`, `version`, `slug`,
   `run`; a second invocation pushes nothing.
2. Changing the log's content pushes it again.
3. A log containing each redaction pattern above and a `$HOME` path: the pushed body contains none of
   the planted values and no `tmp_path` home string; it contains `<redacted>` and `~/`.
4. A 6,000-line log: 5,001 lines pushed, the first is the truncation notice, the last is the log's
   last line.
5. A `codex.log` beside the `land-test.log` with a planted marker string: the marker is never in any
   pushed body; a run whose evidence is `codex_exit.exit` pushes nothing.
6. Loki unreachable: exit 0, no state recorded; the next invocation against a working server pushes.
7. Loki answering 500: no state recorded.
8. `--dry-run` sends no request.
9. `bin/k3dm-dispatch-metrics` without `--dry-run` runs the log shipper once (stub via an env override
   or monkeypatch of the subprocess call); with `--dry-run` it does not.

`scripts/tests/plugins/agent_dispatch_dashboard.bats`:

10. Panel 47's `Log` override has a link to `/d/k3dm-agent-run-log` carrying `var-version`, `var-slug`
    and `var-run` from `__data.fields`, keeps `custom.inspect`, and the dashboard has no `file://`.
11. The run log dashboard exists with uid `k3dm-agent-run-log`, a logs panel on datasource uid `loki`
    whose query selects `job="k3dm-dispatch-run"` and the three variables.

`scripts/tests/plugins/hub_pushgateway.bats` or a new `scripts/tests/plugins/hub_loki_port_forward.bats`:

12. The plist template port-forwards `svc/loki-gateway` `19100:80` in `monitoring`; the Makefile target
    renders and bootstraps it; `bin/hub-restore` calls it.

Existing suites stay green: `test_dispatch_metrics.py`, `agent_dispatch_dashboard.bats`, the agent
dashboards panel-id and link tests, `hub_restore.bats`, `cluster_down.bats`.

## Files

- `bin/k3dm-dispatch-logs` (new)
- `bin/k3dm-dispatch-metrics`
- `bin/hub-restore`
- `Makefile`
- `scripts/etc/launchd/com.k3d-manager.hub-loki-port-forward.plist.tmpl` (new)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-run-log.yaml` (new)
- `scripts/tests/bin/test_dispatch_logs.py` (new)
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `scripts/tests/plugins/hub_loki_port_forward.bats` (new) or `scripts/tests/plugins/hub_pushgateway.bats`
- `scripts/tests/bin/hub_restore.bats` (only if its stubs must learn the new target)
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every run whose evidence is land-test.log or land_refused.tests has its land-test.log pushed to Loki once per distinct content, as one stream labelled job, version, slug and run.
  - id: M2
    text: Shipped lines have the home directory as ~, known credential patterns replaced by <redacted>, each line at most 2,000 characters, and at most the last 5,000 lines with a truncation notice.
  - id: M3
    text: The Log cell in Per run evidence links to a Grafana run-log dashboard showing that run's stream; the path stays copyable.
  - id: M4
    text: make install-hub-loki-port-forward installs a launchd port-forward to monitoring/loki-gateway on 19100, and hub-restore installs it.
  - id: M5
    text: The guide says what is shipped, what is never shipped, and how to open a run log.
must_not:
  - id: N1
    text: codex.log, or any run file other than land-test.log, is never read for shipping or sent.
  - id: N2
    text: An unreachable or failing Loki never fails the metrics run and never marks a log as shipped.
  - id: N3
    text: No file:// link, no new public endpoint, no change to hub workloads or Loki configuration.
  - id: N4
    text: Tests never push to the real Loki or Pushgateway.
  - id: N5
    text: A shipped body never contains the operator's home path or a planted credential value.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4, N5]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 K3DM_DISPATCH_LOKI_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_logs.py scripts/tests/bin/test_dispatch_metrics.py; bats on the dashboard and port-forward suites; tests 3, 5, 6 and 10 red on a temp copy of the pre-fix files (or with the redaction / codex filter / state guard mutated out); ruff clean; shellcheck clean on bin/hub-restore; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M1, M3, M4]
    text: The operator runs make install-hub-loki-port-forward and make dispatch-metrics; Claude runs make dispatch-logs DRY_RUN=1; the operator clicks a Log cell at Window v1.43.7 and the run log dashboard shows that run's test output ending in its summary line.
interface:
  - bin/k3dm-dispatch-logs [--dry-run] [--strict] (env K3DM_DISPATCH_LOKI_URL, K3DM_WORKTREE_ROOT, HOME)
  - make dispatch-logs [DRY_RUN=1]
  - make install-hub-loki-port-forward
  - Loki stream {job="k3dm-dispatch-run", version, slug, run}
  - Grafana /d/k3dm-agent-run-log?var-version&var-slug&var-run
  - Grafana /d/k3dm-agent-dispatch panel 47, Log column link
```

## Definition of Done

- [ ] F1–F5 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries and the red results.
- [ ] Commit: `fix(dispatch): open each run's test log from the Per run Log column`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT read, parse or send `codex.log` or any run file other than `land-test.log`.
- Do NOT run `make install-hub-loki-port-forward`, `launchctl`, or push to the real Loki or Pushgateway;
  tests use stubs and `127.0.0.1`.
- Do NOT change Loki's Helm values, the Grafana datasource, or any hub workload.
- Do NOT change or remove existing tests or assertions, except where this spec changes the behaviour.
- Do NOT modify `scripts/lib/foundation/` or files outside the Files list.
