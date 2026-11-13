# hub-promote prints "git command failed" for every SHA REF (branch probe not quiet)

**Status:** OPEN — captured 2026-11-13 from the operator's M5 promote run (Claude)
**Priority:** P3 (proposed: cosmetic; the promote resolves the SHA correctly, but the line reads like the cause of an unrelated failure)
**Classified:** pending second-agent classification
**Introduced by:** unknown
**Should have been caught by:** review
**Prior art:** exact-slug glob, none; `make find-similar-docs` not run
**Waiting on:** operator decision

## Symptom

`make hub-promote REF=e6b62305` on m5-air.local printed:

`git command failed (1): git -C /Users/cliang/src/gitrepo/personal/k3d-manager show-ref --verify --quiet refs/heads/e6b62305`

and then failed for a different reason (pending check runs). The operator asked why this git command "always" fails.

## Evidence

- `bin/k3dm-hub-promote:59` probes `show-ref --verify --quiet refs/heads/$ref` to decide whether REF is a branch name. For a SHA, exit 1 is the expected "not a branch" answer; line 64 then resolves the SHA with `rev-parse`.
- `git_cmd` (`bin/k3dm-hub-promote:19`) is `_run_command --soft`, and `_run_command_handle_failure` (`scripts/lib/foundation/scripts/lib/system.sh:121`) logs every nonzero exit unless `--quiet` is set.

## Likely fix (for triage, not a spec)

Run the two branch-existence probes on line 59 with `_run_command --quiet --soft` (or a `git_probe` helper), and add a test that a SHA REF prints no `command failed` line, with a branch REF as the positive control.
