# Bug: Hermes alert_delivery probe runs a python3 without PyYAML on the M5

**Status:** OPEN — specced 2026-11-08, intents approved, dispatch to Luna
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-08
**Introduced by:** unknown
**Should have been caught by:** unknown
**Severity:** medium — Hermes cannot check whether Alertmanager can deliver alerts; workaround: run the probe by hand with the venv first on PATH
**Approval:** operator, 2026-11-08 ("sounds good, go ahead", on fixing this in v1.43.15)
**Intent approved:** operator, 2026-11-08
**Prior art:** `docs/bugs/2026-10-13-hermes-alert-delivery-probe-unknown-hides-error.md` (score not available: `make find-similar-docs` store unreachable from the M4) — read; same symptom, this spec fixes the cause proven on the M5; `docs/bugs/2026-11-06-machine-setup-leaves-nightly-suite-without-pyyaml.md` — read, created the venv reused here
**Filed:** 2026-11-08
**Detected by:** operator, Hermes Status dashboard, 2026-11-08
**Affected:** `bin/k3dm-alert-delivery-status`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

`alert_delivery` reads `unknown`, "alert delivery probe unavailable", on every Hermes poll.

## Root cause

Live proof, m5-air.local, 2026-11-08, operator-run, PyYAML 6.0.3 pin from `bin/k3dm-machine-setup:264`:

- With Hermes's plist PATH (`/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`) under `env -i`, the probe printed `ModuleNotFoundError: No module named 'yaml'`, then `{"available":false}`, rc 1.
- `/opt/homebrew/bin/python3` and `/usr/bin/python3` both fail `import yaml`.
- The same command with `$HOME/.local/share/k3d-manager/venv/bin` first on PATH printed `{"available": true, "clusters": [{"context": "k3d-k3d-cluster", "alertmanager": "kube-prometheus-stack-alertmanager", "config_ref": "alertmanager-smtp-secret", "config_ref_missing": false, ...`, rc 0.

Rejected, with the reason:
- Homebrew `pyyaml`: `brew info pyyaml` on the M4 (Homebrew 7.0.12), 2026-11-08: `No available formula with the name "pyyaml"`.
- Venv first on the Hermes plist PATH: neither render path fills `{{HOME}}` (`bin/k3dm-hermes-setup:43-45`; `_install_hermes_agent` in lib-foundation `scripts/lib/system.sh`), so it needs a lib change and a plist reinstall, and moves every `python3` child of Hermes to the venv.

## Fix

In `bin/k3dm-alert-delivery-status`, after the `ROOT=` line and before the first `python3` or `mapfile` use:

    venv_bin="${XDG_DATA_HOME:-$HOME/.local/share}/k3d-manager/venv/bin"
    if [[ -x "${venv_bin}/python3" ]]; then
      PATH="${venv_bin}:${PATH}"
    fi

An absent venv leaves the behaviour unchanged. Add no new failure path, no install step and no reason code (reason codes stay with the 2026-10-13 bug).

## Files

- `bin/k3dm-alert-delivery-status`
- `scripts/tests/bin/alert_delivery_status_python.bats` (new)

## Contract readers

The venv path, found with `git grep 'k3d-manager/venv'`:
- `bin/k3dm-machine-setup:256` creates it and installs PyYAML. Unchanged: already the owner.
- `scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl:20` puts it on the test agent's PATH. Unchanged: independent reader.
- `scripts/tests/bin/machine_setup.bats:350,970-998` fixtures. Unchanged.

Callers of the probe: `scripts/lib/hermes/sensors.py:664`, through `bin/k3dm-hermes:183`. Unchanged: stdout and exit code keep their meaning.

## Do not

- Change the Hermes plist template, lib-foundation, `bin/k3dm-machine-setup` or `sensors.py`.
- Replace `mapfile`: Homebrew bash is first on Hermes's PATH, and the live run passed line 8.
- Print any Secret content in a test or log.

## Acceptance

```yaml
must:
  - id: M1
    text: "with an executable python3 in XDG_DATA_HOME/k3d-manager/venv/bin, every python3 the probe runs is that one"
  - id: M2
    text: "with no venv, the probe runs the python3 found on PATH, as before (paired control for N1)"
  - id: M3
    text: "with XDG_DATA_HOME unset, the venv is looked up under HOME/.local/share"
must_not:
  - id: N1
    text: "with a usable venv, the python3 elsewhere on PATH is run (a recording stub on PATH records zero calls)"
  - id: N2
    text: "a venv python3 that exists but is not executable is put ahead on PATH or run (the PATH python3 is used instead)"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: "tests run the real probe against a stand-in cluster with a scratch home: when the project's Python environment is there the probe uses it, and when it is missing or unusable the probe uses the normal python3"
  - id: E2
    proves: [M1]
    kind: live
    intent: "after make hub-sync on the M5, the next Hermes poll reports alert_delivery as healthy or degraded with a stated reason, never 'probe unavailable', and the dashboard's Unknown sensors tile no longer counts it"
interface:
  - "bin/k3dm-alert-delivery-status --json, with HOME, XDG_DATA_HOME and PATH set by the caller, and kubectl and python3 resolved from PATH"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- E1 and E2 intents approved by the operator on 2026-11-08 ("approve both E1 and E2").
- Test stubs: the `kubectl` stub lists context `k3d-k3d-cluster` and returns an Alertmanager item named as in the live capture above (m5-air.local, 2026-11-08). Each fixture first asserts that HOME is the scratch directory.
- Delivery: this reaches Hermes through the M5 checkout (`make hub-sync`), not `make hub-promote`. No restart needed: Hermes starts a new process each poll.
- The other 2026-10-13 requirements (reason codes, dashboard text) stay open there.
