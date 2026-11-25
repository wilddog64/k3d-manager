# Argon blind review of lib-foundation PR #93 (v0.5.9): one low finding, fixed

**Date:** 2026-11-23
**PR:** wilddog64/lib-foundation#93 (v0.5.9 release), diff `origin/main...22250a3 -- scripts docs CHANGE.md`
**Reviewer:** Argon (`gemini-4-argon-medium`, agy), spec `docs/plans/release-lf-pr93-v0.5.9-review.md`
**Result:** 0 high, 0 medium, 1 low (verified-from-code); fixed in `bdc4d2b`.
Gates reported by the reviewer: `git status --short` empty in the review worktree; shellcheck and
`AGENT_AUDIT_MAX_IF=8` audit exit 0; `bats scripts/tests/lib/` under `env -i` all ok.

## Finding 1: `_istioctl_find_existing` does not clear its result

`scripts/lib/core.sh:472` — the helper sets `_ISTIOCTL_FOUND_PATH` only when it finds a binary. A direct call after
an earlier hit, with istioctl since removed, keeps the stale path. `_install_istioctl` clears the variable before
calling it (`:564`), so the release's behaviour matches v0.5.8; the risk is only for direct callers of the helper,
which `docs/api/functions.md:84` documents.

**Fix (Claude, `bdc4d2b`):** the helper sets `_ISTIOCTL_FOUND_PATH=""` at entry. No new `if`; `bats
scripts/tests/lib/` under `env -i` with sudo/launchctl denied 252/252, shellcheck clean.

## Note: where the review output was

`agy.log` in the dispatch run dir held only "root agent idle; waiting for 1 background task(s) to finish"; the
findings were in the agy session transcript
(`~/.gemini/antigravity-cli/brain/<session>/.system_generated/logs/transcript.jsonl`, last `PLANNER_RESPONSE`), with
`<session>` from the run dir's `session` file.
