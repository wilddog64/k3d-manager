# hub-promote containment check refuses the first promote of every release: `git cherry` cannot see squash merges

**Status:** OPEN
**Priority:** P2 (proposed: blocks every first promote of a new release; workaround BREAK_GLASS=1 after a manual check, which also skips the green-checks gate)
**Classified:** pending second-agent classification
**Introduced by:** `aa97c491` (v1.43.15, the uncontained-commits guard from `2026-11-10-hub-promote-discards-cve-promoter-commits.md`)
**Should have been caught by:** spec (the guard's spec did not consider that releases are squash-merged to `main` and the next release is cut from `main`)
**Prior art:** `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` (grep `cherry`/`squash`, read) — this bug is a false positive of that fix
**Waiting on:** dispatch — since 2026-11-14 (held: Makefile is open in parallel-offline-tests-b)
**Intent approved:** operator ("go ahead"), 2026-11-14

## Symptom

2026-11-12 on the M5: `make hub-promote REF=34707659f2bddc36192d4c49e5fe65acdc9d6de5` (v1.44.0 tip, CI green) failed with
`[hub-promote] ERROR: deploy/hub contains N commit(s) not in …` and listed about 100 v1.43.15 commits ending in `9f5f0d89`.

## Cause

`uncontained_commits` (`bin/k3dm-hub-promote:21-27`) uses `git cherry <new> <old>`, which matches commits by per-commit
patch-id. v1.43.15 merged to `main` as one squash commit (`aa1196ed`, PR #160), and v1.44.0 was cut from `main`,
so none of v1.43.15's original commits match. Every one is reported as "not contained" although its content is in the target.

## Evidence (Claude, 2026-11-12)

- `git merge-base --is-ancestor 9f5f0d89 5a53e35b`: the `deploy/hub` tip is an ancestor of PR #160's head.
- `git rev-list --count 5a53e35b..origin/deploy/hub` = 0: no promoter or other commit outside the PR.
- `git diff --stat aa1196ed 5a53e35b`: 3 files and 4 lines, all newer dependabot bumps on `main`.
- `aa1196ed` is an ancestor of `34707659`.

So the promote drops nothing. It was done with `BREAK_GLASS=1`, which also skips `check_runs`. Claude had checked
both check runs green on `34707659` beforehand.

## Fix direction (for triage)

Treat an `old` commit as contained when it is an ancestor of a merged PR head whose squash commit is an ancestor of
`new` (via `gh api repos/…/commits/<sha>/pulls`). Or, simpler: before the cherry check, accept `old` when the
tree of `old` merged into `new` equals `new`'s tree (`git merge-tree --write-tree new old` with no conflicts). Keep
`check_runs` independent of BREAK_GLASS so the bypass skips only the guard that misfired.

## Outcome (2026-11-13)

The operator promoted with `BREAK_GLASS=1` at 00:34Z: `deploy/hub` moved to 34707659. The tag push then failed in the
pre-push fast gate (`scripts/ci/fast_gate.sh:129-136`): the M5 checkout's `k3d-manager-v1.44.0` still pointed at the
v1.43.15 history (9f5f0d89), whose squashed-away commits (fcc4fa4a, bb71f0cb, …, 2026-11-09) carry
`test@example.invalid`. Same root cause as this bug: individual commits outliving a squash merge. After
`git reset --hard origin/k3d-manager-v1.44.0` (backup `refs/k3dm/manual-backup/20261112`) the tag
`hub-promote/20261113T003457Z` pushed, and `make platform-ops` applied deploy/hub 34707659.

## Decision 2026-11-14

Operator, 2026-11-14: "go with your recommendations" — accept `old` as contained when `git merge-tree --write-tree new old` merges without conflict and the result's tree equals `new`'s tree (no GitHub API). `check_runs` stays independent of `BREAK_GLASS`.

## Spec (2026-11-14; drafted by Sonnet, reviewed by Claude)

## Symptom

`make hub-promote REF=<first commit of a new release>` fails with `[hub-promote] ERROR: deploy/hub contains N commit(s) not in <ref>` and lists every commit of the previous release, although the previous release is squash-merged into `main` and the new release is cut from `main`. The only way through is `BREAK_GLASS=1`, which today also skips the green-checks gate.

## Cause (verified against the file today)

1. `uncontained_commits` (`bin/k3dm-hub-promote:21-27`) uses `git cherry "$target" "$old"` and keeps the `+` rows (`:26`). `git cherry` matches by per-commit patch-id, so squashed-away commits are all `+`.
2. `promote` refuses on any `+` row unless `break_glass == 1` (`bin/k3dm-hub-promote:296-304`).
3. `BREAK_GLASS` also skips the check-run gate: `bin/k3dm-hub-promote:305`: `if [[ "$break_glass" != 1 ]]; then check_runs "$new"; fi`. Confirmed: today BREAK_GLASS=1 skips BOTH the containment refusal (`:298-304`) and `check_runs` (`:305`). The test "H4: break glass skips only checks ..." (`scripts/tests/bin/hub_promote.bats:486-494`) runs `_run_promoter_tty promote empty promote ... 1` with the `empty` gh stub (no check runs) and expects success, and `docs/howto/hub-promote.md:82-83` documents "`BREAK_GLASS=1` skips the check-run gate and the containment refusal".
4. `show_and_confirm` (`:90-117`) never reads BREAK_GLASS; it always needs a TTY and the typed word `promote` (`:112-116`). `record_move` only records `mode: break-glass` in the tag (`:128`). Neither changes.

## Evidence (Claude, 2026-11-14, host m4-air, git 2.56.1, read-only probe in a scratch repo under the session scratchpad, never in k3d-manager)

Probe script and run: `/private/tmp/claude-501/-Users-cliang-src-gitrepo-personal-k3d-manager/d8ec82db-c3d1-4633-abb1-0c5957db78ea/scratchpad/probe/run.sh` (env: `GIT_CONFIG_GLOBAL=/dev/null`, scratch `HOME`, identity via env vars). Output, 2026-11-14T12:37:32Z, `git --version` = `git version 2.56.1`:

```
(a) squash-merge scenario: rel1 has 2 commits; main gets one squash commit + a later bump; rel2 cut from main with one commit
$ git cherry NEW OLD
+ ded2296fd04b70b0fa94508a129e525f55a5370c
+ 4dab103c33bdfc9710e3929a1a513e4747c10134
rc=0
$ git merge-tree --write-tree NEW OLD        -> rc=0
c5d702441b28c4b6fc160daf2c2823b8e0bffc2a
new tree: c5d702441b28c4b6fc160daf2c2823b8e0bffc2a      => TREE EQUAL

(b) real uncontained commit on old (cve-pin.txt exists only on old)
$ git cherry NEW OLD
+ 283477700e6ab71e07434f638583100ea4707320
merge-tree rc=0   first line 4b29d729f735066aecc045dfecbdf15fb61527a4
new tree: cd53f351cffb1bfba1a76c9a6265e2eaa6dc71f0      => TREE DIFFERS

(c) both sides edit base.txt differently
merge-tree rc=1
72dce5b0051694f255e1ae968f30d2b377718879
100644 df967b96... 1	base.txt / ... 2	base.txt / ... 3	base.txt
CONFLICT (content): Merge conflict in base.txt            => exit 1, must mean NOT contained

(d) old is an ancestor of new (ff): merge-tree rc=0, first line == new tree   => TREE EQUAL
(e) unrelated histories: "fatal: refusing to merge unrelated histories", rc=128   => must mean NOT contained
```

Findings that shape the fix:

- A clean merge (rc 0) prints the merged tree OID alone on line 1 (then, if any, a blank line and messages). Rc 1 also prints a tree OID on line 1 (of the conflicted merge), so the exit code must be checked first: tree equality alone is not enough.
- Any non-zero rc (1 conflict, 128 unrelated histories or bad object, 129 usage) is treated as NOT contained, falling back to the existing refusal. This is also the behaviour on git older than 2.38, where `--write-tree` is an unknown option (usage error): the guard then behaves exactly as today. Not probed on git < 2.38 (none on this machine): unproven, stated as such.
- `git merge-tree --write-tree` needs git >= 2.38. Machine-local only: this machine has 2.56.1. NOT discoverable in the repo: `grep -rn "merge-tree\|2\.38"` over `docs/howto`, `.github`, `bin`, `scripts/ci` returned nothing; no repo doc names a git minimum. CI runs on `ubuntu-24.04` / `ubuntu-latest` (`.github/workflows/ci.yml:22,39`, `deploy-worker.yml:21`), whose git version was not probed (no network from this session). The M5 hub's git version was not probed. Open question for the operator below; the fail-closed fallback makes an old git harmless (a refusal, as today).

## Fix

All changes in `bin/k3dm-hub-promote`.

## 1. Tree-containment helper and use in `uncontained_commits`

Old block (`bin/k3dm-hub-promote:21-27`, verbatim):

```
21	uncontained_commits() {
22	  local target="$1" old="$2"
23	  if [[ "$old" =~ ^0+$ || -z "$target" || -z "$old" ]]; then
24	    return 0
25	  fi
26	  git_cmd cherry "$target" "$old" | awk '$1 == "+" {print $2}'
27	}
```

New block:

```bash
tree_contained() {
  local target="$1" old="$2" merged first target_tree
  merged="$(git_cmd merge-tree --write-tree "$target" "$old" 2>/dev/null)" || return 1
  first="${merged%%$'\n'*}"
  [[ "$first" =~ ^[0-9a-f]{40,64}$ ]] || return 1
  target_tree="$(git_cmd rev-parse --verify "$target^{tree}" 2>/dev/null)" || return 1
  [[ "$first" == "$target_tree" ]]
}

uncontained_commits() {
  local target="$1" old="$2" list
  if [[ "$old" =~ ^0+$ || -z "$target" || -z "$old" ]]; then
    return 0
  fi
  list="$(git_cmd cherry "$target" "$old" | awk '$1 == "+" {print $2}')" || return 1
  if [[ -n "$list" ]] && tree_contained "$target" "$old"; then
    printf '[hub-promote] note: deploy/hub commits not matched by patch-id, but merging them into %s changes nothing (squash merge); treating as contained\n' "$target" >&2
    return 0
  fi
  [[ -z "$list" ]] || printf '%s\n' "$list"
}
```

Design notes for the worker (do not deviate):

- `cherry` runs first and its failure still returns non-zero (`|| return 1`), so the existing fail-closed path (`:296` `die "cannot check deploy/hub containment"`; test `hub_promote.bats:302-315`) is unchanged. `merge-tree` runs only when cherry found `+` rows, so the common case costs nothing extra.
- Every `merge-tree` failure (rc != 0, no tree line, tree mismatch) returns 1 from `tree_contained`, so `uncontained_commits` prints the cherry list as today. Never treat rc 1 as contained.
- `uncontained_commits` is also called by `status` (`:179`, against the release's origin SHA) and `rollback` (`:246`, against `live_sha`). Both get the same tree-equality acceptance; this is intended (a squash-merged release is not "uncontained" in `status` either). The note goes to stderr so the captured `$(...)` list (stdout) stays clean.
- `git_cmd` is `_run_command --soft -- git -C "$REPO_ROOT"` (`:19`); do not call `git` directly.

## 2. Separate the green-checks gate from BREAK_GLASS

Old line (`bin/k3dm-hub-promote:305`, verbatim):

```
305	      if [[ "$break_glass" != 1 ]]; then check_runs "$new"; fi
```

New line:

```bash
      check_runs "$new"
```

`:298-304` (the containment refusal that BREAK_GLASS bypasses) is unchanged: BREAK_GLASS now bypasses only the uncontained-commits refusal. `show_and_confirm` and `record_move` (`mode: break-glass`) are unchanged. `rollback` never called `check_runs` and is unchanged.

Instead of the bare line above, the worker writes the block in section 2a, which keeps `check_runs "$new"` as the default path.

## 2a. Explicit outage flag `SKIP_CHECK_RUNS` (operator, 2026-11-14: "so make an explicit flag for this")

The GitHub-outage case gets its own flag, separate from BREAK_GLASS, so each bypass is named for the one gate it skips.

- `promote` takes a fourth positional argument `SKIP_CHECK_RUNS` (default `${SKIP_CHECK_RUNS:-0}`, must be `0` or `1`, same validation as BREAK_GLASS at `:282`). Usage strings at `:261` and `:280` gain `[SKIP_CHECK_RUNS=1]`.
- With `SKIP_CHECK_RUNS=1`, `SKIP_CHECK_RUNS_REASON` must be set, non-empty after trimming and single-line (no newline). Otherwise `die 'SKIP_CHECK_RUNS=1 needs SKIP_CHECK_RUNS_REASON="<why>" (one line)'` before any fetch, confirmation or push.
- Replacement for `:305`:

```bash
      if [[ "$skip_checks" == 1 ]]; then
        printf '[hub-promote] WARNING: check-run gate skipped for %s: %s\n' "$new" "$SKIP_CHECK_RUNS_REASON" >&2
      else
        check_runs "$new"
      fi
```

- `record_move` gains a sixth parameter `skip_checks="${6:-0}"`. When it is 1, it appends `mode: skip-check-runs` and `reason: <SKIP_CHECK_RUNS_REASON>` to the tag message, after the existing break-glass line. The promote call at `:307` passes it. `rollback` is unchanged.
- It does not bypass the containment refusal (that stays BREAK_GLASS), the typed confirmation, origin reachability or the lease. A combined outage-plus-uncontained promote needs both flags, and the tag carries both mode lines.
- `Makefile` `hub-promote` (`:477-478`) becomes `@bin/k3dm-hub-promote promote "$${REF:-}" "$${BREAK_GLASS:-0}" "$${SKIP_CHECK_RUNS:-0}"`. `bin/k3dm-hub-deploy` needs no change: it calls `promote "$ref"`, and the defaults read the environment, so `make hub-deploy REF=... SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...` passes through. E10 proves that.

## 3. Docs

`docs/howto/hub-promote.md:81-83`, replace "`BREAK_GLASS=1` skips the check-run gate and the containment refusal" so it says: `BREAK_GLASS=1` skips only the uncontained-commits refusal; the green check-run gate, `origin` reachability, the typed confirmation and the promotion record still apply. Add one sentence: a deploy/hub whose commits were squash-merged into the target is recognised by content (`git merge-tree --write-tree`, git 2.38 or newer) and needs no BREAK_GLASS; on older git the old refusal applies. Document `SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON="..."` as the GitHub-outage path (skips only the check-run gate; recorded in the tag), and say an outage with an uncontained commit needs both flags.

## Contract readers

Contract: the behaviour of `uncontained_commits` / the promote guard (stdout list, exit codes, message text) and the meaning of `BREAK_GLASS`. Greps run 2026-11-14.

`grep -rn "k3dm-hub-promote" bin Makefile scripts docs/howto` and `grep -rn BREAK_GLASS bin Makefile scripts docs/howto`:

- Readers of the promote command:
  - `Makefile:477-478` `hub-promote` passes `"$${BREAK_GLASS:-0}"` as arg 3: unchanged; meaning narrows (no check-run skip). `Makefile:1805` help text `(BREAK_GLASS=1 optional)`: still true.
  - `Makefile:487` `hub-rollback`, `Makefile:490-491` `hub-promote-status`: call `rollback` / `status`; both use `uncontained_commits`, now with tree acceptance. Exit codes and the list format unchanged.
  - `Makefile:493-496` `promote` runs `hub-promote` without BREAK_GLASS: unchanged.
  - `bin/k3dm-hub-deploy:32` runs `k3dm-hub-promote promote "$ref"` (no BREAK_GLASS): unchanged.
  - `bin/k3dm-repo-sync:91` runs `k3dm-hub-promote is-green`: `classify_check_runs` (`:70-78`) untouched.
  - `scripts/tests/bin/hub_deploy.bats:31` and `scripts/tests/bin/repo_sync_promote_backlog.bats:67,192,262` stub or copy the command; they do not read the guard text. `hub_deploy.bats:141-143` greps the promote source for `promote.*"\$ref"`, `confirmation requires a TTY`, `answer.*promote`: those lines are untouched.
- Tests reading the guard output or BREAK_GLASS semantics, all in `scripts/tests/bin/hub_promote.bats`: `:302-315` (cherry fail closed, keep as is), `:486-494` H4 (must change, see Files), `:773-780` Makefile pass-through (change the gh stub mode, see Files), `:874-901` N1 (keeps passing: its BREAK_GLASS call uses `success`), `:937-968` rollback BREAK_GLASS (no `check_runs`, keeps passing), `:970-983` status (keeps passing: the promoter commit is a genuinely uncontained file add).
- Writers of the contract: only `bin/k3dm-hub-promote` itself (`:21-27`, `:305`). `record_move` (`:128`) still writes `mode: break-glass`; its readers (`rollback` replay `:199-203`, test `:486-494`, `:893-900`) are unchanged.
- Docs reading the semantics: `docs/howto/hub-promote.md:81-83` (changed here). `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` and `docs/bugs/2026-11-12-...squash-merges.md` describe it historically; no edit.
- Message contract: the refusal text `deploy/hub contains N commit(s) not in <ref>` (`:300`) and `check_runs` die texts (`:84-86`) are unchanged.

## Acceptance

```yaml
must:
  M1: promote (BREAK_GLASS=0, green checks) succeeds when deploy/hub holds commits that were squash-merged into a release cut from main, i.e. git cherry reports them '+' but merging them into the target changes nothing; deploy/hub moves to the target and a tag is recorded without "mode: break-glass"
  M2: `status` does not report "uncontained commits on deploy/hub" for that same squash-merged situation
  M3: BREAK_GLASS=1 still bypasses the uncontained-commits refusal (genuinely uncontained promoter commit, green checks, confirmation typed): promotes and records "mode: break-glass"
  M4: a stderr note says the commits were matched by content (squash merge) when the tree check is what accepted them
  M5: SKIP_CHECK_RUNS=1 with a one-line SKIP_CHECK_RUNS_REASON promotes when the check-run lookup fails (or runs are missing, pending or failed), after the typed confirmation, and the tag records "mode: skip-check-runs" and "reason: <text>"
must_not:
  N1: BREAK_GLASS=1 skips the check-run gate: with BREAK_GLASS=1 and checks missing, pending, failed or the lookup failing, promote refuses, deploy/hub is unchanged and no promotion tag is created (red on today's code: today it promotes)
  N2: a genuinely uncontained commit on deploy/hub (content absent from the target) is accepted without BREAK_GLASS, including when the same hub also carries squash-merged commits (regression guard; positive control is M1)
  N3: a merge-tree conflict (both sides changed the same lines differently) is treated as contained (regression guard; positive control is M1)
  N4: a merge-tree failure (non-zero exit, e.g. git older than 2.38 or unrelated histories) is treated as contained; promote must refuse exactly as before (regression guard; positive control is M1)
  N5: a git cherry error stops failing closed ("cannot check deploy/hub containment")
  N6: BREAK_GLASS=1 stops requiring the typed confirmation or the origin-reachability check
  N7: SKIP_CHECK_RUNS=1 with SKIP_CHECK_RUNS_REASON unset, empty, whitespace-only or multi-line promotes; it must refuse with deploy/hub and tags untouched
  N8: SKIP_CHECK_RUNS=1 bypasses the uncontained-commits refusal or the typed confirmation (regression guard; positive control is M5)
evidence:
  - {id: E1, proves: [M1, M4], kind: offline, intent: "You will see a test where deploy/hub holds two commits that were squash-merged into the new release; a normal make hub-promote with green checks moves deploy/hub, and the tag has no break-glass line. Today it refuses and lists both commits."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see make hub-promote-status print nothing about uncontained commits for the squash-merged case. Today it lists them."}
  - {id: E3, proves: [M3, N6], kind: offline, intent: "You will see a real promoter commit on deploy/hub still refused without BREAK_GLASS and still passed with it (green checks, typed confirmation, tag says break-glass)."}
  - {id: E4, proves: [N1], kind: offline, intent: "You will see BREAK_GLASS=1 refuse to promote when the check runs are missing, pending, failed or unreadable, with deploy/hub and the tags untouched. Today it promotes anyway."}
  - {id: E5, proves: [N2], kind: offline, intent: "You will see a squash-merged release that also carries one real promoter commit on deploy/hub get refused, with that commit named."}
  - {id: E6, proves: [N3, N4], kind: offline, intent: "You will see a conflicting change on both sides, and a merge-tree that fails, both end in the usual refusal, never in a promote."}
  - {id: E7, proves: [N5], kind: offline, intent: "You will see the existing git-cherry-failure test still fail closed and then succeed once restored."}
  - {id: E9, proves: [M5, N7], kind: offline, intent: "You will see a test where GitHub's check-run lookup fails: SKIP_CHECK_RUNS=1 with a one-line reason promotes after the typed confirmation and the tag shows mode skip-check-runs and the reason; with the reason missing, blank or two lines it refuses and nothing moves. Today the flag does not exist, so the first case refuses."}
  - {id: E10, proves: [N8, M5], kind: offline, intent: "You will see SKIP_CHECK_RUNS=1 still refuse a real promoter commit unless BREAK_GLASS=1 is also given (then the tag has both mode lines), still refuse without a TTY, and make hub-promote and make hub-deploy both pass the flag and reason through."}
  - {id: E8, proves: [M1], kind: live, intent: "You will see the operator's next first-promote of a squash-merged release (git on the M5 is 2.38 or newer) go through make hub-promote with no BREAK_GLASS. Operator or Claude only, never Gemini."}
interface:
  - "bin/k3dm-hub-promote promote REF [BREAK_GLASS]"
  - "bin/k3dm-hub-promote status"
  - "make hub-promote REF=... [BREAK_GLASS=1] [SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...]"
  - "make hub-deploy REF=... [SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...]"
  - "make hub-promote-status"
```

Test design (all in `scripts/tests/bin/hub_promote.bats`, existing fixture: scratch clone `$WORK` with bare `$ORIGIN`, `deploy/hub` and `k3d-manager-v1.43.15` both at `initial` after `setup`, `:138` region helpers `_make_candidate`, `_create_promoter_commit_on_hub`, `_run_promoter_tty`):

- New helper `_make_squash_release`: from `initial`, create branch `rel-old` with two commits (`f1.txt`, `f2.txt`), push it to `origin deploy/hub` (fast-forward); then on `k3d-manager-v1.43.15` (from `initial`) run `git merge --squash rel-old`, commit as one squash commit, add one `candidate.txt` commit, push to `origin k3d-manager-v1.43.15` (fast-forward). The helper first asserts its own target: `git cherry <new> <old>` outputs two `+` rows and `git merge-tree --write-tree <new> <old>` first line equals `git rev-parse <new>^{tree}` (fixture proves what it claims; this makes the test red on today's code only through the promote result, not a broken fixture).
- E1: `_make_squash_release; _run_promoter_tty promote success promote k3d-manager-v1.43.15 0`; assert status 0, `deploy/hub` equals the new SHA, tag exists, tag data lacks `mode: break-glass`, output contains `squash merge`.
- E2: after `_make_squash_release`, run `status` (like `:970-983`, `RELEASE_BRANCH=k3d-manager-v1.43.15`) and assert output lacks `uncontained commits on deploy/hub`.
- E3: keep `:874-901` as is (positive/negative around BREAK_GLASS with green checks).
- E4: replace H4 (`:486-494`) with two tests. (a) `BREAK_GLASS=1` with gh modes `empty`, `pending`, `failed`, `lookup-fail` (loop like `:359-369`) after `_make_candidate`: status non-zero, output has the matching check-run die text, `deploy/hub` unchanged, no tags. (b) `BREAK_GLASS=1` with `success` still promotes and records `mode: break-glass` (title "H4: break glass skips only the containment refusal and still needs checks, confirmation and records mode"). Positive control for (a) is (b) plus E1.
- E5: `_make_squash_release` plus `_create_promoter_commit_on_hub` pushed on top of `deploy/hub` before promoting with `0`/`success`; assert non-zero, promoter short SHA and subject in the output, `git cherry-pick -x`, hub unchanged, no tag. Fixture asserts the promoter file `cve-pin.txt` is absent from the target tree.
- E6: (a) conflict: put `conflict.txt` on `initial` is not needed; create `shared.txt` with different content on `deploy/hub` and on the release branch, assert `merge-tree` rc is 1 in the fixture, promote with `0`/`success` refuses and names the hub commit. (b) squash case with env `MERGE_TREE_FAIL=1`: extend the git stub (`setup`, next to the `CHERRY_FAIL` branch at `:~58`) with `if [[ "${MERGE_TREE_FAIL:-0}" == 1 && " $* " == *" merge-tree "* ]]; then echo "stubbed git merge-tree failure" >&2; exit 129; fi`; promote refuses with the cherry list. Positive control: the same scenario without the env var succeeds (E1).
- E7: existing test `:302-315` unchanged (its scenario has an empty cherry list on the first call... confirm the worker leaves it green; it must still produce "cannot check deploy/hub containment" under `CHERRY_FAIL=1`).
- Existing test `:773-780` (Makefile pass-through): change `GH_STUB_MODE=empty` to `GH_STUB_MODE=success` so it still reaches the TTY refusal; otherwise it now dies at `check_runs`.
- E9: `_make_candidate`, gh mode `lookup-fail`, `SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON='github outage'` via `_run_promoter_tty`: status 0, hub moved, tag data has both lines; then three refusals (reason unset, `'   '`, `$'a\nb'`): non-zero, hub unchanged, no new tag.
- E10: `_create_promoter_commit_on_hub` + `SKIP_CHECK_RUNS=1` with a reason and `BREAK_GLASS=0`: refused naming the commit; same with `BREAK_GLASS=1`: promotes, tag has `mode: break-glass` and `mode: skip-check-runs`; without a TTY: `confirmation requires a TTY`. Makefile pass-through like `:773-780` for `hub-promote`, and a `hub_deploy.bats` case asserting the promote stub receives `SKIP_CHECK_RUNS=1` in its environment.
- Mutants the worker must run (record rc): (m1) revert `:305` to the BREAK_GLASS conditional: E4 red. (m2) make `tree_contained` ignore rc and compare only the first line: E6a red. (m3) make `tree_contained` always `return 0`: E5 red. (m4) drop the reason check: E9 refusals red. Restore after each (snapshot + `cmp`).

## Files

| File | Change |
|---|---|
| `bin/k3dm-hub-promote` | `tree_contained` + `uncontained_commits` (`:21-27`); `check_runs` unless `SKIP_CHECK_RUNS=1` with a reason (`:305`); `record_move` mode/reason lines; usage strings |
| `Makefile` | `hub-promote` passes `SKIP_CHECK_RUNS` (`:477-478`) |
| `scripts/tests/bin/hub_deploy.bats` | E10 pass-through case |
| `scripts/tests/bin/hub_promote.bats` | helper `_make_squash_release`; stub `MERGE_TREE_FAIL`; E1, E2, E4 (replaces H4), E5, E6; `:773-780` stub mode |
| `docs/howto/hub-promote.md` | `:81-83` BREAK_GLASS semantics, squash-merge sentence |

## Worker definition of done

- Change only the files above. Scratch HOME, no network, no live cluster or hub, no push to the real `origin` (the tests use the bare scratch origin; `git` stub refuses non-fixture targets). Show E1, E2 and E4(a) red on today's code, then green; paste N2, N3 and N4 passing on both (they are regression guards).
- Run `bats scripts/tests/bin/hub_promote.bats scripts/tests/bin/hub_deploy.bats scripts/tests/bin/repo_sync_promote_backlog.bats` from the repo root, plus `shellcheck bin/k3dm-hub-promote`, and paste command, rc and the proving lines for each. Mutants m1 to m3 with their rc.
- Run `git status` and confirm only the five files in the table changed. Leave changes uncommitted. Claude lands them.

## Open questions

1. **Resolved (operator, 2026-11-14): explicit flag, section 2a.** Was: separating `check_runs` from BREAK_GLASS means BREAK_GLASS no longer works while GitHub is down (`check_runs` dies on lookup failure, `bin/k3dm-hub-promote:84`), though `docs/howto/hub-promote.md:81-83` names that outage as a BREAK_GLASS use. Accept, or add a separate explicit flag later? This spec accepts it, per the decision.
2. **Resolved (Claude, 2026-11-14): M5 runs git 2.56.0 (`/opt/homebrew/bin/git`).** Was: what git does the M5 hub run? `merge-tree --write-tree` needs 2.38 or newer (probed only on m4-air, 2.56.1). The fallback to the old refusal is safe, but E8 only passes on 2.38+. `ubuntu-24.04` CI git was not probed.
3. Tag bookkeeping: should the tag record that tree-containment accepted the old commits (for audit)? Not in this spec; the stderr note is the only trace.
