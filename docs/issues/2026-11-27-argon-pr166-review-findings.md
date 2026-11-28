# Argon review findings — PR #166 (v1.46.0 release)

**Date:** 2026-11-27
**Reviewers:** Argon (agy `gemini-4-argon-medium`), blind, two parts: `release-pr166-review-a-argon` (cloud requests,
approvals, routing) and `release-pr166-review-b-argon` (hub, acceptance, providers, cleanup); diff `origin/main...8bca3613`.
Copilot is capped until 2026-12-01, so these reviews are the PR's review gate. Each finding was checked by Claude against the code.

| # | Finding | Severity | Verdict | Action |
|---|---|---|---|---|
| A1 | `bin/k3dm-webhook:593` (`_posix_spawn_capture`) and `:1493` (`_posix_spawn_job`) call `os.posix_spawn(..., setsid=True)` without the `NotImplementedError` fallback that `scripts/lib/webhook/proc.py:44-50` has | low | Real. The webhook runs on the hub's macOS Python, which supports `setsid`; the 2026-11-25 bug was cloud session images running the helper. | P3 capture: `docs/bugs/2026-11-27-webhook-spawn-lacks-setsid-fallback.md` |
| B1 | `_ssh_fragment_hostname` (lib-foundation `scripts/lib/ssh_fragment.sh:111-148`, used by `scripts/plugins/shopping_cart.sh:1229,1248,1461`) parses files instead of using `ssh -G` | low | Not a defect. `docs/plans/lib-foundation-v0.5.12-acg-ssh-sandbox-fragment.md:97` chose fragment-then-main-config parsing because shopping-cart "cannot use `ssh -G` in tests"; `ssh -G` is the post-write effect check only. The review spec's wording ("host lookup uses `ssh -G`") and the W4 commit message `91609294` were wrong. | none (review-spec wording) |
| B2 | `scripts/lib/providers/k3s-hostinger.sh:963` logs "reapplied … and istio-ambient ApplicationSets" even when `istio-ambient.yaml` was skipped (`:938-941`) | low | Real (misleading log). | Fixed: the message names the three sets reapplied and says istio-ambient needs `ISTIO_AMBIENT_APPSET_ENABLE=1`. |
| B3 | `scripts/tests/bin/hub_deploy.bats:276,292,492`: `$REAL_GIT` unquoted inside `$(...)` | low | Real, test-only (breaks only if git's path has whitespace). | Fixed: quoted, matching every other call in the file. |

## Root cause and process note

- B1 came from Claude's own review spec repeating a commit-message claim instead of the spec. Write a review spec's
  "intended behaviour" from the specs' Acceptance and interface text, not from commit messages.
- A1 is the same defect class as the fixed helper bug in a second caller; a fix for one spawn site should grep for the
  others (`posix_spawn(` in `bin/` and `scripts/lib/`).
