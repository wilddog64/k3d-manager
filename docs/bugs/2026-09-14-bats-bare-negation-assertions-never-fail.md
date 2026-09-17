# Bug: bare `! cmd` assertions in BATS never fail a test

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** FIXED `81048cea` (Codex; Claude verified + committed, incl. S5 signing.sh env://COSIGN_KEY)
**Files:** the 14 `.bats` files listed below, `scripts/plugins/signing.sh` (S5), `scripts/tests/lib/bats_negation_lint.bats` (new), `CHANGELOG.md`

## Problem

BATS runs each test body under `set -e`. Bash **exempts `! cmd` from `set -e`**, so a line such as `! grep -q 'kv put' "$calls"` never aborts the test when `grep` matches.

- **Last line of a test:** it still works, because the test function returns that line's status.
- **Anywhere else:** a failed negation is silently ignored, and the next line decides the result.

Inventory on `k3d-manager-v1.34.0` (2026-09-14): `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats'` finds **42** lines in **14** files. **13** are mid-test, so they are ineffective today:

| File | Mid-test lines |
|---|---|
| `scripts/tests/plugins/hub_recovery.bats` | 327, 328, 348, 357, 358, 367, 368 |
| `scripts/tests/plugins/signing.bats` | 190, 283 |
| `scripts/tests/plugins/ldap_chart_passwords.bats` | 11, 12 (inside `bash -c` with no `set -e`: neither the `!` lines nor line 10 are checked) |
| `scripts/tests/lib/install_kubernetes_cli.bats` | 37 |
| `scripts/tests/lib/ensure_bats.bats` | 46 |

There is a separate defect at `scripts/tests/plugins/signing.bats:124`:
```bash
! grep -qE 'imageReferences:' -A2 "$out" 2>/dev/null | grep -qE '^\s*-\s*"?\*"?\s*$'
```
- `grep -q` prints nothing, so the second `grep` always fails and the `!` always succeeds.
- The wildcard-imageReference guard can therefore never fail.

All 42 lines, as `file:line`:

```
scripts/tests/bin/cluster_refresh.bats:26
scripts/tests/bin/cluster_sync_apps.bats:86
scripts/tests/bin/cluster_up.bats:94
scripts/tests/plugins/ldap_chart_passwords.bats:11,12
scripts/tests/plugins/signing.bats:106,116,124,133,141,190,191,229,256,283,303,376
scripts/tests/plugins/vault_app_auth.bats:206
scripts/tests/plugins/argocd_reclaim_release_ownership.bats:53,69,81
scripts/tests/plugins/hub_recovery.bats:327,328,329,339,348,349,357,358,359,367,368,369
scripts/tests/plugins/shopping_cart_seed_idempotent.bats:186
scripts/tests/plugins/vcluster.bats:64,72
scripts/tests/etc/vault_unseal_watchdog.bats:22
scripts/tests/lib/run_command.bats:28,87
scripts/tests/lib/install_kubernetes_cli.bats:37
scripts/tests/lib/ensure_bats.bats:46,105
```

`cluster_up.bats:94` may already be converted by `docs/bugs/2026-09-14-acg-lock-acquire-missing-state-dir-hangs.md` S3. If so, skip it.

## Fix

### S1 — mechanical conversion (every line except the two special cases below)

Replace each line of the form `<indent>! <command>` with two lines at the same indent:

```bash
<indent>run <command>
<indent>[ "$status" -ne 0 ]
```

Example. Old:

```bash
  ! grep -Fq 'kv put' "$MIRROR_CALLS"
```

New:

```bash
  run grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
```

- Keep each command's flags, patterns, quoting and any trailing `2>/dev/null` exactly as they are. `argocd_reclaim_release_ownership.bats:53` uses `rg`; keep `rg`.
- `run` overwrites `$output` and `$status`. Before converting a mid-test line, check whether a later line in the same test reads `$output`/`$status` from an earlier `run`. If one does, stop and report it; do not reorder assertions. None did at spec time.

### S2 — special case: `scripts/tests/plugins/signing.bats:124`

Old:

```bash
  ! grep -qE 'imageReferences:' -A2 "$out" 2>/dev/null | grep -qE '^\s*-\s*"?\*"?\s*$'
```

New:

```bash
  run bash -c 'grep -E -A2 "imageReferences:" "$1" | grep -qE "^[[:space:]]*-[[:space:]]*\"?\*\"?[[:space:]]*$"' _ "$out"
  [ "$status" -ne 0 ]
```

### S3 — special case: `scripts/tests/plugins/ldap_chart_passwords.bats` lines 10–12

Old:

```bash
    _ldap_password_is_chart_safe "safePassword_123.-"
    ! _ldap_password_is_chart_safe "unsafe/password"
    ! _ldap_password_is_chart_safe "unsafe&password"
```

New:

```bash
    _ldap_password_is_chart_safe "safePassword_123.-" || exit 1
    _ldap_password_is_chart_safe "unsafe/password" && exit 1
    _ldap_password_is_chart_safe "unsafe&password" && exit 1
    exit 0
```

### S4 — regression guard: `scripts/tests/lib/bats_negation_lint.bats` (new)

```bash
#!/usr/bin/env bats

@test "no bare '! cmd' assertions in BATS suites (set -e ignores them)" {
  local tests_root="${BATS_TEST_DIRNAME}/.."
  run grep -rnE '^[[:space:]]*! ' "${tests_root}" --include='*.bats'
  [ "$status" -ne 0 ]
}
```

(The pattern in this file is inside quotes, not at the start of a line, so the guard does not match itself.)

### If a converted assertion now fails

That is a real test or product defect the bare `!` was hiding. **Do not** weaken the assertion or revert the conversion. Stop, and report the file, test name, line and the matched content. Claude will triage it separately.

### S5 — exposed defect (triaged 2026-09-14): `signing.sh` passes a key-file path to `cosign --key`

After the conversion, `signing.bats` "signing.sh never passes cosign key/password as a bare CLI argument" fails. It matches `scripts/plugins/signing.sh:195`:
`cosign public-key --key "${workdir}/cosign.key"`.

- The bare `!` had hidden this since `cd38a7e5` (v1.29.0).
- The file's own policy comment (line 44) says cosign must read key material via `--key env://COSIGN_KEY`.
- The temp file is still needed afterwards for `_signing_write_vault`, but cosign does not need to read it.
- Verified locally with a throwaway keypair (cosign v3.1.3): `cosign public-key --key env://COSIGN_KEY` produces the same public key as `--key <file>`.

The assertion is not weakened. Instead, `scripts/plugins/signing.sh`:

Old:

```bash
    if ! COSIGN_PASSWORD="${password}" _no_trace _run_command -- \
        cosign public-key --key "${workdir}/cosign.key" > "${workdir}/cosign.pub" 2>/dev/null; then
```

New:

```bash
    if ! COSIGN_KEY="${key}" COSIGN_PASSWORD="${password}" _no_trace _run_command -- \
        cosign public-key --key env://COSIGN_KEY > "${workdir}/cosign.pub" 2>/dev/null; then
```

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet:

```
- BATS suites no longer use bare `! cmd` assertions, which `set -e` ignores anywhere but the last line of a test: 42 lines across 14 suites now use `run …; [ "$status" -ne 0 ]` (13 were silently ineffective, and the `signing.bats` wildcard-imageReference guard could never fail), and a new lint test rejects the pattern
```

## Definition of Done

- [ ] S1–S4 applied; `git diff --stat` shows only the listed `.bats` files, the new lint file and `CHANGELOG.md`.
- [ ] Disappearance gate: `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats' | wc -l` prints `0`.
- [ ] `bats` on every touched suite plus `scripts/tests/lib/bats_negation_lint.bats`: all pass (paste the per-file summary lines). Use `timeout 300` for `scripts/tests/bin/cluster_up.bats`.
- [ ] Commit message, verbatim: `test(bats): replace bare negation assertions that set -e ignores`

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT change any non-test file except `CHANGELOG.md`.
- Do NOT touch `scripts/lib/foundation/` (including its own tests), `scripts/lib/acg/`, or memory-bank.
- Do NOT convert `!` used inside `if ! …`, `while ! …` or `[[ ! … ]]`; only whole-line `! cmd` statements.
- Do NOT `grep -F` whole source lines in new assertions.
