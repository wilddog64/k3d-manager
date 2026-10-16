# acg: CDP plist writer fails silently; CLI preflight misreports a missing CLI

**Date:** 2026-09-13
**Module:** `scripts/lib/acg/`
**Severity:** low (diagnostics only — both paths already fail closed; the messages are wrong or absent)
**Branch (all work):** `fix/acg-cdp-plist-silent-fail-and-missing-cli-msg`
**Found by:** Copilot review of k3d-manager PR #125 (the v1.32.1 hotfix that vendors lib-foundation `9c0af5b`)

## Finding 1 — `_acg_chrome_cdp_write_plist` returns 1 with no message

`scripts/lib/acg/acg.sh`:

```bash
_acg_chrome_cdp_write_plist() {
  local _chrome_bin
  _chrome_bin="$(_acg_resolve_cdp_browser_bin)" || return 1
  if [[ -z "${_chrome_bin}" || ! -x "${_chrome_bin}" ]]; then
    _err "[acg] Playwright-managed Chromium not found — run 'npm install' in ${_LIB_ACG_ROOT} before installing the CDP agent"
    return 1
  fi
```

`_acg_resolve_cdp_browser_bin` (`cdp.sh`) runs `node -e 'require("playwright")...' 2>/dev/null`.
When `node` is missing or `playwright` is not installed — the **most likely** real-world failure —
it exits non-zero, and `|| return 1` returns **before** the `_err` line. So
`acg_chrome_cdp_install` fails with no explanation. The helpful message only fires in the rarer
case where node succeeds but prints an empty or non-executable path.

### Fix

Let a resolver failure fall through to the existing check, so one message covers every cause:

```bash
  _chrome_bin="$(_acg_resolve_cdp_browser_bin)" || return 1
```

becomes

```bash
  _chrome_bin="$(_acg_resolve_cdp_browser_bin)" || _chrome_bin=""
```

Nothing else in the function changes.

### Test

The existing test `acg CDP plist is not written without a Playwright browser`
(`scripts/tests/lib/acg.bats`) already stubs the resolver with `return 1` and asserts non-zero
status plus no plist file. **Strengthen it** (do not add a duplicate test) by also asserting the
message is emitted:

```bash
  [[ "${output}" == *'Playwright-managed Chromium not found'* ]]
```

Confirm the strengthened assertion **fails against the unfixed code** before applying the fix, and
passes after.

## Finding 2 — "present but cannot run" is printed when the CLI is not installed

`scripts/lib/acg/bin/acg-credential-test`:

```bash
_aws_cli_usable() {
  local _probe_err
  _probe_err="$(aws --version 2>&1)" || {
    printf 'ERROR: the aws CLI is present but cannot run — credential validation is impossible.\n' >&2
    printf 'ERROR: %s\n' "${_probe_err}" >&2
    return 1
  }
  return 0
}
```

If `aws` is not on `PATH`, `aws --version` fails with `command not found` (rc 127) and the script
tells the operator the CLI "is present but cannot run" — pointing them at a broken install that
does not exist. `_az_cli_usable` has the identical defect.

### Fix

Check presence first, with its own message. Keep the existing "present but cannot run" branch
exactly as-is for the broken-install case. Apply the same shape to both functions.

```bash
_aws_cli_usable() {
  local _probe_err
  if ! command -v aws >/dev/null 2>&1; then
    printf 'ERROR: the aws CLI is not installed or not on PATH — credential validation is impossible.\n' >&2
    return 1
  fi
  _probe_err="$(aws --version 2>&1)" || {
    printf 'ERROR: the aws CLI is present but cannot run — credential validation is impossible.\n' >&2
    printf 'ERROR: %s\n' "${_probe_err}" >&2
    return 1
  }
  return 0
}
```

```bash
_az_cli_usable() {
  local _probe_err
  if ! command -v az >/dev/null 2>&1; then
    printf 'ERROR: the az CLI is not installed or not on PATH — credential validation is impossible.\n' >&2
    return 1
  fi
  _probe_err="$(az --version 2>&1)" || {
    printf 'ERROR: the az CLI is present but cannot run — credential validation is impossible.\n' >&2
    printf 'ERROR: %s\n' "${_probe_err}" >&2
    return 1
  }
  return 0
}
```

Behaviour is unchanged apart from the message: both paths still return 1, and callers still refuse
to restart the sandbox.

### Test

Add ONE new test to `scripts/tests/lib/acg.bats`, next to
`acg credential test does not restart when aws CLI cannot run`:

```bash
@test "acg credential test does not restart when aws CLI is missing" {
  local fixture_dir sentinel="${BATS_TEST_TMPDIR}/restart-sentinel"
  fixture_dir=$(_acg_credential_test_fixture)
  rm -f "${fixture_dir}/bin/aws"
  ln -s "$(command -v bash)" "${fixture_dir}/bin/bash"

  run env PATH="${fixture_dir}/bin:/usr/bin:/bin" ACG_RESTART_SENTINEL="${sentinel}" \
    "${fixture_dir}/bin/acg-credential-test" 'https://example.test/sandbox' --provider aws

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'the aws CLI is not installed or not on PATH'* ]]
  [[ "${output}" != *'present but cannot run'* ]]
  [ ! -e "${sentinel}" ]
}
```

Why the restricted `PATH`: a real `aws` may exist in `/opt/homebrew/bin` or `/usr/local/bin` on the
developer machine or CI runner, which would make the test pass for the wrong reason. The `bash`
symlink keeps a modern bash reachable for `#!/usr/bin/env bash` (macOS `/bin/bash` is 3.2).
**Before relying on the test, prove `aws` is absent under that PATH:**
`env PATH="${fixture_dir}/bin:/usr/bin:/bin" bash -c 'command -v aws'` must print nothing. If some
other tool the script needs is not in `/usr/bin:/bin`, symlink it into `${fixture_dir}/bin` the same
way — do NOT widen `PATH` back to the host `PATH`.

Confirm this test fails against the unfixed code before applying the fix.

The existing `aws CLI cannot run` test must keep passing unchanged — it is the proof the
broken-install message still fires.

## CHANGE.md

Add under `## [Unreleased]`. `[Unreleased]` currently holds `### Changed` and `### Security`. Add a
**new `### Fixed` subsection inside `[Unreleased]`**, placed after `### Security` and before
`## [v0.4.17]`. **Do NOT append to any `### Fixed` under `## [v0.4.17]` or any other released
version** — those headings are not unique in this file.

```markdown
### Fixed
- `scripts/lib/acg/acg.sh`: `_acg_chrome_cdp_write_plist` no longer returns 1 silently when
  `_acg_resolve_cdp_browser_bin` fails (node or playwright missing) — the resolver failure now
  falls through to the existing "Playwright-managed Chromium not found" error.
- `scripts/lib/acg/bin/acg-credential-test`: `_aws_cli_usable` / `_az_cli_usable` report a CLI that
  is not installed as "not installed or not on PATH" instead of "present but cannot run". Both
  still fail closed and never restart the sandbox. Found by Copilot on k3d-manager PR #125. Spec:
  `docs/bugs/2026-09-13-acg-cdp-plist-silent-fail-and-missing-cli-message.md`.
```

Verify placement positively: the nearest `## ` heading above the new entry must be
`## [Unreleased]`, and `git diff origin/main -- CHANGE.md` must contain zero deleted lines.

## Rules

- Edit only: `scripts/lib/acg/acg.sh`, `scripts/lib/acg/bin/acg-credential-test`,
  `scripts/tests/lib/acg.bats`, `CHANGE.md`.
- Minimal patches. No refactors, no reformatting, no inline comments.
- `shellcheck` on `scripts/lib/acg/acg.sh` and `scripts/lib/acg/bin/acg-credential-test` — zero new
  warnings versus `origin/main` (compare counts; report both).
- `make bats` (scrubbed env, matches CI) — all green; paste the summary.
- `bats scripts/tests/lib/acg.bats` — paste full TAP output.

## Definition of Done

- [ ] Both strengthened/new assertions shown FAILING on unfixed code, then PASSING after the fix
      (paste both runs)
- [ ] `command -v aws` under the restricted test PATH proven empty (paste)
- [ ] shellcheck counts before/after pasted, no increase
- [ ] `make bats` green, output pasted
- [ ] CHANGE.md entry placement asserted under `[Unreleased]`, 0 deleted lines vs main
- [ ] `git diff --stat origin/main` shows only the 4 files above plus this spec
- [ ] Committed on `fix/acg-cdp-plist-silent-fail-and-missing-cli-msg` with exactly:

```
fix(acg): surface CDP plist resolver failures; distinguish a missing CLI
```

- [ ] Pushed; `git rev-parse origin/fix/acg-cdp-plist-silent-fail-and-missing-cli-msg` reported

## What NOT to Do

- Do NOT create a PR. Do NOT merge. Do NOT commit to `main`.
- Do NOT use `--no-verify`. Do NOT force-push.
- Do NOT modify files outside the four listed.
- Do NOT change behaviour beyond the messages described — no new exit codes, no restart logic changes.
- Do NOT touch k3d-manager.
- If `git commit` fails with `Unable to create '.../.git/index.lock': Operation not permitted`,
  STOP, leave the tree as-is, paste all gate output, and report. Claude will commit.
