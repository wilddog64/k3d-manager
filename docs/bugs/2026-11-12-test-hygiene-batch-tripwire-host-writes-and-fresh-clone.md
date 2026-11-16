# Test-hygiene batch: tripwire host writes, real-Keychain tests, fresh-clone hermeticity and the fast-gate BASE leak

**Status:** VERIFIED — `0b8d2b80` independently verified 2026-11-13 at e9c375c4 (Acceptance-only Opus verifier, own harness: all offline items pass; N1/N5/N8/N11/M14 and E6/E10/E11/E12/E14 red on 0b8d2b80^; N2/N3/N7/N10 red by mutant; real LaunchAgents byte-identical, no real security call; Claude checked the saved outputs and reran E14 BASE=deadbeef: 49/49); live E4/E7/E8/E13/E15 still open; CI has no fast-gate job, so E5's CI part is unconfirmed; landed `0b8d2b80` on k3d-manager-v1.44.0, 2026-11-12 (Codex Luna; Flash 3.8 diff review; Claude verified offline)
**Priority:** P2
**Waiting on:** live check — since 2026-11-12 (operator `make test` on the M4 / fresh clone)
**Introduced by:** per part: unknown (A); `bd68d6ff` v1.43.12 (B); `82c1d9c8` v1.43.14 (C), pre-existing `945018ee` v1.36.0 (D), `76446d6e` v1.43.15 (E); unknown (F)
**Should have been caught by:** review (A, B, C); offline test (D, E); unknown (F, filed before the line was required)
**Prior art:** none above threshold — this is a batch spec over four captured docs; each doc carries its own Prior art line
**Approval:** operator, 2026-11-12 ("dispatch as you suggest": test-hygiene batch, prerequisite for plan 1 Part B)
**Intent approved:** operator, 2026-11-12
**Intent approval source:** "aporved" (operator, 2026-11-12), from https://claude.ai/artifact/JJJykdXexdKzfdoQ5cKXcm; every decision at its default
**Decisions:** operator, 2026-11-12: N3, N7, N10 shown red by mutation only (Accept); possible false red on a concurrent real plist rewrite (Accept); add `test-host` to `NEVER_EXPOSED` in `scripts/tests/bin/test_cloud_bridge.py:935` (Yes)
**Filed:** 2026-11-12
**Branch:** `k3d-manager-v1.44.0`
**Agent:** Codex `gpt-6-luna`; cross-vendor diff review Flash 3.8 (`gemini-3.8-flash-medium`)

One dispatch, because one dispatch per file: A and E both edit `scripts/tests/tripwire.sh`; A, B and E all touch
`scripts/tests/bin/test_test_tripwire.py`; B adds a `Makefile` target; C and F both edit
`scripts/tests/plugins/agent_dispatch_dashboard.bats`; B and F both edit `scripts/ci/fast_gate.sh` and
`scripts/tests/lib/fast_gate.bats`. `docs/plans/v1.44.0-parallel-offline-tests.md` Part B waits on
A and B (C3 and C4 of the parent) landing.

Parent: `docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`. C1 landed in `d96547df`. C2
(`docs/bugs/2026-11-09-promtool-tests-need-pinned-install-on-every-host.md`) is **not** in this batch: its Part A is a
lib-foundation change that needs a subtree pull first. None of the four docs below depends on C2: C2's tests run under
`make test-pytest`, and the fresh-clone doc's live check (E13) runs `make test` only. The parent's integration check
(full `make test-all` green) still waits on C2, so the parent stays open after this batch lands.

| Part | Doc | Priority |
|---|---|---|
| A | `docs/bugs/2026-11-09-cluster-status-test-rewrites-real-launch-agent.md` (C3) | P2 |
| B | `docs/bugs/2026-11-09-machine-secrets-real-keychain-tests-run-under-tripwire.md` (C4) | P2 |
| C | `docs/bugs/2026-11-10-make-test-fails-on-fresh-linux-control-clone.md` (root cause A) | P3 |
| D | the same doc (root cause B) | P3 |
| E | the same doc (root cause C) | P3 |
| F | `docs/bugs/2026-11-01-make-fast-gate-base-leaks-into-dashboard-suite.md` | P3 |

Read every doc above in full before starting, including the fresh-clone doc's Recurrence section (2026-11-11: same
three causes, no new failure). Each part keeps the Fix, Contract readers and Acceptance its own doc carries; they are
restated below with new IDs so one verifier can work from one block. Checked against the tree at `a5e2f206`
(2026-11-12): no part is already fixed (no `HOME`/`launchctl` stub in the cluster-status test, no
`scripts/tests/host/`, no `test-host` target, `git show 028b898f` still at `agent_dispatch_dashboard.bats:61`, no
`htpasswd` stub in `observability.bats`, the tripwire still shims every listed tool, `BASE=` still at line 3).

## Fix

**A. The cluster-status test is isolated, and the tripwire catches plist writes (C3).** As its doc's Fix:

1. `scripts/tests/bin/cluster_status_app_cluster_registration.bats`: in `setup` (`:3`):
   - `export HOME="${BATS_TEST_TMPDIR}/home"` and `mkdir -p "$HOME"`.
   - `export LAUNCHCTL_LOG="${BATS_TEST_TMPDIR}/launchctl.log"`, `: > "$LAUNCHCTL_LOG"`, and a `"${STUB_BIN}/launchctl"`
     that appends `"$*"` as one line to `$LAUNCHCTL_LOG` and exits 0.
   - A `"${STUB_BIN}/lsof"` that exits 0. Reason: with `launchctl` stubbed to succeed, the restore ends in
     `_observability_wait_for_port 19093` and `9093` (`observability.sh:618-619`), each 5 × `sleep 1` (`:328-337`) when
     nothing listens, so 10 s per case, and the result would depend on whether the host really has listeners on those
     ports. `lsof` is read only by `_observability_port_listening` (`:306-310`); with it reporting "listening", the
     restore still runs because the two plists are missing from the fresh test HOME (`:603-604`), and both waits
     return at once.
   - Add one new case, `cluster-status restore path bootstraps launch agents under the test HOME`: first line
     `[[ "$(uname -s)" == Darwin ]] || skip "macOS only"` (`_is_mac` gates the restore, `observability.sh:590`, so the
     stub log is empty on Linux CI where `fast_gate.sh` runs this changed file); then `run bin/cluster-status`,
     `[ "$status" -eq 0 ]`, and assert `$LAUNCHCTL_LOG` contains `bootstrap gui/` followed by
     `$HOME/Library/LaunchAgents/com.k3d-manager.alertmanager-port-forward.plist`, and that it does not contain
     `$REAL_HOME/Library/LaunchAgents` (capture `REAL_HOME="$HOME"` at the top of `setup` before overriding). This is M2.
     The three existing cases are unchanged.
   - Do not stub out the restore call at `bin/cluster-status:431` (`_observability_restore_alertmanager_access_layer`,
     `scripts/plugins/observability.sh:589`, which reaches `_observability_install_alertmanager_port_forward` at `:272`
     and, when the auth file is missing, `_observability_ensure_alertmanager_login`, which writes
     `$HOME/.local/share/k3d-manager/alertmanager-basic-auth.env` at `:503-509`). With `HOME` isolated, that file now
     lands in the test HOME too.
2. `scripts/tests/tripwire.sh` write check. Exactly this behaviour:
   - Watch directory: `_tripwire_watch_dir="${K3DM_TRIPWIRE_WATCH_DIR:-${HOME:+$HOME/Library/LaunchAgents}}"`, computed
     before the command. Empty (no `HOME`, no override) means the check is off.
   - Before the command: write a snapshot to `$_tripwire_dir/watch.before`, one line per
     `com.k3d-manager.*.plist` directly in the directory (`find "$dir" -maxdepth 1 -type f -name 'com.k3d-manager.*.plist'`,
     sorted): the path, a tab, and `cksum < file` (CRC and size; POSIX, same output format on macOS and GNU). Then
     `touch "$_tripwire_dir/watch.marker"` and record into `watch.newer.before` the files already `-newer` the marker
     (normally none; guards against files with a future mtime). A directory that does not exist gives an empty
     snapshot; guard every `find` with `[[ -d "$dir" ]]`, because `find` on a missing path exits 1 and the script runs
     under `set -euo pipefail`.
   - After the command (whatever its exit code, and whether or not any call was blocked): take the same snapshot into
     `watch.after`, and list files `-newer` the marker into `watch.newer.after`. A path only in `before` is `removed`,
     only in `after` is `created` (this includes a directory that did not exist before and was created by the command),
     in both with a different `cksum` line is `modified`, and in `watch.newer.after` but not `watch.newer.before` is
     `modified` (catches a rewrite with identical bytes, as `sed ... > plist` does). Missing before and after: no-op.
   - On any finding: one stderr line per file, `[tripwire] FAIL: <path> <created|modified|removed> during the run — isolate HOME and stub launchctl in the test.`,
     and `[[ $_rc -eq 0 ]] && _rc=1`, the same rule as the unsafe-call block at `:87-90`: a non-zero exit code from the
     command is kept, never replaced. Put the check after the blocked-call block (`:78-91`) and before `exit "$_rc"`.
   - Do not use `stat` (`stat -f` is BSD-only, `stat -c` GNU-only; the tripwire runs on both, via `fast_gate.sh:47`
     on Linux CI and `make test*` on macOS). Only `find`, `cksum`, `touch`, `sort`, `comm`/`diff`.
   - Scope is the plist glob only, by design. Other host writes under `HOME` (the alertmanager auth file above) are
     covered by the test's own HOME isolation and by E2's sentinel HOME, not by the tripwire.
3. No production change to `bin/cluster-status` or `observability.sh`.

**B. The real-Keychain cases move to `make test-host` (C4).** As its doc's Fix: move the two cases
(`scripts/tests/bin/machine_secrets.bats:375` and `:414`) into the new
`scripts/tests/host/machine_secrets_real_keychain.bats`, with `setup` recording `security list-keychains -d user`,
`teardown` deleting both keychains and restoring the list whatever the outcome (and failing if it differs), the
`/usr/bin/security` assertion (`:378`) kept, and the `skip` fallbacks (`:385-386`, `:419-420`) dropped on macOS. New
`Makefile` target `test-host` runs `bats scripts/tests/host` on macOS with no tripwire, is not part of `test`,
`test-bin`, `test-python` or `test-all`, and gets a help line saying it touches the real Keychain tool and the user's
search list and restores the list. Add it to `.PHONY` (`Makefile:110`). `test_test_tripwire.py` gains an assertion
that `test-host` is *not* wrapped. Add `"test-host"` to `NEVER_EXPOSED` in `scripts/tests/bin/test_cloud_bridge.py:935` (operator, 2026-11-12). No change to `bin/k3dm-machine-secrets`. `make test-bin` loses exactly these two
cases, by design.

Decided details for B:

1. The moved file's `setup` sets only what the two cases use, copied from `machine_secrets.bats:4-13` and `:65`:
   `ROOT`, `source "${ROOT}/scripts/tests/test_helpers.bash"` (for `require_macos`, `test_helpers.bash:43`), `TMP`,
   `mkdir -p "$TMP/bin" "$TMP/home"`, `PATH="$TMP/bin:$PATH"`, `HOME="$TMP/home"`, the passphrase file, and `SCRIPT`.
   It does **not** write a `security` stub (the original setup's stub at `:16` existed only for the other cases; each
   moved case's `rm -f "$TMP/bin/security"` stays and becomes a no-op). Keychain paths go in variables the teardown
   can see (`source_keychain`, `target_keychain`, set as today).
2. `setup` then, on Darwin only (`[[ "$(uname -s)" == Darwin ]]`; not `require_macos`, which would skip from setup),
   runs `security list-keychains -d user > "$TMP/search-list.before"` (raw output, kept for the comparison). Teardown is the same `HOME` and `PATH` as setup, so record and restore talk
   to the same domain whether or not `security` honours `HOME`.
3. `teardown`, on Darwin only, whatever the outcome: for each of `source_keychain`, `target_keychain` that is set,
   `security delete-keychain "$k" >/dev/null 2>&1 || true`; then read the current list into `search-list.after`; if it
   differs from `before`, restore with
   `security list-keychains -d user -s "${saved[@]}"`, where `saved` is `before` parsed one entry per line with
   `sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'` (the tool prints each path indented and double-quoted), read
   with `while IFS= read -r` so paths with spaces survive; re-read the list and `return 1` with both lists on stderr
   if it still differs. Do not call `list-keychains -s` when nothing changed.
4. Non-macOS: both cases keep `require_macos` as their first line, so they skip on Linux.
5. `Makefile` recipe, placed after `test-bin` (`:1453-1457`), with a `## Run the real-host BATS suites under scripts/tests/host (macOS only, no tripwire)` comment above it:
   `@set -euo pipefail;` then `[ "$$(uname -s)" = Darwin ] || { echo "[make] test-host is macOS only" >&2; exit 2; };`,
   the same `command -v bats` check as `test-bin`, an `echo` saying "[make] test-host uses the real Keychain tool and
   your keychain search list; the suite restores the list", then `bats scripts/tests/host`. Help line in `help`
   after `make test-bin` (`:1750`):
   `make test-host     Run real-host BATS suites (macOS; real Keychain tool, restores your keychain search list)`.
6. `scripts/ci/fast_gate.sh` never runs anything under `scripts/tests/host/`. Today it would: `add_test` (`:140`)
   accepts `scripts/tests/*.bats` (a `case` `*` matches `/`), so a change to the host file queues it, and the
   name-match `find scripts/tests ...` (`:160`) queues it whenever a changed file's path or basename appears in it
   (for example a change to `bin/k3dm-machine-secrets`). Bats suites run with no tripwire (`:35`), and the pre-push
   hook runs the fast gate on the operator's Mac, so that would be a real `security create-keychain` on every such
   push. Fix: in `add_test`, `scripts/tests/host/*) return 0 ;;` before the existing pattern; in the `find`, add
   `-not -path 'scripts/tests/host/*'`. Add a `fast_gate.bats` case (scratch fixture, as the file's other cases): a
   `scripts/tests/host/probe.bats` that names `thing.txt` and touches a marker; change `thing.txt` and the probe
   itself; assert the gate passes, its output has no `scripts/tests/host/`, and the marker is absent (N11).
7. `scripts/tests/core/suite_discovery.bats:15-18` fails `make test` on any `.bats` outside `lib|core|plugins|etc|bin`,
   so it would flag the new file. Add `host/*/*` to the orphan pattern and `host/*` to the accepted pattern, and add
   one line to its message: `make test-host globs scripts/tests/host (macOS, real host tools, not offline).` (M14).
   `scripts/tests/lib/bats_negation_lint.bats:5` greps every `.bats` recursively: the new file must not use bare
   `! cmd` (use `run !`).

**C. The verification-ladder test stops reading git history (fresh-clone root cause A).** As its doc's Fix: replace
the `git show 028b898f:` baseline at `scripts/tests/plugins/agent_dispatch_dashboard.bats:61` with a committed
fixture, byte-identical to `git show 028b898f:scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
(sha256 `607f22085c433f645b67a8ab0eb756181674110e5338024e91e11ad9b32a8c9d`, checked 2026-11-12), under
`scripts/tests/fixtures/agent-dispatch-dashboard-028b898f.yaml`. The existing `agent-dispatch-dashboard-pre-split.yaml`
is a different version (differs at line 12); do not reuse it. `028b898f` is still reachable only from
`origin/k3d-manager-v1.43.14` (re-checked 2026-11-12: `git branch -a --contains 028b898f` lists only that branch; the
sha256 above matches). Create it with
`git show 028b898f:scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml > scripts/tests/fixtures/agent-dispatch-dashboard-028b898f.yaml`
and check the sha256. In the test: add `BASELINE_FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/agent-dispatch-dashboard-028b898f.yaml"`
next to `FIXTURE` (`:4`), pass it as a third argument to the `python3 -` call at `:25`, unpack three paths at `:28`,
and replace the `subprocess.run([... "git", "-C", ..., "show", ...])` line (`:61`) and the `dashboard_repo_path` line
(`:60`) with `baseline_text = baseline_path.read_text()`. Drop `subprocess` from the import at `:26` if nothing else
uses it. The baseline path is not derived from the dashboard directory variable (F), so `AGENT_DASHBOARD_DIR` pointing
elsewhere never moves the baseline.

**D. The observability test stubs `htpasswd` (root cause B).** As its doc's Fix: in the
`deploy_observability calls envsubst ...` test (`scripts/tests/lib/observability.bats:17`; it fails at the status
assertion at `:82`), put an `htpasswd` stub on PATH that records argv and prints a fixed `admin:$2y$12$...` line. The
real call it replaces is `scripts/plugins/observability.sh:955-964`. Assertions unchanged.

Decided details for D: follow the file's existing pattern, an exported shell function inside the `run bash -c '...'`
script (as `envsubst`, `_kubectl`, `curl`, `kubectl`, `launchctl` at `:30-78`); `command -v htpasswd` at `:955`
finds an exported function. The function consumes stdin (`cat >/dev/null`, so the password is never echoed or
logged), appends `"$*"` to `"${HTPASSWD_STUB_LOG}"`, and prints
`admin:\$2y\$12\$abcdefghijklmnopqrstuu0123456789ABCDEFGHIJKLMNOPQRSTU` (60-character bcrypt shape; the dollars are
escaped because the script is single-quoted outside and the line is double-quoted inside). Set
`HTPASSWD_STUB_LOG="${BATS_TEST_TMPDIR}/htpasswd.log"` and export it next to `ENVSTUB_LOG` (`:21`), add `htpasswd` to
the `export -f` list (`:75`). No new assertion: the log is evidence for E11 only.

**E. The tripwire shims only tools that exist (root cause C).** As its doc's Fix: in `scripts/tests/tripwire.sh`,
create a shim only for a `TRIPWIRE_TOOLS` entry that resolves on the PATH as it was before the shim dir is prepended.
An absent tool stays absent, so the `command -v helm || skip` guard in `scripts/tests/plugins/argocd_loki.bats:17-19`
(`_ensure_loki_chart_18_2_0`, used by 5 tests) works under the tripwire. `TRIPWIRE_TOOLS` itself is unchanged.

Decided details for E: the test is `type -P -- "$_tool" >/dev/null` inside the loop at `:60`, before the heredoc
(`type -P` looks at PATH only; `command -v` would also accept an exported function or alias inherited from the
caller). The loop still runs before `PATH` is changed at `:74`, so "the PATH before the shim dir is prepended" is the
script's own `PATH`. The shim body, passthrough list and `_tripwire_is_read` are unchanged.

Accepted consequence (from the source doc, restated so nobody "fixes" it): on a host without a listed tool, a test
that calls that tool now gets `command not found` (127) instead of a logged block. Nothing can reach a binary that does
not exist, so no host write is possible; what is lost is the tripwire's report of an unstubbed call on that host only.
macOS hosts, where `security` and `launchctl` always exist, keep the report. No test depends on the shim existing for
an absent tool: `git grep` on 2026-11-12 found no assertion on exit 97 from a tripwire shim, and every
`command -v <listed tool>` assertion in `scripts/tests` checks a test's own stub.

**F. `make fast-gate BASE=` no longer leaks into the dashboard suite.** As its doc's Fix:
1. `scripts/tests/plugins/agent_dispatch_dashboard.bats`: rename the override at line 3 to `AGENT_DASHBOARD_DIR`
   (default unchanged) and replace every `$BASE` in the file (48 uses plus the definition at `:3`; afterwards
   `grep -nE '\$\{?BASE([^A-Z_]|$)|^BASE=' scripts/tests/plugins/agent_dispatch_dashboard.bats` prints nothing). C and F do not collide:
   today the baseline's `git -C` directory comes from `dashboard_path.parent` (`:61`), i.e. from this variable; after C
   the baseline is `BASELINE_FIXTURE`, which is built from `BATS_TEST_DIRNAME` and never from `AGENT_DASHBOARD_DIR`. Do
   C first, then the rename; a blind global replace is safe because no `$BASE` remains in C's new code.
2. `scripts/ci/fast_gate.sh`: run each check with `BASE` removed from its environment. Decided: `unset BASE` as the
   first statement of `worker()` (`:31`), which covers both check launches at `:51` and `:73` (each worker is a fresh
   `/bin/bash scripts/ci/fast_gate.sh --worker` from `xargs`, `:207`, `:210`, inheriting the caller's environment). The positional base selection
   (`:44-47`) and `Makefile:1566-1567` (`fast-gate: ... $(BASE)`) are unchanged.

F's doc also lists `CHANGELOG.md`: leave it; Claude updates it at land.

## Line references that moved since the source docs

| Doc | Cited | Now (at `a5e2f206`) |
|---|---|---|
| A (C3) | `Makefile:1408` (`test`), `:1415` (`test-bin`), `:1431` (`test-python` per file), `:1553` (`test-metrics` python) | `:1450` (`test`), `:1457` (`test-bin`), `:1473` (target is now `test-python-unit`), `:1595` (target is `test-pytest`; `test-metrics` does not call the tripwire directly) |
| A (C3) | `observability.sh:273` (`_observability_install_alertmanager_port_forward`) | `:272` |
| C/D/E | "test 526", "test 272", "tests 800-804" | Numbering from the 2026-11-10 run; use the test names. `agent_dispatch_dashboard.bats` now has 49 cases (F's doc said 35) |
| D | `observability.bats:82` | the test starts at `:17`; `:82` is its failing status assertion |
| E | `argocd_loki.bats:17-19` | guard function at `:17`, check at `:18-19` (unchanged in substance) |
| C | `bin/k3dm-machine-setup:119` (`--single-branch`) | unchanged; `:286` clones `--single-branch` too |

Unchanged and re-checked: `bin/cluster-status:431`, `observability.sh:589`, `machine_secrets.bats:375/378/410-411/414/431-432`,
`agent_dispatch_dashboard.bats:3` and `:61`, `scripts/ci/fast_gate.sh:47`, `:51`, `test_test_tripwire.py:16`, `:40`,
`scripts/tests/lib/fast_gate.bats:9`.

## Files

| File | Parts |
|---|---|
| `scripts/tests/tripwire.sh` | A, E |
| `scripts/tests/bin/cluster_status_app_cluster_registration.bats` | A |
| `scripts/tests/bin/test_test_tripwire.py` | A (write-check cases), B (`test-host` not wrapped), E (absent-tool case) |
| `scripts/tests/bin/machine_secrets.bats` | B (remove the two cases) |
| `scripts/tests/host/machine_secrets_real_keychain.bats` (new) | B |
| `Makefile` | B (`test-host`, `.PHONY`, help line) |
| `scripts/tests/bin/test_cloud_bridge.py` | B (`test-host` in `NEVER_EXPOSED`) |
| `scripts/tests/core/suite_discovery.bats` | B (accept `scripts/tests/host/`) |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | C, F |
| `scripts/tests/fixtures/agent-dispatch-dashboard-028b898f.yaml` (new) | C |
| `scripts/tests/lib/observability.bats` | D |
| `scripts/ci/fast_gate.sh` | B (skip `scripts/tests/host/`), F (`unset BASE`) |
| `scripts/tests/lib/fast_gate.bats` | B (host-suite case), F (env case); must still pass after A and E |

## Old ID → new ID

E1-E13 intents are copied word for word from their source docs; only IDs and `proves` references are renumbered.
F's doc has no `**Intent approved:**` line, so E14 and E15 are not yet approved. E16 and E17 are new in this batch
(added 2026-11-12 after the cross-vendor spec review), with new items M14 and N11; they are not yet approved either.
That is why the header reads `pending`.

| Source doc | Old | New |
|---|---|---|
| C3 (Part A) | M1, M2, M3 | M1, M2, M3 |
| | N1, N2, N3 | N1, N2, N3 |
| | E1, E2, E3, E4 (live), E5 | E1, E2, E3, E4 (live), E5 |
| C4 (Part B) | M1, M2, M3 | M4, M5, M6 |
| | N1, N2, N3 | N4, N5, N6 |
| | E1, E2 (live), E3 (live), E4 | E6, E7 (live), E8 (live), E9 |
| fresh clone (Parts C, D, E) | M1, M2, M3, M4 | M7, M8, M9, M10 |
| | N1, N2 | N7, N8 |
| | E1, E2, E3, E4 (live) | E10, E11, E12, E13 (live) |
| fast-gate BASE (Part F) | M1, M2, M3 | M11, M12, M13 |
| | N1, N2 | N9, N10 |
| | E1, E2 (live) | E14, E15 (live) — intents not yet approved |
| this batch (Part B gaps) | — | M14, N11, E16, E17 — new, intents not yet approved |

## Contract readers

Found by `git grep`, 2026-11-12.

| Contract | Component | Role | Change |
|---|---|---|---|
| `scripts/tests/tripwire.sh` behaviour | `Makefile:1450` (`test`), `:1457` (`test-bin`), `:1473` (`test-python-unit`), `:1595` (`test-pytest`) | reader | a run that changes a real k3dm plist now fails (A); an absent listed tool is no longer shimmed (E). Recipes unchanged |
| same | `scripts/ci/fast_gate.sh:47`, `:51` | reader | none on Linux CI: the watch directory does not exist (no-op); absent tools stay absent. Must stay green (E5) |
| same | `bin/k3dm-codex-dispatch land --test` (runs whatever `--test` names, often `make test*`) | reader | as the Makefile rows |
| same | `scripts/tests/bin/test_test_tripwire.py:16`, `:40` | reader | gains A's and E's cases and B's not-wrapped assertion; existing assertions unchanged |
| same | `scripts/tests/lib/fast_gate.bats:9` (copies the file into a fixture) | reader | must still pass (E5) |
| `K3DM_TRIPWIRE_WATCH_DIR` (new env var) | `scripts/tests/tripwire.sh` | reader | new; default `$HOME/Library/LaunchAgents` |
| same | `test_test_tripwire.py` (new cases) | writer | sets it to a sentinel folder; nothing else sets it |
| `~/Library/LaunchAgents/com.k3d-manager.*.plist` | `scripts/plugins/observability.sh:283`, `:531` (installers called by the restore at `:589`); `:259`, `:564` and the other launchd installers | writer | none in production; the cluster-status test stops writing there (A) |
| same | `scripts/tests/tripwire.sh` | reader | new: snapshots the directory before and after the command (A) |
| `~/.local/share/k3d-manager/alertmanager-basic-auth.env` | `scripts/plugins/observability.sh:503-509` (`_observability_ensure_alertmanager_login`, reached from the restore at `:614` when the file is missing) | writer | none in production; with `HOME` isolated the cluster-status test writes it under the test HOME (A). Not watched by the tripwire (plist glob only); N1/E2 cover it |
| same | `bin/cluster-status:433` (`_ALERTMANAGER_AUTH_FILE` default) | reader | none; reads the test HOME's file in the test |
| `make test-host` (new target) | `Makefile` | writer | new; `grep -n test-host Makefile` empty on 2026-11-12 |
| same | `test_test_tripwire.py` | reader | asserts it is not tripwire-wrapped |
| same | `scripts/lib/webhook/cloud_actions.py:32-36` (cloud-bridge `make-test*` allowlist) | reader | none: `test-host` is **not** added; it touches the real Keychain tool |
| user keychain search list | `scripts/tests/host/machine_secrets_real_keychain.bats` | writer | `create-keychain` adds entries; teardown restores the recorded list |
| `scripts/tests/host/` (new path) | `scripts/ci/fast_gate.sh:140` (`add_test`), `:160` (name-match `find`) | reader | **changes**: both skip `scripts/tests/host/` (B, N11); today either would run the host file with no tripwire |
| same | `scripts/tests/core/suite_discovery.bats:15-20` (orphan check, part of `make test`) | reader | **changes**: accepts `host/*` (B, M14) |
| same | `scripts/tests/lib/bats_negation_lint.bats:5` (recursive grep of every `.bats`) | reader | none; the new file must pass it (no bare `! cmd`) |
| same | `scripts/k3d-manager:440-443` (`test all` search dirs `lib core plugins etc`, `-maxdepth 1`); `Makefile:1457` (`bats scripts/tests/bin`, not recursive) | reader | none; neither reaches `host/` |
| `scripts/tests/fixtures/agent-dispatch-dashboard-028b898f.yaml` (new) | `agent_dispatch_dashboard.bats` (ladder test, via `BASELINE_FIXTURE`) | reader | new; no other reader. Writer: none after creation (frozen copy) |
| `BASE` env var | `Makefile:1567` via GNU make's export of command-line variables | writer | none; `fast_gate.sh` stops passing it to checks (F) |
| same | `scripts/tests/plugins/agent_dispatch_dashboard.bats:3` | reader | renamed to `AGENT_DASHBOARD_DIR` (F) |
| `fast_gate.sh` positional base | `.githooks/pre-push:24`, `:26`; `bin/k3dm-codex-dispatch:1197`; `Makefile:1567` | writer | none |
| `AGENT_DASHBOARD_DIR` (new) | `agent_dispatch_dashboard.bats` | reader | new; no other reader or writer |
| `028b898f` reachability | `agent_dispatch_dashboard.bats:61` | reader | removed: reads the committed fixture (C) |

## Acceptance

```yaml
must:
  - id: M1
    text: "cluster_status_app_cluster_registration.bats passes all its cases under make test-bin (inside the tripwire), with the tripwire reporting zero blocked calls from this file."
  - id: M2
    text: "The restore path still runs in the test; the launchctl stub records a bootstrap whose plist path is under the test's own HOME, not the real one."
  - id: M3
    text: "scripts/tests/tripwire.sh fails the run, naming the file, when a com.k3d-manager.*.plist in the watched LaunchAgents directory is created, modified (including rewritten with identical bytes) or removed during the command, even if the command exited 0, and also when the command creates the watched directory itself with such a plist in it. A non-zero exit code from the command is kept."
  - id: M4
    text: "make test-bin no longer contains either real-Keychain case, and machine_secrets.bats has zero failures and zero tripwire-blocked security calls."
  - id: M5
    text: "make test-host on macOS runs both cases against /usr/bin/security and both pass, with no skip."
  - id: M6
    text: "After make test-host, the user keychain search list is identical to before, including when a case fails partway."
  - id: M7
    text: "The verification-ladder test passes in a clone that has no commit 028b898f (single-branch clone of main), comparing against the committed fixture."
  - id: M8
    text: "The deploy_observability envsubst test passes on a host with no htpasswd, and on macOS still passes with the same assertions."
  - id: M9
    text: "On a host without helm, the five Loki render tests report skip \"helm is missing\" under scripts/tests/tripwire.sh."
  - id: M10
    text: "On a host with helm, the Loki render tests still run and pass under the tripwire (paired with M9)."
  - id: M11
    text: "agent_dispatch_dashboard.bats passes with BASE=<any sha> set in its environment."
  - id: M12
    text: "AGENT_DASHBOARD_DIR=<dir> points the suite at another dashboard directory (paired positive control: a directory missing the dashboards makes it fail)."
  - id: M13
    text: "A check run by fast_gate.sh does not see a BASE variable from the caller's environment."
  - id: M14
    text: "make test's suite_discovery.bats passes with scripts/tests/host/machine_secrets_real_keychain.bats present, and still reports an orphan for a .bats file in any other unlisted directory (positive control)."
must_not:
  - id: N1
    text: "Running the cluster-status test file must not create, modify or remove any file under the HOME it inherited."
  - id: N2
    text: "The tripwire write check must not fail a run in which nothing in the watched directory changed, and must be a no-op when the directory does not exist before or after the command."
  - id: N3
    text: "No cluster-status case is deleted, skipped or weakened, and the restore call at bin/cluster-status:431 is not removed, guarded off, or bypassed by an env var."
  - id: N4
    text: "Neither real-Keychain case is weakened; every assertion in the original two cases is still present in the moved file."
  - id: N5
    text: "A case in the moved file must not pass when create-keychain fails (no skip fallback on macOS)."
  - id: N6
    text: "make test-host must not leave a keychain file or a search-list entry behind after any outcome."
  - id: N7
    text: "The tripwire never lets a blocked (mutating) call to a tool that exists reach the real binary; the block report still lists it."
  - id: N8
    text: "No test in agent_dispatch_dashboard.bats, observability.bats or argocd_loki.bats reads git history for its baseline."
  - id: N9
    text: "make fast-gate BASE=<sha> never reports agent_dispatch_dashboard.bats FAIL when the suite passes run directly."
  - id: N10
    text: "fast_gate.sh's base selection (positional arg, then default) does not change."
  - id: N11
    text: "fast_gate.sh never runs a suite under scripts/tests/host/, whether that suite file itself changed or it names a changed file."
evidence:
  - id: E1
    proves: [M1, M2]
    kind: offline
    intent: >-
      The cluster-status test passes under the normal test-bin run, and its fake launchctl shows the restore
      still runs, pointed at a throwaway home.
  - id: E2
    proves: [N1, N3]
    kind: offline
    intent: >-
      Run the test with HOME set to a sentinel folder; before the fix the sentinel gains a plist (red), after
      the fix it is byte-for-byte unchanged (green). Your real home is never used.
  - id: E3
    proves: [M3, N2]
    kind: offline
    intent: >-
      The tripwire goes red when a command touches a plist in a sentinel watch folder, stays green when it does
      not, and stays green when the folder is missing.
  - id: E4
    proves: [M1, N1]
    kind: live
    intent: >-
      Claude runs make test-bin on the M4 and shows the mtimes of every k3dm plist in your real LaunchAgents are
      the same before and after.
  - id: E5
    proves: [N2]
    kind: offline
    intent: >-
      fast_gate.bats and the CI fast gate stay green, so Linux CI is unaffected.
  - id: E6
    proves: [M4]
    kind: offline
    intent: >-
      make test-bin's machine-secrets file goes from 1 failure plus a blocked keychain call to zero of each.
  - id: E7
    proves: [M5, N4]
    kind: live
    intent: >-
      Claude runs make test-host on the M4 and both round trips pass against the real keychain tool, with a
      side-by-side list showing every original assertion survived the move.
  - id: E8
    proves: [M6, N6]
    kind: live
    intent: >-
      Claude records your keychain search list, runs make test-host once normally and once with a case forced
      to fail midway, and shows the list identical and no throwaway keychain left each time.
  - id: E9
    proves: [N5]
    kind: offline
    intent: >-
      With a create-keychain that fails, the moved case reports a failure, where before it reported a skip.
  - id: E10
    proves: [M7, N8]
    kind: offline
    intent: >-
      You will see test 526 pass in a scratch single-branch clone where `git cat-file -t 028b898f` fails, and
      fail on today's test.
  - id: E11
    proves: [M8]
    kind: offline
    intent: >-
      You will see test 272 pass with PATH stripped of htpasswd, and fail on today's test.
  - id: E12
    proves: [M9, M10, N7]
    kind: offline
    intent: >-
      You will see the tripwire run the Loki tests as skips with helm hidden from PATH and as passes with helm
      present, and a stubbed `kubectl apply` still blocked and reported.
  - id: E13
    proves: [M7, M8, M9]
    kind: live
    intent: >-
      Claude reruns make test as k3dm-control in a fresh Vagrant VM clone and sees 0 not ok.
  - id: E14
    proves: [M11, M12, M13, N10]
    kind: offline
    intent: >-
      You will see BATS run the dashboard suite with BASE=deadbeef exported and pass (red on the pre-fix suite), with
      AGENT_DASHBOARD_DIR at an empty dir and fail, and a fast_gate.bats case whose fixture check prints its env show
      no BASE while the positional base is still honoured.
  - id: E15
    proves: [N9]
    kind: live
    intent: >-
      You will see make fast-gate BASE=<v1.43.12 merge base> on the M4 report PASS for agent_dispatch_dashboard.bats.
  - id: E16
    proves: [M6, N6]
    kind: offline
    intent: >-
      With a fake keychain tool that keeps its own search list in a scratch file, a moved case forced to fail
      midway leaves that list unchanged and no throwaway keychain behind; the same forced failure on today's test
      leaves two extra entries (red). Your real keychain is never used.
  - id: E17
    proves: [M14, N11]
    kind: offline
    intent: >-
      In a scratch repo, the fast gate skips a host-only test that names a changed file or was itself changed
      (today it runs it: red), and the make test suite check accepts the new host folder but still flags a test
      file in any other new folder.
interface:
  - "bin/cluster-status"
  - "scripts/tests/bin/cluster_status_app_cluster_registration.bats"
  - "scripts/tests/tripwire.sh <command> (K3DM_TRIPWIRE_WATCH_DIR)"
  - "make test, make test-bin, make test-host"
  - "scripts/tests/core/suite_discovery.bats"
  - "scripts/tests/host/machine_secrets_real_keychain.bats"
  - "scripts/tests/bin/machine_secrets.bats"
  - "scripts/tests/bin/test_test_tripwire.py"
  - "bats scripts/tests/plugins/agent_dispatch_dashboard.bats scripts/tests/lib/observability.bats scripts/tests/plugins/argocd_loki.bats"
  - "make fast-gate BASE=<sha>; scripts/ci/fast_gate.sh [BASE]"
  - "env BASE, AGENT_DASHBOARD_DIR"
```

Notes carried from the source docs:
- E2 shows N1 and N3 red on the pre-fix code (sentinel HOME gains a plist); a mutation deleting
  `bin/cluster-status:431` empties M2's stub log.
- E3's cases (in `test_test_tripwire.py`, each with `K3DM_TRIPWIRE_WATCH_DIR` at a sentinel under `tmp_path`):
  create, modify, rewrite-with-identical-bytes, remove, a missing folder that the command creates with a plist (red),
  a missing folder that stays missing (green), an unchanged folder (green), and a command that exits 3 and touches a
  plist (exit stays 3). Each asserts the sentinel path, not `~/Library`, is the one watched before it acts.
- E9 and E16 must not run either real-Keychain case as written. The pre-fix case deletes `$TMP/bin/security`
  (`machine_secrets.bats:377`), so a shim placed there is removed and the next call is the real
  `/usr/bin/security`; and the `/usr/bin/security` assertion (`:378`, kept in the moved file) fails before any shim is
  reached. So both run on **scratch copies** of the case (pre-fix: the case from `machine_secrets.bats` at `a5e2f206`;
  post-fix: the moved file), in which the one `[ "$(command -v security)" = /usr/bin/security ]` line is replaced by
  `[ "$(command -v security)" = "$SHIM_DIR/security" ]`, with `SHIM_DIR` a scratch directory outside `$TMP/bin`,
  prepended to `PATH` by the runner. If that replacement assertion fails, stop: nothing else may run. The copies live
  at `<scratch>/scripts/tests/bin/` (pre-fix) or `<scratch>/scripts/tests/host/` (post-fix) next to a copy of
  `scripts/tests/test_helpers.bash`, so `ROOT` resolves to `<scratch>`; set `MACHINE_SECRETS_SOURCE` to the checkout's
  `bin/k3dm-machine-secrets`. Run one case with `bats -f`. Never write the copies into the checkout.
- E9: the shim's `create-keychain` exits 1, as the tripwire's 97 does. Pre-fix the case reports `skip`; post-fix it
  fails.
- E16: a stateful shim with its search list in a scratch file outside `BATS_TEST_TMPDIR` (which bats deletes):
  `create-keychain` creates the file and appends its path; `delete-keychain` removes both; `list-keychains -d user`
  prints the list indented and double-quoted like the real tool; `list-keychains -d user -s ...` replaces it;
  `unlock-keychain` exits 0; `add-generic-password` exits 1 when `SHIM_FAIL_ADD=1`. With `SHIM_FAIL_ADD=1` the case
  fails midway in both runs. Pre-fix (no teardown): the list file has two extra entries (red). Post-fix: list file
  byte-identical to before, and no `*.keychain-db` left (green). This also exercises teardown's quote-stripping parse.
- E7's side-by-side list (every assertion line of the two original cases at `a5e2f206`, each found in the moved file)
  is a text check the worker produces offline as well; it is red on the pre-fix tree because the moved file is absent.
- E8 (live): the moved file sets `HOME="$TMP/home"` like the original setup, and whether `security` honours `HOME`
  for the user search list is not proven. Claude records `security list-keychains -d user` from the operator's real
  shell before and after each run, as well as reading the suite's own before/after.
- E17: the scratch repo is `fast_gate.bats`'s existing fixture (`setup`, `:3-21`) plus
  `scripts/tests/host/probe.bats`. The suite-discovery half runs `suite_discovery.bats` against a scratch copy of
  `scripts/tests` (or with `TESTS_ROOT` pointed at one) containing the host file (green) and a `scripts/tests/newdir/x.bats`
  (red, positive control); never add files to the real tree for it.
- N3, N7 and N10 are already true of the pre-fix code (they guard against regressions), so their red runs are the
  mutations of DoD item 2: delete `bin/cluster-status:431` in a scratch copy (N3; M2's stub log empties), make a shim
  `exec` the real tool for every call (N7; E12's `kubectl apply` reaches the fake real binary), and change
  `base=${1:-}` (N10).
- E10 runs in a scratch `--single-branch` clone under the scratchpad; E11 with PATH stripped of `htpasswd`; E12 with
  PATH stripped of `helm`.
- E14's commands: `bats scripts/tests/plugins/agent_dispatch_dashboard.bats scripts/tests/lib/fast_gate.bats`.
- Live items E4, E7, E8, E13 and E15 are run by Claude, never the worker or Gemini.

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
5. Batch-specific: paste the tripwire's stderr for one red E3 case (the `[tripwire] FAIL: <path> ...` line);
   `shellcheck -S error scripts/tests/tripwire.sh scripts/ci/fast_gate.sh` with rc; `grep -n 'stat ' scripts/tests/tripwire.sh`
   (expect nothing); the sha256 of the new fixture; and the run time of `bats scripts/tests/bin/cluster_status_app_cluster_registration.bats`
   with a scratch `HOME` (it should be seconds, not tens of seconds; if not, say why).
6. Suites to run (all offline, scratch `HOME`, never the real one): `test_test_tripwire.py` (pytest),
   `scripts/tests/lib/fast_gate.bats`, `scripts/tests/core/suite_discovery.bats`, `scripts/tests/lib/bats_negation_lint.bats`,
   `scripts/tests/bin/machine_secrets.bats` with `HOME` pointed at a scratch folder (its remaining cases all stub
   `security`), `scripts/tests/plugins/agent_dispatch_dashboard.bats`, `scripts/tests/lib/observability.bats`,
   `scripts/tests/plugins/argocd_loki.bats`, and the cluster-status file under `scripts/tests/tripwire.sh` with
   `HOME` and `K3DM_TRIPWIRE_WATCH_DIR` at scratch folders. Do not run the new `scripts/tests/host/` file at all
   except as E9/E16's scratch copies.

## What NOT to do

- Never run the pre-fix cluster-status test with the real `HOME`; E2's red run uses only a sentinel HOME under the
  scratch directory. Never point `K3DM_TRIPWIRE_WATCH_DIR` at the real `~/Library/LaunchAgents` in a test.
- Never run `make test-host` or any real `security create-keychain`; E7 and E8 are live, for Claude. Never run
  either real-Keychain case as written (in `machine_secrets.bats` before the move, or in the moved file): the case
  removes `$TMP/bin/security` itself, so only E9/E16's scratch copies with the replaced assertion are safe.
- Do not use `stat` in the tripwire; do not widen the write check beyond the `com.k3d-manager.*.plist` glob.
- Do not add `test-host` to `test`, `test-bin`, `test-python`, `test-all`, `scripts/lib/webhook/cloud_actions.py`, or
  `scripts/etc/fast-gate/static.list`.
- Do not stub `_observability_wait_for_port` or `_observability_restore_alertmanager_access_layer` in the
  cluster-status test; the `lsof` stub is the only speed-up.
- Do not add an assertion to the observability envsubst test (D) beyond what is there.
- Do not change `bin/cluster-status`, `scripts/plugins/observability.sh`, `bin/k3dm-machine-secrets` or
  `_observability_restore_alertmanager_access_layer`.
- Do not change `TRIPWIRE_TOOLS`, the shim passthrough list or `_tripwire_is_read`.
- Do not change the `make fast-gate BASE=` interface, the positional argument of `fast_gate.sh`, or any dashboard
  assertion in `agent_dispatch_dashboard.bats` (only the variable name and the baseline source).
- Do not run the real full fast gate inside a test; use a scratch repo or fixture suite. Do not change
  `fast_gate.sh` beyond `unset BASE` in `worker()` and the two `scripts/tests/host/` exclusions.
- Do not touch the promtool fallback (`fast_gate.sh:48-60`, the C2 files): C2 is a separate dispatch.
- Do not edit `CHANGELOG.md`, `docs/` or `memory-bank/`.
