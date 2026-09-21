# Image promotion fails in `shopping-cart-product-catalog`: `PROMOTER_SSH_KEY` is never passed to the reusable workflow

**Filed:** 2026-09-21
**Revised:** 2026-09-21 — scope corrected after Codex caught a spec/repository mismatch. See
`## Spec correction` for what the first version got wrong.
**Branch (spec):** `k3d-manager-v1.36.0`
**Severity:** High — `shopping-cart-product-catalog` has failed image promotion on **every** push to
`main` since at least 2026-08-26. The image builds, pushes and is attested, but the infra repo never
receives the new digest.

## Evidence

Every recent `main` push of `shopping-cart-product-catalog` fails the same way:

```
run 35117065512  2026-09-16T15:41 => failure   FAILED JOB: Build, Scan & Push / build-push
run 33510350374  2026-09-01T12:55 => failure   FAILED JOB: Build, Scan & Push / build-push
run 32914072637  2026-08-26T00:11 => failure   FAILED JOB: Build, Scan & Push / build-push
```

Failing step and cause (run `35117065512`):

```
FAILED STEP: Fail when image promotion did not complete

PROMOTER_SSH_KEY:
Load key "/home/runner/.ssh/promoter_key": error in libcrypto
```

The variable is **empty**. Note what succeeded first — the image was built, pushed and attested:

```
DIGEST: sha256:e9bcb925619b5344a958fc359091b651c61365ce7b8a65c354408ee2f7198b92
cosign attest --yes --key env://COSIGN_KEY --type vuln ...
```

That digest is exactly what `product-catalog` on the hub is trying to pull, so the image exists in
GHCR. **`PACKAGES_TOKEN` is working** — the registry half of this pipeline is healthy. Only the git
promotion half is broken.

## Root cause

`shopping-cart-infra/.github/workflows/build-push-deploy.yml` declares the secret optional:

```yaml
      PROMOTER_SSH_KEY:
        required: false
```

and consumes it around line 170:

```yaml
          printf '%s\n' "${PROMOTER_SSH_KEY}" > ~/.ssh/promoter_key
```

Because it is `required: false`, a caller that omits it passes validation and then fails deep inside
`ssh` with `error in libcrypto` — a message naming neither the secret nor the caller.

`shopping-cart-product-catalog/.github/workflows/ci.yml` calls the reusable workflow but omits
`PROMOTER_SSH_KEY` from its `secrets:` block. It is also the only one of the five repos with **no**
`PROMOTER_SSH_KEY` repository secret at all.

## Verified state of all five repos

| Repo | Caller workflow | Calls reusable? | Forwards key? | Repo secret? | Last `main` pushes |
|---|---|---|---|---|---|
| shopping-cart-basket | `go-ci.yml` | yes | yes | yes | 1 failure — **different cause**, see below |
| shopping-cart-order | `ci.yml` | yes | yes | yes | success |
| shopping-cart-payment | `ci.yaml` | yes | yes | yes | success |
| **shopping-cart-product-catalog** | `ci.yml` | yes | **no** | **no** | **failure 3/3** |
| shopping-cart-frontend | `ci.yml` | **no** — inline publish | n/a | n/a | success |

`shopping-cart-frontend` does not use the reusable workflow. Its `publish` job is inline and promotes
via a deploy PR using `PACKAGES_TOKEN` as `GH_TOKEN`; it never references `PROMOTER_SSH_KEY`. It is
out of scope.

## Why CI looked green

`publish` is gated on `if: github.ref == 'refs/heads/main' && github.event_name == 'push'`. Every
Dependabot and feature-branch run **skips** it, and a skipped job does not fail a run. The most
recent product-catalog run (2026-09-21) reads `success` with `Build, Scan & Push = skipped`. Only a
push to `main` exercises the path. Read the job list, not the run conclusion.

## Out of scope — separate follow-up, do NOT fix here

`shopping-cart-basket` run `33507015429` (2026-09-01) also failed `Fail when image promotion did not
complete`, but for an unrelated reason. Its key was present (`PROMOTER_SSH_KEY: ***`) and the failure
was:

```
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-basket.git'
```

That is a push rejection, not a missing credential. Single occurrence; order and payment succeed with
the same shape. File separately if it recurs.

## Spec correction

The first version of this spec named four repos and three code changes. Three of those were wrong,
and the error was Claude's, not Codex's — the detection script globbed `*.yml` only and took the
first match per repo:

- **payment** — tested `go-ci.yml`, which has no `publish` job. The real caller is `ci.yaml`
  (`.yaml`, not `.yml`), which **already forwards the key**. Not broken.
- **frontend** — does not call the reusable workflow at all. Not broken.
- **basket** — already correct; its one failure has a different cause (above).

Codex stopped and asked rather than editing files that did not match the spec. That was the right
call and is why this revision exists.

---

## Before You Start

**Spec repo:** k3d-manager — `git pull origin k3d-manager-v1.36.0`, read this file in full.
**Work repos and branch (create from `origin/main` in each):** `fix/pass-promoter-ssh-key`

- `~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog`
- `~/src/gitrepo/personal/shopping-carts/shopping-cart-infra`

Only these two. Never work from `main`. Never push to `main`.

You already created branches in `shopping-cart-payment` and `shopping-cart-frontend` during the
first attempt. Leave them alone — do not commit to them, and do not delete them.

Read before editing:
- `shopping-cart-product-catalog/.github/workflows/ci.yml` — the `publish:` job
- `shopping-cart-order/.github/workflows/ci.yml` — the `publish:` job. This is the **correct
  reference shape**; read it, do not edit it.
- `shopping-cart-infra/.github/workflows/build-push-deploy.yml` lines 20–40 and 160–190

## Change 1 — forward the secret in product-catalog

In `shopping-cart-product-catalog/.github/workflows/ci.yml`, in the `publish:` job:

**OLD:**

```yaml
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
      COSIGN_KEY: ${{ secrets.COSIGN_KEY }}
      COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
```

**NEW:**

```yaml
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
      COSIGN_KEY: ${{ secrets.COSIGN_KEY }}
      COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
      PROMOTER_SSH_KEY: ${{ secrets.PROMOTER_SSH_KEY }}
```

Add one line. Do not reorder or reformat the existing three.

## Change 2 — fail fast with an actionable message in the reusable workflow

In `shopping-cart-infra/.github/workflows/build-push-deploy.yml`, insert a guard step immediately
**before** the step that consumes the key (the one containing
`printf '%s\n' "${PROMOTER_SSH_KEY}" > ~/.ssh/promoter_key`, around line 165). Match the surrounding
indentation exactly.

```yaml
      - name: Verify the promoter SSH key was provided
        env:
          PROMOTER_SSH_KEY: ${{ secrets.PROMOTER_SSH_KEY }}
        run: |
          if [ -z "${PROMOTER_SSH_KEY}" ]; then
            echo "::error::PROMOTER_SSH_KEY is empty. The calling workflow did not forward it, or the repository has no such secret." >&2
            echo "::error::Add 'PROMOTER_SSH_KEY: \${{ secrets.PROMOTER_SSH_KEY }}' to the secrets block of the job that calls build-push-deploy.yml, and confirm the secret exists in the calling repository." >&2
            exit 1
          fi
```

Leave `required: false` unchanged — flipping it to `required: true` fails at workflow-validation time
with a less informative message, and this guard gives a better one.

## Change 3 — do not touch the rest of the pipeline

The build, push, cosign sign and attest steps are verified working. Do not modify them.

## Rules

- YAML only. Do not edit application code, Dockerfiles, or any other workflow.
- Validate both changed files parse:
  `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" <file>` — paste both results.
- Prove the product-catalog change is real, before/after:
  - `git show origin/main:.github/workflows/ci.yml | grep -c 'PROMOTER_SSH_KEY'` → expect `0`
  - `grep -c 'PROMOTER_SSH_KEY' .github/workflows/ci.yml` → expect `1`
- Prove the guard precedes the consumer in `build-push-deploy.yml` — paste both line numbers and
  show the guard's is smaller:
  - `grep -n 'Verify the promoter SSH key was provided' .github/workflows/build-push-deploy.yml`
  - `grep -n 'promoter_key' .github/workflows/build-push-deploy.yml`
- LF line endings. Preserve indentation exactly — indentation is semantic in YAML.

## Commit message (verbatim, both repos)

```
fix(ci): forward PROMOTER_SSH_KEY to the reusable build-push-deploy workflow

shopping-cart-product-catalog failed image promotion on every push to main
since 2026-08-26: the publish job never forwarded PROMOTER_SSH_KEY, so the
reusable workflow wrote an empty key file and ssh failed with "error in
libcrypto". The image itself built, pushed and was attested successfully, so
the failure was confined to the git promotion step, and it was invisible on
pull requests where the publish job is skipped.

Forward the secret from the product-catalog caller, and add a guard in
build-push-deploy.yml that fails immediately with a message naming the secret
and the fix when it arrives empty.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## Definition of Done

- [ ] `PROMOTER_SSH_KEY` forwarded in `shopping-cart-product-catalog/.github/workflows/ci.yml`
- [ ] Guard step added to `build-push-deploy.yml`, placed before the consuming step
- [ ] Both files parse as valid YAML — output pasted
- [ ] Before/after `grep -c` counts pasted (`0` → `1`)
- [ ] Guard-before-consumer line numbers pasted
- [ ] Committed on `fix/pass-promoter-ssh-key` in both repos with the message above
- [ ] Pushed — `git rev-parse origin/fix/pass-promoter-ssh-key` matches local HEAD in both
- [ ] Report one SHA per repo (2 total)

## Operator action required (NOT Codex — needs key material)

`shopping-cart-product-catalog` has **no** `PROMOTER_SSH_KEY` secret. Change 1 forwards a secret
that does not yet exist there, so promotion will still fail — but with the explicit guard message
instead of `error in libcrypto`.

The operator must add the secret to that repo, using the same key already present in
`shopping-cart-basket`, `shopping-cart-order` and `shopping-cart-payment`.

## What NOT to Do

- Do NOT create a PR in any repo. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify`.
- Do NOT change `required: false` to `required: true`.
- Do NOT touch `shopping-cart-payment`, `shopping-cart-frontend`, `shopping-cart-basket` or
  `shopping-cart-order` — all four are correct for this defect.
- Do NOT delete the stray branches from the first attempt.
- Do NOT attempt to fix the basket push-rejection failure. It is a separate, unfiled issue.
- Do NOT touch the build, push, cosign sign or attest steps.
- Do NOT create, read, print or guess the `PROMOTER_SSH_KEY` value.
- Do NOT modify `PACKAGES_TOKEN` handling. It is not broken.
- Do NOT re-run or trigger any GitHub Actions workflow.
