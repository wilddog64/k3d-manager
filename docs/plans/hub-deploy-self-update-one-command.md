# hub-deploy fetches, catches the checkout up and re-execs its promoted copy: one promote command

**Status:** LIVE-VERIFIED — 3b541f3b, 2026-11-19 (Sonnet Acceptance verifier + Claude: 42/42, pre-fix 8 red, 5 mutants red); E2 live 2026-11-20: operator ran `make hub-deploy REF=9d7973b6…` alone on the M5, Claude read the pane: "continuing with the promoted copy at 9d7973b", one tag hub-promote/20261120T152130Z, summary 3d5fd9e..9d7973b, no checkout-catch-up stop
**Bug:** `docs/bugs/2026-11-19-hub-deploy-runs-stale-checkout-copy-of-itself.md` (P2)
**Risk:** medium — changes `bin/k3dm-hub-deploy` control flow before appsets-check/platform-ops on the hub
**Agent:** Luna (codex gpt-6-luna)
**Intent approved:** operator, 2026-11-19
**Intent note:** operator: "go ahead to file a P2 bug then dispatch to Luna if there is a free slot", answering "when can we have one command to promote REF?"

## Problem

`make hub-deploy REF=<sha>` runs `bin/k3dm-hub-deploy` from the hub checkout (`REPO_ROOT`, `:3`), and that checkout trails
deploy/hub until repo-sync's next 5-minute run. 2026-11-19 16:06 PST, M5: deploy/hub `072bcb5..364dce3` with the checkout
still at `072bcb57`, so the old copy ran (no launchd reconcile: Part 1 `643747e5` did not run, no
`~/.local/share/k3d-manager/hub-deploy/` directory); repo-sync moved the checkout at ~16:11.

The bytes bash is running, and the libraries it sourced (`:6`, `system.sh`), are the pre-promote ones even after the
checkout moves. Children started with `make -C "$REPO_ROOT"` read whatever checkout exists when they start. So the
deploy must (a) bring the checkout to the promoted commit before any apply, and (b) re-exec the promoted script.

Not changed (rev 1 was wrong): REF resolution. `bin/k3dm-hub-promote:322` already fetches before `resolve_on_origin`
(`:323`); no extra fetch.

## Change (`bin/k3dm-hub-deploy`, plus tests and docs)

Two stages, told apart by `K3DM_HUB_DEPLOY_PREV` (unset: stage 1; set: stage 2).

1. **Stage 1, bind the target.** After the promote (`:81`) and the `new` read (`:82`): resolve
   `want="$(git -C "$REPO_ROOT" rev-parse --verify "$ref^{commit}")"` (promote has fetched). If `new != want`: print
   `hub-deploy: deploy/hub is <new7>, not the promoted <want7>; superseded` and `stop superseded 1`.
2. **Stage 1, catch the checkout up (checkout only).** Move the `checkout_ok`, `lock_stamp`, `take_lock`, `release_lock`
   definitions and `RS_DIR`/`RS_STALE` (`:144-170`) above this point unchanged; install `trap release_lock EXIT` here.
   Loop until a deadline of `${K3DM_HUB_DEPLOY_CHECKOUT_WAIT:-330}` s (the existing variable, `:176`), sleeping
   `min(10, remaining)` between tries:
   - `take_lock` (repo-sync's directory lock); on failure release and retry.
   - If `checkout_ok`: done.
   - Else, if the tracked tree is clean (`status --porcelain --untracked-files=no` empty) and HEAD is an ancestor of
     `$new` (`merge-base --is-ancestor HEAD "$new"`): `git -C "$REPO_ROOT" merge --ff-only --quiet "$new"`; then
     re-check `checkout_ok`.
   - Otherwise (dirty, diverged): release the lock and retry (repo-sync's own reset-with-backup path, `bin/k3dm-repo-sync:259-281`,
     is the only thing allowed to reset a diverged hub checkout).
   - Always `release_lock` before sleeping or leaving the loop.
   On timeout: print `hub-deploy: hub checkout not at <new7> with a clean tracked tree; nothing applied` and
   `stop checkout-catch-up 1`. This happens before the appsets block, so no apply runs and `appsets` in state is not
   advanced; the rerun hint (`stop`, `:10`) is the retry.
3. **Stage 1, re-exec.** With the checkout at `$new`:
   - If `git -C "$REPO_ROOT" grep -q K3DM_HUB_DEPLOY_PREV "$new" -- bin/k3dm-hub-deploy` fails (the promoted copy
     predates this handoff, e.g. a rollback): print
     `hub-deploy: promoted copy has no handoff; continuing with the running copy` and continue in this process.
   - Else, if `[[ -x "$REPO_ROOT/bin/k3dm-hub-deploy" ]]`: print
     `hub-deploy: continuing with the promoted copy at <new7>` and
     `exec env K3DM_HUB_DEPLOY_PREV="$old" "$REPO_ROOT/bin/k3dm-hub-deploy" "$new"`. Do not close fd 9 first; the
     promoted copy's `exec 9>>` (`:22`) replaces it and re-acquires the lock.
   - Not executable: `stop handoff 1`.
4. **Stage 2** (`K3DM_HUB_DEPLOY_PREV` set):
   - Right after the usage check: copy it to a local `prev`, `unset K3DM_HUB_DEPLOY_PREV`, and require `prev` and `$1`
     to match `^[0-9a-f]{40}([0-9a-f]{24})?$`; else `die 'K3DM_HUB_DEPLOY_PREV must be a commit sha'`. After the role
     gate, `git cat-file -e "$prev^{commit}"` must succeed (same die).
   - Role gate, state dir, run lock and state read/init run as today; `old="$prev"` replaces the `remote_sha` read at
     `:69`.
   - No promote, no catch-up loop, no re-exec. `new="$(remote_sha)"` must equal `$1` and `checkout_ok` must hold, else
     print `hub-deploy: deploy/hub or the checkout moved from <ref7> before the promoted copy ran; superseded` and
     `stop superseded 1`.
   - Everything from the appsets block on is unchanged; the summary prints `<prev7>..<new7>`.
5. **Accepted residuals** (write them in the howto):
   - `k3dm-require-role` and `k3dm-hub-promote` always run from the pre-promote checkout, so a change to them takes effect one promote later.
   - The promote that delivers this change runs the old copy; it is the last one needing a second
     `make hub-deploy REF=<sha>`.
   - Stage 1 always writes state before promote (`:71-80`), so stage 2's "no state" branch is reachable only by a direct
     call with the env var.
   - A deploy/hub move between promote and platform-ops is still caught only by the pin check (`:98-103`), as today.

## Files

- `bin/k3dm-hub-deploy`
- `scripts/tests/bin/hub_deploy.bats`: the fixture commits, as the promoted revision, a `bin/k3dm-hub-deploy` that is the
  real script plus one first line appending `stage2 <args> prev=$K3DM_HUB_DEPLOY_PREV` to `$CALLS`; a second fixture revision
  without the string `K3DM_HUB_DEPLOY_PREV` for the no-handoff case; the existing git stub keeps logging; the checkout
  catch-up uses the fixture repo (no repo-sync stub needed, repo-sync is not called)
- `docs/howto/hub-promote.md`: the single command on the M5; no `git fetch` / `hub-sync` step there; the residuals above
- `docs/howto/makefile.md`: the `hub-deploy` row says it catches the checkout up and runs the promoted copy

## Contract readers

- `K3DM_HUB_DEPLOY_PREV` (new env var): writer `bin/k3dm-hub-deploy` stage 1; reader `bin/k3dm-hub-deploy` stage 2, which
  unsets it, so no child sees it. `grep -rn K3DM_HUB_DEPLOY_PREV` is empty before the change. It is a cross-version
  contract: step 3's `git grep` makes a promoted copy without it run in-process instead.
- repo-sync lock `~/.local/share/k3d-manager/repo-sync/lock` (`bin/k3dm-repo-sync:17,35-44,341-350,520-526`): now also taken
  in stage 1 for the catch-up, with the same `take_lock` (`:157-170`); repo-sync, when it finds the lock held, prints
  `already running` and exits 0, as today.
- Hub checkout HEAD: writers `bin/k3dm-repo-sync` (`:259-288`) and now `bin/k3dm-hub-deploy` (fast-forward only, clean tree,
  under the lock).
- `K3DM_HUB_DEPLOY_CHECKOUT_WAIT` (`:176`): now bounds both waits.
- `bin/k3dm-hub-promote promote`: unchanged, still called once per deploy.
- `Makefile:525-527`: unchanged.
- Remote-promote 2b/2c/2d/2e specs (`docs/plans/v1.45.0-remote-promote-2{b,c,d,e}-*.md`) cite `bin/k3dm-hub-deploy` line
  numbers; not started; they rebase onto this.

## What NOT to Do

- Do not call `bin/k3dm-repo-sync` from hub-deploy, and do not reset or rebase the checkout (fast-forward only).
- Do not apply anything (appsets, platform-ops, installers) unless the checkout is at the target.
- Do not re-exec more than once, or from stage 2; do not call promote twice.
- Do not run hub-deploy, hub-promote, repo-sync or make targets against the real hub or `$HOME`.
- Do not change `bin/k3dm-hub-promote`, `bin/k3dm-repo-sync` or the Makefile.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "checkout behind the promoted sha with a clean tree: stage 1 fast-forwards it under the repo-sync lock, prints 'continuing with the promoted copy at <new7>', and the promoted copy runs with prev=<pre-promote sha> and $1=<promoted full sha>; across both stages promote is called once and hub-deploy invokes appsets-check and platform-ops once each; summary <pre7>..<new7>"
  - id: M2
    text: "checkout dirty, diverged, or repo-sync lock held past K3DM_HUB_DEPLOY_CHECKOUT_WAIT: stops at checkout-catch-up with 'nothing applied'; no appsets-reapply, appsets-check or platform-ops call; state appsets value unchanged; the lock directory is removed on exit"
  - id: M3
    text: "promoted copy without the string K3DM_HUB_DEPLOY_PREV: prints 'promoted copy has no handoff', does not exec, and finishes in-process"
  - id: M4
    text: "deploy/hub not equal to the commit REF resolves to after promote: stage 1 stops superseded before the catch-up"
  - id: M5
    text: "stage 2: invalid prev or non-sha $1 dies 'K3DM_HUB_DEPLOY_PREV must be a commit sha'; deploy/hub != $1 or checkout not at $1 stops superseded before appsets-check; stage 2 never calls promote or execs; children do not see K3DM_HUB_DEPLOY_PREV"
  - id: M6
    text: "the promoted copy acquires the run lock (no 'another run is active'); the existing 38 tests pass, including 'role gate refuses before git'"
must_not:
  - id: N1
    text: "a deploy whose checkout trails the promoted sha finishes without the promoted copy running (red on 34b60bf9: no catch-up or exec)"
  - id: N2
    text: "a deploy runs appsets-check or platform-ops while the checkout is not at the promoted sha (red on 34b60bf9: with the checkout held behind, both run)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2]
    kind: offline
    command: "bats scripts/tests/bin/hub_deploy.bats; new tests red on 34b60bf9; mutants red: drop the exec (N1), continue on catch-up timeout (N2/M2), drop the git grep guard (M3), drop the REF binding (M4), allow stage 2 to promote or exec (M5, counted calls), skip the unset (M5 child env); shellcheck bin/k3dm-hub-deploy clean; the Acceptance YAML parses"
    intent: "Offline proof that one hub-deploy command brings the hub checkout to the promoted commit and finishes with the promoted deploy script, and applies nothing when it cannot."
  - id: E2
    proves: [M1]
    kind: live
    command: "operator, on the M5, the first promote after the one that delivers this change: 'make hub-deploy REF=<sha>' alone; Claude reads the pane: 'continuing with the promoted copy', one promote tag, summary <old7>..<new7>, no 'checkout-catch-up' stop"
    intent: "On the real hub, you type one command and the new deploy code runs in that same promote."
interface:
  - "hub-deploy: continuing with the promoted copy at <new7>"
  - "hub-deploy: promoted copy has no handoff; continuing with the running copy"
  - "hub-deploy: hub checkout not at <new7> with a clean tracked tree; nothing applied"
  - "hub-deploy: deploy/hub is <new7>, not the promoted <want7>; superseded"
  - "hub-deploy: deploy/hub or the checkout moved from <ref7> before the promoted copy ran; superseded"
  - "K3DM_HUB_DEPLOY_PREV must be a commit sha"
  - "K3DM_HUB_DEPLOY_PREV"
```
