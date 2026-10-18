# Bug: cluster-up leaves an older in-shell ACG watcher running when launchd owns the watcher

**Status:** OPEN — fix specified 2026-10-18, dispatched to Codex
**Priority:** P3
**Filed:** 2026-10-16
**Detected by:** Claude, live check of `docs/bugs/2026-10-16-cluster-up-shell-acg-watcher-writes-to-terminal.md`
**Affected:** `scripts/lib/providers/k3s-aws.sh` `_k3s_aws_start_watcher`
**Branch:** `k3d-manager-v1.43.4`
**Approval:** approved — operator, 2026-10-18: "others please dispatch to codex" (v1.43.4 bug)

## Problem

When `com.k3d-manager.acg-watch` is loaded, `_k3s_aws_start_watcher` returns before it reads
`acg-watch.pid`. If an earlier run left an in-shell watcher alive, two watchers run: launchd's
and the old shell one, and the old one keeps writing `[acg]` lines into the terminal that ran it.

Seen 2026-10-16: PID 89270 (`bash bin/cluster-up`, started 06:01 local by a `make up` before
`ca6b59ce`) was still alive after two post-fix `make up` runs. Each run logged "skipping
in-shell watcher". The operator stopped it by hand with `kill 89270`.

This recurs whenever launchd's watcher is reloaded while a shell watcher is alive (the operator
ran `launchctl unload` earlier the same day), so it is not only a one-time migration.

## Fix

`scripts/lib/providers/k3s-aws.sh`, `_k3s_aws_start_watcher`. Replace the launchd branch:

```bash
  if launchctl list "${_ACG_WATCH_LAUNCHD_LABEL}" >/dev/null 2>&1; then
    _info "[k3s-aws] launchd watcher ${_ACG_WATCH_LAUNCHD_LABEL} is loaded — skipping in-shell watcher"
    return 0
  fi
```

with:

```bash
  if launchctl list "${_ACG_WATCH_LAUNCHD_LABEL}" >/dev/null 2>&1; then
    _info "[k3s-aws] launchd watcher ${_ACG_WATCH_LAUNCHD_LABEL} is loaded — skipping in-shell watcher"
    _k3s_aws_retire_shell_watcher
    return 0
  fi
```

and add, directly above `_k3s_aws_start_watcher`:

```bash
function _k3s_aws_retire_shell_watcher() {
  [[ -f "${_ACG_WATCH_PID_FILE}" ]] || return 0
  local _old_pid _cmd _i
  _old_pid=$(cat "${_ACG_WATCH_PID_FILE}")
  if [[ "${_old_pid}" =~ ^[0-9]+$ ]] && kill -0 "${_old_pid}" 2>/dev/null; then
    _cmd=$(ps -o command= -p "${_old_pid}" 2>/dev/null || true)
    if [[ "${_cmd}" == *cluster-up* || "${_cmd}" == *k3d-manager* ]]; then
      kill "${_old_pid}" 2>/dev/null || true
      for _i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "${_old_pid}" 2>/dev/null || break
        sleep 0.5
      done
      if kill -0 "${_old_pid}" 2>/dev/null; then
        _warn "[k3s-aws] stale in-shell watcher PID ${_old_pid} did not exit — leaving ${_ACG_WATCH_PID_FILE}"
        return 0
      fi
      _info "[k3s-aws] stopped stale in-shell watcher PID ${_old_pid} (launchd owns the watcher)"
    else
      _warn "[k3s-aws] ${_ACG_WATCH_PID_FILE} names PID ${_old_pid}, which is not a k3d-manager watcher — not killing it"
    fi
  fi
  rm -f "${_ACG_WATCH_PID_FILE}"
}
```

The command-line check guards against PID reuse: the file can outlive its process, and the PID
may now belong to something unrelated. The watcher is a backgrounded subshell, so its command line
is the parent's (`bash bin/cluster-up` in the 2026-10-16 sighting, or the `k3d-manager`
dispatcher). Tests may stub `ps`, `kill` and `sleep` as shell functions.

## Acceptance

```yaml
must:
  - id: M1
    text: With launchd loaded and the PID file naming a live process whose command line contains cluster-up, _k3s_aws_start_watcher kills it, waits for it to exit, removes the PID file, logs "stopped stale in-shell watcher", and returns 0.
  - id: M2
    text: With launchd loaded and the PID file naming a dead PID, the file is removed, nothing is killed, and the function returns 0.
  - id: M3
    text: With launchd loaded and no PID file, behaviour is unchanged (skip log line, no file created, acg_watch never runs).
must_not:
  - id: N1
    text: With launchd loaded and a live stale shell watcher, the function must not return leaving that process alive and the PID file in place (red on pre-fix).
  - id: N2
    text: A live PID whose command line is not a k3d-manager watcher (e.g. "sleep 300") must never be killed; the file is still removed and a warning logged.
  - id: N3
    text: The no-launchd branch (start, already-running, dead-PID restart) behaves exactly as before; all existing k3s_aws_provider.bats tests stay green.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: bats scripts/tests/lib/k3s_aws_provider.bats; N1 shown red against the pre-fix k3s-aws.sh copied from git show into a temp directory; shellcheck scripts/lib/providers/k3s-aws.sh clean.
  - id: E2
    proves: [M1]
    kind: live
    text: Operator's next make up with a stale shell watcher present logs the stop line; ps shows only launchd's watcher; the PID file is gone.
interface:
  - scripts/lib/providers/k3s-aws.sh _k3s_aws_start_watcher (inputs _ACG_WATCH_PID_FILE, _ACG_WATCH_LAUNCHD_LABEL; launchctl, kill, ps)
```

## Definition of Done

- [ ] Files: `scripts/lib/providers/k3s-aws.sh`, `scripts/tests/lib/k3s_aws_provider.bats` — nothing else.
- [ ] E1 green; N1 red on the pre-fix file, output pasted. Tests use a real background `sleep` (or a stub) — never a real watcher, never `$$`.
- [ ] Commit message verbatim: `fix(k3s-aws): retire a stale in-shell ACG watcher when launchd owns the watcher`
- [ ] Pushed to `origin/k3d-manager-v1.43.4`; memory-bank updated with the SHA.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`. Do NOT use `--no-verify`.
- Do NOT touch launchd, real watchers, AWS, or any cluster. Do NOT modify `scripts/lib/foundation/`.
- Do NOT kill by name (`pkill`); only the PID in the file, after the command-line check.
