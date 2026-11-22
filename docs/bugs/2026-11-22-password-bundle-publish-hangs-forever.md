# Bug: password-bundle publish can hang forever and silently stop every later run

**Status:** OPEN — filed 2026-11-22
**Priority:** P2
**Introduced by:** ddd9329e (travel bundle, v1.45.0 plan 2)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-22
**Prior art:** `docs/bugs/2026-11-22-test-all-failures-not-attributable-to-host.md` (slug grep, not scored) — read, different root cause; `make find-similar-docs` not run (vector store unreachable from m4-air).
**Approval:** operator, 2026-11-22: "go ahead to file a P2 bug then dispatch to Luna" (dispatch without waiting for triage); Fable spec review requested by the operator, folded in (rev 2).
**Intent approved:** operator, 2026-11-22
Intents approved for rev 2, E1-E6 ("Approve, dispatch + investigate").

## Symptom

PasswordBundleStale fired on the hub (cluster=hub, reason=stale) on 2026-11-22. Operator capture on m5-air:

- `launchctl list` showed `88191  0  com.k3d-manager.password-bundle`: a PID, so a run was **still in progress**, and
  last exit status 0.
- `~/Library/Logs/k3dm-password-bundle.log` was last written Nov 22 02:01; it held only `running under bash` start lines.
- A manual `make password-bundle-publish` in the operator's Terminal succeeded at once.

launchd never starts a StartInterval job while the previous run is alive. The 02:01 run hung, so every 15-minute run
after it was skipped, and the stale alert (no successful publish for 2 h) fired. A hang reports no failure, so the
`PasswordBundleStale` `reason=publish_failed` rule never fires.

## Root cause

### Where it hangs (live, m5-air, 2026-11-22 04:39-04:41, read-only capture by Claude via the operator's tmux pane)

`launchctl kickstart -k` killed 88191 (last exit -15) and started PID 7460, which hung at once:

- Process tree: `bash 7460` → `bash 7521` → `git 7524`, all state S, over 1:38 elapsed.
- `git 7524` is `git -C "$HOME/Library/Mobile Documents/com~apple~CloudDocs/k3dm/password-bundle" rev-parse --is-inside-work-tree`
  (`scripts/plugins/password_bundle.sh:141`), Homebrew git 2.56.1, cwd the iCloud delivery folder.
- `sample 7524`: `cmd_rev_parse` → `setup_git_directory_gently` → `strbuf_getcwd` → `__getcwd` → `open$NOCANCEL`
  (blocked in the kernel).

The same line returns at once from the operator's Terminal. When launchd runs the job, opening paths in iCloud Drive
blocks in the kernel. Why (a missing privacy grant for the launchd-run bash, or the iCloud file provider stalled) is not
yet known. Runs before 02:01 succeeded, so something changed around then.

### Why nothing recovers

Nothing in the publish path is time-limited:

- The iCloud steps in `password_bundle_publish`: `mkdir -p "$PB_DIR"` (140), `git -C "$PB_DIR"` (141), `mktemp` (148-149),
  both `mv` (155-156).
- `make -s show-service-passwords` (142): the target (`Makefile:1075-1171`) calls `kubectl get` and `curl` with no
  `--max-time`.
- `age -e` (151) and the metrics push (`scripts/plugins/password_bundle.sh:15`, no `--max-time`).

## Scope

This fix changes **only** `scripts/plugins/password_bundle.sh` and `scripts/tests/plugins/password_bundle.bats`. It
turns a silent, permanent hang into a bounded, reported failure (`publish_success 0`, so the `publish_failed` rule fires
after 30 min) and lets the next scheduled run start.

Not in scope:

- Why iCloud access blocks when launchd runs the job. Claude investigates read-only on the hub. If iCloud access can't
  be made reliable for the job, the follow-up changes the delivery path. The timeout fix alone makes the failure
  visible but does not deliver the bundle.
- Per-call `--max-time` in the `Makefile` target: follow-up after web-console C r2 lands (C r2 has an open `Makefile`
  edit, one dispatch per file). That follow-up must keep in mind that killing make during `install-vault-port-forward`
  (bootout, then bootstrap) can leave the Vault port-forward unloaded.

## External behaviour proof

Claude, m4-air, 2026-11-22T12:36Z, against a local listener that accepts connections and never answers:

- `curl 8.7.1`: `curl -m 2` exits 28 after 2 s.
- `kubectl v1.37.2 --request-timeout=2s`: exits 1 after 10 s (the TLS handshake has its own 10 s limit).
- `perl -e 'alarm 2; exec @ARGV' curl ...` exits 142 after 2 s, but kills only the exec'd process. Children survive and
  keep pipes open (seen on 2026-11-21 in the mutation harness).
- `timeout`/`gtimeout` exist on m4-air only through Homebrew coreutils. The launchd PATH on the hub is not proven to
  include them, so the fix must not depend on them.

Fable, m4-air, 2026-11-22 (bash 5.3.20, perl 5.34.1, bats 1.14.0):

- `set -m` inside `$(...)` gives a background job its own process group.
- A perl wrapper that forks, calls `setpgrp(0,0)` in the child and `exec`s it, while the parent `alarm`s and then sends
  `kill TERM`/`KILL` to the negative pgid, returned rc 124 in 3 s with a grandchild holding the pipe, and left nothing
  alive.
- TERM to the subshell PID alone ran its EXIT trap but orphaned the foreground child.
- A watchdog `(sleep N) &` started inside `payload="$(...)"` holds the pipe, so the substitution waits the full N.

m5-air: git blocked in `open` under launchd (above). A blocked `open` in state S was killable: the earlier 88191 died on
TERM. On the hub, tool versions and the fix mechanism are proved live by E6.

## Implementation notes (guidance, not the interface)

- Preferred approach: a single perl wrapper (fork; the child calls `setpgrp(0,0)` and execs; the parent waits with
  `alarm`, then sends TERM to the group and KILL after 5 s), routed through `_run_command --no-exit --`. For the whole-run
  limit, it can re-invoke the dispatcher on a private inner function (e.g. `_password_bundle_publish_inner`).
- The watchdog parent pushes the failure metric outside the killed group. Take `change` from `PB_STATE/last-change`
  and `count` from the line count of `PB_STATE/recipients`.
- The parent traps TERM and kills the group, so `launchctl kickstart -k` still clears everything (a process in its own
  group escapes launchd's cleanup when the job exits).
- KILL skips the inner EXIT trap (line 150). On timeout the parent removes `$PB_DIR/.service-passwords.*.??????`
  temp files, best effort, without blocking on them.
- No `timeout`/`gtimeout`. Never echo the payload.

## Acceptance

```yaml
interface:
  env:
    K3DM_PASSWORD_BUNDLE_TIMEOUT: "limit in seconds for the whole of password_bundle_publish (every step after the recipients file is read, except the final failure-metric push, which has its own 10 s limit); must match ^[1-9][0-9]{0,4}$, anything else falls back to 300 with one stderr line; default 300"
  grace: "on timeout, TERM to the run's process group, then KILL after 5 s"
  metrics_push: "curl --max-time 10, fixed, no env var"
  behaviour: "password_bundle_publish returns nonzero within the limit + 20 s when any step does not finish, and pushes k3dm_password_bundle_publish_success 0"
must:
  - id: M1
    text: "A publish where any step after the recipients read never returns ends within K3DM_PASSWORD_BUNDLE_TIMEOUT + 20 s, exits nonzero, and pushes k3dm_password_bundle_publish_success 0."
  - id: M2
    text: "On timeout, no process started by that publish run (including grandchildren of make and processes ignoring TERM) is still alive after publish returns."
  - id: M3
    text: "Publish returns within 15 s when the push endpoint accepts and never answers."
  - id: M4
    text: "The time limit works with timeout and gtimeout absent from PATH."
  - id: M5
    text: "A normal publish (payload returns at once) is unchanged: success 1 pushed, bundle and meta written, all existing password_bundle.bats tests pass."
  - id: M6
    text: "With the default limit, a publish whose payload returns at once returns within 10 s and leaves no watchdog process."
must_not:
  - id: N1
    text: "Publish must not stay running past the limit when a step hangs (red on pre-fix code: it never returns)."
  - id: N2
    text: "A timed-out run must not update PB_STATE/last-publish or last.sha256 (red by mutant: timeout branch writes last-publish)."
  - id: N3
    text: "A timed-out run must not print any part of the payload to stdout or stderr, or leave it in any file under PB_DIR or PB_STATE (red by mutant: timeout branch echoes the captured payload)."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3]
    kind: offline
    intent: "If a step of the 15-minute bundle publish freezes, the job gives up on its own after a set time, says it failed, leaks nothing, and leaves no stray processes behind."
    how: "bats: stub make prints a unique marker string, starts a grandchild 'sleep 3600' tagged with a second marker, starts a second grandchild with trap '' TERM, then sleeps; K3DM_PASSWORD_BUNDLE_TIMEOUT=2; stub push endpoint records bodies. Assert the marker grandchildren are alive before the limit passes. Then assert publish returns within 25 s with rc != 0, the recorded body has publish_success 0, last-publish and last.sha256 are unchanged, no marker process exists, and the payload marker is absent from stdout, stderr and every file under PB_DIR and PB_STATE. The harness limit is BATS_TEST_TIMEOUT or a perl alarm, not timeout; teardown kills marker processes by group so the pre-fix red run leaks nothing."
  - id: E2
    proves: [N1]
    kind: offline
    intent: "A freeze in the delivery folder step (where the hub froze on 2026-11-22) is cut off the same way."
    how: "bats: stub git (first on PATH) that sleeps for 'rev-parse'; K3DM_PASSWORD_BUNDLE_TIMEOUT=2; publish returns within 25 s, rc != 0, publish_success 0 pushed."
  - id: E3
    proves: [M3]
    kind: offline
    intent: "If the metrics endpoint stops answering, the publish still finishes instead of waiting forever."
    how: "bats: push URL points at a local listener that accepts and never replies; assert the listener accepted one connection; fast stub make; publish returns within 15 s."
  - id: E4
    proves: [M4]
    kind: offline
    intent: "The time limit works on a Mac without the Homebrew timeout tool, which is how launchd runs the job."
    how: "bats: E1 rerun with PATH built from a scratch bin holding only the needed tools plus /usr/bin/perl, asserting command -v timeout and gtimeout both fail first."
  - id: E5
    proves: [M5, M6]
    kind: offline
    intent: "Normal publishing still works exactly as before and is not slowed down."
    how: "positive control for E1: fast stub make with the default limit; success 1 pushed, bundle written, publish returns within 10 s, no watchdog process left; full scripts/tests/plugins/password_bundle.bats green."
  - id: E6
    proves: [M1]
    kind: live
    intent: "On the hub, a frozen run no longer blocks the schedule: within one interval the job either publishes or reports a failure, and the next run starts."
    how: "operator or Claude after make hub-deploy: launchctl list shows '-' in the PID column between runs; log mtime advances each 15 min over 1 h; k3dm_password_bundle_publish_success and last_publish_timestamp move as expected."
```

## Contract readers

- New env var `K3DM_PASSWORD_BUNDLE_TIMEOUT`: reader `scripts/plugins/password_bundle.sh` (new). Writers: none; the
  launchd template `scripts/etc/launchd/com.k3d-manager.password-bundle.plist.tmpl:6` does not set it, so the default
  applies. No other reader (`grep -rn K3DM_PASSWORD_BUNDLE_TIMEOUT` empty before this fix).
- Metric `k3dm_password_bundle_publish_success`: reader `scripts/etc/prometheus/rules/password-bundle.yaml:22`
  (`== 0 for 30m`, reason publish_failed). It will now fire on repeated timeouts, which is intended.
- `make show-service-passwords` is unchanged; its other callers (`scripts/tests/bin/webhook_make_targets.py:189`,
  `scripts/tests/bin/makefile_show_service_passwords.bats`) are unaffected.

## Operator workaround until the fix lands

`launchctl kickstart -k gui/$(id -u)/com.k3d-manager.password-bundle` on m5 kills the hung run. On 2026-11-22 the next
run hung again at the same line, so the workaround only clears it; a manual `make password-bundle-publish` from
Terminal delivers the bundle.
