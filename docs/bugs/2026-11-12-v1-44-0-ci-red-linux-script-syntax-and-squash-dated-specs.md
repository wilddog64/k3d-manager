# v1.44.0 branch CI red: BSD-only `script` call in hub_promote.bats; squash merge re-dates 22 specs for spec-intent; security test needs a tripwire shim Linux no longer gets

**Status:** LANDED — test-only fixes on `k3d-manager-v1.44.0`, 2026-11-12 (Claude; macOS + Ubuntu 24.04 container)
**Priority:** P1 (proposed: CI red on the release branch and the pre-push hook refuses every push, no workaround short of `--no-verify`)
**Classified:** pending second-agent classification
**Introduced by:** (1) `c7466d65` deploy-hub batch (new "G regression" test); (2) `aa1196ed` v1.43.15 squash merge (re-dated files; latent until a push ran the suite); (3) `0b8d2b80` test-hygiene batch (`tripwire.sh` skips the shim for a tool the host lacks)
**Should have been caught by:** (1) review (Claude verified the land on macOS only); (2) offline test (the suite was not run on the branch after the cut); (3) review (same: macOS-only land check; hidden in CI behind item 1's earlier red)
**Prior art:** none above threshold (exact-slug glob; `find-similar-docs` vector store unavailable)
**Waiting on:** live check

## Symptoms

1. CI run on `fd553b9a` (lint job): `not ok 583 G regression: non-TTY promoter test completes when suite stdin is a terminal`
   (`scripts/tests/bin/hub_promote.bats:721`). The test calls `script -q /dev/null bats …`, which is BSD `script`
   syntax. util-linux `script` on the Linux runner reads it differently. Reproduced in `ubuntu:24.04`, which has util-linux 2.39.3. Two further
   faults appeared inside `script`: the nested bats inherited the outer run's `BATS_*` variables and its libexec dir at the head of
   `PATH` (`bats_readlinkf: command not found`), and the pretty formatter needs `TERM`, which CI does not set.
2. Pre-push on 2026-11-12 (subtree pull `5f832339`): `test_spec_intent.py::test_all_existing_specs_are_exempt_as_of_this_commit`
   flagged 22 specs that existed at baseline `c5d28596` (2026-11-07). `_first_commit_date` takes the oldest `git log`
   date on the branch, and the v1.43.15 squash merge made `aa1196ed` (2026-11-12) the first commit for every file
   carried in it.

3. CI run 43284086266 on `f3becda3` (lint, pytest step): `FAILED scripts/tests/bin/test_hermetic_guard.py::test_real_security_is_blocked - FileNotFoundError: [Errno 2] No such file or directory: 'security'`.
   `0b8d2b80` added `type -P -- "$_tool" >/dev/null || continue` to `scripts/tests/tripwire.sh`, so on Linux no `security` shim exists, the
   test's tripwire skip no longer fires, and the bare call raises. The test is unchanged since `ef6f48a1` (v1.41.0).

## Fix (landed)

1. The G test builds a clean environment (`env -i HOME TMPDIR PATH`), strips `*/libexec/bats-core` from `PATH`, and on util-linux
   uses `script -qec "<bats --tap …>" /dev/null`. On macOS it keeps the BSD form. 44/44 pass on macOS and on Ubuntu 24.04.
2. The baseline test passes the baseline commit's date as `first_commit_date`: every file in `c5d28596` was filed by
   2026-11-07. `SPEC_INTENT_DATE_BASELINE=1`, which moves the rule date to 2026-11-07, still turns it red.

3. `test_real_security_is_blocked` skips when `security` does not resolve, as its sibling `test_absolute_security_is_blocked` already
   does. Checked: macOS without tripwire 14 passed (the guard assertion still runs); under tripwire 13 passed, 1 skipped; `ubuntu:24.04`
   under tripwire 12 passed, 2 skipped; the pre-fix tree on `ubuntu:24.04` fails exactly this test (`1 failed, 12 passed, 1 skipped`).

## Left open (for triage)

The production gate (`scripts/lib/spec_intent.py` from `bin/k3dm-codex-dispatch start`) has the same re-dating.
Dispatching any of those 22 pre-rule specs, mostly v1.45.0+ plans, would now demand intents. That arguably
does no harm, because every new dispatch should carry intents, but it is not what the 2026-11-08 rule date says. Decide at triage.
