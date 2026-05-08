# 2026-05-01 — Copilot docs still reference the stale gate and caller surface

## What Was Verified

The current `k3d-manager-v1.4.1` branch still has documentation that describes the Copilot
surface using the old `_copilot_review`/`K3DM_ENABLE_AI` mental model.

I checked these files directly:

```bash
rg -n "K3DM_ENABLE_AI=1|_copilot_review|source scripts/lib/system.sh|AGENT_LINT_AI_FUNC=\"_copilot_review\"" \
  docs/howto/copilot.md docs/api/functions.md .github/copilot-instructions.md \
  scripts/lib/foundation/docs/api/functions.md
```

Current branch still shows:

- `docs/api/functions.md` says the Copilot plugin functions require `K3DM_ENABLE_AI=1`
  and routes through `_ai_agent_review`, which mixes the old gate with the new dispatch surface.
- `docs/howto/copilot.md` still says `_ai_agent_review` exits non-zero when `K3DM_ENABLE_AI=0`,
  which is no longer true for the low-level wrapper.
- `.github/copilot-instructions.md` still says the Copilot plugin routes through `_copilot_review`.
- `scripts/lib/foundation/docs/api/functions.md` still shows the pre-commit hook example with
  `AGENT_LINT_AI_FUNC="_copilot_review"` and still describes `K3DM_ENABLE_AI` as the lib-foundation
  gate, which is stale relative to the current `_ai_agent_review` abstraction.

## Actual Output

The current grep output still contains the stale references above in the tracked files.

## Root Cause

The docs were updated partially during the `_ai_agent_review` refactor, but not all user-facing
references and repo instructions were brought forward to the new dispatch surface.

## Recommended Follow-Up

- Update the Copilot docs to center `_ai_agent_review` instead of `_copilot_review`.
- Remove the low-level claim that `_ai_agent_review` itself is gated by `K3DM_ENABLE_AI`.
- Update `.github/copilot-instructions.md` to match the current plugin dispatch surface.
- Update the lib-foundation docs snippet so the pre-commit example uses `AGENT_LINT_AI_FUNC="_ai_agent_review"`.
