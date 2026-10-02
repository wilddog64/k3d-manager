# No safe way to set the GitHub Actions secrets the workflows read

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** medium. A typo or stale GitHub secret silently breaks the Slack relay on the next
`deploy-worker.yml` run, and every slash command fails with "the app did not respond".
**Status:** OPEN

## Observed (2026-10-01)

1. `gh workflow run deploy-worker.yml` (run 36958122506) was the workflow's first successful run.
   It uploaded the GitHub copy of `SLACK_SIGNING_SECRET` (dated 2026-06-23, stale) to the relay.
   Every slash command then failed the signature check.
2. While fixing it, the operator ran `gh secret set` by hand and created `SLACK_SIGING_SECRET`
   (typo). `gh` accepts any name, so nothing flagged it, and the real secret stayed stale.

Nothing in the repo tells the operator which secret names the workflows read, and nothing
rejects a name the workflows do not read.

## Fix

### A. `make gh-secret` (Makefile)

Add a `gh-secret` target, list it in `.PHONY`, and give it a `##` help comment like its neighbours.

- **Allowlist derived from the workflows**, never hardcoded: the unique names matched by
  `secrets\.([A-Z0-9_]+)` across `.github/workflows/*.yml` and `*.yaml`, excluding `GITHUB_TOKEN`.
  Today that is `CLOUDFLARE_API_TOKEN`, `COPILOT_TOKEN`, `K3DM_WEBHOOK_TOKEN`, `SLACK_SIGNING_SECRET`.
- `make gh-secret` with no `NAME` prints each allowed name and its last-updated date. Take the
  dates from `gh secret list --repo "$(GH_REPO)"`, or show `(not set)`. It also lists any repo
  secret that is **not** on the allowlist as `unused (typo?)`. Exit 0.
- `make gh-secret NAME=<X>`:
  - `X` not on the allowlist → print the allowed names and exit 1. Never call `gh secret set`.
  - Otherwise run `gh secret set "$NAME" --repo "$(GH_REPO)"` with **no** `--body`, so `gh`
    prompts on the TTY and the value never shows up in argv, make output, or shell history.
    stdin must stay attached to the terminal: no pipe, and no `$( )` around the call.
  - Afterwards, print the new date from `gh secret list`.
- `GH_REPO ?= wilddog64/k3d-manager`.
- No `VALUE=` variable, and no way at all to pass the secret on the command line.

### B. Keychain sync for the relay secrets (Makefile)

Add `make gh-secret-sync-relay`. It reads `k3dm-webhook-token` and `k3dm-slack-signing-secret`
from the Keychain, using the same `security find-generic-password -s … -a k3dm -w` calls as
`deploy-worker`, and pipes each value on stdin to
`gh secret set K3DM_WEBHOOK_TOKEN` / `gh secret set SLACK_SIGNING_SECRET`.

- A missing or empty item → the same style of error as `deploy-worker`, exit 1, and **nothing**
  is set.
- Never echo a value.

This keeps the GitHub copies equal to the Keychain values that `make deploy-worker` pushes, so
the workflow can no longer roll the relay back.

### C. Docs

- `docs/howto/slack-slash-commands.md`: a short section, "GitHub secrets for the relay
  workflow", covering:
  - the two targets;
  - that `deploy-worker.yml` overwrites the relay's `WEBHOOK_TOKEN` and `SLACK_SIGNING_SECRET`
    with the GitHub copies;
  - that "app did not respond" on every command right after a relay deploy means the signing
    secret does not match.
- CHANGELOG `Added` bullet.

## Tests

Use a new `scripts/tests/bin/makefile_gh_secret.bats` (look at `makefile_signing_restore.bats` for
the stub pattern). Put stub `gh` and `security` on `PATH`; they record their argv, and their stdin
where relevant, to a file. No network.

- No `NAME`: the output lists all four allowed names and flags a stubbed extra repo secret
  `SLACK_SIGING_SECRET` as `unused (typo?)`.
- `NAME=SLACK_SIGING_SECRET` → exit non-zero, and the `gh` log has no `secret set`.
- `NAME=SLACK_SIGNING_SECRET` → `gh secret set SLACK_SIGNING_SECRET --repo wilddog64/k3d-manager`
  is recorded, and no `--body`/`-b` appears in argv.
- The allowlist is derived: in a temp copy of the workflows dir, a new `secrets.FOO_BAR` makes
  `FOO_BAR` allowed. If the Makefile cannot point at a temp dir, add `GH_WORKFLOWS_DIR ?=
  .github/workflows`.
- Sync: the stub `security` returns values → two `secret set` calls, each with its value on
  **stdin** and absent from argv. One empty item → exit 1 and zero `secret set` calls.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) skip the allowlist check → typo test red;
(b) pass the value with `--body` in the sync → argv test red;
(c) drop the empty-item guard → partial-set test red.

## Rules

- Linux-portable shell (CI is Ubuntu): no `sed -i ''`, no BSD-only flags. The recipe uses bash
  (`SHELL := /bin/bash`).
- `make test-bin` (or `bats` on the new file) green, plus `make check-doc-links`.
- Touch only: `Makefile`, the new bats file, `docs/howto/slack-slash-commands.md`, `CHANGELOG.md`,
  and this bug doc (Resolution section and Status FIXED).
