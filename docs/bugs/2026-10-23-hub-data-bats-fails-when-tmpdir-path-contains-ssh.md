# Bug: `hub_data.bats` fails when the `TMPDIR` path contains `ssh-config-guard`

**Filed:** 2026-10-23 (Claude, found while landing `ssh-config-guard`)
**Status:** OPEN
**Priority:** P3 — test-only; it breaks `bin/k3dm-codex-dispatch land` for any task whose slug produces such a path
**Severity:** low
**Approval:** pending
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/tests/plugins/hub_data.bats`
**Related:** `docs/bugs/2026-10-22-ssh-config-lost-operator-host-aliases.md`

## Symptom

`bin/k3dm-codex-dispatch land` runs the task's tests with
`TMPDIR=<worktree>.run/state/tmp`. For the slug `ssh-config-guard`, that path is
`~/.local/share/k3d-manager/worktrees/v1.43.5/ssh-config-guard.run/state/tmp`. With that
`TMPDIR`, six `hub_data.bats` tests fail, on the pre-fix tree as well:

- 16 `hub data export: streams each claim from its own node and path`
- 17 `hub data export: encrypted contents, checksums, and split limit`
- 37 `5 prune keeps recent exports and the last passing export`
- 83, 84, 90 `recover preflight: …`

What makes them fail:

| `TMPDIR` | Failures |
|---|---|
| `/tmp` or a scratch dir | 0 |
| `~/.local/share/k3d-manager/probe/x.run/state/tmp` | 0 |
| `~/.local/share/k3d-manager/probe/ssh-config-guard/tmp` | 6 |

Only the path text changes between the rows, so some stub or assertion matches the string
`ssh` (or `config`, or `guard`) inside a path that comes from `TMPDIR`.

## Workaround used

`ssh-config-guard` landed (`f3002d12`) with `--test` set to `ssh_config_guard.bats` plus
`bats -f 'scheduled export' hub_data.bats`. Before that, the full `hub_data.bats` suite was run
green (120 tests) with the default `TMPDIR`.

## Fix

- **F1.** Find the stub or assertion in `hub_data.bats` that matches on `TMPDIR` path text, and anchor
  it to the command or argument instead of a substring.
- **F2.** Add a regression test: run the affected tests with a `TMPDIR` whose path contains
  `ssh-config-guard` (for example `$BATS_TEST_TMPDIR/ssh-config-guard/tmp`).

## Files

- `scripts/tests/plugins/hub_data.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: hub_data.bats passes with TMPDIR set to a directory whose path contains "ssh-config-guard".
must_not:
  - id: N1
    text: No hub_data.bats assertion depends on text in the TMPDIR path (red on the current suite with such a TMPDIR).
evidence:
  - id: E1
    kind: offline
    proves: [M1, N1]
    text: TMPDIR=<dir>/ssh-config-guard/tmp bats scripts/tests/plugins/hub_data.bats is green after the fix and has 6 failures before it.
interface:
  - bats scripts/tests/plugins/hub_data.bats
  - TMPDIR
```

## Definition of Done

- [ ] F1–F2; only `scripts/tests/plugins/hub_data.bats` changes.
- [ ] N1 shown red on the current suite.
- [ ] Commit: `test(hub-data): stop matching TMPDIR path text in hub_data.bats`

## What NOT to Do

- Do NOT change `scripts/plugins/hub_data.sh` or the dispatcher's `TMPDIR` isolation.
- Do NOT create a PR, commit to `main`, or use `--no-verify`.
