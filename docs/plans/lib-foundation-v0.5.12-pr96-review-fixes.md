# lib-foundation v0.5.12 — PR #96 Argon review fixes (ACG ssh fragment)

**Status:** SPEC rev 0 — review-fix child of `docs/plans/lib-foundation-v0.5.12-acg-ssh-sandbox-fragment.md` (landed `dacd479`)
**Priority:** P2 (blocks merge of lib-foundation PR #96)
**Repo / branch:** `lib-foundation` / `release/v0.5.12` (head 715dda0)
**Source:** Argon blind review `release-lf-pr96-v0.5.12-review`, 2026-11-27 (full text: dispatch run dir `agy.log`)
**Implementer:** Luna · **Verifier:** Claude
**Intent approved:** operator, 2026-11-27
**Intent note:** same intent as the parent (approved 2026-11-27, "Approve all three"); review comments are fixed under the standing rule that release-PR review findings are addressed before merge. No behaviour beyond the parent's Acceptance changes.

## Findings to fix

1. **Bare negations (tests cannot fail).** `scripts/tests/lib/ssh_fragment.bats:55-56` and `scripts/tests/lib/acg.bats:488` use
   `! grep -q ...`; under BATS `set -e` a negated command never fails the test (shellcheck SC2314). Use `run ! grep -q ...`.
2. **False success on a failed fragment write.** `scripts/lib/acg/acg.sh:75-89` (`_acg_update_ssh_config`, `_acg_upsert_ssh_host`)
   and the caller at `acg.sh:293-298`: if `_ssh_fragment_upsert` fails (e.g. the fragment is a symlink), `_acg_upsert_ssh_host`
   still logs `[acg] Updated SSH fragment: Host ...`, `_acg_update_ssh_config` returns 0 because `_ssh_fragment_check_resolves`
   overwrites the status, and under `set -e` the `mktemp` block file in `${TMPDIR:-/tmp}` leaks. Fix: capture the upsert status,
   remove the block file on every path, log success only on rc 0, return the failing rc from both functions, and make the
   provision caller stop (no CloudFormation-dependent work after a failed write; keep the existing return-code meanings).
   Do not add an `if` to `acg_teardown` (8-`if` audit limit; new logic goes in helpers declared with `function`).
3. **Alias matching on commented or multi-alias headers.** `scripts/lib/ssh_fragment.sh:36-39, 65-66, 118`: strip an inline `#`
   comment from the `Host` line before splitting; upsert, set-hostname and remove act only on a stanza whose alias list is exactly
   the one name (a multi-alias header that contains the name is left untouched and reported once on stderr).
4. **Preflight syntax gaps.** `scripts/lib/ssh_fragment.sh:165-170` (`_ssh_fragment_include_preflight`): treat `=` as a keyword
   separator (`Host=foo`, `Match=all`, `Include=path`), ignore empty Include values and empty comparison forms (a fragment outside
   `$HOME/.ssh` must not match `Include ""`).

## Files

- `scripts/lib/acg/acg.sh`, `scripts/lib/ssh_fragment.sh`
- `scripts/tests/lib/acg.bats`, `scripts/tests/lib/ssh_fragment.bats`
- `CHANGE.md` (v0.5.12 entry: one clause for the error propagation, only if the wording changes)

## What NOT to Do

- Do NOT commit, push, tag or comment on the PR. Do NOT touch `scripts/lib/acg/playwright/**`.
- Do NOT read the real `~/.ssh`; every test uses `BATS_TEST_TMPDIR` HOME and absolute `Include` paths.
- Do NOT weaken or delete an existing assertion.

## Acceptance

```yaml
must:
  - id: F-M1
    text: "a failed fragment write makes _acg_update_ssh_config return non-zero, prints no 'Updated SSH fragment' line, and leaves no k3dm-block temp file"
  - id: F-M2
    text: "Host lines with an inline comment or several aliases are never rewritten or removed when acting on 'ubuntu'"
  - id: F-M3
    text: "the preflight treats 'Host=x' / 'Match=all' as a block start and ignores empty Include values"
must_not:
  - id: F-N1
    text: "a negative grep assertion that cannot fail remains in ssh_fragment.bats or acg.bats"
    red_on_current: "red: shellcheck SC2314 on ssh_fragment.bats:55-56 and acg.bats:488"
  - id: F-N2
    text: "provisioning continues after a failed fragment write"
    red_on_current: "red: current _acg_update_ssh_config returns 0 after a symlinked-fragment refusal"
  - id: F-N3
    text: "acting on ubuntu changes a 'Host ubuntu-gcp # formerly ubuntu' or 'Host ubuntu-gcp ubuntu' stanza"
    red_on_current: "red: current matches() finds 'ubuntu' in head[1:]"
  - id: F-N4
    text: "an Include placed after 'Host=foo' passes the preflight"
    red_on_current: "red: current regex requires whitespace after Host"
evidence:
  - id: F-E1
    proves: [F-M1, F-M2, F-M3, F-N1, F-N2, F-N3, F-N4]
    kind: offline
    command: "env -i PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=$HOME bats scripts/tests/lib/acg.bats scripts/tests/lib/ssh_fragment.bats and make bats pass; shellcheck on touched .sh and .bats shows no SC2314; AGENT_AUDIT_MAX_IF=8 audit on the staged files prints nothing; F-N2..F-N4 tests fail against 715dda0"
    intent: "Before you merge v0.5.12, the sandbox SSH writer never reports success when it failed to write, and never edits the wrong host entry."
interface: none
```

## Worker definition of done

The F-E1 command passes under the BSD-first PATH above and your default PATH; F-N2, F-N3, F-N4 tests are shown red against
715dda0 (report the failing test names); `git add -A` then the audit prints nothing; `git status` shows only the Files above.
Do not commit.
