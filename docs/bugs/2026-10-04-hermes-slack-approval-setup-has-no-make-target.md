# Bug: Hermes Slack-approval setup is five hand-typed credential commands with no make target

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** low. Operator friction, and a credential step that is easy to get subtly wrong.

## Observed

`docs/guides/hermes.md` § "Slack approvals (opt-in)" has the operator run these steps by hand:

1. `wrangler kv namespace create APPROVALS_KV`, then hand-edit `workers/slack-relay/wrangler.toml`
   to uncomment the binding with the printed id.
2. Generate a random drain token (at least 32 characters).
3. Store it in the Keychain as `k3dm-hermes-approval-drain-token`.
4. Put the same value into the relay with `wrangler secret put APPROVAL_DRAIN_TOKEN`.
5. Set the approvers with `wrangler secret put APPROVER_ALLOWLIST`.

Steps 2–4 must agree byte for byte. A trailing newline or a mis-paste silently breaks the drain:
the relay returns 401, and Hermes's `fetch_approvals` fails closed to `[]` with no log. The
operator asked for a make target (2026-10-04).

Facts the fix depends on:

- **The relay** (`workers/slack-relay/index.js`):
  - `drainAuthorized` rejects tokens shorter than 32 characters.
  - `approverAllowed` splits `APPROVER_ALLOWLIST` on `,` and trims each entry.
- **`deploy-worker`** (`Makefile:576`) is the house pattern for wrangler:
  - the Cloudflare token comes from Keychain `k3dm-cloudflare-api-token`;
  - commands run as `CLOUDFLARE_API_TOKEN=… npx --yes wrangler …` from `workers/slack-relay`;
  - secret values are piped on stdin.
- **`argocd-hermes-token`** (`Makefile:894`) is the house pattern for a credential target:
  - a `[ -t 0 ]` TTY gate;
  - the Keychain is written with `-U`;
  - the value is read back before reporting success, and the token is never echoed.
  - It does pass its token to `security` through argv. The new target must not: the guide says
    "entered via prompt, not argv".

## Fix spec

### File 1 — `Makefile`

Add `RELAY_DIR ?= workers/slack-relay` near the other `?=` variables. Add the four targets below to
`.PHONY`. Each gets a `## ` help comment block in the style of the existing targets. Place them right
after `argocd-hermes-token`. All recipes use `@set -euo pipefail;` like `gh-secret`.

**Shared preamble.** All three wrangler-using targets need the Cloudflare token:
- read Keychain `k3dm-cloudflare-api-token` (account `k3dm`) into `_cf`;
- if it is empty, fail with the same message `deploy-worker` uses;
- run every wrangler call as `CLOUDFLARE_API_TOKEN="$$_cf" npx --yes wrangler …` with
  `cd "$(RELAY_DIR)"`.

**`hermes-approvals-kv`** creates the KV namespace and wires the binding into `wrangler.toml`.

- **Idempotent:** if `$(RELAY_DIR)/wrangler.toml` already has an uncommented
  `binding = "APPROVALS_KV"` line, print `[hermes-approvals-kv] APPROVALS_KV already bound in wrangler.toml — nothing to do`
  and exit 0, without calling wrangler.
- **Otherwise:**
  - run `wrangler kv namespace create APPROVALS_KV`;
  - extract the id with `grep -oE '[0-9a-f]{32}' | head -1`;
  - if no id is found, fail. Print wrangler's output in that case, since it contains no secret.
- **Rewrite** the three commented lines, keeping the comment lines above them, from
  ```
  # [[kv_namespaces]]
  # binding = "APPROVALS_KV"
  # id = "<namespace-id>"
  ```
  to
  ```
  [[kv_namespaces]]
  binding = "APPROVALS_KV"
  id = "<extracted id>"
  ```
  Use `python3` with the id passed in the environment (`KV_ID="$$_id" python3 - "$(RELAY_DIR)/wrangler.toml"`),
  not `sed -i`, which differs between BSD and GNU.
- **Finish** by printing:
  `[hermes-approvals-kv] bound APPROVALS_KV (<id>). Commit $(RELAY_DIR)/wrangler.toml, then run: make deploy-worker`.
  The namespace id is not a secret.

**`hermes-drain-token`** creates the drain token, or syncs an existing one, and pushes it to the relay.

- **TTY gate**, copied from `argocd-hermes-token`, including the wording "must not run unattended".
- **Choose the token:**
  - if Keychain `k3dm-hermes-approval-drain-token` (account `k3dm`) exists and `ROTATE` is not
    `1`, reuse its value. This mode syncs the existing token to the relay.
  - otherwise set `_tok=$$(openssl rand -hex 32)` (64 hex characters) and write it with
    ```
    printf 'add-generic-password -U -a k3dm -s k3dm-hermes-approval-drain-token -w %s\n' "$$_tok" | security -i
    ```
    `printf` is a shell builtin, so the token goes to `security` on stdin and never appears in
    any process's argv. Never use `security add-generic-password … -w "$$_tok"`.
- **Read back** the Keychain into `_stored`:
  - if `_stored` is empty, fail with a message containing `reads back empty`;
  - if `${#_stored}` is less than 32, fail;
  - when a new token was generated and `[ "$$_stored" != "$$_tok" ]`, fail.
  - Never print either value or its length.
- **Push** with `printf '%s' "$$_stored" | … wrangler secret put APPROVAL_DRAIN_TOKEN`.
- **Finish** with `[hermes-drain-token] drain token stored in Keychain and pushed to the relay (created|reused)`.
  It names the mode, not the value.

**`hermes-approvers`** sets the approver allowlist.

- **Require `APPROVERS`**, a comma-separated list of Slack user IDs.
  - Validate it against `^[UW][A-Z0-9]{2,}(,[UW][A-Z0-9]{2,})*$` before reading any Keychain item.
    No spaces are allowed.
  - If it is unset or invalid, fail with a message naming `APPROVERS=U0123ABCD` and exit non-zero,
    without calling `security` or `npx`.
- **Push** with `printf '%s' "$(APPROVERS)" | … wrangler secret put APPROVER_ALLOWLIST`. The IDs are
  not secret, so no TTY gate is needed.

**`hermes-approvals-setup`** is the umbrella target. It runs, in order:
1. `$(MAKE) hermes-approvals-kv`
2. `$(MAKE) hermes-drain-token`
3. `$(MAKE) hermes-approvers APPROVERS="$(APPROVERS)"`

Fail fast if `APPROVERS` is unset, before step 1 runs. Use single-dollar `$(MAKE)`. Finish by
printing the remaining manual steps:
- commit `wrangler.toml` if it changed;
- `make deploy-worker`;
- turn on Slack Interactivity with Request URL `https://k3dm-slack-relay.k3dm.workers.dev/slack/interactivity`
  and register `/hermes-auth`;
- set `K3DM_HERMES_APPROVAL_DRAIN_URL`. A follow-up spec will add this to the LaunchAgent template.

### File 2 — `scripts/tests/bin/makefile_hermes_approvals.bats` (new)

Follow the style of `scripts/tests/bin/makefile_argocd_hermes_token.bats`: static `RECIPE` extraction
with `awk '/^<target>:/,/^$/'`. Add behavioural tests that put stubs for `security`, `npx` and
`openssl` on `PATH`. Each stub logs its argv, and its stdin, to `$BATS_TEST_TMPDIR`. Point `RELAY_DIR`
at a temporary copy of `workers/slack-relay/wrangler.toml`.

The tests must cover:

1. All four targets are in `.PHONY`.
2. `hermes-drain-token` has the TTY gate and the "must not run unattended" wording.
3. No recipe echoes `$$_tok` or `$$_stored`.
4. No recipe contains `-w "$$_tok"` or `-w "$$_stored"`, which would put the token in argv.
5. `hermes-drain-token` contains `| security -i` and `reads back empty`.
6. Behavioural: `make -f <Makefile> hermes-approvers APPROVERS='U1 2'` exits non-zero, and neither
   the `security` stub nor the `npx` stub was called.
7. Behavioural: `APPROVERS=U0123ABCD,W0456EFGH` exits 0, and the `npx` stub received exactly
   `U0123ABCD,W0456EFGH` on stdin, with no trailing newline.
8. Behavioural: `hermes-approvals-kv` against the temporary toml. The `npx` stub prints
   `id = "0123456789abcdef0123456789abcdef"`.
   - The rewritten file has the uncommented `binding = "APPROVALS_KV"` line and that id.
   - A second run prints `nothing to do`, and the `npx` stub log shows only one call.
9. Behavioural: `hermes-approvals-setup` without `APPROVERS` exits non-zero before any stub is called.

Use `run` + `$status`. No bare `! cmd`.

### File 3 — `docs/guides/hermes.md`

In § "Slack approvals (opt-in)", replace operator steps 1–3 and the `APPROVER_ALLOWLIST` half of
step 2 with:
- `make hermes-approvals-setup APPROVERS=<your Slack user ID>`, run in Terminal.app;
- one sentence each on what the three sub-targets do;
- a note that `ROTATE=1 make hermes-drain-token` rotates the token.

Keep steps 4 and 5, the Slack app and the LaunchAgent URL, as they are, and add `make deploy-worker` before them.

### File 4 — `CHANGELOG.md`

Add one entry under `## [Unreleased]` → `### Added` covering:
- the four targets;
- that the token reaches `security` via `security -i` stdin, never argv;
- that it is read back and compared before it is pushed;
- that the allowlist is validated.

## Rules

- Modify only Files 1–4. Do not touch `workers/slack-relay/wrangler.toml`; the operator's run
  edits it. Do not touch `scripts/lib/foundation/`.
- Never run the real targets. They write the Keychain and Cloudflare. Tests use stubs only.
- Run and paste:
  - `bats scripts/tests/bin/makefile_hermes_approvals.bats scripts/tests/bin/makefile_argocd_hermes_token.bats scripts/tests/lib/bats_negation_lint.bats`
  - `make -n hermes-approvers APPROVERS=U0123ABCD`. This executes `$(MAKE)` lines only for the
    umbrella target, so do not run `make -n` on `hermes-approvals-setup`.
- Mutations (snapshot first, then restore and check with `cmp`):
  - change the `security -i` write to `security add-generic-password -U -a k3dm -s k3dm-hermes-approval-drain-token -w "$$_tok"`,
    and show test 4 red;
  - delete the `APPROVERS` regex check, and show test 6 red.
- Do not run `make test` (Claude runs it).
