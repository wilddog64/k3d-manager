# 2026-06-19 — Tighten pre-push main-guard (block ALL direct pushes to main) + document core.hooksPath

**Filed:** 2026-06-19 (Claude)
**Type:** hardening — addresses Copilot review findings on the pre-push rollout PRs
**Repos (this task):** `rabbitmq-client-python`, `rabbitmq-client-java`, `rabbitmq-client-go`, `observability-stack`
**Handoff:** Codex (content/commits). Local hook *activation* (`core.hooksPath`) stays Claude-only.

## Why

Copilot reviewed all four open `chore/add-pre-push-hook` PRs and raised two valid points on
`.githooks/pre-push`:

1. **The guard allows `git push origin main` (local `main` → remote `main`).** It only blocks when
   `local_ref != refs/heads/main`, so the most direct kind of push to `main` slips through. Policy is
   *never push directly to main* — so the guard must refuse **any** push to `refs/heads/main` unless
   `ALLOW_MAIN_PUSH=1`.
2. **Committed hooks under `.githooks/` don't run by default.** Add a short activation note in the
   hook so contributors know to set `core.hooksPath`.

This spec tightens the guard and documents activation in the hook itself, addressing both findings.

## Branch (all four work repos)

Use the **existing** PR branch — do NOT create a new one, do NOT branch off main:

```
git fetch origin
git checkout chore/add-pre-push-hook
git pull --ff-only origin chore/add-pre-push-hook
```

| Repo | PR | Branch (existing) |
|---|---|---|
| rabbitmq-client-python | #1 | `chore/add-pre-push-hook` |
| rabbitmq-client-java | #7 | `chore/add-pre-push-hook` |
| rabbitmq-client-go | #1 | `chore/add-pre-push-hook` |
| observability-stack | #1 | `chore/add-pre-push-hook` |

## The change — `.githooks/pre-push` (identical in all four repos)

### Edit 1 — add activation note after the shebang

**Exact old block:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Exact new block:**
```bash
#!/usr/bin/env bash
# Committed pre-push hook: refuses direct pushes to 'main'.
# Activate per-clone (core.hooksPath cannot be committed):
#   git config core.hooksPath .githooks
# Intentional override for a single push: ALLOW_MAIN_PUSH=1 git push ...
set -euo pipefail
```

### Edit 2 — drop the `local_ref` exemption so ALL pushes to remote main are gated

**Exact old block:**
```bash
  if [[ "$remote_ref" == "refs/heads/main" ]] && \
     [[ "$local_ref" != "refs/heads/main" ]]; then
```

**Exact new block:**
```bash
  if [[ "$remote_ref" == "refs/heads/main" ]]; then
```

Everything else in the hook (the `ALLOW_MAIN_PUSH` branch, the echo lines, `exit 1`, the
`while IFS=' ' read` loop, `chmod 0755`, LF endings) stays exactly as-is.

### Resulting hook (for reference — must match after edits)
```bash
#!/usr/bin/env bash
# Committed pre-push hook: refuses direct pushes to 'main'.
# Activate per-clone (core.hooksPath cannot be committed):
#   git config core.hooksPath .githooks
# Intentional override for a single push: ALLOW_MAIN_PUSH=1 git push ...
set -euo pipefail

remote="$1"

while IFS=' ' read -r local_ref _ remote_ref _; do
  if [[ "$remote_ref" == "refs/heads/main" ]]; then
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

## Verify (direct invocation — do NOT set core.hooksPath)

In each repo, after editing:
- Feature → main is blocked:
  `printf 'refs/heads/feat x refs/heads/main 0\n' | bash .githooks/pre-push origin` exits **1**
- main → main is **now also blocked** (the fix):
  `printf 'refs/heads/main x refs/heads/main 0\n' | bash .githooks/pre-push origin` exits **1**
- Override works:
  `printf 'refs/heads/main x refs/heads/main 0\n' | ALLOW_MAIN_PUSH=1 bash .githooks/pre-push origin` exits **0**
- Non-main target is untouched:
  `printf 'refs/heads/feat x refs/heads/feat 0\n' | bash .githooks/pre-push origin` exits **0**

## Rules

- LF line endings only. `set -euo pipefail` preserved. `.githooks/pre-push` stays mode 0755.
- `bash -n .githooks/pre-push` (syntax) clean; `shellcheck .githooks/pre-push` zero new warnings.
- Only `.githooks/pre-push` may change in each repo. No other files.
- No `--no-verify`. Never commit on `main`.
- Push the existing branch explicitly: `git push origin chore/add-pre-push-hook`.

## Definition of Done

- [ ] All four repos: `.githooks/pre-push` has the activation note AND the tightened condition.
- [ ] All four `printf | bash .githooks/pre-push origin` checks above pass per repo.
- [ ] Committed on `chore/add-pre-push-hook` and pushed; one SHA per repo confirmed on
      `origin/chore/add-pre-push-hook`.
- [ ] PRs already had Copilot tagged — re-request review is NOT needed; the push re-triggers it.
- [ ] memory-bank `activeContext.md` + `progress.md` updated with the four SHAs and status.

**Commit message (exact, all four repos):**
```
chore(git): tighten pre-push guard to block all direct pushes to main + document core.hooksPath
```

## What NOT to do

- Do NOT create a PR (the PRs already exist — pushing the branch updates them).
- Do NOT merge any PR.
- Do NOT set `core.hooksPath` (Claude's post-merge job).
- Do NOT create a new branch or branch off `main` — use the existing `chore/add-pre-push-hook`.
- Do NOT touch the already-merged repos (infra/order/payment/frontend/product-catalog/basket/e2e-tests),
  k3d-manager, or the two empty repos (rabbitmq-client-dotnet/library). Claude handles those follow-ups separately.
- Do NOT modify any file other than `.githooks/pre-push`.
