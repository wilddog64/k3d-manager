# Bug: the M2 e2e runner executes a stale, hand-synced checkout

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN
**Files:** `scripts/plugins/e2e_remote.sh`, `scripts/tests/plugins/e2e_remote.bats`, `CHANGELOG.md`

## Evidence (2026-09-15, read-only)

- `e2e_runner_dispatch` runs `cd ${E2E_M2_REPO}; ./scripts/k3d-manager e2e_verify_vcluster` on the M2, where `E2E_M2_REPO` defaults to `$HOME/src/gitrepo/personal/k3d-manager`.
- That M2 checkout is on branch `k3d-manager-v1.7.2` at `f5a40988` (2026-06-21), with **631 modified files** (hand-synced).
- Its `scripts/plugins/e2e.sh`, `scripts/plugins/e2e_remote.sh`, and `scripts/etc/e2e/kustomization.yaml` all differ from the M4 branch. Example: the substrate basket image is `sha-f70d5801…` on the M2 vs `sha-4b42ecc7…` in the repo.
- Every result reports `commit: f5a40988…`, which is meaningless. What was tested cannot be tied to any commit.
- Contract-drift failures jumped from 31 (08-27) to 45 (09-15) with the same reported commit.

## Fix

`e2e_runner_dispatch` runs from an e2e-owned, clean clone on the M2, pinned to the M4's commit. It never touches the operator's M2 checkout.

1. New default `E2E_M2_REPO="${E2E_M2_REPO:-\$HOME/.k3dm/e2e/runner-src}"`. An explicit override is still honoured.
2. On the M4, before SSH:
   - `sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"`.
   - Require that the SHA exists on origin: `git -C "$REPO_ROOT" branch -r --contains "$sha"` is non-empty. Otherwise `_err "[e2e-remote] HEAD ${sha} is not pushed; push the branch first"` and return non-zero before any SSH.
   - `E2E_M2_REPO_URL="${E2E_M2_REPO_URL:-https://github.com/wilddog64/k3d-manager.git}"` must match `^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$`.
3. Remote prelude, prepended to the existing remote command, with the SHA and URL `printf -v … %q`-quoted:

   ```
   [ -d "$E2E_M2_REPO/.git" ] || git clone --quiet <url> "$E2E_M2_REPO" || exit 1
   git -C "$E2E_M2_REPO" fetch --quiet origin || exit 1
   git -C "$E2E_M2_REPO" checkout --quiet --force --detach <sha> || exit 1
   git -C "$E2E_M2_REPO" clean -fdq -e .k3dm || exit 1
   ```

   The clone is anonymous HTTPS (public repo), so no M2 GitHub credentials are needed.
4. `_info "[e2e-remote] runner source pinned to ${sha}"` so the transcript records it. The summary's `commit` field then comes from this clean clone.

## Tests (`e2e_remote.bats`, stubbed `ssh`/`git`)

- The remote command contains `fetch`, `checkout --quiet --force --detach` with the M4 SHA, and `clone` guarded by `[ -d`.
- An unpushed SHA (empty `branch -r --contains`) errors with "is not pushed" and `ssh` is never called.
- A malformed `E2E_M2_REPO_URL` is refused.
- An `E2E_M2_REPO` override is used verbatim.
- `shellcheck -S warning` stays clean.

## Operator note

The operator's old M2 checkout (`~/src/gitrepo/personal/k3d-manager`) is left untouched. Whether to clean it up is the operator's call.

## What NOT to do

- Do not modify, reset, clean, or stash the operator's existing M2 checkout.
- Do not run a real dispatch, `ssh`, or `git clone` in tests.
- Do not edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- No PR, no merge, no `main` commit, no force-push, no `--no-verify`. No `git add -A`, no `git stash`.
