# AGENTS.md (Codex CLI)

Purpose: a tiny, one‑page guide for asking Codex CLI for small, safe, repo‑aligned changes. No special slash commands required.

## Principles

* Smallest viable change. Prefer patches over rewrites.
* Keep existing style (indentation, quoting, filenames, paths).
* Never invent secrets; use `${PLACEHOLDER}`.
* LF newlines only; no CRLF.
* Shell blocks: no inline comments unless asked.
* Please use plain text instead of icon for status check or anything that required status

## What to Provide

1. **Goal** (1–2 lines): what must work after the change.
2. **Single file/lines allowed** (e.g., `scripts/plugins/jenkins.sh:160-210`).
3. **Minimal evidence**: short error excerpt or failing test output.
4. **Repo context**: list a few relevant files (not whole repo).

## Patch Request Template

```
Task: Fix <short issue>.
Constraints:
- Edit only <path:line-range>.
- Keep style; do not refactor.
- No comments in shell blocks.
- Use ${VARS} for unknowns.
Output format: unified diff from repo root.
Evidence:
<3–6 lines of log or test failure>
```

## Alternate Output (exact block)

```
Return only the full replacement for <function or YAML block>.
No diff headers or commentary. LF newlines only.
```

## Good Prompts (copy/paste)

* **Tiny shell fix**: “Quote variables and handle errors for the function at `scripts/plugins/vault.sh:120-170`. Output unified diff. No other edits.”
* **YAML micro‑diff**: “Adjust JCasC group mapping in `scripts/etc/jenkins/jcasc/jenkins.yaml` without adding plugins. Output a minimal diff touching only that block.”
* **Istio runbook (read‑only first)**: “Provide 5 diagnostic commands to trace `404` at ingress for Jenkins from LB→Gateway→VS→DR→Pod. No changes unless a check fails.”

## Context Hygiene

* Prefer exact line ranges over full files for large sources.
* Replace screenshots with typed commands + short outputs.
* Keep one problem per session.
* Summarize long threads before continuing (short bullet recap).

## Git Recipes (minimal)

```
# See what changed vs upstream
git fetch --all --tags --prune
git diff --stat upstream/main..HEAD

# Create a clean worktree to test a patch
git worktree add ../wt-fix HEAD

# Cherry-pick one commit but only for a path (then test)
git cherry-pick -n <sha> -- scripts/plugins/jenkins.sh || git cherry-pick --abort
```
## House Rules (apply to every answer)

1. Smallest patch; no unsolicited refactors.
2. Preserve style and file layout.
3. State required tools explicitly when introducing new ones.
4. Use placeholders for secrets/hosts.
5. Keep explanations to ≤3 bullets when requested.
