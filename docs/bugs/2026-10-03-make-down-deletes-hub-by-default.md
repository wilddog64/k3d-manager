# Bug: `make down CLUSTER_PROVIDER=k3s-aws` deletes the local hub unless the operator remembers `KEEP_LOCAL=1`

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude
**Status:** FIXED in `435c95a1` — `make down` keeps the hub; deleting it requires `DELETE_HUB=1`.
**Severity:** High. A routine sandbox teardown destroyed the hub cluster: every hub service and dashboard, plus the Vault PVC.
**Files:** `bin/cluster-down`, `Makefile`, `scripts/tests/bin/cluster_down.bats` (or a new BATS file), docs, `CHANGELOG.md`

## What happened (2026-10-03, about 08:35)

- **The teardown command.** The ACG sandbox had stopped answering (see `2026-10-03-sandbox-up-hangs-on-unresponsive-server-node.md`). To tear it down, Claude gave the operator a `make down CLUSTER_PROVIDER=k3s-aws` command **without `KEEP_LOCAL=1`**, and the operator ran it.
- **The hub was deleted.** `bin/cluster-down` defaults to `_keep_hub=0`, so it ran `k3d cluster delete k3d-cluster`. Docker now has no `k3d-*` containers, networks or volumes. Context `k3d-k3d-cluster` is gone from `~/.kube/config`.
- **The port-forward logs show the moment it happened:**
  - `lost connection to pod`;
  - `TLS handshake timeout`;
  - `127.0.0.1:52888 refused`;
  - `context "k3d-k3d-cluster" does not exist`.
- **The operator saw it in Grafana.** Every hub Grafana panel errors; the operator first noticed on *k3dm VectorDB Health*. The page was already loaded in the browser, and its queries now fail.

## Root cause

- **Hub deletion is the default, and keeping the hub is the opt-in:**
  - `Makefile`: `KEEP_LOCAL ?= 0`;
  - `bin/cluster-down`: `_keep_hub=0` unless `--keep-hub` is passed.
- **`--keep-hub` dates from `bin/acg-down`,** when the hub and a sandbox were brought up and down together.
- **The hub is now long-lived,** and a sandbox comes and goes about every 4 hours. Deleting the hub has a far bigger blast radius than deleting a sandbox, yet it happens when someone *leaves out* a flag.
- **The webhook path is already safe.** It passes `KEEP_LOCAL=1` (`scripts/lib/webhook/lifecycle.py:271`). Only the human path was exposed.

## Fix — invert the default; hub deletion becomes explicit

### D1 — `bin/cluster-down`

- **Default to keeping the hub:** `_keep_hub=1`.
- **Add a `--delete-hub` flag** that sets `_keep_hub=0`.
- **Keep `--keep-hub`** as an accepted no-op, so existing callers and docs still work.
- **Reject the conflict:** `--keep-hub` together with `--delete-hub` fails with exit 2 and a clear message, before anything is torn down.
- **Let `CLUSTER_PROVIDER=k3d` imply `--delete-hub`.** For that provider the hub *is* the target; `make down CLUSTER_PROVIDER=k3d` is the documented hub-only teardown in the rebuild runbook.
- **Update the usage text:**
  - `--confirm`: tears down the remote cluster; the local Hub is preserved.
  - `--delete-hub`: also deletes the local Hub cluster and its access layer.
- **Leave the existing `_keep_hub` checks alone** (lines ~66, 179, 194, 332, 373); they keep working as they are.
- **Log the decision:** the `_info "[acg-down] keep-hub=..."` line stays and prints the resolved value.

### D2 — `Makefile` `down`

- **Default:** `KEEP_LOCAL ?= 1`.
- **Add `DELETE_HUB ?= 0`.** `DELETE_HUB=1` passes `--delete-hub`.
- **`KEEP_LOCAL=0` is the same as `DELETE_HUB=1`,** for backward compatibility.
- **Reject the conflict:** `DELETE_HUB=1` with an explicit `KEEP_LOCAL=1` errors.
- **Leave `CLEANUP_STALE=1`** forcing keep-hub, as it does today.
- **Update the comments and the `make help` line:** `make down` preserves the Hub, and `DELETE_HUB=1` also deletes it.
- **Do not change** the `k3s-oci` / `k3s-hostinger` branches.

### D3 — docs

- **Fix every page that tells a reader `KEEP_LOCAL=1` is needed to keep the hub,** or that `make down` deletes it. `git grep -nE 'KEEP_LOCAL|keep-hub' -- docs/howto docs/guides docs/architecture README.md` finds them. Change only those sentences.
- **`CHANGELOG.md` `[Unreleased]` → `### Changed`:** a prose bullet explaining the inverted default and why.

## Gates (offline; paste actual output)

**Test harness for `bin/cluster-down`:**
- run it with `DRY_RUN=1`, a temp `HOME`, and stub `k3d`, `aws`, `kubectl`, `launchctl`, `docker` and `autossh` on `PATH`; each stub appends its argv to a call log;
- the `k3d` stub prints a `cluster list` line for `k3d-cluster`;
- use `CLUSTER_PROVIDER=k3s-gcp` or another path with no remote side effects under the stubs.

**Never** run `make down`, `make -n down` or `bin/cluster-down` without the stubs. `make -n` still executes recipe lines containing `$(MAKE)`, and the `down` recipe has one.

1. **Default keeps the hub.** `bin/cluster-down --confirm` logs `keep-hub=1` and `local Hub cluster preserved`. The `k3d` call log never contains `cluster delete`, and the output never contains `would delete local Hub cluster`.
2. **Explicit delete:** `--confirm --delete-hub` logs `keep-hub=0` and `DRY_RUN: would delete local Hub cluster k3d-cluster`.
3. **`k3d` provider:** `CLUSTER_PROVIDER=k3d bin/cluster-down --confirm` resolves `keep-hub=0`.
4. **Conflict:** `--keep-hub --delete-hub` exits 2, and the `k3d` / `aws` call logs are empty.
5. **Makefile flag mapping.** Factor the flag computation so it can be tested without running the recipe:
   - either a tiny `bin/` helper, or a `make --eval` print target that does not contain `$(MAKE)`;
   - default → no `--delete-hub`;
   - `DELETE_HUB=1` → `--delete-hub`;
   - `KEEP_LOCAL=0` → `--delete-hub`;
   - `DELETE_HUB=1 KEEP_LOCAL=1` → error;
   - `CLEANUP_STALE=1` → keep.
6. **Mutations.** For each one, `cp` a snapshot, mutate, show the test red, restore from the snapshot, and show `cmp`. Never use `git checkout`.
   - (a) `_keep_hub=0` default → gate 1 red;
   - (b) `--delete-hub` ignored → gate 2 red;
   - (c) conflict check removed → gate 4 red.
7. **Other checks:**
   - `shellcheck bin/cluster-down` (no new warnings);
   - the touched BATS;
   - the existing `scripts/tests/bin/cluster_down.bats` still green;
   - `python3 scripts/check-doc-links.py`.
8. **Scope:** `git diff --stat` shows only the files named above.

## Definition of Done

- [ ] D1–D3 complete; gates 1–8 pass, with output pasted.
- [ ] Commit message, exactly (trailers on consecutive lines):

  ```
  fix(cluster-down): keep the local hub by default; deleting it requires DELETE_HUB=1

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`.
- Do NOT edit `memory-bank/`, `scripts/lib/foundation/`, `scripts/lib/acg/`, or the webhook.
- Do NOT run any real teardown or bring-up, and do not touch Docker, k3d, AWS, the hub or the sandbox.
- Do NOT change what a hub deletion *does*, only when it happens.

## Recovery (operator, not part of the fix)

The hub must be rebuilt. Follow the hub-only sequence (`deploy_cluster --provider k3d k3d-cluster`, then Vault, LDAP, ArgoCD, `make observability`, `make platform-ops`), then reseed Vault from the Keychain backups. `app-cluster-kubeconfig` and `cosign-public-key` have no Keychain backup.
