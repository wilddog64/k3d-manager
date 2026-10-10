# Bug: `bin/dr-drill` turns off `nounset` around three Vault calls

**Filed:** 2026-10-10
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — spec ready (v1.43.2 batch 2; same agent as `2026-10-10-dr-drill-keep-deletes-kubeconfig.md`)
**Priority:** P3 — hygiene; nothing fails today
**Severity:** low

## Symptom

Three call sites in `bin/dr-drill`, which runs under `set -euo pipefail`, wrap a call with `set +u`:

```bash
set +u; VAULT_API_WAIT_S="$limit" _vault_wait_api secrets vault; rc=$?; set -u        # _dr_drill_wait_vault
set +u; _vault_exec secrets 'vault status -format=json' vault | jq -e '.sealed == false' >/dev/null; local rc=$?; set -u; return "$rc"   # _dr_drill_v1
set +u; hub_data_verify_vault_paths secrets vault "$(_dr_drill_inventory)"; local rc=$?; set -u; return "$rc"   # _dr_drill_v2
```

The wrappers hide any unbound variable in `vault.sh` or `hub_data.sh` on exactly the path the drill
is meant to prove. On 2026-10-10, `_vault_wait_api` and `_vault_exec` ran cleanly under
`set -euo pipefail` with a stub `kubectl`, so the wrappers look like leftovers from an
earlier failure, not a current need. The likely origin is the 2026-10-10 export failure caused by an
unset `stdin_payload` under `set -u` in `vault.sh`, which was fixed at its source (memory-bank
progress, 2026-10-10).

## Fix

- Remove the three `set +u` / `set -u` pairs.
- Keep the return-code capture. All three run in an `||` or `_dr_drill_check` (`if`) context, so
  `set -e` does not abort them. Keep it that way:
  `_vault_wait_api ... || rc=$?` with `local rc=0`, and the same for the other two.
- If removing a wrapper exposes a real unbound variable:
  - give that variable a default (`${VAR:-}`) at its use site in `vault.sh` or `hub_data.sh`;
  - name the variable in the commit body;
  - do not restore the wrapper.

## Tests (`scripts/tests/bin/dr_drill.bats`, stubbed)

- `grep -c 'set +u' bin/dr-drill` is `0`. This is a disappearance gate, so use `run` and assert on
  the output, because `grep -c` exits 1 on zero matches.
- Run V1 and V2 through the existing stubbed harness under `set -u`, once failing and once
  succeeding. Both keep their true/false result in the result JSON.

Mutation: make the V1 stub fail and drop the `|| rc=$?`. The run must stop with V1 unrecorded, not
silently pass.

## Files

- `bin/dr-drill`
- `scripts/tests/bin/dr_drill.bats`
- only if a real unbound variable appears: `scripts/plugins/vault.sh` and/or `scripts/plugins/hub_data.sh`
- `CHANGELOG.md`

Commit message: `fix(dr): run the drill's Vault checks under nounset`
