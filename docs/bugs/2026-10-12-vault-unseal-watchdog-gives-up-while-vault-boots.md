# Bug: the Vault unseal watchdog gives up while Vault is still booting

**Filed:** 2026-10-12
**Branch:** `k3d-manager-v1.44.0`
**Status:** OPEN
**Priority:** P2 — Vault, and every secret read through it, stays sealed up to 5 minutes longer than needed after a restart; it recovers on its own
**Release:** v1.44.0 (bug fix carried per docs/roadmap.md) (backlog triage, Claude, 2026-10-22)
**Approval:** explicit 2026-10-12 "let's get those two to v1.44.0" (operator, to "should I file them, and for v1.43.2 or v1.44?")
**Severity:** medium

## Symptom

The OrbStack 2.2.4 upgrade on 2026-10-12 restarted every hub container at about 11:35Z. Vault came
back sealed. The `vault-unseal-watchdog` CronJob (namespace `secrets`, `*/5`) logged:

- first run after the restart: `[unseal-watchdog] vault unreachable at <VAULT_ADDR> — skipping`, exit 0;
- the 11:40Z run: `vault sealed — replaying shard`, then `unseal succeeded`.

Vault stayed sealed for one full schedule interval. Keycloak, Prometheus and every ExternalSecret
refresh waited on it.

## Root cause

`scripts/etc/vault/unseal-watchdog.yaml.tmpl` checks `vault status` once. Return code 1 means
Vault could not be reached, which is what a booting Vault pod returns, and the script exits:

```sh
if [ "$rc" -eq 1 ]; then
  echo "[unseal-watchdog] vault unreachable at $VAULT_ADDR — skipping"
  exit 0
fi
```

A restart is exactly when the watchdog is needed, and exactly when Vault is briefly unreachable.

## Fix

`scripts/etc/vault/unseal-watchdog.yaml.tmpl`, inline script only:

1. Replace the single `vault status` check with a bounded retry while it returns 1: up to 12
   attempts, 5 seconds apart (60 s), printing
   `[unseal-watchdog] vault unreachable at $VAULT_ADDR — retry <n>/12` on each failed attempt.
2. Return code 0 → `vault already unsealed`, exit 0 (unchanged). Return code 2 (sealed) → leave the
   loop and run the existing unseal path (unchanged).
3. Still 1 after the last attempt → print the existing `vault unreachable … — skipping` line and
   exit 0. The next scheduled run tries again.
4. The total stays inside `activeDeadlineSeconds: 150`: 60 s of retries plus the unseal call.
   Do not raise the deadline or change the schedule.
5. POSIX `sh` only (the image has no bash). Keep `set -u`.

Out of scope, noted for a later bug: the shard is passed to `vault operator unseal` as an argument.
Do not change that here.

## Files

| File | Change |
|---|---|
| `scripts/etc/vault/unseal-watchdog.yaml.tmpl` | bounded retry while unreachable |
| `scripts/tests/etc/vault_unseal_watchdog.bats` | tests below |
| `docs/howto/vault.md` | one line: after a restart the watchdog retries for up to a minute before waiting for its next run |
| `CHANGELOG.md` | `[Unreleased]` → `### Fixed` |

## Tests

`scripts/tests/etc/vault_unseal_watchdog.bats`. Extract the rendered inline script and run it with
`sh` against a stub `vault` on `PATH` and a temp `SHARD_FILE` path; stub `sleep` so the test is fast.
No test may reach a real Vault.

1. `vault status` returns 1, 1, then 2 → the stub sees an `operator unseal` call; output contains
   `retry 1/12` and `retry 2/12`.
2. `vault status` returns 1 every time → exactly 12 status calls and 11 `sleep 5` calls before the
   skip, then `— skipping`, rc 0, no `operator unseal`.
3. `vault status` returns 0 first → `vault already unsealed`, one status call, no sleep.
4. `vault status` returns 2 first → unseal path runs with no retry lines.
5. The rendered template has no `bash`-only syntax: `sh -n` on the extracted script passes.

The existing five tests stay green.

Mutations (each must turn a test red; restore with `cmp` against a snapshot): retry count 12 → 1
(test 1); drop the loop exit on rc 2 (test 4); remove the `sleep` from the loop (test 2).

Gates: `bats scripts/tests/etc/vault_unseal_watchdog.bats`, `make test` (read the per-suite counts).

## Proof it works

The next hub restart (an OrbStack update or a rebuild): the first watchdog run after Vault's pod
starts logs `retry <n>/12` lines followed by `unseal succeeded`, in the same run.

## What NOT to Do

- Do NOT change the schedule, `activeDeadlineSeconds`, `backoffLimit` or the image.
- Do NOT print, log or `echo` the shard.
- Do NOT apply the template to the live hub; the operator does that.
- Do NOT commit, push or create a PR. Claude verifies and commits.
- Do NOT modify files outside the Files list.
