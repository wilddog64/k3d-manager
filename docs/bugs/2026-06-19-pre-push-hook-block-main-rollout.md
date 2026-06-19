# 2026-06-19 — Roll out committed pre-push main-guard hook across shopping-cart repos + k3d-manager

**Filed:** 2026-06-19 (Claude)
**Type:** hardening (incident-driven) — multi-repo
**Repos:** `k3d-manager` + all shopping-cart repos
**Handoff:** Codex (content/commits). Local hook *activation* (`git config core.hooksPath`) is Claude-only and is NOT Codex's task.

## Incident / Why

A shopping-cart-infra feature branch (`fix/data-layer-cluster-generator`) had its local
upstream tracking pointed at `origin/main`, so a plain `git push` would have silently pushed to
`main`. The committed pre-push guard that should have caught this was **inert** because three
shopping-cart repos had `core.hooksPath=/dev/null` set (an agent bypassing hooks), which disables
*all* git hooks.

Claude has already fixed the local state on this machine (upstream tracking on infra/frontend;
activated `.githooks` on infra/payment; local stopgap hooks on frontend/product-catalog). This spec
makes the guard **durable and committed** so it survives fresh clones and agent bypass.

## Canonical hook (verbatim — identical to the version already committed on infra/order/payment and k3d-manager's local `.git/hooks/pre-push`)

`.githooks/pre-push`:
```bash
#!/usr/bin/env bash
set -euo pipefail

remote="$1"

while IFS=' ' read -r local_ref _ remote_ref _; do
  if [[ "$remote_ref" == "refs/heads/main" ]] && \
     [[ "$local_ref" != "refs/heads/main" ]]; then
    if [[ "${ALLOW_MAIN_PUSH:-0}" == "1" ]]; then
      echo "pre-push: ALLOW_MAIN_PUSH=1 — bypassing main-guard for '$local_ref' → ${remote}/main" >&2
    else
      echo "pre-push: refusing to push '$local_ref' directly to ${remote}/main" >&2
      echo "  Use a feature branch + PR instead." >&2
      echo "  To override intentionally: ALLOW_MAIN_PUSH=1 git push ..." >&2
      exit 1
    fi
  fi
done
```
- `chmod +x .githooks/pre-push` (mode 0755).
- LF line endings only.

## Target repos

| Repo | `.githooks/pre-push` on `origin/main`? | Action |
|---|---|---|
| shopping-cart-infra | check | skip if present on origin/main, else add |
| shopping-cart-payment | check | skip if present on origin/main, else add |
| shopping-cart-order | check | skip if present on origin/main, else add |
| shopping-cart-frontend | needs | add |
| shopping-cart-product-catalog | needs | add |
| shopping-cart-basket | needs | add |
| shopping-cart-e2e-tests | needs | add |
| observability-stack | needs | add |
| rabbitmq-client-dotnet | needs | add |
| rabbitmq-client-go | needs | add |
| rabbitmq-client-java | needs | add |
| rabbitmq-client-library | needs | add |
| rabbitmq-client-python | needs | add |
| k3d-manager | needs (special — see below) | add + relocate pre-commit |

**Before adding, verify on origin:** `git show origin/main:.githooks/pre-push` — if it already
exists there, SKIP that repo (do not open an empty PR).

## Per-repo recipe (every repo EXCEPT k3d-manager)

For each repo that needs the hook:

1. `git fetch origin`
2. `git checkout -b chore/add-pre-push-hook origin/main`
   (A clean standalone branch off `origin/main` — do NOT bundle into an in-flight feature branch,
   and never commit on `main`.)
3. Create `.githooks/pre-push` with the canonical content above; `chmod +x`.
4. Commit (verbatim message):
   `chore(git): add committed pre-push hook to block direct pushes to main`
5. `git push origin chore/add-pre-push-hook` (push the branch explicitly — never a bare `git push`).
6. `gh pr create` against `main`; tag Copilot:
   `gh api repos/wilddog64/<repo>/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`
7. Report the PR URL + the SHA confirmed on `origin/chore/add-pre-push-hook`.

## k3d-manager (special handling)

k3d-manager currently runs hooks from `.git/hooks` (untracked) and has a **pre-commit** that guards
the `scripts/lib/foundation/` subtree + runs agent_rigor. Switching to `core.hooksPath=.githooks`
must NOT lose that pre-commit.

On branch `k3d-manager-v1.7.1` (current milestone branch — do NOT branch off, do NOT touch main):

1. Create `.githooks/pre-push` with the canonical content; `chmod +x`.
2. Relocate the pre-commit: copy the current `.git/hooks/pre-commit` to `.githooks/pre-commit`,
   and **fix the relative path**: the existing hook computes
   `SCRIPT_DIR=".../$(dirname BASH_SOURCE)/../../scripts"` which is correct from `.git/hooks/` but
   wrong from `.githooks/`. From `.githooks/` it must be `../scripts` (one level up), so the hook
   still resolves `scripts/lib/agent_rigor.sh` and the subtree guard fires. `chmod +x`.
3. Verify BOTH hooks fire from `.githooks/`:
   - `git config core.hooksPath .githooks` (local, this machine)
   - confirm a staged edit under `scripts/lib/foundation/` is still rejected by pre-commit
   - confirm `printf 'refs/heads/x x refs/heads/main 0\n' | .githooks/pre-push origin` exits 1
4. Commit (verbatim):
   `chore(git): commit pre-push + pre-commit hooks under .githooks for durable activation`
5. `git push origin k3d-manager-v1.7.1`.
6. Report SHA confirmed on `origin/k3d-manager-v1.7.1`.

## Activation (Claude-only — NOT Codex)

`core.hooksPath` is a local per-clone setting and cannot be committed. After each PR merges, Claude
runs on this machine, per repo:
```
git -C <repo> config core.hooksPath .githooks
```
and re-checks that `printf 'refs/heads/x x refs/heads/main 0\n' | <repo>/.githooks/pre-push origin`
exits 1. Codex does NOT set `core.hooksPath`.

## Rules

- Never commit on `main` in any repo. Feature branch + PR only.
- Push branches explicitly (`git push origin <branch>` / `HEAD:<branch>`) — never a bare `git push`
  (upstream-tracking quirk can target main).
- No `--no-verify`. LF only. `set -euo pipefail` preserved.
- Run `./scripts/k3d-manager _agent_audit` in k3d-manager before reporting done (clean).

## Definition of Done

- [ ] Every target repo lacking the hook on `origin/main` has a `chore/add-pre-push-hook` PR open
      (or k3d-manager commit on `k3d-manager-v1.7.1`), Copilot tagged.
- [ ] k3d-manager: both `.githooks/pre-commit` (path-fixed) and `.githooks/pre-push` committed and
      verified firing.
- [ ] One SHA per repo confirmed on `origin/<branch>`; PR URLs listed.
- [ ] Repos already carrying the hook on `origin/main` are explicitly reported as SKIPPED.
- [ ] Do NOT merge any PR — Claude reviews + merges after CI green + Copilot addressed.

## What NOT to do

- Do NOT set `core.hooksPath` (Claude's job, post-merge).
- Do NOT merge PRs.
- Do NOT modify anything other than `.githooks/` (and, in k3d-manager only, the relocation described).
- Do NOT touch repos outside the target list (no ansible/*, lib-foundation, articles, etc.).
