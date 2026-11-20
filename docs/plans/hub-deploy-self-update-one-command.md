# hub-deploy fetches, catches the checkout up and re-execs its promoted copy: one promote command

**Status:** DRAFT rev 1 — review owed (medium risk: hub deploy path; Fable + Astra blind)
**Bug:** `docs/bugs/2026-11-19-hub-deploy-runs-stale-checkout-copy-of-itself.md` (P2)
**Risk:** medium — changes `bin/k3dm-hub-deploy` control flow before appsets-check/platform-ops on the hub
**Agent:** Luna (codex gpt-6-luna)
**Intent approved:** operator, 2026-11-19
**Intent note:** operator: "go ahead to file a P2 bug then dispatch to Luna if there is a free slot", answering "when can we have one command to promote REF?"

## Problem

`make hub-deploy REF=<sha>` runs `bin/k3dm-hub-deploy` from the hub checkout (`REPO_ROOT`, `:3`). That checkout trails
deploy/hub until repo-sync's next 5-minute run, so:
1. `k3dm-hub-promote` resolves REF locally (`bin/k3dm-hub-promote:87`, `resolve_on_origin`) and fails for a commit the
   checkout has not fetched; the operator has to `git fetch origin` first.
2. The deploy runs the old copy of `bin/k3dm-hub-deploy`. 2026-11-19 16:06 PST: deploy/hub `072bcb5..364dce3`, checkout
   still at `072bcb57`, whose copy has no launchd reconcile, so Part 1 (`643747e5`) did not run; repo-sync moved the
   checkout at ~16:11.

Once the checkout is at the promoted commit, everything `hub-deploy` calls through `make -C "$REPO_ROOT"` and
`"$REPO_ROOT/bin/..."` is already the promoted code. Only the bytes of the running script are stale, so re-executing that
one file is enough.

## Change (`bin/k3dm-hub-deploy` only, plus docs)

Two stages, told apart by `K3DM_HUB_DEPLOY_PREV` (unset: first stage; set: re-exec stage).

1. **Self blob.** Right after the usage check (`:14-15`), record
   `self_blob="$(git -C "$REPO_ROOT" hash-object -- "${BASH_SOURCE[0]}")"` (empty on failure; empty disables re-exec).
2. **Fetch (first stage only).** Immediately before the promote (`:81`):
   `_run_command --soft -- git -C "$REPO_ROOT" fetch --quiet --no-tags origin 9>&-`; failure → `stop fetch <code>`.
3. **Catch up and re-exec (first stage only).** Immediately after `new` is read (`:82`) and before the appsets block:
   1. Run `_run_command --soft -- "$REPO_ROOT/bin/k3dm-repo-sync" 9>&-` once; its exit status is ignored (a held
      repo-sync lock or a dirty checkout just means no catch-up).
   2. If `checkout_ok` (HEAD == `$new`, clean tracked tree; move the existing `checkout_ok` definition, `:149-154`, above
      this point unchanged), `self_blob` is non-empty, and `git -C "$REPO_ROOT" rev-parse "$new:bin/k3dm-hub-deploy"`
      differs from `self_blob`: print
      `hub-deploy: deploy script changed in <new7>; continuing with the promoted copy`, close the run lock with
      `exec 9>&-`, then `exec env K3DM_HUB_DEPLOY_PREV="$old" "$REPO_ROOT/bin/k3dm-hub-deploy" "$new"`.
   3. If the checkout is not at `$new`: print `hub-deploy: hub checkout not at <new7>; continuing with the running copy`
      and continue unchanged (the launchd step already waits for the checkout, `:176-184`).
   4. Otherwise (same blob) continue silently.
4. **Re-exec stage** (`K3DM_HUB_DEPLOY_PREV` set):
   - Its value must match `^[0-9a-f]{40}([0-9a-f]{24})?$` and pass `git cat-file -e "<v>^{commit}"`, and `$1` must be a
     full sha of the same form; otherwise `die 'K3DM_HUB_DEPLOY_PREV must be a commit sha'`.
   - Role check, state dir, run lock and state read/init run as today; `old="$K3DM_HUB_DEPLOY_PREV"` replaces the
     `remote_sha` read at `:69` (so a missing state file starts from the pre-promote base, as today).
   - No fetch, no promote, no repo-sync, no re-exec. `new="$(remote_sha)"` must equal `$1`, else print
     `hub-deploy: deploy/hub moved from <ref7> to <new7> before the promoted copy ran; superseded` and `stop superseded 1`.
   - Everything from the appsets block on is unchanged, and the summary line prints `old..new` from the pre-promote sha.
5. **Bootstrap note.** The first promote after this change lands still runs the old copy; that run is the last one that
   needs a second `make hub-deploy REF=<sha>` (record it in the howto).

## Files

- `bin/k3dm-hub-deploy`
- `scripts/tests/bin/hub_deploy.bats`
- `docs/howto/hub-promote.md`: the single command; drop any separate `git fetch` / `hub-sync` step for the M5; the bootstrap note
- `docs/howto/makefile.md`: `hub-deploy` row says it fetches and runs the promoted copy

## Contract readers

- `K3DM_HUB_DEPLOY_PREV` (new env var): writer `bin/k3dm-hub-deploy` (step 3.2), reader `bin/k3dm-hub-deploy` (step 4).
  `grep -rn K3DM_HUB_DEPLOY_PREV` is empty before the change.
- `bin/k3dm-repo-sync` (called once, unchanged): takes `~/.local/share/k3d-manager/repo-sync/lock`; `hub-deploy`'s own
  use of that lock (`:144-170`) comes later and is unchanged.
- `bin/k3dm-hub-promote promote` (`:81`, unchanged): now called after a fetch; still called exactly once per deploy.
- `Makefile:525-527` (`hub-deploy`): unchanged.
- Remote-promote 2b/2c/2d/2e specs (`docs/plans/v1.45.0-remote-promote-2{b,c,d,e}-*.md`) cite `bin/k3dm-hub-deploy` line
  numbers; not started; they rebase onto this change.

## What NOT to Do

- Do not run `hub-deploy`, `hub-promote`, `repo-sync` or `make` targets against the real hub or `$HOME`; tests use the
  existing stubs and a scratch HOME.
- Do not re-exec more than once, and never from the re-exec stage.
- Do not call `k3dm-hub-promote promote` twice in one deploy.
- Do not change `bin/k3dm-hub-promote`, `bin/k3dm-repo-sync` or the Makefile.
- Do not update `memory-bank/`, create a PR, or skip hooks.

## Acceptance

```yaml
must:
  - id: M1
    text: "first stage runs 'git fetch --quiet --no-tags origin' before 'k3dm-hub-promote promote'; a failing fetch stops at 'fetch' and promote is never called"
  - id: M2
    text: "when repo-sync moves the checkout to the promoted sha and the promoted bin/k3dm-hub-deploy blob differs from the running one, the promoted copy runs with K3DM_HUB_DEPLOY_PREV=<pre-promote sha> and \$1=<promoted full sha>, after 'deploy script changed' is printed; appsets-check and platform-ops each run exactly once across both stages; promote runs exactly once"
  - id: M3
    text: "same blob → no re-exec and no message; checkout not at the promoted sha after repo-sync → 'hub checkout not at <new7>; continuing with the running copy' and no re-exec; repo-sync exiting non-zero does not stop the deploy"
  - id: M4
    text: "re-exec stage does not fetch, promote, run repo-sync or re-exec; its summary prints <pre-promote7>..<new7>; with no state file it uses the pre-promote sha as the appsets base"
  - id: M5
    text: "re-exec stage with deploy/hub != \$1 prints the superseded line and exits non-zero before appsets-check; invalid K3DM_HUB_DEPLOY_PREV or non-sha \$1 dies with 'K3DM_HUB_DEPLOY_PREV must be a commit sha'"
  - id: M6
    text: "the run lock is released before exec: the promoted copy acquires it (no 'another run is active')"
must_not:
  - id: N1
    text: "a deploy whose promoted bin/k3dm-hub-deploy differs from the running copy finishes without running the promoted copy (red on 34b60bf9: no re-exec exists)"
  - id: N2
    text: "the first stage calls promote without a prior fetch (red on 34b60bf9)"
  - id: N3
    text: "a deploy calls promote twice or re-execs twice (paired with M2's single re-exec)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3]
    kind: offline
    command: "bats scripts/tests/bin/hub_deploy.bats (all 38 existing tests still pass); new tests red on 34b60bf9; mutants red: drop the exec (N1), drop the fetch (N2), allow re-exec in the re-exec stage (N3), keep fd 9 open across exec (M6), skip the deploy/hub == \$1 check (M5); shellcheck bin/k3dm-hub-deploy clean"
    intent: "Offline proof that one hub-deploy command fetches the commit, catches the hub checkout up and finishes with the promoted deploy script, without promoting or applying twice."
  - id: E2
    proves: [M2, M4]
    kind: live
    command: "operator, on the M5, the next promote that changes bin/k3dm-hub-deploy after this one is on deploy/hub: 'make hub-deploy REF=<sha>' alone (no fetch, no hub-sync); Claude reads the pane: the 'deploy script changed' line, one promote tag, summary <old7>..<new7>"
    intent: "On the real hub, you type one command and the new deploy code runs in that same promote."
interface:
  - "hub-deploy: deploy script changed in <new7>; continuing with the promoted copy"
  - "hub-deploy: hub checkout not at <new7>; continuing with the running copy"
  - "hub-deploy: deploy/hub moved from <ref7> to <new7> before the promoted copy ran; superseded"
  - "K3DM_HUB_DEPLOY_PREV must be a commit sha"
  - "K3DM_HUB_DEPLOY_PREV"
```
