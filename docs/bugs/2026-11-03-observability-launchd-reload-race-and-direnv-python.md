# Bug: observability LaunchAgent installs race launchd bootout/bootstrap and embed ephemeral direnv python3 paths

**Status:** LIVE-VERIFIED 2026-11-07 — Claude read the M5 agents (see `## Live verification (Claude, M5, 2026-11-07)`). Was: VERIFIED — restated 2026-11-07 by Claude, verification already recorded below; was: Fixed & Verified (`fadbfb80`; live-verified on `m5-air.local` via Slack job `0d15432a` on `2026-11-03`)
**Priority:** P1
**Fix commit:** `fadbfb80`
**Live evidence:** 2026-11-07 · run claude-m5-launchctl-read · env hub · scenario observability-agents-loaded-no-direnv-python · commit fadbfb80 · proves fix
**Severity:** high — `make up` aborts at Step 14/14 (`exit 5`) or leaves `com.k3d-manager.alertmanager-port-forward` unloaded (`HTTP 502` on Alertmanager login) when reloading a running LaunchAgent; running from a `direnv` shell writes a `.cache/direnv/layouts/...` Python path into LaunchAgent plists
**Filed:** 2026-11-03
**Detected by:** M5 live verification (`2026-11-03 19:02:02 PST` unified log & Slack job `4a9b212c`)
**Branch:** `k3d-manager-v1.43.14`
**Approval:** Operator requested filing proper bug specs and dispatching to Luna on `2026-11-03`
**Related:** `docs/bugs/2026-10-31-hub-port-forward-reload-race-and-hub-migrate-entrypoint.md`

## Evidence

On `2026-11-03` on `m5-air.local`, two live `make up CLUSTER_PROVIDER=k3s-aws` runs exposed a `launchctl bootout` → `launchctl bootstrap` teardown race and a `direnv` Python path leak in `scripts/plugins/observability.sh`:

1. **Interactive terminal run (`19:02:02.915–19:02:02.920 PST` on `m5-air.local`):**
   - At Step 14/14 (`observability_deploy_all` -> `_observability_install_alertmanager_port_forward` in `scripts/plugins/observability.sh:255-256`), the script ran:
     ```bash
     launchctl bootout "gui/$(id -u)/com.k3d-manager.alertmanager-port-forward" 2>/dev/null || true
     launchctl bootstrap "gui/$(id -u)" "${_plist}"
     ```
   - `m5-air.local` unified log (`/usr/bin/log show --info --start "2026-11-03 19:01:55" --end "2026-11-03 19:02:20"`):
     ```text
     2026-11-03 19:02:02.915 Df launchctl[85797:e0d58f] [com.apple.xpc.launchctl:All] launchctl bootout: <private>
     2026-11-03 19:02:02.915 Df launchd[1:e0ced7] [gui/501/com.k3d-manager.alertmanager-port-forward [57952]:] signaled service: Terminated: 15
     2026-11-03 19:02:02.915 Df launchd[1:e0ced7] [gui/501/com.k3d-manager.alertmanager-port-forward [57952]:] service state: SIGTERMed
     2026-11-03 19:02:02.915 Df launchd[1:e0ced7] [gui/501/com.k3d-manager.alertmanager-port-forward [57952]:] scheduling cleanup in 5 sec after sending Terminated: 15
     2026-11-03 19:02:02.920 Df launchctl[85799:e0d594] [com.apple.xpc.launchctl:All] launchctl bootstrap: <private>
     2026-11-03 19:02:02.920 Df launchd[1:e0b9af] [gui/501 [100024]:] Bootstrap by launchctl[85799] for <private> failed (37: Operation already in progress)
     2026-11-03 19:02:02.920 Df launchd[1:e0b6cf] [gui/501/com.k3d-manager.alertmanager-port-forward [57952]:] exited due to SIGTERM | sent by kubectl[57952], ran for 3381993ms
     2026-11-03 19:02:02.920 Df launchd[1:e0b6cf] [gui/501 [100024]:] removing service: com.k3d-manager.alertmanager-port-forward
     ```
   - Under `bin/cluster-up` (`set -e`), `launchctl bootstrap` returning exit `5` (`Bootstrap failed: 5: Input/output error`) aborted the run at Step 14/14.
2. **Slack webhook run (`job 4a9b212c` on `m5-air.local`):**
   - Step 14/14 inside `bin/cluster-up` succeeded because the prior failed run had left `com.k3d-manager.alertmanager-port-forward` unloaded.
   - Seconds later, `Makefile`'s `up` recipe invoked `./scripts/k3d-manager deploy_observability --confirm`, which called `_observability_install_alertmanager_port_forward` a second time while `com.k3d-manager.alertmanager-port-forward` was running.
   - `webhook-jobs/4a9b212c/output` logged:
     ```text
     INFO: [observability] Alertmanager login credentials ready (/Users/cliang/.local/share/k3d-manager/alertmanager-basic-auth.env)
     Bootstrap failed: 5: Input/output error
     Try re-running the command as root for richer errors.
     INFO: [observability] Alertmanager port-forward agent installed — raw backend stays open on port 19093
     ```
   - Because `./scripts/k3d-manager` does not run with `set -e`, `_observability_install_alertmanager_port_forward` ignored exit `5` and left `com.k3d-manager.alertmanager-port-forward` unloaded (`:19093` closed), causing the post-provision smoke test to fail with `Alertmanager login: ❌ admin via ~/.local/share/k3d-manager/alertmanager-basic-auth.env: HTTP 502`.
3. **Ephemeral `direnv` `python3` path in LaunchAgent plists (`19:02:08.379 PST` on `m5-air.local`):**
   - `scripts/plugins/observability.sh:501,535` (and `Makefile:726`) substitute `{{PYTHON3_PATH}}` with `$(command -v python3)`. When run from an interactive terminal with `direnv` active, `backgroundtaskmanagementd` logged:
     ```text
     2026-11-03 19:02:08.379 E backgroundtaskmanagementd[747:e0d601] Immediate resolution failed for file:///Users/cliang/Library/LaunchAgents/com.k3d-manager.alertmanager-auth-proxy.plist executable path /Users/cliang/.cache/direnv/layouts/71281905981fbf9ad2262f01f7003323cfbb34ce  --Users-cliang-src-gitrepo-personal/python-3.15/bin/python3
     ```

## Files

- `scripts/plugins/observability.sh`
- `Makefile`
- `scripts/tests/lib/observability.bats`
- `CHANGELOG.md`

## Fix scope

1. **`scripts/plugins/observability.sh`:**
   - Add helper `function _observability_python3_path()`:
     - If `[[ -n "${K3DM_PYTHON3_PATH:-}" && -x "${K3DM_PYTHON3_PATH}" ]]`, print `"${K3DM_PYTHON3_PATH}"` and return `0`.
     - Otherwise iterate `_candidate` over `/opt/homebrew/opt/python@3.14/bin/python3.14`, `/opt/homebrew/bin/python3`, `/usr/local/bin/python3`, `/usr/bin/python3`; for the first executable candidate (`[[ -x "${_candidate}" ]]`), print it and return `0`.
     - Otherwise fall back to `command -v python3`.
   - Add helper `function _observability_launchd_reload()`:
     - Take `local _label="$1" _plist="$2"`.
     - Set `local _domain="gui/$(id -u)"`, `local _tries="${K3DM_LAUNCHD_BOOTSTRAP_TRIES:-10}"`, `local _wait="${K3DM_LAUNCHD_BOOTSTRAP_WAIT:-0.5}"`, `local _attempt _rc=0`.
     - Run `launchctl bootout "${_domain}/${_label}" 2>/dev/null || true`.
     - Loop `for (( _attempt = 1; _attempt <= _tries; _attempt++ ))`:
       - If `launchctl bootstrap "${_domain}" "${_plist}"`, return `0`.
       - Record `_rc=$?`.
       - If `(( _attempt < _tries ))`, run `sleep "${_wait}"`.
     - If all attempts fail, call `_err "[observability] Failed to bootstrap ${_label} after ${_tries} attempts (exit ${_rc})"` (so failure is never silently ignored when `set -e` is off).
   - Update all four LaunchAgent install functions in `scripts/plugins/observability.sh` to use `_observability_launchd_reload` instead of raw `launchctl bootout` + `launchctl bootstrap`:
     - `_observability_install_prometheus_credential_rotator`: call `_observability_launchd_reload "com.k3d-manager.prometheus-credential-rotator" "${_plist}"` inside the `if [[ "${K3DM_AGENT_LOAD:-1}" != 0 ]]; then` block.
     - `_observability_install_alertmanager_port_forward`: call `_observability_launchd_reload "com.k3d-manager.alertmanager-port-forward" "${_plist}"`.
     - `_observability_install_alertmanager_auth_proxy`: replace `$(command -v python3)` with `$(_observability_python3_path)` and call `_observability_launchd_reload "com.k3d-manager.alertmanager-auth-proxy" "${_plist}"`.
     - `_observability_install_prometheus_auth_proxy`: replace `$(command -v python3)` with `$(_observability_python3_path)` and call `_observability_launchd_reload "com.k3d-manager.prometheus-auth-proxy" "${_plist}"`.
2. **`Makefile`:**
   - In `install-alertmanager-auth-proxy` (`Makefile:724-736`), replace `$$(command -v python3)` with `$(K3DM_PYTHON3_PATH)` and replace the inline `launchctl bootout ...` + `launchctl bootstrap ...` lines with:
     `bin/launchd-reload com.k3d-manager.alertmanager-auth-proxy "$(HOME)/Library/LaunchAgents/com.k3d-manager.alertmanager-auth-proxy.plist"`
3. **`scripts/tests/lib/observability.bats`:**
   - Keep all existing tests intact and passing without weakening any assertion.
   - Append isolated BATS tests at the end of `scripts/tests/lib/observability.bats` covering `M1`–`M3` and `N1`–`N2` below (recording the `m5-air.local` `2026-11-03` capture comment beside the `launchctl` exit-code stub).
4. **`CHANGELOG.md`:**
   - Add a `Fixed` bullet under `## [1.43.14] - Unreleased` for retrying observability LaunchAgent `launchctl bootstrap` across `bootout` teardown and avoiding ephemeral `direnv` `python3` paths in auth-proxy plists.

## Acceptance

```yaml
must:
  - id: M1
    req: when launchctl bootstrap returns exit 5 on the first attempt after launchctl bootout (simulating launchd 37 Operation already in progress while SIGTERMed) and returns 0 on the second attempt, _observability_install_alertmanager_port_forward (and the other three observability LaunchAgent installers) retries bootstrap and succeeds with exit 0
  - id: M2
    req: _observability_install_alertmanager_auth_proxy and _observability_install_prometheus_auth_proxy substitute {{PYTHON3_PATH}} using K3DM_PYTHON3_PATH (when set and executable) or the system/Homebrew python3 rather than an ephemeral .cache/direnv/ path earlier in PATH
  - id: M3
    req: make -n install-alertmanager-auth-proxy renders {{PYTHON3_PATH}} from $(K3DM_PYTHON3_PATH) and reloads via bin/launchd-reload com.k3d-manager.alertmanager-auth-proxy
must_not:
  - id: N1
    req: when launchctl bootstrap fails on all K3DM_LAUNCHD_BOOTSTRAP_TRIES attempts, _observability_install_alertmanager_port_forward exits non-zero via _err and never logs "Alertmanager port-forward agent installed"
  - id: N2
    req: when PATH starts with a scratch .cache/direnv/layouts/test/bin/python3 executable, _observability_install_alertmanager_auth_proxy and _observability_install_prometheus_auth_proxy never write ".cache/direnv/" into the rendered LaunchAgent plist
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      Isolated BATS tests in scripts/tests/lib/observability.bats prove N1 and N2 fail (red) on pre-fix code and M1-M3 + N1-N2 pass (green) on fixed code with scratch HOME.
    what: env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/lib/observability.bats
```

## Rules

- Touch only the 4 files listed under `## Files`. Do not create or modify any other files, and do not touch `memory-bank/`.
- Do not run `git add`, `git commit`, or `git push`. Leave changes in the working tree.
- Never weaken, skip, or delete any existing test in `scripts/tests/lib/observability.bats`.
- Run and paste the output of:
  - `bats scripts/tests/lib/observability.bats`
  - `shellcheck -x -S warning scripts/plugins/observability.sh`
  - `git --no-pager diff --check`

## Live verification (Claude, M5, 2026-11-07)

The Acceptance has no live item; this records the deployed state on the hub, read over SSH (read-only).

- M5 checkout `8e483765` contains `fadbfb80` (committed 2026-11-03 19:41). The four plists in `~/Library/LaunchAgents`
  were rewritten 2026-11-03 20:59, after the fix.
- `alertmanager-auth-proxy` and `prometheus-auth-proxy`: `state = running`, `ProgramArguments[0]` is
  `/opt/homebrew/opt/python@3.14/bin/python3.14` (the first candidate of `_observability_python3_path`); no
  `.cache/direnv` string in either plist.
- `alertmanager-port-forward`: `state = running`. `http://127.0.0.1:9093/` answers 401 (auth proxy asks for a login), not 502.
- `prometheus-credential-rotator`: loaded, `runs = 0`. It runs on `StartCalendarInterval` day 1 00:00 and has not
  reached its first run; loaded means the bootstrap succeeded.
- The Status's earlier "live-verified via Slack job `0d15432a`" claim had no recorded output; this read replaces it.
