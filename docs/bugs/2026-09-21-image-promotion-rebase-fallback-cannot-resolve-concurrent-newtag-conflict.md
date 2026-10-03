# Image promotion's rebase fallback cannot resolve two concurrent `newTag:` bumps

**Filed:** 2026-09-21
**Status:** OPEN — spec refreshed 2026-10-02 (recurrence + ordering guard), dispatched to Codex
**Branch (spec):** `k3d-manager-v1.41.0`
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

## Recurrence — 2026-10-01, `shopping-cart-payment`

`#80` (`19c42aa`) and `#82` (`e3b6f06`, the Netty CVE override) merged close together. The `#80`
promotion landed `51322f2` (`newTag: sha-19c42aa…`); the `#82` promotion (run `37083351829`) was
rejected, rebased, conflicted on the same line, and failed. Payment `k8s/base` is still stuck at
`sha-19c42aa`.

An operator `gh run rerun --failed` failed **identically** — the rerun checks out the same
`github.sha`, so it replays the same conflict. It also rebuilt the image, which moved the
`sha-e3b6f06` tag from digest `3551ec8d…` to `1335d451…`. A rerun is never a recovery for this bug.

## Root cause

The promote step builds a commit locally, then on rejection replays **that same commit** onto the
updated remote:

```yaml
          git commit -m "ci: update ${{ inputs.service-name }} to sha-${{ github.sha }} [skip ci]"
          ...
          if ! git push origin "HEAD:${{ github.ref_name }}"; then
            git pull --rebase origin "${{ github.ref_name }}"
            git push origin "HEAD:${{ github.ref_name }}"
          fi
```

Both promotions rewrite the **same single line** of `k8s/base/kustomization.yaml`. A rebase of one
`newTag:` edit onto another `newTag:` edit is a guaranteed content conflict — there is no version of
this race the retry can win.

## The fix — regenerate on the current tip, but never move the tag backwards

Replace commit-then-rebase with a fetch → reset → reapply → push loop. Regenerating the edit on the
current tip cannot conflict.

The original version of this spec stopped there, which has a second bug: **last finisher wins**. If
the build for an older commit finishes after the build for a newer one, a blind reapply moves
`newTag` backwards (in the 10-01 recurrence, that would have reverted payment to `sha-19c42aa` and
dropped the CVE fix). So each attempt first reads the tag already on the tip and leaves it alone when
it names a commit that has `github.sha` as an ancestor.

Why this works on the default shallow (`fetch-depth: 1`) checkout: `github.sha` is always present. If
the pinned commit is **newer**, the fetch of the tip brings it and its history down to `github.sha`,
so `merge-base --is-ancestor` answers `0` and the run skips. If the pinned commit is **older**, it is
either reachable-but-not-a-descendant (exit `1`) or absent below the shallow boundary (exit `128`);
both mean "apply". Only exit `0` skips.

The fetch uses an explicit refspec because a bare `git fetch origin <branch>` is only guaranteed to
write `FETCH_HEAD`, not `refs/remotes/origin/<branch>`.

### OLD — the whole `run:` body of the `Update image tag in k8s/base/kustomization.yaml` step

```yaml
          sed -i "s|newTag:.*|newTag: sha-${{ github.sha }}|" k8s/base/kustomization.yaml
          git config user.name "sc-image-promoter"
          git config user.email "sc-image-promoter@users.noreply.github.com"
          git add k8s/base/kustomization.yaml
          if git diff --cached --quiet; then
            echo "Image tag already matches sha-${{ github.sha }}"
            exit 0
          fi
          git commit -m "ci: update ${{ inputs.service-name }} to sha-${{ github.sha }} [skip ci]"
          install -d -m 700 ~/.ssh
          printf '%s\n' "${PROMOTER_SSH_KEY}" > ~/.ssh/promoter_key
          chmod 600 ~/.ssh/promoter_key
          ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
          export GIT_SSH_COMMAND="ssh -i ~/.ssh/promoter_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
          git remote set-url origin "git@github.com:${{ github.repository }}.git"
          if ! git push origin "HEAD:${{ github.ref_name }}"; then
            git pull --rebase origin "${{ github.ref_name }}"
            git push origin "HEAD:${{ github.ref_name }}"
          fi
```

### NEW

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
            git fetch origin "+refs/heads/${{ github.ref_name }}:refs/remotes/origin/${{ github.ref_name }}"
            git reset --hard "origin/${{ github.ref_name }}"
            _current=$(sed -n 's|^[[:space:]]*newTag:[[:space:]]*sha-\([0-9a-f]\{40\}\).*|\1|p' k8s/base/kustomization.yaml | head -n 1)
            if [ -n "${_current}" ] && [ "${_current}" != "${{ github.sha }}" ] && git merge-base --is-ancestor "${{ github.sha }}" "${_current}" 2>/dev/null; then
              echo "::notice::${{ github.ref_name }} already pins sha-${_current}, which is newer than sha-${{ github.sha }}; leaving it"
              _pushed=1
              break
            fi
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

Key properties:

- **Reset to the fetched tip before each attempt** — nothing to merge, no conflict possible.
- **Never-backwards guard** — a slower build of an older commit leaves a newer tag in place and
  succeeds with a `::notice::`.
- **No-op early exit inside the loop** — a concurrent run that already promoted this SHA is success.
- **Bounded retries with backoff** and an explicit `::error::` naming the SHA.
- The SSH setup moves above the loop because the fetch now needs the key too.

`git reset --hard` is safe: the runner checkout is disposable and the only local change is this
step's own `sed`.

## Sequencing

The prerequisite `fix/pass-promoter-ssh-key` merged as infra `#99` (`91432535`, 2026-09-22). Branch
from current `origin/main`.

## Before You Start

**Spec repo:** k3d-manager — `git pull origin k3d-manager-v1.41.0`, read this file in full.
**Work repo:** `~/src/gitrepo/personal/shopping-carts/shopping-cart-infra`
**Branch (work repo):** `fix/promote-refetch-never-backwards`, created from fresh `origin/main`
(`git fetch origin && git checkout -b fix/promote-refetch-never-backwards origin/main`).
Do NOT use or touch `fix/promote-refetch-instead-of-rebase` — it holds the superseded 2026-09-21
implementation (`e99960e`, no ordering guard, no refspec) and is left for the operator to delete.
The work repo currently has another branch checked out with a clean tree; do not touch that branch.

Read `.github/workflows/build-push-deploy.yml` from the `Verify the promoter SSH key was provided`
step to the end of the file before editing. The OLD block above must match the file byte-for-byte
(after the `run: |` line); if it does not, stop and report the mismatch instead of improvising.

## Rules

- YAML only. Only the promote step's `run:` body changes. Do not touch build, push, cosign
  sign/attest, the `Verify the promoter SSH key was provided` guard, the step's `id`,
  `continue-on-error` or `env`, or the `Fail when image promotion did not complete` step.
- Validate it parses: `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/build-push-deploy.yml` — paste the result.
- If `actionlint` is installed, run it on the file and paste the output.
- Paste each count (file `.github/workflows/build-push-deploy.yml`):
  - `grep -c 'git pull --rebase'` → `0`
  - `grep -c 'git reset --hard'` → `1`
  - `grep -c 'merge-base --is-ancestor'` → `1`
  - `grep -c 'Verify the promoter SSH key was provided'` → `1`
- Paste the step indices of the guard and the promote step from a YAML parse; guard < promote.
- LF line endings. Indentation is semantic — preserve it exactly.

## Commit message (verbatim)

```
fix(ci): reapply the image tag on the current tip instead of rebasing the promote commit

Two main pushes a few minutes apart each trigger a promotion, and both rewrite
the same newTag: line of k8s/base/kustomization.yaml. Rebasing one such edit
onto the other is a guaranteed content conflict, so the pull --rebase retry
could never recover and the promotion was lost: shopping-cart-basket run
33507015429 on 2026-09-01, and shopping-cart-payment run 37083351829 on
2026-10-01, whose rerun failed identically.

Replace commit-then-rebase with a bounded fetch, reset --hard, reapply, push
loop. Before reapplying, leave the tag alone when it already names a commit
that descends from this build's commit, so a slower build of an older commit
can no longer move newTag backwards.

Co-Authored-By: Codex <noreply@openai.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

## Definition of Done

- [ ] OLD block replaced by NEW exactly; nothing else in the file changed (`git diff --stat` = 1 file)
- [ ] YAML parse output pasted; actionlint output pasted if available
- [ ] All four `grep -c` counts pasted
- [ ] Guard-before-promote step indices pasted
- [ ] Committed on `fix/promote-refetch-never-backwards` with the message above
- [ ] Pushed — `git rev-parse origin/fix/promote-refetch-never-backwards` matches local HEAD
- [ ] Report the SHA

## What NOT to Do

- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`. Do NOT force-push. No `--no-verify`.
- Do NOT re-run or trigger any GitHub Actions workflow.
- Do NOT touch any other repo, and do NOT edit k3d-manager files (Claude updates the memory-bank).
- Do NOT "fix" this by adding `-X ours`/`-X theirs` to a rebase.
- Do NOT add `fetch-depth: 0` to the checkout — the guard is designed for the shallow checkout.
- Do NOT change `required: false` on any secret.
- Do NOT read, print or guess `PROMOTER_SSH_KEY`.

## Follow-up — Part B (after the infra PR merges; Claude dispatches separately)

Bump each caller's `build-push-deploy.yml@<sha>` pin to the merged infra commit, **payment first**.
Payment CI rebuilds and promotes on every `main` merge, so merging payment's pin bump both repairs
its stale `k8s/base` (`sha-19c42aa` → the merge commit) and is the first live run of the new loop.
A separate hand-edit of payment's `newTag` would be overwritten by that same promotion, so none is
needed. Then basket, order, product-catalog.

### Part B spec (dispatched 2026-10-02)

infra PR #107 merged as `98b10f051bda5ffe28299dac288f11fe568a7a1c`. Every caller already forwards
`PROMOTER_SSH_KEY` and holds that secret (checked by name), so the `Verify the promoter SSH key`
step that basket/order/product-catalog gain by moving past `e41f2adb` cannot fail them. No other
input or secret changed between the old pins and `98b10f0`.

**Branch (all work repos):** `ci/bump-build-push-deploy-98b10f0`, created from `origin/main`.

| Repo | File:line | OLD pin | NEW pin |
|---|---|---|---|
| shopping-cart-payment | `.github/workflows/ci.yaml:199` | `e41f2adbc2023064e277dae4bf9ba756c9560110` | `98b10f051bda5ffe28299dac288f11fe568a7a1c` |
| shopping-cart-basket | `.github/workflows/go-ci.yml:71` | `45def89e151bc9d3506f7d641f46d045bc84029d` | `98b10f051bda5ffe28299dac288f11fe568a7a1c` |
| shopping-cart-order | `.github/workflows/ci.yml:60` | `af4b053dc9e1015141ae142a5329ab90b6348b43` | `98b10f051bda5ffe28299dac288f11fe568a7a1c` |
| shopping-cart-product-catalog | `.github/workflows/ci.yml:134` | `af4b053dc9e1015141ae142a5329ab90b6348b43` | `98b10f051bda5ffe28299dac288f11fe568a7a1c` |

Each line reads `    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@<OLD pin>`;
replace only the 40-hex SHA.

**Gates (per repo):**
- `grep -c 'build-push-deploy.yml@<OLD pin>' <file>` → `0`
- `grep -c 'build-push-deploy.yml@98b10f051bda5ffe28299dac288f11fe568a7a1c' <file>` → `1`
- `git diff --stat origin/main` → exactly 1 file, `1 insertion(+), 1 deletion(-)`
- `actionlint <file>` if installed (report if not)

**Commit message (all four repos):**

```
ci: pin build-push-deploy to the never-backwards promote loop (infra #107)

Co-Authored-By: Codex <noreply@openai.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

**What NOT to do:** no PR, no merge, no `--no-verify`, no commit to `main`, no other file, no edit
to `k8s/base/kustomization.yaml` (the promote step owns `newTag`). Push each branch with
`git push -u origin ci/bump-build-push-deploy-98b10f0` and confirm with
`git rev-parse origin/ci/bump-build-push-deploy-98b10f0`.

**Merge order (operator):** payment first; confirm its main run's promote step pushes
`newTag: sha-<merge>` (repairs `k8s/base`), then basket, order, product-catalog.
