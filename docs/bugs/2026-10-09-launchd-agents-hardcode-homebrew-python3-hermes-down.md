# Bug: a Homebrew upgrade removed `/opt/homebrew/bin/python3`; Hermes stopped and nothing alerted

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `625b44a7` 2026-10-09 (Codex via worktree dispatch; Claude verified 8 BATS + 64 pytest, both mutations red, landed with `land --test`). Claude found after landing that running `scripts/tests/hermes/` pushed a REAL `k3dm_hermes_last_tick_timestamp_seconds` to the hub Pushgateway (the timestamp moved while Hermes was not running), which would make a dead Hermes look alive to HermesNotRunning. Fixed in the test conftest: every Pushgateway URL points at 127.0.0.1:9. Hermes was recovered first by the operator (brew install python@3.14 + symlink + kickstart). Operator follow-up: re-render the three plists from the templates, then remove the symlink. HermesNotRunning goes live with the next platform-ops sync.
**Priority:** P1 — Hermes (sensors, triage, index refresh) has been down since 18:42 with no workaround short of fixing the path; the webhook and cloud-bridge fail on their next restart
**Severity:** high
**Origin:** operator, 2026-10-09: "the documents you created are not indexed". The index had not changed since 18:22.

## Symptom

- `launchctl print gui/$UID/com.k3d-manager.hermes`: `state = spawn scheduled`, `last exit code = 78: EX_CONFIG`. The last Hermes log line is at 18:41:58, and the last Pushgateway push from `k3dm-vectordb-index` at 18:21.
- `/opt/homebrew/bin/python3` does not exist. A Homebrew upgrade at 18:47 (`awscli`, pulling in `python@3.14` 3.14.8_2) left only the versioned `python3.14` link in `/opt/homebrew/bin`. Only `python@3.14` remains in the Cellar. The `cpython-313` caches in `bin/__pycache__` show the agents ran on 3.13 until then.
- All three LaunchAgent templates run that exact path:
  - `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`
  - `scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl`
  - `scripts/etc/launchd/com.k3d-manager.cloud-bridge.plist.tmpl`

  The webhook (pid 14776) and cloud-bridge (pid 14782) still run only because they started before the upgrade. The next `make restart-webhook`, reboot or crash takes Slack commands and the cloud bridge down too.
- **Nothing alerted.** The nearest rules, `VectorDBMetricsStale` (> 1 h + 15 m) and `HostDiskMetricsStale` (> 30 m + 30 m), only fire as side effects. Their names do not say that Hermes is down.

## Cause

- The templates name an **unversioned** interpreter path that Homebrew owns. Its target changes or disappears whenever the default Python changes.
- The Python behind it, python@3.13, was installed only as a dependency of other formulae (awscli and others). When they moved to python@3.14, Homebrew's cleanup removed 3.13. The operator ran that upgrade (2026-10-09). python@3.14 is in the same state now: `installed_on_request: false`, needed by awscli, azure-cli, gcloud-cli, ggshield, oci-cli, ollama, yamllint and others.
- Hermes is the watcher, and nothing watches Hermes.

## Immediate recovery (operator)

```
brew install python@3.14
ln -s ../opt/python@3.14/bin/python3.14 /opt/homebrew/bin/python3
launchctl kickstart gui/$(id -u)/com.k3d-manager.hermes
```

- `brew install` on a formula installed as a dependency marks it **installed on request**, so
  Homebrew never removes it as an orphan.
- The symlink gets the three agents running again with no plist change, until the fix below lands
  and they are re-rendered. Remove it afterwards.
- Hermes and the webhook use only the standard library and their own modules, so 3.14 runs them.
- Do **not** `brew pin python@3.14`. A pin blocks 3.14.x security patches, and it would not have
  stopped this: the failure was an orphan removal, not an upgrade. A versioned formula never moves
  to a new minor version by itself.

## Fix

1. **Pinned interpreter (operator decision 2026-10-09: pin the version).**
   - In all three `.plist.tmpl` files, replace `/opt/homebrew/bin/python3` with
     `/opt/homebrew/opt/python@3.14/bin/python3.14`. The `opt/` link survives 3.14.x patch upgrades,
     and the versioned formula never moves to 3.15 by itself. A move to a new minor version is a
     deliberate change to these templates.
   - Every installer that renders one of these templates (`make install-cloud-bridge`,
     `bin/k3dm-webhook-setup`) checks first that the interpreter exists and
     is executable. If it is missing, the installer prints `python@3.14 is not installed; run: brew
     install python@3.14` and exits 1, before writing or loading any plist.
2. **Hermes heartbeat.** At the end of every tick, success or failure, `bin/k3dm-hermes` pushes
   `k3dm_hermes_last_tick_timestamp_seconds` to the Pushgateway as job `k3dm-hermes`. Use the same
   Pushgateway URL and non-fatal push as the index metrics. A failed push never fails the tick.
3. **Alert `HermesNotRunning`.** In `scripts/etc/argocd/platform-ops/prometheusrule.yaml` (GitOps), in a
   new group `hermes.alerts`:
   - `expr: time() - k3dm_hermes_last_tick_timestamp_seconds > 900 or absent(k3dm_hermes_last_tick_timestamp_seconds)`
   - `for: 5m`, `severity: warning`, `cluster: hub`.
   - Description: Hermes runs every 300 s. Check `launchctl print gui/$UID/com.k3d-manager.hermes`
     for the last exit code and `~/Library/Logs/k3dm-hermes.log`. Exit 78 (EX_CONFIG) means launchd
     could not start the interpreter named in the plist.
   - Laptop sleep: Prometheus stops scraping while the M4 sleeps, so the alert cannot fire falsely
     during sleep. After wake, Hermes ticks within 300 s, inside `for: 5m` plus the 900 s threshold.
4. **Docs.** In `docs/guides/hermes.md`, the Hermes plist has no installer; its install steps are in the guide. Update those steps to the pinned interpreter. Add `HermesNotRunning`, what exit 78 means, and the recovery (`brew install python@3.14` plus `kickstart`). Add the same interpreter note to `docs/howto/webhook-operations.md`.

## Files

| File | Change |
|---|---|
| `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl` | item 1 |
| `scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl` | item 1 |
| `scripts/etc/launchd/com.k3d-manager.cloud-bridge.plist.tmpl` | item 1 |
| `bin/k3dm-hermes` | item 2 |
| `Makefile` | item 1 installer check (install-cloud-bridge) |
| `bin/k3dm-webhook-setup` | item 1 installer check |
| `scripts/etc/argocd/platform-ops/prometheusrule.yaml` | item 3 |
| `scripts/tests/bin/launchd_plist_path.bats` | tests 1, 2 and 5 |
| `scripts/tests/hermes/test_hermes.py` | test 3 |
| `scripts/tests/plugins/hermes_alert_rules.bats` | new: test 4 |
| `docs/guides/hermes.md` | item 4 |
| `docs/howto/webhook-operations.md` | item 4 |

## Tests

1. No template under `scripts/etc/launchd/` names `/opt/homebrew/bin/python3`.
2. Every template whose first program argument is a Python interpreter names
   `/opt/homebrew/opt/python@3.14/bin/python3.14`.
5. `make install-cloud-bridge` with the interpreter path pointed at a missing file (override the
   path through a test variable) exits 1 with the `brew install python@3.14` message, and writes no
   plist.
3. A tick whose sensors raise still pushes `k3dm_hermes_last_tick_timestamp_seconds` with job
   `k3dm-hermes`, and a Pushgateway that refuses the push does not fail the tick. Stub the opener;
   never reach a real Pushgateway.
4. `HermesNotRunning` exists, its expression names `k3dm_hermes_last_tick_timestamp_seconds` with
   `> 900` and `absent(`, and its severity is `warning`.

Mutation checks. Paste the red output for each:
- Put `/opt/homebrew/bin/python3` back in the hermes template. Test 1 must fail.
- Move the heartbeat push inside the success path. Test 3 must fail.

## Rules

- `bats scripts/tests/bin/launchd_plist_path.bats scripts/tests/plugins/hermes_alert_rules.bats` and
  bare `pytest scripts/tests/hermes/test_hermes.py`: green.
- Every function stays at 8 `if`s or fewer.
- Do not commit. `.git` is read-only in the sandbox.

## After landing (operator)

- Re-render and reload the three agents from the templates: `make install-cloud-bridge`,
  `bin/k3dm-webhook-setup`, and the Hermes plist from `docs/guides/hermes.md`. These are launchd changes and the
  operator's to run.
- The alert goes live with the next `platform-ops` sync.
