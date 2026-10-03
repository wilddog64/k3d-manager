# Bug: there is no `make` path to rebuild the local hub alone

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude
**Status:** SPEC — ready for Codex. Dispatch it after `2026-10-03-make-down-deletes-hub-by-default.md`, which also edits the `Makefile` `up`/`down` area.
**Files:** `Makefile`, `bin/hub-up` (new), `scripts/tests/bin/hub_up.bats` (new), docs, `CHANGELOG.md`

## What the operator asked for

> "can we have make up CLUSTER_PRIVDER=k3s?"

That is, one command that brings the hub back. The provider is named `k3d`, not `k3s`: the hub is a k3d cluster, and `k3s` already means a native k3s install in the dispatcher.

## Why it is a bug

- **The 2026-10-03 hub loss had no `make` recovery path.** See `2026-10-03-make-down-deletes-hub-by-default.md`.
- **`make up CLUSTER_PROVIDER=k3d` fails.** It falls to the `*)` branch and `bin/cluster-up:91` rejects it: `Unsupported CLUSTER_PROVIDER: k3d`.
- **Bare `make up` is not a hub rebuild.** It runs the full ACG sandbox bring-up.
- **So the only path is seven dispatcher commands,** kept in a memory note rather than in the repo.
- **`make down` and `make up` are not symmetric.** `make down CLUSTER_PROVIDER=k3d` tears the hub down, but nothing brings it back up.

## Fix

### U1 — `bin/hub-up` (new, `set -euo pipefail`)

- **Model it on the other `bin/` scripts,** which source lib-foundation the same way `bin/cluster-up` does. Run, in order, the same steps `bin/cluster-up` Steps 3.5/3.6 run for a missing hub:
  1. if `k3d cluster list` already shows `${HUB_CLUSTER_NAME:-k3d-cluster}`, log `hub exists — skipping create`; otherwise run `deploy_cluster --provider k3d "${HUB_CLUSTER_NAME:-k3d-cluster}"`;
  2. wait for the hub API on context `k3d-${HUB_CLUSTER_NAME:-k3d-cluster}`, in the same shape as cluster-up's post-create API wait;
  3. `deploy_vault --confirm`;
  4. `deploy_ldap --confirm`;
  5. `deploy_argocd --confirm`.
- **Call each step through the dispatcher.** Use `"${K3DM_DISPATCHER:-${REPO_ROOT}/scripts/k3d-manager}"`, so tests can stub it.
- **Pin the context on every step.** Use `kubectl --context`, or a temporary `KUBECONFIG`, as cluster-up does. Never change the operator's global `current-context`.
- **Log a step marker** before each step: `[hub-up] Step N/5 — …`.
- **Stop on the first failure,** with the step name in the error.
- **Do not touch AWS, Hostinger, the sandbox or `deploy_shopping_cart_data`.**

### U2 — `Makefile`

- **`up`:** add a `k3d)` branch that runs `bin/hub-up`. The existing `observability` and `platform-ops` lines that follow the `case` then run for the hub as they already do.
- **After them,** for `k3d` only, run `$(MAKE) --no-print-directory install-hub-pushgateway-port-forward`.
- **Add a named target `hub-up`** (operator ask: "we should have a make <target> that can executed your recover commands"). Its body is only `@$(MAKE) --no-print-directory up CLUSTER_PROVIDER=k3d`. Add it to `.PHONY`, and to `make help` as `make hub-up   Rebuild the local hub only (no AWS, no sandbox)`.
- **Update the usage comment on line 2 and the `make help` line,** so they list `k3d` (the local hub only).

### U3 — docs

- Add a short "Rebuild the hub" section to the doc that covers hub lifecycle. `git grep -ln "deploy_cluster --provider k3d" -- docs/howto docs/guides` finds it; if none exists, use `docs/howto/`. The section covers:
  - `make up CLUSTER_PROVIDER=k3d`;
  - what it does **not** restore: shopping-cart Vault data, which is seeded on the next sandbox `make up`; `cosign-public-key`; `app-cluster-kubeconfig`; and old ArgoCD/Vault tokens;
  - the matching `make down CLUSTER_PROVIDER=k3d`.
- **`CHANGELOG.md` `[Unreleased]` → `### Added`:** one bullet.

## Gates (offline; paste actual output)

**Harness:** run `bin/hub-up` with `K3DM_DISPATCHER` pointed at a stub that appends its argv to a call log, plus stub `k3d` and `kubectl` on `PATH` and a temp `HOME`. Never run the real dispatcher, k3d or Docker.

1. **Missing hub:** the `k3d cluster list` stub prints no hub. The call log then shows `deploy_cluster --provider k3d k3d-cluster`, `deploy_vault --confirm`, `deploy_ldap --confirm` and `deploy_argocd --confirm`, in that order.
2. **Existing hub:** the stub lists `k3d-cluster`. Then no `deploy_cluster` call is made, the three deploys still run, and the output contains `hub exists — skipping create`.
3. **Fail fast:** the stub fails `deploy_vault`. The exit code is non-zero, the output names the step, and the call log has no `deploy_ldap` or `deploy_argocd`.
4. **No global context change:** the `kubectl` stub's call log never contains `config use-context`.
5. **Makefile routing.** Do NOT use `make -n up`, because recipe lines containing `$(MAKE)` still execute. Prove the `k3d)` branch calls `bin/hub-up` and that `k3s-aws` still calls `bin/cluster-up`, using any of:
   - a parsed check of the recipe text, asserting meaningful tokens rather than whole lines;
   - or `make up` with `PATH` stubs for `bin/hub-up` and `bin/cluster-up`, plus `make observability`/`platform-ops` overridden;
   - or factor the provider → command choice into a testable helper.
5b. **`hub-up` forwards to `up CLUSTER_PROVIDER=k3d`.** Assert it from the parsed recipe text, using the tokens `up` and `CLUSTER_PROVIDER=k3d`. Assert also that `hub-up` is in `.PHONY` and in the `make help` output. `make help` is safe to run.
6. **Mutations.** For each one, `cp` a snapshot, mutate, show the test red, restore from the snapshot, and show `cmp`. Never use `git checkout`.
   - (a) remove the skip-if-exists guard → gate 2 red;
   - (b) swallow a step failure (`|| true`) → gate 3 red;
   - (c) route `k3d)` to `bin/cluster-up` → gate 5 red.
7. **Other checks:** `shellcheck bin/hub-up` is clean; the new and touched BATS pass; `python3 scripts/check-doc-links.py` passes.
8. **Scope:** `git diff --stat` shows only the files named above.

## Definition of Done

- [ ] U1–U3 complete; gates 1–8 pass, with output pasted.
- [ ] Commit message, exactly (trailers on consecutive lines):

  ```
  feat(make): make up CLUSTER_PROVIDER=k3d rebuilds the local hub alone

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, or use `--no-verify`.
- Do NOT edit `memory-bank/`, `scripts/lib/foundation/`, `scripts/lib/acg/`, `bin/cluster-up` or `bin/cluster-down`.
- Do NOT run anything live: no dispatcher, k3d, Docker, kubectl against a real cluster, or `make up`/`down`.

## Review finding on `abbcfd65` (Claude, 2026-10-03) — follow-up U4

**Defect:** `bin/hub-up` pins the context only for its Step 2 API wait. Steps 3–5 call
`deploy_vault`, `deploy_ldap` and `deploy_argocd`, and those act on the **current** kube context.
When the operator's current context is `ubuntu-hostinger`, which is common, `make hub-up` against an
existing hub would install Vault, LDAP and ArgoCD on Hostinger.

**U4 fix (`bin/hub-up` only, plus its test):**
- After Step 2 and before Step 3, read `kubectl config current-context`.
- If it is not `${_hub_context}`, stop with
  `_err "[hub-up] current kube context is '<ctx>', not '${_hub_context}' — run: kubectl config use-context ${_hub_context}"`.
- Do not switch the context automatically; the global context is never changed by hub-up.
- k3d's create switches the context to the new cluster, so the create path passes the guard naturally.

**Gate:**
- A test whose `kubectl` stub reports `current-context` = `ubuntu-hostinger` shows:
  - a non-zero exit;
  - output naming both contexts;
  - no `deploy_vault`, `deploy_ldap` or `deploy_argocd` in the dispatcher call log.
- Mutation: remove the guard → that test is red. Restore from a `cp` snapshot and confirm with `cmp`.
- The existing 6 tests stay green. Their `kubectl` stub must return `k3d-k3d-cluster` for `config current-context`.

**Commit message (exact):**

```
fix(hub-up): refuse to deploy when the current kube context is not the hub

Co-Authored-By: Codex <noreply@openai.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
