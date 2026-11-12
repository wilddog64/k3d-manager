# Bug: repo-sync reports 0 commits behind for a checkout it skipped because it has local commits

**Status:** OPEN
**Priority:** P3
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (Post-run behind-commit log and metric falsely report 0 for skipped checkouts, though core sync behavior is intact and operators can check the `behind before` log count or `git status` as a workaround); Claude proposed P3. Higher stands until the operator decides.
**Triage:** carry → v1.44.0 (deploy/hub batch) — grooming 2026-11-12, operator. Priority: operator kept Claude's P3 over Argon's P2.
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** `f310b4d4` (checkout-auto-sync)
**Should have been caught by:** review (the plan defines the metric as commits behind; no test covers a diverged checkout)
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store context missing on the M4, 2026-11-10). Related: `docs/plans/v1.43.15-checkout-auto-sync.md`
**Severity:** misleading log line and metric, no alert reads it. A checkout with local commits that is also behind
its upstream is correctly left alone, but the log says `0 after` and `k3dm_repo_sync_behind_commits` is 0, so it looks
current. Workaround: read the `behind before` number in the log, or run `git status` in that checkout.
**Approval:** Claude, 2026-11-10 (found on the first M4 run after the operator ran `make install-repo-sync`)
**Intent approved:** operator, 2026-11-11 ("P2/P3 approved")
**Filed:** 2026-11-10
**Detected by:** Claude, first repo-sync run on the M4, 2026-11-10
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, M4, 2026-11-10)

- `~/.local/share/k3d-manager/logs/repo-sync.log`, first run after install:
  `zshdotfiles: main skipped:ahead (3 behind before, 0 after)`.
- `git -C ~/src/gitrepo/personal/zshdotfiles rev-list --left-right --count HEAD...@{u}` → `1	3`: 1 ahead, 3 behind,
  unchanged by the run. The true value after the run is 3.
- `bin/k3dm-repo-sync:108` initialises `behind_after` to 0; the two `skipped:ahead` returns (`:149`, `:169`) leave it
  there. Only the fast-forward path sets it (`:188`). The log line (`:329`) and the metric (`:331`) print it.

## Fix

On every path that does not move the checkout (`skipped:*`, `fetch_failed`, `--check`), set `behind_after` to the
behind count already measured (`behind_before`). Name a diverged checkout `skipped:diverged` when it is both ahead and
behind, and keep `skipped:ahead` for ahead only.

## Files

| File | Change |
|---|---|
| `bin/k3dm-repo-sync` | `behind_after` on non-moving paths; `skipped:diverged` |
| `scripts/tests/bin/repo_sync.bats` | diverged-checkout test and its paired control |

## Contract readers

- `k3dm_repo_sync_behind_commits{repo}`: writer `bin/k3dm-repo-sync:331`; readers `scripts/tests/bin/repo_sync.bats:236`
  (name only, unchanged). No dashboard or PrometheusRule reads it (`git grep`, 2026-11-10).
- The `result` word in the log: read only by people. `skipped:diverged` is new; `skipped:ahead` keeps its meaning.

## Acceptance

```yaml
must:
  - id: M1
    text: "For a checkout 1 ahead and 3 behind its upstream, the log and the metric report 3 behind after the run, and the checkout is not moved."
  - id: M2
    text: "A checkout that is only behind still fast-forwards and reports 0 after."
must_not:
  - id: N1
    text: "A checkout that was not moved never reports fewer commits behind after the run than before it."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see a test with a scratch upstream where the checkout has 1 local commit and is 3 behind: the log reads skipped:diverged (3 behind before, 3 after), the metric is 3, and HEAD is unchanged. Against today's code it reads 0 after."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see the existing fast-forward test pass unchanged as the paired control."}
  - {id: E3, proves: [M1], kind: live, intent: "Claude shows the next M4 run logging zshdotfiles with 3 after (or 0 if the operator has reconciled it by then)."}
interface:
  - "bin/k3dm-repo-sync (log lines on stdout, Pushgateway body)"
```

## Worker definition of done

- Change only the files above. Show E1 red against today's code, then green. Paste command, rc and proving lines.
  Leave changes uncommitted; Claude reviews and lands.
