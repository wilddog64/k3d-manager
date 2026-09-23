# Image promotion's rebase fallback cannot resolve two concurrent `newTag:` bumps

**Filed:** 2026-09-21
**Branch (spec):** `k3d-manager-v1.36.0`
**Repo to fix:** `shopping-cart-infra` — `.github/workflows/build-push-deploy.yml`
**Severity:** Medium — loses one image promotion whenever two `main` pushes land a few minutes apart.
Not transient: the retry is structurally incapable of recovering from this conflict.

This is the failure that was deliberately kept **out of scope** of
`2026-09-21-image-promotion-fails-promoter-ssh-key-not-passed-to-reusable-workflow.md`. Same failing
step, different bug. That separation was correct — the key was present here.

## Evidence

`shopping-cart-basket` run `33507015429` (Go CI, 2026-09-01T12:19Z, head `b84a534d`) failed
`Fail when image promotion did not complete`. The key was fine (`PROMOTER_SSH_KEY: ***`). The promote
step log, in order:

```
[main e71f7f9] ci: update shopping-cart-basket to sha-b84a534d... [skip ci]
 ! [rejected]        HEAD -> main (fetch first)
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-basket.git'
hint: Updates were rejected because the remote contains work that you do not have locally
Auto-merging k8s/base/kustomization.yaml
CONFLICT (content): Merge conflict in k8s/base/kustomization.yaml
error: could not apply e71f7f9... ci: update shopping-cart-basket to sha-b84a534d... [skip ci]
```

Two `main` pushes three minutes apart, each triggering a promotion:

```
12:16Z  chore(deps): bump infra reusable workflow   => success, promoted newTag: sha-<A>
12:19Z  ci: re-pin infra reusable workflow          => FAILURE
```

The 12:16 promotion had already advanced `main` by the time the 12:19 promotion tried to push.

## Root cause

The promote step builds a commit locally, then on rejection replays **that same commit** onto the
updated remote:

```yaml
          sed -i "s|newTag:.*|newTag: sha-${{ github.sha }}|" k8s/base/kustomization.yaml
          git add k8s/base/kustomization.yaml
          git commit -m "ci: update ${{ inputs.service-name }} to sha-${{ github.sha }} [skip ci]"
          ...
          if ! git push origin "HEAD:${{ github.ref_name }}"; then
            git pull --rebase origin "${{ github.ref_name }}"
            git push origin "HEAD:${{ github.ref_name }}"
          fi
```

Both promotions rewrite the **same single line** of `k8s/base/kustomization.yaml`. A rebase of one
`newTag:` edit onto another `newTag:` edit is a guaranteed content conflict — there is no version of
this race the retry can win. The rebase halts mid-operation, leaving a conflicted worktree and
`.git/rebase-merge` in place, and the second `git push` runs against that broken state.

So the fallback is not a flaky retry that occasionally loses. It is **certain** to fail for the one
scenario it exists to handle. It only looks rare because it needs two `main` pushes close together —
which Dependabot auto-merge plus a manual re-pin produces regularly.

## The fix — regenerate, don't replay

Replace the commit-then-rebase with a fetch-reset-reapply loop. Regenerating the edit on top of the
current remote tip can never conflict, because the file is rewritten wholesale rather than merged.

**OLD** (the `if ! git push ...` block above, and the `git add`/`git commit` that precede it)

**NEW:**

```yaml
          install -d -m 700 ~/.ssh
          printf '%s\n' "${PROMOTER_SSH_KEY}" > ~/.ssh/promoter_key
          chmod 600 ~/.ssh/promoter_key
          ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
          export GIT_SSH_COMMAND="ssh -i ~/.ssh/promoter_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
          git remote set-url origin "git@github.com:${{ github.repository }}.git"
          git config user.name "sc-image-promoter"
          git config user.email "sc-image-promoter@users.noreply.github.com"

          _pushed=0
          for _attempt in 1 2 3 4 5; do
            git fetch origin "${{ github.ref_name }}"
            git reset --hard "origin/${{ github.ref_name }}"
            sed -i "s|newTag:.*|newTag: sha-${{ github.sha }}|" k8s/base/kustomization.yaml
            git add k8s/base/kustomization.yaml
            if git diff --cached --quiet; then
              echo "Image tag already matches sha-${{ github.sha }}"
              _pushed=1
              break
            fi
            git commit -m "ci: update ${{ inputs.service-name }} to sha-${{ github.sha }} [skip ci]"
            if git push origin "HEAD:${{ github.ref_name }}"; then
              _pushed=1
              break
            fi
            echo "push rejected on attempt ${_attempt}; refetching and reapplying"
            sleep $(( _attempt * 3 ))
          done

          if [ "${_pushed}" -ne 1 ]; then
            echo "::error::could not promote sha-${{ github.sha }} after 5 attempts — ${{ github.ref_name }} kept moving" >&2
            exit 1
          fi
```

Key properties, and why each matters:

- **`git reset --hard origin/<ref>` before each attempt** — the edit is always applied to the current
  tip, so there is nothing to merge and no conflict is possible.
- **The `git diff --cached --quiet` early exit moves inside the loop** — after a reset it correctly
  detects that a concurrent run already promoted this same SHA, which is a success, not a failure.
- **Bounded retries with backoff** — a genuinely hot branch fails loudly instead of looping.
- **Explicit `::error::`** — names the SHA and the reason.

Note `git reset --hard` is safe here: the runner's checkout is disposable and the only local change is
the `sed` this step just made.

## Sequencing — do NOT start before the promoter-key branch merges

`fix/pass-promoter-ssh-key` already has an unmerged commit (`94b16bc9`) touching
**this same file**. Starting this work in parallel guarantees a conflict.

Order:

1. Merge `fix/pass-promoter-ssh-key` in `shopping-cart-infra`.
2. Branch `fix/promote-refetch-instead-of-rebase` from the updated `origin/main`.
3. Implement the change above.

## Before You Start

**Spec repo:** k3d-manager — `git pull origin k3d-manager-v1.36.0`, read this file in full.
**Work repo:** `~/src/gitrepo/personal/shopping-carts/shopping-cart-infra`
**Branch:** `fix/promote-refetch-instead-of-rebase`, created from `origin/main` **after** step 1 above.

Read `.github/workflows/build-push-deploy.yml` lines 155–195 before editing — the guard step added by
the promoter-key fix sits immediately before the promote step and must be left intact.

## Rules

- YAML only. One step's `run:` block changes. Do not touch build, push, cosign sign/attest, or the
  `Verify the promoter SSH key was provided` guard.
- Validate it parses: `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/build-push-deploy.yml` — paste the result.
- Prove the rebase fallback is gone and the refetch loop is present — paste both counts:
  - `grep -c 'git pull --rebase' .github/workflows/build-push-deploy.yml` → expect `0`
  - `grep -c 'git reset --hard' .github/workflows/build-push-deploy.yml` → expect `1`
- Confirm the guard survived: `grep -c 'Verify the promoter SSH key was provided'` → expect `1`.
- Confirm step ordering with a YAML parse: the guard's index must be lower than the promote step's.
- LF line endings. Indentation is semantic — preserve it exactly.

## Commit message (verbatim)

```
fix(ci): reapply the image tag on the current tip instead of rebasing the promote commit

Two main pushes a few minutes apart each trigger a promotion, and both rewrite
the same newTag: line of k8s/base/kustomization.yaml. Rebasing one such edit
onto the other is a guaranteed content conflict, so the existing
pull --rebase retry could never recover: it halted mid-rebase and left the
worktree conflicted, and the promotion was lost. shopping-cart-basket run
33507015429 failed exactly this way on 2026-09-01.

Replace commit-then-rebase with a bounded fetch, reset --hard, reapply, push
loop. Regenerating the edit on the current tip cannot conflict, and an
already-promoted SHA is now detected after the reset and treated as success
rather than as a failure.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## Definition of Done

- [ ] `git pull --rebase` removed from the promote step
- [ ] Bounded fetch/reset/reapply/push loop in place, with the no-op early exit inside the loop
- [ ] Guard step and all build/push/cosign steps untouched
- [ ] File parses as valid YAML — output pasted
- [ ] All four `grep -c` counts pasted
- [ ] Guard-before-promote step indices pasted from a YAML parse
- [ ] Committed on `fix/promote-refetch-instead-of-rebase` with the message above
- [ ] Pushed — `git rev-parse origin/fix/promote-refetch-instead-of-rebase` matches local HEAD
- [ ] Report the SHA

## What NOT to Do

- Do NOT start before `fix/pass-promoter-ssh-key` is merged — same file, guaranteed conflict.
- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`. Do NOT force-push. No `--no-verify`.
- Do NOT re-run or trigger any GitHub Actions workflow.
- Do NOT touch any other repo.
- Do NOT "fix" this by adding `-X ours`/`-X theirs` to the rebase — that silently picks a tag by
  merge strategy rather than by what is actually on `main`.
- Do NOT change `required: false` on any secret.
- Do NOT read, print or guess `PROMOTER_SSH_KEY`.
