# hub-promote containment check refuses the first promote of every release: `git cherry` cannot see squash merges

**Status:** OPEN
**Priority:** P2 (proposed: blocks every first promote of a new release; workaround BREAK_GLASS=1 after a manual check, which also skips the green-checks gate)
**Classified:** pending second-agent classification
**Introduced by:** `aa97c491` (v1.43.15, the uncontained-commits guard from `2026-11-10-hub-promote-discards-cve-promoter-commits.md`)
**Should have been caught by:** spec (the guard's spec did not consider that releases are squash-merged to `main` and the next release is cut from `main`)
**Prior art:** `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` (grep `cherry`/`squash`, read) — this bug is a false positive of that fix
**Waiting on:** fix running — since 2026-11-16 (Luna, codex)
**Triage:** patch → v1.44.1 (P2, flagged: every first promote of a release needs BREAK_GLASS) — operator grooming 2026-11-15 ("Accept as shown")
**Release:** v1.44.1 (bug; operator, 2026-11-15: "let's get those two done at v1.44.1" — out of the v1.44.0 cut)
**Intent approved:** operator, 2026-11-16
**Approval note:** ("Approve all 9")
**Operator decisions (2026-11-16, accepted Claude defaults):** check only the deploy/hub tip; rollback during a GitHub API outage needs BREAK_GLASS; keep SKIP_CHECK_RUNS in this patch (operator request 2026-11-14).

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

## Spec (2026-11-14; drafted by Sonnet, reviewed by Claude) (superseded by the 2026-11-16 respec; sections 2 and 2a are carried over there)

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

## Fix (superseded)

All changes in `bin/k3dm-hub-promote`.

## 1. Tree-containment helper and use in `uncontained_commits` (superseded)

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

## 2. Separate the green-checks gate from BREAK_GLASS (carried into the 2026-11-16 respec)

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

## 2a. Explicit outage flag `SKIP_CHECK_RUNS` (operator, 2026-11-14: "so make an explicit flag for this") (carried into the 2026-11-16 respec)

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

## 3. Docs (superseded)

`docs/howto/hub-promote.md:81-83`, replace "`BREAK_GLASS=1` skips the check-run gate and the containment refusal" so it says: `BREAK_GLASS=1` skips only the uncontained-commits refusal; the green check-run gate, `origin` reachability, the typed confirmation and the promotion record still apply. Add one sentence: a deploy/hub whose commits were squash-merged into the target is recognised by content (`git merge-tree --write-tree`, git 2.38 or newer) and needs no BREAK_GLASS; on older git the old refusal applies. Document `SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON="..."` as the GitHub-outage path (skips only the check-run gate; recorded in the tag), and say an outage with an uncontained commit needs both flags.

## Contract readers (superseded)

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

## Acceptance (superseded)

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
- E6: (a) conflict: put `conflict.txt` on `initial` is not needed; create `shared.txt` with different content on `deploy/hub` and on the release branch, assert `merge-tree` rc is 1 in the fixture, promote with `0`/`success` refuses and names the hub commit. (b) squash case with env `MERGE_TREE_FAIL=1`: extend the git stub (`setup`, next to the `CHERRY_FAIL` branch at `:~58`) with `if [[ "${MERGE_TREE_FAIL:-0}" == 1 && " $* " == *" merge-tree "* ]]; then echo "stubbed git merge-tree failure" >&2; exit 129; fi`; promote refuses with the cherry list. Positive control: the same scenario without the env var succeeds (E1). (c) squash case with env `MERGE_TREE_RC1_TARGET=1`: in the same git stub, for `merge-tree`, print the tree OID of the second-to-last argument (the target; resolve it with the real git, `"$REAL_GIT_PATH" rev-parse "<target>^{tree}"` (`hub_promote.bats:51`)) and `exit 1`; promote refuses with the cherry list. This fixture is synthetic (real git never returns rc 1 with the target's tree); it exists only so mutant m2 has a red test. Fixture asserts the stub printed the target tree.
- E7: existing test `:302-315` unchanged (its scenario has an empty cherry list on the first call... confirm the worker leaves it green; it must still produce "cannot check deploy/hub containment" under `CHERRY_FAIL=1`).
- Existing test `:773-780` (Makefile pass-through): change `GH_STUB_MODE=empty` to `GH_STUB_MODE=success` so it still reaches the TTY refusal; otherwise it now dies at `check_runs`.
- E9: `_make_candidate`, gh mode `lookup-fail`, `SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON='github outage'` via `_run_promoter_tty`: status 0, hub moved, tag data has both lines; then three refusals (reason unset, `'   '`, `$'a\nb'`): non-zero, hub unchanged, no new tag.
- E10: `_create_promoter_commit_on_hub` + `SKIP_CHECK_RUNS=1` with a reason and `BREAK_GLASS=0`: refused naming the commit; same with `BREAK_GLASS=1`: promotes, tag has `mode: break-glass` and `mode: skip-check-runs`; without a TTY: `confirmation requires a TTY`. Makefile pass-through like `:773-780` for `hub-promote`, and a `hub_deploy.bats` case asserting the promote stub receives `SKIP_CHECK_RUNS=1` in its environment.
- Mutants the worker must run (record rc): (m1) revert `:305` to the BREAK_GLASS conditional: E4 red. (m2) make `tree_contained` ignore rc and compare only the first line: E6c red (E6a stays green under m2; Sol worker probe 2026-11-15: conflict tree `0f906e96` != target `6ca45b19`). (m3) make `tree_contained` always `return 0`: E5 red. (m4) drop the reason check: E9 refusals red. Restore after each (snapshot + `cmp`).

## Files (superseded)

| File | Change |
|---|---|
| `bin/k3dm-hub-promote` | `tree_contained` + `uncontained_commits` (`:21-27`); `check_runs` unless `SKIP_CHECK_RUNS=1` with a reason (`:305`); `record_move` mode/reason lines; usage strings |
| `Makefile` | `hub-promote` passes `SKIP_CHECK_RUNS` (`:477-478`) |
| `scripts/tests/bin/hub_deploy.bats` | E10 pass-through case |
| `scripts/tests/bin/hub_promote.bats` | helper `_make_squash_release`; stub `MERGE_TREE_FAIL`; E1, E2, E4 (replaces H4), E5, E6; `:773-780` stub mode |
| `docs/howto/hub-promote.md` | `:81-83` BREAK_GLASS semantics, squash-merge sentence |

## Worker definition of done (superseded)

- Change only the files above. Scratch HOME, no network, no live cluster or hub, no push to the real `origin` (the tests use the bare scratch origin; `git` stub refuses non-fixture targets). Show E1, E2 and E4(a) red on today's code, then green; paste N2, N3 and N4 passing on both (they are regression guards).
- Run `bats scripts/tests/bin/hub_promote.bats scripts/tests/bin/hub_deploy.bats scripts/tests/bin/repo_sync_promote_backlog.bats` from the repo root, plus `shellcheck bin/k3dm-hub-promote`, and paste command, rc and the proving lines for each. Mutants m1 to m3 with their rc.
- Run `git status` and confirm only the five files in the table changed. Leave changes uncommitted. Claude lands them.

## Open questions (2026-11-14 spec, resolved or superseded)

1. **Resolved (operator, 2026-11-14): explicit flag, section 2a.** Was: separating `check_runs` from BREAK_GLASS means BREAK_GLASS no longer works while GitHub is down (`check_runs` dies on lookup failure, `bin/k3dm-hub-promote:84`), though `docs/howto/hub-promote.md:81-83` names that outage as a BREAK_GLASS use. Accept, or add a separate explicit flag later? This spec accepts it, per the decision.
2. **Resolved (Claude, 2026-11-14): M5 runs git 2.56.0 (`/opt/homebrew/bin/git`).** Was: what git does the M5 hub run? `merge-tree --write-tree` needs 2.38 or newer (probed only on m4-air, 2.56.1). The fallback to the old refusal is safe, but E8 only passes on 2.38+. `ubuntu-24.04` CI git was not probed.
3. Tag bookkeeping: should the tag record that tree-containment accepted the old commits (for audit)? Not in this spec; the stderr note is the only trace.

## Review 2026-11-15 (Sol run 2 diff, not landed)

Gate rerun on the M4 green; 7 new tests red on pre-fix code; independent verifier (Opus) PASS on every offline item,
mutants m1 to m4 killed. Blind land call: Argon APPROVE WITH CHANGES, Fable LAND WITH CHANGES (pair 2 in
`docs/reviews/reviewer-trial-fable-vs-argon.md`).

**Blocking:** on the real history, `git merge-tree --write-tree <target> 9f5f0d89` exits 1 for every candidate target
(34707659: 73 conflicts; aa1196ed, the squash itself: 24; c4d647bf: 95). deploy/hub was promoted mid-release, and
PR #160 gained commits before the squash (`git diff --shortstat 9f5f0d89 aa1196ed`: 36 files). So E8 would fail and the
first promote of a release would still need BREAK_GLASS. The spec's probe used a toy repo; E1 models only "deploy/hub
equals the squashed tip".

**Candidate redesign (needs spec + review):** 9f5f0d89 is an ancestor of PR #160's head 5a53e35b
(`refs/pull/160/head`, kept by GitHub after a squash merge). Containment could accept deploy/hub when it is an ancestor
of the head of a merged PR whose merge commit is an ancestor of the target, via the same GitHub API the check-run gate
uses, falling back to the current refusal. The parts of run 2 that are sound and independent (SKIP_CHECK_RUNS,
BREAK_GLASS narrowed to the containment refusal) could land separately.

**Non-blocking follow-ups:** `.github/copilot-instructions.md:42,138` (missed contract reader); E10 make test cannot
catch a `Makefile:478` revert (`:299` falls back to the environment); the "before fetching" `From ` assertion cannot
fail; E9 M5 checks only the newest tag; make expands `$` in a reason passed as a make variable.

**Decision (operator, 2026-11-15): (a)** respec containment on merged-PR head ancestry; do not land run 2 piecemeal. Likely v1.44.1.

## Spec (2026-11-16 respec, option a)

Drafted by Sonnet, for Claude's review, then operator intent approval. Replaces the 2026-11-14 tree-merge spec (its `## Fix` section 1, its tree-based acceptance items and its Files table are superseded; sections 2 and 2a are carried over below). Nothing from Sol run 2 lands piecemeal; the worker implements this whole section.

### Containment rule

`deploy/hub` commit `old` is contained in `target` when `git cherry` flags it, and some merged GitHub PR is associated with `old` (`gh api repos/$GH_REPO/commits/<old>/pulls`) such that (1) `refs/pull/<n>/head` on `origin` equals the API's `head.sha` (the API is not trusted alone), (2) `old` is an ancestor of that head, and (3) the PR's `merge_commit_sha` is an ancestor of `target`. Any failure (API error, no merged PR, head mismatch, missing object, ancestry false) falls back to today's refusal. Only the `old` tip is tested, in one API call; a promoter commit added on top of a squashed tip therefore still refuses (the tip then is in no PR), which is the CVE-pin case the guard exists for.

### Evidence (Claude, 2026-11-16, host m4-air.local, git 2.56.1, gh 2.104.0, read-only against the real repo; prototype `scratchpad/proto.sh` of the rule above, nothing pushed)

```
$ gh api --paginate repos/wilddog64/k3d-manager/commits/9f5f0d89/pulls --jq '.[] | select(.merged_at != null) | [.number,.head.sha,.merge_commit_sha] | @tsv'
160  5a53e35bfd8be5a4c6d4bbcdbe993b55c0bec0f7  aa1196ed4c23e218cf27fcc31143301a17aadd4a
161  12bd21b7718f9da62743878dacee47b2367a9ad8  46ec5b36f72990f276575d5c486167cffe02fa2c
$ git ls-remote origin refs/pull/160/head   -> 5a53e35bfd8b...  (equals the API head; refs/pull/161/head -> 12bd21b7... also equal)
$ git merge-base --is-ancestor 9f5f0d89 5a53e35b  -> yes;  aa1196ed is an ancestor of 34707659, c4d647bf, b5b931df, origin/main
rule applied (target old -> result):
  34707659 9f5f0d89 -> CONTAINED via PR#160      aa1196ed 9f5f0d89 -> CONTAINED via PR#160
  b5b931df 50a42198 -> CONTAINED via PR#161 (head 12bd21b7, merge 46ec5b36)   [the 2026-11-16 promote: git cherry listed 390 '+' commits, first f5c6cc79 docs(plans), the promote needed BREAK_GLASS=1]
  b5b931df f5c6cc79 -> CONTAINED via PR#161      b5b931df 9f5f0d89 -> CONTAINED via PR#160
  b5b931df ebf0a1c9 (release-branch tip, no merged PR) -> NOT contained (API returns [])
  aa1196ed 50a42198 -> NOT contained ("PR#161: merge not in target": 46ec5b36 is not an ancestor of aa1196ed)
$ gh api repos/.../commits/0000...0001/pulls -> HTTP 422 "No commit found for SHA" (gh exits 1: fail closed)
```

Why the tree approach could not work: `git merge-tree --write-tree <target> 9f5f0d89` exits 1 on every real target (Sol run 2: 73 conflicts on 34707659), because the PR gained commits before the squash. Ancestry on the PR head does not care about those. f5c6cc79 itself is a docs-only commit on the v1.43.15 line that `git cherry` marks `+` (its patch is inside the squash, not as a separate commit).

Not probed: GitHub behaviour for fork PRs, PRs closed without merge (filtered by `merged_at != null`; stub fixture covers the filter), rebase-merged PRs (`merge_commit_sha` is then the rebased tip: the ancestor test (3) still holds), and `gh` pagination beyond one page (a commit in more than 30 PRs; `--paginate` is passed).

### Fix

All edits in `bin/k3dm-hub-promote` unless stated; line numbers are the current file (unchanged since `ebf0a1c9`).

1. Replace `:21-27` (`uncontained_commits`) with a helper plus the new function:

```bash
merged_pr_contains() {
  local target="$1" old="$2" rows number head merge remote_head
  rows="$(_run_command --soft -- gh api --paginate "repos/$GH_REPO/commits/$old/pulls" --jq '.[] | select(.merged_at != null) | [.number,.head.sha,.merge_commit_sha] | @tsv')" || return 1
  while IFS=$'\t' read -r number head merge; do
    [[ "$number" =~ ^[0-9]+$ && "$head" =~ ^[0-9a-f]{40,64}$ && "$merge" =~ ^[0-9a-f]{40,64}$ ]] || continue
    remote_head="$(git_cmd ls-remote "$REMOTE" "refs/pull/$number/head")" || continue
    [[ "${remote_head%%$'\t'*}" == "$head" ]] || continue
    git_cmd cat-file -e "$head^{commit}" 2>/dev/null || git_cmd fetch --no-tags "$REMOTE" "refs/pull/$number/head" >/dev/null 2>&1 || continue
    git_cmd cat-file -e "$merge^{commit}" 2>/dev/null || continue
    git_cmd merge-base --is-ancestor "$old" "$head" || continue
    git_cmd merge-base --is-ancestor "$merge" "$target" || continue
    printf '%s\n' "$number"
    return 0
  done <<< "$rows"
  return 1
}

uncontained_commits() {
  local target="$1" old="$2" list pr
  if [[ "$old" =~ ^0+$ || -z "$target" || -z "$old" ]]; then
    return 0
  fi
  list="$(git_cmd cherry "$target" "$old" | awk '$1 == "+" {print $2}')" || return 1
  if [[ -n "$list" ]] && pr="$(merged_pr_contains "$target" "$old")"; then
    printf '[hub-promote] note: deploy/hub %s is contained in merged PR #%s whose merge commit is in %s (squash merge); not treating its commits as uncontained\n' "$old" "$pr" "$target" >&2
    return 0
  fi
  [[ -z "$list" ]] || printf '%s\n' "$list"
}
```

   `cherry` still runs first and its failure still returns 1 (the fail-closed path at `:296`, `:246`, test `hub_promote.bats:302-315`). The API is called only when cherry found `+` rows. A `gh` failure returns 1 from `merged_pr_contains`, so the refusal list prints as today; it never dies. `status` (`:179`) and `rollback` (`:246`) call the same function and get the same acceptance (intended).
2. New subcommand in `main` after `is-green` (`:263-271`): `is-contained <target> <old>` resolves both with `git_cmd rev-parse --verify "<x>^{commit}"`, exits 0 when `uncontained_commits` prints nothing, 1 when it prints a list, 2 on a usage or resolve error. Usage string `:261` gains `| is-contained TARGET OLD`. It exists so the live check (E8) is read-only and exact.
3. Carried over unchanged from the 2026-11-14 spec: section 2 (`:305` check-runs not skipped by BREAK_GLASS) and section 2a (`SKIP_CHECK_RUNS` plus `SKIP_CHECK_RUNS_REASON`: usage strings `:261`, `:280`, parse near `:281-282`, replacement for `:305`, `record_move` sixth parameter and tag lines, `Makefile:478`). Reason: they fit (each bypass names the gate it skips, the operator asked for the explicit flag) and the operator said not to land run 2 piecemeal. Two additions from the review: a reason passed as a make variable has `$` expanded by make, so the docs say to pass it in the environment (`SKIP_CHECK_RUNS_REASON='...' make hub-promote ...`) or avoid `$`; and `Makefile:2315` help text gains `SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...`.
4. Docs, `docs/howto/hub-promote.md`: `:67-72` (containment paragraph) gains one sentence on the PR-ancestry rule and that `GH_REPO`/`gh` access is needed for it; `:81-83` says `BREAK_GLASS=1` skips only the uncontained-commits refusal (check-run gate, `origin` reachability, typed confirmation and the record still apply) and documents `SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...` as the outage path (needs both flags with an uncontained commit); `:87` example unchanged.
5. `.github/copilot-instructions.md`: `:42` replace "`BREAK_GLASS=1` skips the check-run gate and is recorded in the tag" with the two-flag semantics (BREAK_GLASS skips only the containment refusal; `SKIP_CHECK_RUNS=1` with a reason skips the check-run gate; both recorded in the tag) and add that containment recognises squash-merged releases by merged-PR head ancestry. `:138` replace "a promote that skips the check-run gate without `BREAK_GLASS=1` being recorded" with "without `SKIP_CHECK_RUNS=1` and its reason being recorded, or a promote that treats uncontained commits as contained without a merged-PR ancestry match or `BREAK_GLASS=1`".

### Test design (all in `scripts/tests/bin/hub_promote.bats` unless stated)

- `gh` stub (setup, `:~78`): add a branch for `api --paginate repos/wilddog64/k3d-manager/commits/*/pulls --jq <filter>`: it runs `jq -r "<filter>" "$PULLS_JSON"` (default: `[]`), exits 1 when `PULLS_FAIL=1`. Comment above it: "Read-only capture: m4-air.local, 2026-11-16, gh 2.104.0: `gh api repos/wilddog64/k3d-manager/commits/9f5f0d89/pulls` returned PR objects with number, state, merged_at, merge_commit_sha, head.sha; this stub keeps those fields". The fixture JSON is built by `jq` with exactly those fields. Existing check-runs branch unchanged; the first `exit 97` guard now allows either endpoint (a mode unknown to both still exits 97).
- Helper `_make_squash_release`: from `initial`, branch `rel-old` with commits c1 (`f1.txt`=1) and c2; push to `origin deploy/hub` (the old tip); add c3 (edits `f1.txt` to 2) so the PR head is c3; `git update-ref refs/pull/160/head <c3>` in the bare `$ORIGIN`; on `k3d-manager-v1.43.15` from `initial` run `git merge --squash <c3>`, commit (the squash), add `candidate.txt` commit, push. Writes `$PULLS_JSON` with one merged PR (160, head c3, merge = squash). The helper first asserts its target: `git cherry <new> <old>` lists `+` rows; `merge-base --is-ancestor <old> <new>` is false; `merge-base --is-ancestor <old> refs/pull/160/head` is true; `merge-base --is-ancestor <squash> <new>` is true; and `git merge-tree --write-tree <new> <old>` exits 1 (conflict on `f1.txt`, modelling the real 73 conflicts, so a tree-merge design would fail here).
- E1: `_make_squash_release; _run_promoter_tty promote success promote k3d-manager-v1.43.15 0`: status 0, hub equals new, tag exists, tag data lacks `mode: break-glass`, output contains `merged PR #160`.
- E2: after `_make_squash_release`, `status` (`RELEASE_BRANCH=k3d-manager-v1.43.15`) output lacks `uncontained commits on deploy/hub`.
- Refusals, each after `_make_squash_release` with one thing broken, each asserting refusal text `not in`, hub unchanged, no new tag, and paired with E1 as the positive control: (R1) a promoter commit pushed on top of `deploy/hub` (`_create_promoter_commit_on_hub`; the fixture asserts its file is absent from the target and that the stub returns no PR for the new tip) names the promoter commit; (R2) PR row `merge_commit_sha` set to a commit not in the target (a side branch commit; fixture asserts non-ancestor); (R3) `refs/pull/160/head` in `$ORIGIN` pointing elsewhere than the API head; (R4) the PR row has `merged_at: null`; (R5) `PULLS_FAIL=1`; (R6) `old` not an ancestor of the PR head (head set to c2's parent, fixture asserts non-ancestry).
- E5 `is-contained`: exit 0 on the squash case, 1 on R1, 2 with a bad argument count and with an unresolvable SHA.
- Carried tests: H4 replacement (BREAK_GLASS refuses with checks missing, pending, failed, lookup-fail; still promotes with `success`, records `mode: break-glass`); E9 and E10 of the 2026-11-14 spec with two fixes from the review: E9 asserts on the tag created by this run (tag list before and after, new tag's data holds `mode: skip-check-runs` and `reason:`), not the newest tag; E10's Makefile check is `make -n hub-promote REF=x BREAK_GLASS=1 SKIP_CHECK_RUNS=1` asserting the printed command contains `promote "x" "1" "1"`, which fails when `Makefile:478` is reverted (the recipe has no `$(MAKE)`; the worker confirms with `make -n` output before relying on it). `:773-780` stub mode `empty` to `success`.
- The "before fetching `From `" assertion lived only in unlanded run 2 and cannot fail; it is dropped, not rewritten (nothing in this design claims a fetch ordering).
- Mutants the worker records (rc each, restore with snapshot and `cmp`): (m1) `:305` back to the BREAK_GLASS conditional: H4 red. (m2) `merged_pr_contains` always `return 0`: R1 to R6 red. (m3) drop the `ls-remote` head comparison: R3 red. (m4) drop `merge-base --is-ancestor "$merge" "$target"`: R2 red. (m5) drop the `merge-base --is-ancestor "$old" "$head"`: R6 red. (m6) drop `select(.merged_at != null)`: R4 red. (m7) drop the reason check: E9 refusals red.

## Files

| File | Change |
|---|---|
| `bin/k3dm-hub-promote` | `merged_pr_contains`, `uncontained_commits` (`:21-27`), `is-contained` subcommand, usage strings, plus carried-over sections 2 and 2a (`:261`, `:280-282`, `:305`, `record_move`) |
| `Makefile` | `:478` passes `SKIP_CHECK_RUNS`; `:2315` help text |
| `scripts/tests/bin/hub_promote.bats` | gh stub pulls branch; `_make_squash_release`; E1, E2, R1-R6, E5, H4 replacement, E9, E10, `:773-780` stub mode |
| `scripts/tests/bin/hub_deploy.bats` | SKIP_CHECK_RUNS pass-through case (carried E10) |
| `docs/howto/hub-promote.md` | `:67-72`, `:81-83` |
| `.github/copilot-instructions.md` | `:42`, `:138` |

## Contract readers

Contract: `uncontained_commits` behaviour (stdout list, exit codes, stderr note), `BREAK_GLASS` meaning, the `promote` argument list, the tag message fields. Greps run 2026-11-16 (`grep -rn "BREAK_GLASS\|k3dm-hub-promote\|uncontained"` over the repo minus `docs/bugs`, `docs/reviews`, `memory-bank`).

- Writers: `bin/k3dm-hub-promote` only (`:21-27`, `:128`, `:261`, `:280-282`, `:305`).
- Command callers: `Makefile:478` (changes, carried), `:487` rollback and `:491` status (use `uncontained_commits`, now with API lookup; output format unchanged), `:496` `promote` target (no flags, unchanged); `bin/k3dm-hub-deploy:32` (`promote "$ref"`, unchanged; flags pass by environment); `bin/k3dm-repo-sync:91` (`is-green`, unchanged; `status`-style readers of the list: none).
- Tests: `hub_promote.bats` `:302-315` (cherry fail closed, unchanged), `:486-494` H4 (replaced), `:773-780` (stub mode), `:874-901`, `:937-968`, `:970-983` (unchanged; their gh calls now also hit the pulls stub branch and get `[]`); `hub_deploy.bats:31,141-143`, `repo_sync_promote_backlog.bats:67,192,262` (do not read guard text, unchanged).
- Docs/readers of BREAK_GLASS semantics: `docs/howto/hub-promote.md:67-72,81-83` (changed), `.github/copilot-instructions.md:42,138` (changed; missed by the 2026-11-14 spec), `Makefile:2315` (help, changed). Historical, no edit: `CHANGELOG.md:53`, `memory-bank/projectbrief.md:105`, `docs/plans/v1.43.15-hub-deploy-ref-and-live-write-guard.md:73`. Forward-looking, flagged not edited: `docs/plans/v1.45.0-remote-promote-approval.md:22,40,85,101` read BREAK_GLASS as "skips checks"; its author should re-read after this lands.
- New external reader: GitHub API `commits/<sha>/pulls` and `refs/pull/<n>/head` on `origin` (needs `gh` auth and network, as `check_runs` already does).

## Acceptance

Revised 2026-11-16 (Claude) after the Luna worker stopped twice. (2) E8's Makefile check used `make -n`, which prints the recipe unexpanded (and executes `$(MAKE)` lines); it now runs real make in a scratch root with a recording stub, as `hub_deploy.bats` does. (1) only N1 is red on pre-fix code, so the former N2 to N8 moved to `must` as regression guards M6 to M12.

```yaml
must:
  M1: with deploy/hub holding commits that git cherry flags but that sit in a merged PR whose head contains deploy/hub and whose merge commit is in the target (PR gained commits before squash, so a tree merge conflicts), promote with green checks and no BREAK_GLASS moves deploy/hub, records a tag without "mode: break-glass", and prints a note naming the PR
  M2: status reports no uncontained commits for that same situation
  M3: BREAK_GLASS=1 still bypasses the uncontained-commits refusal for a real promoter commit (green checks, typed confirmation) and records "mode: break-glass"
  M4: is-contained exits 0 for the squash case, 1 for an uncontained case, 2 on bad input
  M5: SKIP_CHECK_RUNS=1 with a one-line SKIP_CHECK_RUNS_REASON promotes when the check-run lookup fails, after the typed confirmation, and this run's tag records "mode: skip-check-runs" and "reason: <text>"
  M6: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that a promoter commit added on top of a squash-merged deploy/hub tip is treated as contained
  M7: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that a merged PR whose merge commit is not in the target, whose origin refs/pull/<n>/head differs from the API head, whose head does not contain old, or that is not merged, is treated as contained
  M8: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that a gh lookup failure is treated as contained or aborts the refusal listing; promote must refuse with the usual list
  M9: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that a git cherry error stops failing closed
  M10: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that BREAK_GLASS=1 or SKIP_CHECK_RUNS=1 stops requiring the typed confirmation or origin reachability
  M11: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that SKIP_CHECK_RUNS=1 with a reason unset, empty, whitespace-only or multi-line promotes
  M12: (regression guard, passes on pre-fix code; proven by mutant plus positive control, not by a pre-fix red) it is not the case that SKIP_CHECK_RUNS=1 bypasses the uncontained-commits refusal
must_not:
  N1: BREAK_GLASS=1 skips the check-run gate (red on pre-fix code: today it promotes with checks missing)
evidence:
  - {id: E1, proves: [M1], kind: offline, intent: "You will see a test where deploy/hub holds two commits that were squash-merged as part of a larger PR (so merging them conflicts); a normal make hub-promote with green checks moves deploy/hub, names PR 160 in a note, and the tag has no break-glass line. Today it refuses and lists the commits."}
  - {id: E2, proves: [M2], kind: offline, intent: "You will see make hub-promote-status print nothing about uncontained commits for that squash-merged case. Today it lists them."}
  - {id: E3, proves: [M6, M7, M8], kind: offline, intent: "You will see six variations of the squash case each end in the usual refusal and an unmoved hub: a real promoter commit on top, a merge commit not in the new release, a PR ref that does not match GitHub's answer, a PR head that lacks the hub commit, an unmerged PR, and GitHub being unreachable. The unbroken case beside them promotes."}
  - {id: E4, proves: [M3, M10], kind: offline, intent: "You will see a real promoter commit on deploy/hub refused without BREAK_GLASS and accepted with it (green checks, typed confirmation, tag says break-glass); with no terminal it still refuses."}
  - {id: E5, proves: [N1], kind: offline, intent: "You will see BREAK_GLASS=1 refuse to promote when the check runs are missing, pending, failed or unreadable, hub and tags untouched. Today it promotes anyway."}
  - {id: E6, proves: [M9], kind: offline, intent: "You will see the existing git-cherry-failure test still fail closed and succeed once restored."}
  - {id: E7, proves: [M4], kind: offline, intent: "You will see the new is-contained command say yes for the squash case, no for a promoter commit, and exit 2 for a missing or unknown SHA."}
  - {id: E8, proves: [M5, M11, M12], kind: offline, intent: "You will see GitHub's check-run lookup fail: SKIP_CHECK_RUNS=1 with a one-line reason promotes after the typed confirmation and the new tag shows the mode and reason; a missing, blank or two-line reason, or a real promoter commit without BREAK_GLASS, refuses and nothing moves. make hub-promote, run in a scratch copy of the repo with a recording stub in place of bin/k3dm-hub-promote, passes both flags, so reverting the Makefile line turns it red."}
  - {id: E9, proves: [M1], kind: live, intent: "You will see the real 9f5f0d89 case, read-only on the M5 or M4, answered by the shipped code: is-contained b5b931df 50a42198 exits 0 naming PR 161, is-contained b5b931df 9f5f0d89 exits 0 naming PR 160, is-contained b5b931df ebf0a1c9 exits 1, is-contained aa1196ed 50a42198 exits 1. Claude or the operator runs it, never Gemini; the operator's next first promote of a release then needs no BREAK_GLASS."}
interface:
  - "bin/k3dm-hub-promote promote REF [BREAK_GLASS] [SKIP_CHECK_RUNS]"
  - "bin/k3dm-hub-promote is-contained TARGET OLD"
  - "bin/k3dm-hub-promote status"
  - "make hub-promote REF=... [BREAK_GLASS=1] [SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...]"
  - "make hub-deploy REF=... [SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=...]"
  - "make hub-promote-status"
```

## Worker definition of done

- Change only the six files in Files. Scratch HOME, no network, `gh` is the stub (no real GitHub call; a test that reaches real `gh` is a defect), no push to the real `origin`. Show E1, E2 and E5 red on today's code, then green; M6 to M8 are regression guards, so paste their passing lines and the mutant results instead.
- Run `bats scripts/tests/bin/hub_promote.bats scripts/tests/bin/hub_deploy.bats scripts/tests/bin/repo_sync_promote_backlog.bats` from the repo root and `shellcheck bin/k3dm-hub-promote`; paste command, rc and proving lines. Run mutants m1 to m7 with rc each.
- `git status`: only the six files changed. Leave uncommitted; Claude lands them. Do not run `make hub-promote` or any target that pushes or deploys.

## Open questions (resolved, operator 2026-11-16: accepted Claude defaults)

Resolutions: Q1 accept tip-only for v1.44.1; Q2 accept (rollback in an outage needs BREAK_GLASS); Q3 keep SKIP_CHECK_RUNS in this patch; Q4 out of scope.


1. Tip-only test: a promoter commit on top of a squashed tip makes the whole old range look uncontained, so the refusal lists hundreds of commits, not just the promoter. Accept for v1.44.1 (safe, noisy), or add a second pass that lists only commits outside every associated PR head?
2. Rollback (`rollback`, `:246`) now also calls the API. In a GitHub outage a rollback with a squash-merged old tip refuses and needs BREAK_GLASS. Accept?
3. Scope: carrying SKIP_CHECK_RUNS (a new flag) into a bug-fix patch. Kept because run 2 is not landed piecemeal; say if it should move to a minor release and BREAK_GLASS narrowing alone ships.
4. A merge commit later reverted in `target` still counts as containing the PR (ancestry only). Out of scope; the check-run gate and review cover it.
