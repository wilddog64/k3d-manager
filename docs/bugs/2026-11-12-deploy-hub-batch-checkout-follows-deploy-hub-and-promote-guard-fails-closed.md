# deploy/hub batch: the hub checkout follows deploy/hub, the promote guard fails closed, and four P3s on the same files

**Status:** OPEN — batch fix spec, written 2026-11-12
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** v1.43.15 (checkout auto-sync and deploy/hub promote plans)
**Should have been caught by:** offline test
**Prior art:** none above threshold — this is a batch spec over six captured docs; each doc carries its own Prior art line
**Approval:** operator, 2026-11-12 ("dispatch as you suggest": deploy/hub batch first, in the bug slot)
**Intent approved:** operator, 2026-11-12
**Intent approval source:** "aporved" (operator, 2026-11-12), from https://claude.ai/artifact/JJJykdXexdKzfdoQ5cKXcm; every decision at its default
**Decisions:** operator, 2026-11-12, all Accept: missing role file exits 1; backup ref is the only copy kept; containment failure warns in status and refuses promote/rollback even with BREAK_GLASS; new result words; Part G regression test only; Claude edits `.github/copilot-instructions.md:42,139` at land
**Filed:** 2026-11-12
**Branch:** `k3d-manager-v1.44.0`
**Agent:** Codex `gpt-6-luna`; cross-vendor diff review Flash 3.8 (`gemini-3.8-flash-medium`)

One dispatch, because one dispatch per file: all six touch `bin/k3dm-repo-sync`, `bin/k3dm-hub-promote` or
`bin/k3dm-hermes`. `docs/plans/v1.44.0-deploy-hub-behind-alert.md` edits the first two and waits for this batch.

| Part | Doc | Priority |
|---|---|---|
| A | `docs/bugs/2026-11-12-hub-checkout-stops-following-deploy-hub-and-promote-guard-fails-open.md` (defect 1) | P2 |
| B | the same doc (defect 2) | P2 |
| C | `docs/bugs/2026-11-10-hub-promote-status-ahead-counts-local-release-branch.md` | P3 |
| D | `docs/bugs/2026-11-10-repo-sync-reports-zero-behind-for-diverged-checkout.md` | P3 |
| E | `docs/bugs/2026-11-10-hermes-checkout-lag-compares-newest-release-not-deploy-hub.md` | P3 |
| F | `docs/bugs/2026-11-11-repo-sync-role-defaults-to-worker.md` | P3 |
| G | `docs/bugs/2026-11-11-hub-promote-non-tty-tests-hang-when-stdin-is-a-terminal.md` | P3 |

Read every doc above in full before starting. Parts C, D and E keep the Fix, Contract readers and Acceptance their own
docs already carry (intents approved 2026-11-10/11); they are restated below with new IDs so one verifier can work from
one block.

Revised 2026-11-12 after the Argon cross-vendor spec review: Claude checked each finding against the code. Below, "proved
2026-11-12" means a scratch script on the M4 (`git` 2.x, `bash` 5) showed it.

## Fix

**A. The hub checkout follows deploy/hub (`bin/k3dm-repo-sync`, hub role, k3d-manager root only).** Today `:200-204`
stops with `skipped:not-ff-to-deploy-hub` when `HEAD` is not an ancestor of `<remote>/deploy/hub`. After the fetch and
the fresh counts (`:194-199`), the hub root does this, in order:

1. `HEAD` is an ancestor of `<remote>/deploy/hub`: `merge --ff-only` as today (`updated`, `current`, or `blocked`).
2. Not an ancestor, and dirty: stop with `skipped:dirty`, move nothing, write no backup ref. Dirty means
   `git status --porcelain --untracked-files=no` is not empty, or a path that `<remote>/deploy/hub` adds
   (`git diff --name-only --diff-filter=A HEAD <remote>/deploy/hub`) already exists in the working tree. `reset --hard`
   overwrites such an untracked or ignored file silently, where `merge --ff-only` refuses (proved 2026-11-12). Other
   untracked files do not count.
3. Not an ancestor, clean: `git update-ref refs/k3dm/repo-sync-backup/<UTC yyyymmddTHHMMSSZ> <old_head> ""`
   (create-only; on failure, result `blocked` and no reset), then `git reset --hard <remote>/deploy/hub` (on failure,
   result `blocked`; the backup ref stays). On success: result `reset-to-deploy-hub`, `new_head` the new `HEAD`,
   `behind_after` measured as on the fast-forward path, and the record gains `"backup_ref": "<full ref name>"`. That key
   exists only on `reset-to-deploy-hub` records. The log line is today's (`:361`) plus
   ` old=<old_head> new=<new_head> backup=<backup_ref>` (full SHAs), for that result only.
4. `--check` still fetches and moves nothing (`:167-171`). For the hub root when `HEAD` is not an ancestor of the
   already-fetched `<remote>/deploy/hub`, it reports `skipped:dirty` (step 2's test) or `would-reset-to-deploy-hub`.
5. `main()` treats `reset-to-deploy-hub` like `updated`: it sets `last_success_timestamp_seconds` (`:278`) and runs the
   webhook-restart diff (`:294-296`). `git diff old..new` compares two trees, so a rollback to an ancestor still lists
   its paths (proved 2026-11-12); keep it.
6. Use the configured `remote`, never a literal `origin`: `:201` and `main()`'s `:318`, `:354`, `:356`. `result_for`
   stores it on the hub root record as `"remote"`; `main()` reads `root_rec.get("remote") or "origin"`.
7. Worker-role checkouts and every repository other than the hub's k3d-manager root never reset. Every result exits 0,
   as today.

Why reset is right: the hub checkout is a deploy target, not a work area; `deploy/hub` only moves through
`make hub-promote` or `make hub-rollback`, both typed-confirmation gated. The backup ref keeps any commit the reset
would leave behind. The CVE promoter clones into a temp dir (`scripts/etc/argocd/platform-ops/app-cve-scan.sh:566-590`)
and never touches the hub checkout.

**B. The promote containment guard fails closed (`bin/k3dm-hub-promote`; `REMOTE` is the fixed `origin`, `:13`).**

1. In `promote`, after `old="$(remote_sha 1)"` (`:252`) and the no-op check (`:253-256`), when `old` is not all zeros
   (bootstrap skips this step): `git_cmd fetch --no-tags "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH"`
   or `die "cannot fetch $REMOTE $BRANCH"`; then `git_cmd cat-file -e "$old^{commit}"` or
   `die "deploy/hub commit $old is not available locally; refusing to promote"`. If deploy/hub moves again after
   `ls-remote`, a forward move keeps `old` reachable and a force-move makes the check die; the lease still guards the push.
2. `uncontained_commits` (`:21-27`) drops `2>/dev/null` and `|| true`: git's error reaches stderr and, with `pipefail`,
   the function returns non-zero when `git cherry` fails.
3. Every caller captures it by command substitution, never `< <(...)`: a failure or `die` inside process substitution
   ends only the subshell, the loop reads zero lines and the parent goes on (proved 2026-11-12). Form:
   `list="$(uncontained_commits "$target" "$old")" || die "cannot check deploy/hub containment ($old against $target)"`,
   then `[[ -z "$list" ]] || mapfile -t uncontained <<< "$list"`.
   - promote (`:257-260`) and rollback (`:220-223`): `die` as above, whatever `BREAK_GLASS` says. Rollback is
     otherwise unchanged.
   - status (`:153-156`): print `[hub-promote] WARNING: cannot check deploy/hub containment` to stderr, exit 0.
4. The lease, the confirmation text and the tag-push order are unchanged.

**C. As its doc's Fix, with these decisions (`status()`, `:137-162`).**

1. The fallback release (`:145`) uses `--format='%(refname:lstrip=3)'`, so it is a bare branch name (today it is
   `origin/k3d-manager-v…`, which would make `refs/remotes/origin/origin/…`).
2. `git_cmd fetch --quiet --no-tags "$REMOTE" "+refs/heads/$release:refs/remotes/$REMOTE/$release"
   "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH"`. It may move those two remote-tracking refs and nothing else. On
   failure print `[hub-promote] WARNING: fetch failed; counts may be stale` to stderr and go on.
3. `ahead` is `git rev-list --count "$sha..refs/remotes/$REMOTE/$release"`, `?` if that fails; never the local branch.
4. When `refs/heads/$release` exists and differs from `refs/remotes/$REMOTE/$release`, print
   `[hub-promote] local <release> is N behind / M ahead of origin` (both numbers, from `rev-list --left-right --count`).
   No line when they agree or the local branch does not exist.
5. status never changes `refs/heads/*`, `refs/tags/*`, `HEAD`, the index or the working tree. The `M5` test
   (`hub_promote.bats:635-643`) compares `git for-each-ref refs/heads refs/tags`, `HEAD`, `write-tree` and
   `status --porcelain` instead of all of `git show-ref`, which the fetch may change.

**D. As its doc's Fix (`bin/k3dm-repo-sync`), with these decisions.**

1. Remove the pre-fetch `skipped:ahead` return (`:164-166`): an upstream not fetched yet looks ahead-only there, so a
   diverged checkout is never seen as behind. Classify on the fresh counts after the fetch (`:196-199`): ahead and
   behind is `skipped:diverged`, ahead only is `skipped:ahead`. `--check` (no fetch) applies the same rule to the
   pre-fetch counts.
2. Every path that does not move the checkout after a count was taken (`skipped:ahead`, `skipped:diverged`,
   `skipped:dirty`, `blocked`, `fetch_failed`, and `--check`'s results) sets `behind_after = behind_before`. Paths that
   return before any count (`skipped:missing`, `not-repository`, `detached`, `operation-in-progress`, `no-upstream`)
   keep 0 and 0.
3. `repo_sync.bats:172-187` ("ahead and diverged"): its clone is 1 ahead and 1 behind after the fetch, so `:186` asserts
   `skipped:diverged`; add an ahead-only case that asserts `skipped:ahead`.

**E. As its doc's Fix (`bin/k3dm-hermes`), with these decisions.** Hermes uses the literal `origin`, like every other git
call in the file (`:610`, `:714-729`); it has no configured remote.

1. `_refresh_index` replaces the lag's upstream-branch fetch (`:723-737`) with
   `git fetch --quiet origin +refs/heads/deploy/hub:refs/remotes/origin/deploy/hub`, with or without `K3DM_INDEX_REF`.
   On failure print `hub checkout lag skipped: deploy/hub fetch failed` to stderr and push no lag.
2. `_push_checkout_lag(lag_ref)` takes one argument, called with `"origin/deploy/hub"`. It counts `HEAD..<lag_ref>` on
   code paths as today and pushes `k3dm_hub_checkout_code_commits_behind{branch="deploy/hub"}` and
   `k3dm_hub_checkout_last_check_timestamp_seconds`; it never pushes `k3dm_hub_checkout_on_newest_release`.
3. The index ref logic (`:701-722`, `state["index_ref"]`, `_newest_release_branch`) is unchanged.
4. Panel 19 (`grafana-dashboard-bugs.yaml:384-400`): delete target `B` and its `byFrameRefID` `B` override
   (`"overrides": []`); target `A` stays. New description: "Code commits promoted to deploy/hub that the hub's checkout
   has not pulled yet. repo-sync pulls them within about 5 minutes. Commits not yet promoted are not counted: see make
   hub-promote-status. Doc text does not need a pull."

**F. A missing or empty machine-role file fails closed (`bin/k3dm-repo-sync`).** `role()` (`:83-88`) returns `missing`
when the file cannot be read or is empty after `strip()`, as `bin/k3dm-require-role:5-8` does. `main()` checks it right
after parsing arguments, before the lock (`:248-250`): when `missing`, repo-sync syncs no repository, writes no
state.json, pushes nothing, prints `[repo-sync] ERROR: machine-role file missing or empty: <path>` to stderr and exits 1.
This covers the default run and `--check`; `--remote` and `--hub-summary` read no role and are unchanged. Any other value
keeps today's meaning (only `hub` is hub). `K3dmRepoSyncStale` then fires after its window, the intended signal.

**G. Only the regression test is left.** Every direct promoter call in `scripts/tests/bin/hub_promote.bats` already has
`< /dev/null` and the TTY cases use `_run_promoter_tty` (checked 2026-11-12; `script -q /dev/null bats -f non-TTY
scripts/tests/bin/hub_promote.bats` passed, rc 0). Add one test that runs `bats -f 'N2: non-TTY'` on this file under
`script -q /dev/null`, bounded at 60 s with `perl -e 'alarm 60; exec @ARGV'` (macOS has no `timeout`), and asserts rc 0.
Its own name must not match that filter.

Out of scope (noted in the A/B doc, suspected, not reproduced): the tag-push-after-branch-push failure at
`bin/k3dm-hub-promote:123-133`. Do not change it.

## Files

| File | Parts |
|---|---|
| `bin/k3dm-repo-sync` | A, D, F |
| `bin/k3dm-hub-promote` | B, C |
| `bin/k3dm-hermes` | E |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | E (panel 19: description, delete target `B` and its override) |
| `scripts/tests/bin/repo_sync.bats` | A, D, F. Rewrite `:416-435`: its clean hub checkout with a local commit is now reset, so it becomes M1's local-commit case and keeps its no-push, no-promote assertions. `:186` per D.3 |
| `scripts/tests/bin/hub_promote.bats` | B, C, G; `M5` at `:635-643` per C.5 |
| `scripts/tests/bin/test_hermes_checkout_lag.py` | E; move the calls at `:102-161`, `:181-213` to the new signature and drop the newest-release assertion at `:161` |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | E; `:31-40` assert no target `B`, no override, no "older release" and no `BRANCH=` |
| `docs/howto/hub-promote.md` | A (the "carried promoter commit" and rollback paragraphs: the hub now follows by itself) |
| `docs/howto/checkout-auto-sync.md` | A, D, F (`:5` says the sync never resets and skips local commits; add the hub-root reset, `skipped:diverged`, `skipped:dirty` and the missing-role exit) |
| `docs/howto/hub-sync.md` | E (`:11-16`: drop the second value and the second fetch) |
| `.github/copilot-instructions.md` | `:42` ("default `worker`", "never merges or resets") and `:139`. **Claude edits these at land**: `land` refuses worker edits to instruction files |

## Contract readers

Found by `git grep`, 2026-11-12, and rechecked after the spec review.

| Contract | Component | Role | Change |
|---|---|---|---|
| repo-sync `result` word (state.json, log, `k3dm_repo_sync_result{result}`) | `bin/k3dm-repo-sync:165,198,203` | writer | new `reset-to-deploy-hub`, `would-reset-to-deploy-hub`, `skipped:dirty`, `skipped:diverged`; `skipped:not-ff-to-deploy-hub` no longer written |
| same | `bin/k3dm-repo-sync:278` (last success), `:294` (webhook diff) | reader | `reset-to-deploy-hub` counts as `updated` (A.5) |
| same | `scripts/etc/prometheus/rules/repo-sync.yaml:14` (`result=~"blocked\|fetch_failed"`, last success) | reader | rule unchanged. A hub held at `skipped:dirty` or `skipped:diverged` sets no last success, so `K3dmRepoSyncStale` fires after 60 min (intended); a reset sets it |
| same | `bin/k3dm-repo-sync:241` (`--hub-summary`) | reader | none (prints the new word) |
| same | `scripts/tests/bin/repo_sync.bats:186`, `:416-435` | reader | updated (D.3; rewritten as an M1 case) |
| same | `docs/howto/checkout-auto-sync.md:5`, `.github/copilot-instructions.md:42,139` | reader (people, agents) | text updated |
| state.json `backup_ref`, `remote` (new keys) | `bin/k3dm-repo-sync` `result_for` | writer | new; read by `main()` (`remote`) and people |
| `refs/k3dm/repo-sync-backup/*` (new) | `bin/k3dm-repo-sync` | writer | new; nothing reads it but people |
| hub checkout `HEAD` | webhook, Hermes, launchd agents, `bin/` on the M5 | reader | now follow `deploy/hub` after a rollback or a carried promoter commit (the intended effect) |
| `deploy/hub` | `bin/k3dm-hub-promote:123` (`record_move`, promote and rollback) | writer | promote and rollback refuse when containment cannot be checked; no other change |
| `deploy/hub` | CVE promoter `scripts/etc/argocd/platform-ops/app-cve-scan.sh:566-590` | writer | none: its commits are kept by B instead of being dropped in the race |
| `refs/remotes/origin/deploy/hub` | `bin/k3dm-repo-sync:148-153`; new: `bin/k3dm-hub-promote` (B.1, C.2), `bin/k3dm-hermes` (E.1) | writer | same forced refspec everywhere; on the M5 Hermes and repo-sync share the checkout, which is safe for a fetch |
| `uncontained_commits` output | `bin/k3dm-hub-promote:156` (status), `:223` (rollback), `:260` (promote) | reader | capture form (B.3) |
| `make hub-promote-status` output | people; `scripts/tests/bin/hub_promote.bats:635-643`, `:842-851` | reader | new local-vs-origin line; `M5` comparison narrowed (C.5) |
| `machine-role` file | `bin/k3dm-machine-setup:729` | writer | none |
| same | `bin/k3dm-require-role:4` | reader | none (already fails closed) |
| same | `bin/k3dm-repo-sync:84` | reader | missing or empty now fails closed (F) |
| `k3dm_repo_sync_behind_commits` | writer `bin/k3dm-repo-sync:363`; reader `repo_sync.bats:236` (name only) | both | value on non-moving paths (D) |
| `k3dm_hub_checkout_code_commits_behind` | writer `bin/k3dm-hermes:644`; readers `grafana-dashboard-bugs.yaml:392`, `grafana_dashboard_bugs.bats:32-33`, `test_hermes_checkout_lag.py` | both | `branch` label becomes `deploy/hub`; expression unchanged |
| `k3dm_hub_checkout_on_newest_release` | writer `bin/k3dm-hermes:645`; readers `grafana-dashboard-bugs.yaml:393,398`, `grafana_dashboard_bugs.bats:34-40`, `test_hermes_checkout_lag.py:161`, `docs/howto/hub-sync.md:13-16` | both | removed everywhere |

## Acceptance

N1 and N2 of the first draft are now M10 and M11: pre-fix code never resets, so they cannot be red before the fix. They
guard the new reset and are shown red by mutation (Definition of done, item 2). The same holds for the regression parts
of M7 and for M9. Every remaining `must_not` is red on today's code.

```yaml
must:
  - id: M1
    text: "Hub role, clean checkout, HEAD not an ancestor of <remote>/deploy/hub (after a rollback, after a carried promoter commit, or with a local commit): one repo-sync run leaves HEAD equal to <remote>/deploy/hub, records reset-to-deploy-hub with old_head, new_head and backup_ref, and that backup ref points at the old HEAD. --check in the same state reports would-reset-to-deploy-hub and moves nothing."
  - id: M2
    text: "Hub role, a pure fast-forward to deploy/hub still reports updated, creates no backup ref."
  - id: M3
    text: "promote refuses when a promoter commit lands on deploy/hub between the fetch and ls-remote (listing that commit), when deploy/hub's commit is not available locally after the fetch (naming the SHA), and when git cherry fails (cannot check deploy/hub containment); a bootstrap promote with no deploy/hub still works after the confirmation."
  - id: M4
    text: "The hub path uses the configured remote, never a literal origin."
  - id: M5
    text: "hub-promote-status reports the count of commits on origin's release branch that deploy/hub lacks, says when the local branch differs from origin, and leaves local branches, tags, HEAD, the index and the working tree unchanged."
  - id: M6
    text: "A checkout 1 ahead and 3 behind its upstream, not fetched before the run, reports skipped:diverged with 3 behind before and after, HEAD unchanged; an ahead-only checkout reports skipped:ahead; a behind-only checkout still fast-forwards and reports 0 after."
  - id: M7
    text: "On the hub, the Hermes lag count is the number of code commits in origin/deploy/hub that HEAD lacks; unpromoted release-branch commits do not raise it. The document index ref is unchanged and the tile has no BRANCH= text (regression guard: both already true before the fix)."
  - id: M8
    text: "With no machine-role file, or an empty one, repo-sync syncs no repository, writes no state.json, prints the missing-or-empty error and exits 1."
  - id: M9
    text: "hub_promote.bats finishes when run with a terminal as stdin (regression guard: already true before the fix)."
  - id: M10
    text: "Hub role, HEAD not an ancestor of deploy/hub, and a tracked edit or an untracked file at a path deploy/hub adds: the result is skipped:dirty; HEAD, the files and the untracked file are unchanged and no backup ref is written."
  - id: M11
    text: "A worker-role checkout, or any repository other than the hub's k3d-manager root, is never reset, even when it is not a fast-forward."
  - id: M12
    text: "A reset counts as a successful sync: last_success_timestamp_seconds is the run time, and webhook_restart_pending is set when the reset changes a webhook path, including a rollback to an ancestor."
must_not:
  - id: N3
    text: "promote never force-pushes deploy/hub without BREAK_GLASS when the old deploy/hub commit has commits the target does not contain, including when that commit arrived between the fetch and ls-remote."
  - id: N4
    text: "hub-promote-status never reports a count taken from a local branch that differs from origin."
  - id: N5
    text: "A checkout that was not moved never reports fewer commits behind after the run than before."
  - id: N6
    text: "Hermes never pushes k3dm_hub_checkout_on_newest_release, and the Hub code behind tile never shows older release."
  - id: N7
    text: "A missing or empty machine-role file never makes repo-sync act as worker."
evidence:
  - id: E1
    proves: [M1, M2, M10, M11]
    kind: offline
    intent: >-
      You will see repo_sync.bats build a scratch bare origin and a scratch HOME, then: after a rollback E to D, after a
      carried promoter commit, and with a local commit on the hub, --check first says would-reset-to-deploy-hub and one
      run puts the hub checkout at deploy/hub, with state.json naming a backup ref at the old HEAD; a plain fast-forward
      still says updated with no backup; a dirty hub checkout, an untracked file in deploy/hub's way and a worker checkout
      are left exactly as they were. Against today's code the stuck cases stay stuck.
  - id: E2
    proves: [M3, N3]
    kind: offline
    intent: >-
      You will see hub_promote.bats land a promoter commit on deploy/hub between the fetch and ls-remote (a git
      wrapper, as in the Fable reproduction): promote refuses and lists that commit, and deploy/hub on the scratch
      origin is unchanged. Against today's code it prints "no commits between refs" and force-pushes. Two more cases
      refuse: a deploy/hub commit that cannot be fetched (the message names the SHA) and a failing git cherry ("cannot
      check deploy/hub containment"). The bootstrap test still passes.
  - id: E3
    proves: [M4]
    kind: offline
    intent: >-
      You will see a test with the scratch remote named something other than origin: the hub path fetches,
      compares and resets against that remote. Against today's code the ancestor check fails on the missing origin ref.
  - id: E4
    proves: [M5, N4]
    kind: offline
    intent: >-
      You will see a bats case where the local release branch is 3 behind origin and origin is 5 past deploy/hub:
      status prints ahead 5 (not 2) and "local ... is 3 behind / 0 ahead of origin", and HEAD, the index, the working
      tree, every local branch and every tag are unchanged.
  - id: E5
    proves: [M6, N5]
    kind: offline
    intent: >-
      You will see a checkout with 1 local commit and 3 behind, not fetched before the run, log skipped:diverged (3
      behind before, 3 after) and push 3; an ahead-only checkout logs skipped:ahead; the existing fast-forward test
      passes unchanged as the paired control. Against today's code the first case logs skipped:ahead (0 behind before,
      0 after).
  - id: E6
    proves: [M7, N6]
    kind: offline
    intent: >-
      You will see test_hermes_checkout_lag.py report 0 when the release branch is 3 code commits past deploy/hub and
      the checkout equals deploy/hub, then 2 when deploy/hub moves 2 ahead, with no newest-release metric pushed and
      the index ref the same as before; the dashboard test finds no "older release" mapping and no BRANCH= text in the
      tile. Against today's code the first case reports 3 and the tile still has the "older release" mapping.
  - id: E7
    proves: [M8, N7]
    kind: offline
    intent: >-
      You will see repo-sync run with a scratch HOME that has no machine-role file, then an empty one: each time it
      exits 1 with the error, writes no state.json and no scratch repository moves; with the file set to worker (the
      paired control) the same repositories fast-forward.
  - id: E8
    proves: [M9]
    kind: offline
    intent: >-
      You will see the N2 non-TTY case run under script(1), so stdin is a terminal, and finish within 60 seconds.
      Today's test file already passes it; the worker shows the check fail by deleting that case's stdin redirect, then
      restores it.
  - id: E9
    proves: [M1, M7]
    kind: live
    intent: >-
      After the operator promotes the fix, Claude reads the M5 repo-sync log and state.json: the hub checkout equals
      origin/deploy/hub and Hermes' "Hub code behind" tile reads 0 while the release branch has unpromoted commits.
      A rollback drill is not required; if one happens, Claude shows the checkout following it within one run.
  - id: E10
    proves: [M12]
    kind: offline
    intent: >-
      You will see repo_sync.bats roll deploy/hub back over a commit that changed webhook code: after one run,
      state.json shows this run's time as the last success and webhook_restart_pending true. Against today's code the
      run is skipped and neither changes.
interface:
  - "bin/k3dm-repo-sync [--check] (ROOT is the script's parent directory, so tests copy it into the scratch hub checkout's bin/ as prepare_hub_checkout does; XDG_CONFIG_HOME/k3d-manager/machine-role, K3DM_REPO_SYNC_REPOS, K3DM_REPO_SYNC_STATE_DIR, state.json, log lines on stdout, Pushgateway body via PUSHGATEWAY_URL)"
  - "bin/k3dm-hub-promote promote REF [BREAK_GLASS=1] | rollback [BREAK_GLASS=1] | status (REPO_ROOT is the script's parent directory and REMOTE is fixed to origin; env RELEASE_BRANCH, GH_REPO)"
  - "bin/k3dm-hermes _refresh_index(state, now) and _push_checkout_lag(lag_ref), loaded by test_hermes_checkout_lag.py with ROOT monkeypatched to a scratch clone (there is no CLI subcommand)"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (Hub code behind tile, panel 19)"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests: `repo_sync.bats`,
   `repo_sync_promote_backlog.bats`, `repo_sync_launchd_env.bats`, `hub_sync.bats`, `hub_promote.bats` (with
   `< /dev/null`), `grafana_dashboard_bugs.bats`, `test_hermes_checkout_lag.py`. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item, and for the regression guards M7 (index ref, `BRANCH=`), M9, M10 and M11: break the guard
   that enforces it (comment out the check, invert the condition, drop the role gate or the dirty test, delete the
   stdin redirect), run its test, show it red, then restore the guard and show it green. List any whose test stayed
   green with the guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## What NOT to do

- Do not run `bin/k3dm-repo-sync`, `bin/k3dm-hub-promote` or `bin/k3dm-hermes` against the real checkout, the real
  `~/.config`, the real Pushgateway or GitHub. Every test uses a scratch HOME, a scratch bare origin and a stubbed
  `PUSHGATEWAY_URL` (`http://127.0.0.1:9`).
- Do not change the lease, the typed confirmation, the tag-push order, or rollback beyond B.3 in `bin/k3dm-hub-promote`.
- Do not read `uncontained_commits` through `< <(...)` anywhere.
- Do not reset any checkout other than the hub's k3d-manager root, and do not drop the worker `reset` grep in
  `repo_sync.bats:409-411`.
- Do not change Hermes' document index ref logic.
- Do not edit `.github/copilot-instructions.md`; Claude does at land.
