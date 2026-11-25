# web-console-sshd: new bin script has no `set -euo pipefail`; one revoke mutant survives

**Status:** OPEN
**Priority:** P3
**Triage:** backlog — pull into a release that already touches `bin/k3dm-web-console-sshd` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** `6b34bd55` (v1.45.0 plan 4, web-console part A)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Code style, test coverage, and test execution speed hygiene issues in `bin/k3dm-web-console-sshd` and `web_console_sshd.bats`.)
**Waiting on:** operator decision — since 2026-11-19
**Prior art:** not run (find-similar-docs vector store unavailable: cluster context missing); exact-slug glob found no match

## Symptom

1. `bin/k3dm-web-console-sshd` (new in part A) has no `set -euo pipefail`. CLAUDE.md Code Style requires it on all new bash
   scripts. The script tracks return codes explicitly instead. Adding the line on a copy turned 17 of 56 tests in
   `scripts/tests/bin/web_console_sshd.bats` red (Claude, 2026-11-19, scratch copy), so this needs a refactor, not a one-line fix.
   The spec (`docs/plans/v1.45.0-web-console-a-console-sshd.md`) did not mention the rule, so the worker never had to meet it.
2. The independent verifier's mutant H survived: deleting revoke's final `[[ ! -e "$plist" ]] || rc=1` left all N13 tests green.
   A failed `mv` already sets `rc=1`, so only a plist that reappears after the stop is uncovered. Rated low.

## Fix options (operator decision)

- (a) Accept the explicit-rc design. Record it as an exception in the spec, and add a test that recreates the plist after
  the stop so mutant H turns red.
- (b) Refactor for `-e` in a later release, making each intended non-zero return explicit (`|| rc=$?`).

## Also: the BATS file is the slowest test file in the repo

3. `scripts/tests/bin/web_console_sshd.bats` takes 555–563 s for 56 tests (pre-push fast gate, m4-air, 2026-11-20).
   It was long enough to make GitHub drop the idle SSH connection while pushing. The operator's `~/.ssh/config` now has
   `ServerAliveInterval 30` for `github.com` (2026-11-20). Speeding the file up belongs to the same follow-up. Find the
   per-test cost (stub sshd start-up, waits) first, and don't remove the file from the gate.
