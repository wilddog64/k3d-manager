# Image promotion fails silently-then-cryptically: `PROMOTER_SSH_KEY` is never passed to the reusable workflow

**Filed:** 2026-09-21
**Branch (spec):** `k3d-manager-v1.36.0`
**Severity:** High — images build and push to GHCR successfully, then the promotion step fails, so
the infra repo is never updated with the new digest. CI reports overall `success` on PRs because the
publish job is skipped there, which hid this for weeks.

## Evidence

Last `main` push of `shopping-cart-product-catalog` (run `35117065512`, 2026-09-16):

```
success   Lint & Type Check
success   Integration Test — Schema Self-Heal
success   Lint, Test & Build
success   Security Scan
failure   Build, Scan & Push / build-push
            FAILED STEP: Fail when image promotion did not complete
```

The job log shows the cause directly:

```
PROMOTER_SSH_KEY:
Load key "/home/runner/.ssh/promoter_key": error in libcrypto
```

The variable is **empty**. Note what did succeed first — the image was built, pushed, and attested:

```
DIGEST: sha256:e9bcb925619b5344a958fc359091b651c61365ce7b8a65c354408ee2f7198b92
cosign attest --yes --key env://COSIGN_KEY --type vuln ...
```

That digest is exactly what `product-catalog` on the hub is trying to pull. **`PACKAGES_TOKEN` is
working.** The registry push half of this pipeline is healthy; only the git promotion half is broken.

## Root cause

`shopping-cart-infra/.github/workflows/build-push-deploy.yml` declares:

```yaml
      PROMOTER_SSH_KEY:
        required: false
```

and consumes it at line 170:

```yaml
          printf '%s\n' "${PROMOTER_SSH_KEY}" > ~/.ssh/promoter_key
```

Because it is `required: false`, a caller that omits it passes validation and fails much later inside
`ssh` with `error in libcrypto` — a message that names neither the secret nor the caller.

Three of five callers omit it from their `secrets:` block:

| Repo | Workflow | Passes `PROMOTER_SSH_KEY`? | Repo secret set? |
|---|---|---|---|
| shopping-cart-basket | `go-ci.yml` | yes | yes |
| shopping-cart-order | `ci.yml` | yes | yes |
| **shopping-cart-payment** | `go-ci.yml` | **no** | yes |
| **shopping-cart-product-catalog** | `ci.yml` | **no** | **no** |
| **shopping-cart-frontend** | `ci.yml` | **no** | **no** |

So `shopping-cart-payment` is a pure code fix — the secret exists, the workflow just never forwards
it. `product-catalog` and `frontend` need the code fix **and** an operator action to set the secret.

## Why CI looked green

`publish` is gated on `if: github.ref == 'refs/heads/main' && github.event_name == 'push'`. Every
Dependabot and feature-branch run **skips** it, and a skipped job does not fail a run. The most
recent product-catalog run (2026-09-21) is `success` with `Build, Scan & Push = skipped`. Only a push
to `main` exercises the path, and those are comparatively rare.

---

## Before You Start

**Spec repo:** k3d-manager — `git pull origin k3d-manager-v1.36.0`, read this file in full.
**Work repos and branch (create from `origin/main` in each):** `fix/pass-promoter-ssh-key`

- `~/src/gitrepo/personal/shopping-carts/shopping-cart-payment`
- `~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog`
- `~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend`
- `~/src/gitrepo/personal/shopping-carts/shopping-cart-infra`

Never work from `main`. Never push to `main`.

Read before editing, in each repo:
- the caller workflow (`go-ci.yml` or `ci.yml`) — specifically its `publish:` job
- `shopping-cart-infra/.github/workflows/build-push-deploy.yml` lines 20–40 and 160–190
- `shopping-cart-basket/.github/workflows/go-ci.yml` `publish:` job — this is the **correct
  reference shape**; make the three broken callers match it.

## Change 1 — forward the secret in the three callers

In `shopping-cart-payment/.github/workflows/go-ci.yml`,
`shopping-cart-product-catalog/.github/workflows/ci.yml`, and
`shopping-cart-frontend/.github/workflows/ci.yml`, find the `publish:` job's `secrets:` block.

**OLD** (product-catalog shown; the other two are the same shape):

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

Do not reorder or reformat the existing three lines. Add one line.

## Change 2 — fail fast with an actionable message in the reusable workflow

In `shopping-cart-infra/.github/workflows/build-push-deploy.yml`, insert a guard step immediately
**before** the promotion step that consumes `PROMOTER_SSH_KEY` (the step containing
`printf '%s\n' "${PROMOTER_SSH_KEY}" > ~/.ssh/promoter_key`, around line 165).

**NEW step to insert** (match the surrounding indentation exactly):

```yaml
      - name: Verify the promoter SSH key was provided
        env:
          PROMOTER_SSH_KEY: ${{ secrets.PROMOTER_SSH_KEY }}
        run: |
          if [ -z "${PROMOTER_SSH_KEY}" ]; then
            echo "::error::PROMOTER_SSH_KEY is empty. The calling workflow did not forward it." >&2
            echo "::error::Add 'PROMOTER_SSH_KEY: \${{ secrets.PROMOTER_SSH_KEY }}' to the secrets block of the job that calls build-push-deploy.yml, and confirm the secret exists in this repository." >&2
            exit 1
          fi
```

Leave `required: false` as-is — changing it to `required: true` would break callers at
workflow-validation time with a less informative message, and this guard gives a better one.

## Change 3 — do not touch the rest of the pipeline

The build, push, cosign sign and attest steps are working and verified. Do not modify them.

## Rules

- YAML only. Do not edit application code, Dockerfiles, or any other workflow.
- Validate each changed workflow parses:
  `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" <file>` — paste the result for
  each of the four files.
- Confirm the guard step is placed **before** the consuming step: print the line numbers of
  `Verify the promoter SSH key was provided` and of `promoter_key` in
  `build-push-deploy.yml` and show that the guard's line number is smaller.
- Confirm each caller now matches the basket reference:
  `grep -c 'PROMOTER_SSH_KEY' <caller-workflow>` must be `1` in each of the three, and was `0`
  before. Paste before/after counts.
- LF line endings. Preserve existing indentation exactly — these are YAML files, indentation is
  semantic.

## Commit message (verbatim, all four repos)

```
fix(ci): forward PROMOTER_SSH_KEY to the reusable build-push-deploy workflow

Image promotion failed on every push to main in payment, product-catalog and
frontend: the publish job never forwarded PROMOTER_SSH_KEY, so the reusable
workflow wrote an empty key file and ssh failed with "error in libcrypto".
The image itself built, pushed and was attested successfully, so the failure
was confined to the git promotion step and was invisible on pull requests,
where the publish job is skipped.

Forward the secret from the three callers, and add a guard in
build-push-deploy.yml that fails immediately with a message naming the secret
and the fix when it arrives empty.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

## Definition of Done

- [ ] `PROMOTER_SSH_KEY` forwarded in payment, product-catalog and frontend callers (1 line each)
- [ ] Guard step added to `build-push-deploy.yml`, placed before the consuming step
- [ ] All four workflow files parse as valid YAML — output pasted
- [ ] Before/after `grep -c` counts pasted for the three callers (`0` → `1`)
- [ ] Guard-before-consumer line numbers pasted
- [ ] Committed on `fix/pass-promoter-ssh-key` in each repo with the message above
- [ ] Pushed — `git rev-parse origin/fix/pass-promoter-ssh-key` matches local HEAD in each repo
- [ ] Report one SHA per repo

## Operator action required (NOT Codex — needs key material)

`shopping-cart-product-catalog` and `shopping-cart-frontend` have **no** `PROMOTER_SSH_KEY` secret.
The code fix forwards a secret that does not yet exist there, so promotion in those two repos will
still fail — but now with the explicit guard message instead of `error in libcrypto`.

The operator must add the secret to both repos, using the same key already present in
`shopping-cart-basket`, `shopping-cart-order` and `shopping-cart-payment`.

## What NOT to Do

- Do NOT create a PR in any repo. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify`.
- Do NOT change `required: false` to `required: true`.
- Do NOT touch the build, push, cosign sign or attest steps — they are verified working.
- Do NOT attempt to create, read, print or guess the `PROMOTER_SSH_KEY` value.
- Do NOT modify `PACKAGES_TOKEN` handling. It is not broken; the registry push succeeds.
- Do NOT re-run or trigger any GitHub Actions workflow.
