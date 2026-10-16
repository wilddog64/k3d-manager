# Bug: `cluster-up` leaves a second, in-shell ACG TTL watcher writing into the operator's terminal (2026-10-16)

**Status:** OPEN — spec ready
**Priority:** P3 — cosmetic and redundant: the launchd watcher still extends the sandbox; the in-shell copy only prints into a terminal and runs a duplicate check
**Branch:** `k3d-manager-v1.43.3`
**Release:** v1.43.3
**Filed:** 2026-10-16, at operator request
**Approval:** explicit 2026-10-16 "yes please file a P3 bug under v1.43.3" (operator)
**Component:** `scripts/lib/providers/k3s-aws.sh` (`_k3s_aws_start_watcher`), `bin/cluster-up`
**Related:** `docs/bugs/v1.6.0-bugfix-acg-watch-disown.md` (same class: a disowned watcher still holding
the caller's stdout; that fix covered the webhook pipe, not a terminal),
`docs/bugs/2026-10-06-acg-watch-make-targets.md` (the launchd watcher and its make targets)

## Observed

After `make e2e-sandbox` exited with `Error 1` and the shell prompt was drawn, this appeared below
the prompt, so the terminal looked hung:

```text
INFO: [acg] Extending sandbox TTL...
INFO: [acg] Extending ACG sandbox TTL at https://app.pluralsight.com/hands-on/playground/cloud-sandboxes..
INFO: Connected via CDP to existing browser session.
INFO: Already on sandbox page: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Calculated remaining TTL: ~195 minutes
INFO: Extension window not open yet (195m remaining). Skipping extension.
```

Read-only checks on 2026-10-16:

- PID 89270, `bash bin/cluster-up <sandbox-url>`, parent 1, was 54 minutes old and was sleeping in
  `sleep 1800`. `~/.local/share/k3d-manager/acg-watch.pid` held 89270.
- `lsof` showed its fds 0, 1 and 2 all on `/dev/ttys003`, the operator's terminal.
- The launchd job `com.k3d-manager.acg-watch` was loaded at the same time, so two watchers were
  checking the same sandbox every 30 minutes.

The operator killed 89270 by hand.

## Root cause

1. **`deploy_cluster` starts an in-shell watcher.** `_k3s_aws_start_watcher`
   (`scripts/lib/providers/k3s-aws.sh`) runs `acg_watch &` and `disown`. `disown` only removes the
   job from the shell's job table; the child keeps the caller's stdin, stdout and stderr. Run from a
   terminal, it writes every pass into that terminal until the sandbox instance is gone.
2. **`cluster-up` then installs the launchd watcher anyway.** `bin/cluster-up` provisions through
   `deploy_cluster` (around line 443), which starts the in-shell watcher, and at Step 12/14 runs
   `acg_watch_start`, which installs `com.k3d-manager.acg-watch`. Nothing stops the first one, so
   every `cluster-up` leaves both running. When the extend window opens, both may try to extend in
   the same 30-minute span.

## Fix

Work only in k3d-manager. Do **not** edit `scripts/lib/foundation/` (`acg_watch`,
`acg_watch_start`, `_ACG_WATCH_*` live there and stay unchanged).

### 1. `_k3s_aws_start_watcher`: never write to the caller's terminal

Replace the start lines

```bash
    acg_watch &
    local _watcher_pid=$!
```

with

```bash
    mkdir -p "$(dirname "${_ACG_WATCH_PID_FILE}")"
    acg_watch </dev/null >>"$(dirname "${_ACG_WATCH_PID_FILE}")/acg-watch-shell.log" 2>&1 &
    local _watcher_pid=$!
```

and drop the later, now-duplicate `mkdir -p "$(dirname "${_ACG_WATCH_PID_FILE}")"`. Keep `disown`,
the PID file and every `_info` line.

### 2. `_k3s_aws_start_watcher`: skip when the launchd watcher is loaded

At the top of the function, after the first `_info`, add:

```bash
  if launchctl list "${_ACG_WATCH_LAUNCHD_LABEL}" >/dev/null 2>&1; then
    _info "[k3s-aws] launchd watcher ${_ACG_WATCH_LAUNCHD_LABEL} is loaded — skipping in-shell watcher"
    return 0
  fi
```

### 3. `bin/cluster-up`, Step 12/14: stop the in-shell watcher once launchd owns the job

Directly after `acg_watch_start "${sandbox_url:-${_ACG_SANDBOX_LIST_URL}}"`, stop an in-shell watcher
left by step 1 on a first run, when launchd was not loaded yet:

```bash
if [[ -f "${_ACG_WATCH_PID_FILE}" ]]; then
  _shell_watcher_pid=$(cat "${_ACG_WATCH_PID_FILE}")
  if [[ "${_shell_watcher_pid}" =~ ^[0-9]+$ ]] && kill -0 "${_shell_watcher_pid}" 2>/dev/null; then
    kill "${_shell_watcher_pid}" 2>/dev/null || true
    _info "[acg-up] Stopped in-shell TTL watcher ${_shell_watcher_pid}; launchd ${_ACG_WATCH_LAUNCHD_LABEL} owns it now"
  fi
  rm -f "${_ACG_WATCH_PID_FILE}"
fi
```

Only when `acg_watch_start` returned 0: if it failed, the in-shell watcher is the only one left and
must keep running. Match the surrounding error handling in `bin/cluster-up`.

### 4. Docs

- The guide or how-to that documents `make acg-watch` (find it with
  `grep -rln 'acg-watch' docs/guides docs/howto`): one short note that `cluster-up` relies on the
  launchd watcher, and that a provider-only `deploy_cluster` starts an in-shell fallback that logs
  to `~/.local/share/k3d-manager/acg-watch-shell.log`.
- `CHANGELOG.md` `[Unreleased]`: one `Fixed:` entry.

## Files

| File | Change |
|---|---|
| `scripts/lib/providers/k3s-aws.sh` | items 1–2 |
| `bin/cluster-up` | item 3 |
| `scripts/tests/lib/k3s_aws_provider.bats` | tests below |
| the `acg-watch` guide or how-to, `CHANGELOG.md` | item 4 |

No other file.

## Tests (each new one shown failing against the pre-change code, on a temp copy)

In `k3s_aws_provider.bats`, stub `acg_watch` (a short-lived function that prints a marker), `launchctl`
and `disown`; point `_ACG_WATCH_PID_FILE` into `$BATS_TEST_TMPDIR`. No real launchd, sandbox or browser.

1. With `launchctl list` failing (not loaded): the marker lands in `acg-watch-shell.log` beside the
   PID file and **not** in the function's captured stdout or stderr.
2. With `launchctl list` succeeding (loaded): `acg_watch` is never called, no PID file is written,
   and the skip message is printed.
3. The existing "already running" PID-file branch keeps its behaviour.
4. `bin/cluster-up` item 3: a source-level check is not enough. Extract the Step 12 block into a test
   harness, or assert behaviour with a stubbed `acg_watch_start` and a live `sleep` child as the
   recorded PID: rc 0 → the child is gone and the PID file removed; rc non-zero → the child survives.

### Mutations (Claude, at verification)

Each must turn a test red:

- drop the `>>…acg-watch-shell.log 2>&1` redirection;
- drop the launchd skip;
- kill the in-shell watcher even when `acg_watch_start` fails.

## Operational Requirements

| Item | Requirement |
|---|---|
| Resources | One fewer long-lived bash process per sandbox. One small append-only log file. |
| Rollback | Revert. No state outside the PID file and the new log. |
| Proof it works | The next `make up` (or `bin/cluster-up`) ends with exactly one watcher: `launchctl list com.k3d-manager.acg-watch` loaded, no live PID in `acg-watch.pid`, and no `[acg]` lines in the operator's terminal after the prompt returns. |

## Definition of Done

- [ ] Items 1–4 exactly as written; `shellcheck scripts/lib/providers/k3s-aws.sh bin/cluster-up`
  reports no new warning.
- [ ] `bats scripts/tests/lib/k3s_aws_provider.bats` green; paste the summary.
- [ ] Leave the changes **uncommitted**. Claude verifies, commits and lands them with:
  `fix(acg): keep the cluster-up TTL watcher out of the terminal and single-owned by launchd`

## What NOT to Do

- Do NOT touch `scripts/lib/foundation/`, the launchd plist, or `acg_watch` itself.
- Do NOT run `launchctl`, `bin/cluster-up`, `make up` or any live ACG, sandbox or browser command.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.
- Do NOT modify files outside the Files table, including `memory-bank/`.
