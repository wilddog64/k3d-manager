# Plan: hub recovery rewrites the `vault-unseal` Secret from the restored shards (unseal watchdog stage 2, v1.44.2)

**Filed:** 2026-11-17
**Branch:** `k3d-manager-v1.44.2`
**Status:** ready for dispatch
**Covers:** stage 2 of `docs/bugs/2026-11-15-vault-unseal-watchdog-secret-shard-rejected-errors-suppressed.md` (stage 1 live-verified; E0 proved the Secret held a shard from an earlier init, Keychain `4d9e743984dd` vs Secret `f1bffbb8cc7e`).
**Risk:** low-medium (one extra Secret write in the hub recovery path; no change to the watchdog, the init path or the drill path)
**Agent:** Flash (agy, `gemini-3.8-flash-medium`)

## Problem

`_hub_data_repoint_vault` (`scripts/plugins/hub_data.sh:844`) restores a Vault whose keys come from the DR Keychain item
`k3dm-vault-unseal-dr`, then caches those shards in the Keychain (`_vault_cache_unseal_keys`, `:863`). It never updates the
cluster Secret `secrets/vault-unseal`, whose only writer is the init path (`scripts/plugins/vault.sh:1756-1766`). The unseal
watchdog CronJob reads only `vault-unseal` `shard-1` (`scripts/etc/vault/unseal-watchdog.yaml.tmpl:42,83-89`). So after a
restore, the Secret keeps the shard of the Vault that was created and then overwritten, and every later Vault restart stays
sealed (`cipher: message authentication failed`, live 2026-11-17 01:05Z) until someone unseals by hand.

## Before You Start

1. Read `memory-bank/activeContext.md` and the bug doc above (Root cause, Stage 2 outline, E0).
2. `git pull` on `k3d-manager-v1.44.2`.
3. Read `_hub_data_repoint_vault` (`hub_data.sh:844-871`) and these tests in `scripts/tests/plugins/hub_data.bats` before editing:
   `recover K1` (~903), `recover B4-18` (~915), `recover B4-D3` (~1170); also `scripts/tests/plugins/vault_k8s_auth_config.bats:150-178`.

## Fix (`scripts/plugins/hub_data.sh`, `_hub_data_repoint_vault` only)

In the **non-drill** branch, immediately after `_vault_cache_unseal_keys "$ns" "$release" "${shards[@]}" || return 1` and
before the `printf '%s\n' cached` line, write the Secret from the same validated `shards` array:

1. Build the whole Secret as JSON with `jq` from stdin, never from argv: `apiVersion v1`, `kind Secret`, `metadata`
   `{name: "vault-unseal", namespace: "secrets"}`, `type Opaque`, `stringData` with `key-shares` and `key-threshold` both
   equal to `"$count"` (strings), and `shard-1` … `shard-N` in order. Feed the shards to `jq` on stdin (e.g.
   `printf '%s\n' "${shards[@]}" | jq -Rn --arg n "$count" '…[inputs]…'`). `--arg n "$count"` is fine (a count, not a secret);
   no shard may appear in any argv.
2. If `_kubectl --context "$context" -n "$ns" get secret vault-unseal` succeeds (output to `/dev/null`), pipe the JSON to
   `_no_trace _kubectl --context "$context" replace -f -`; otherwise to `_no_trace _kubectl --context "$context" create -f -`.
   Use `replace`/`create`, not `apply`: the init path made the Secret with `create` (no last-applied annotation), and a merge
   would keep a stale `shard-2` from an older init.
3. On failure `return 1` (same as the surrounding steps). Print one line to stderr on success:
   `[hub-recover] vault-unseal Secret rewritten from restored shards (<N> shard(s))` — the count only, never a value.

The drill branch (`k3d-dr-drill` or `K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1`) is unchanged: no Keychain cache and no Secret write.

## Files

| File | Change |
|---|---|
| `scripts/plugins/hub_data.sh` | Fix 1-3 in `_hub_data_repoint_vault` |
| `scripts/tests/plugins/hub_data.bats` | new tests below; update `recover B4-18` order and any `_kubectl` stub that the new calls break (say which in the report) |

## Contract readers

`vault-unseal` Secret (2026-11-17, `grep -rn "vault-unseal" scripts bin`, excluding `-dr`, `-watchdog` and the Keychain service):
- writers: `vault.sh:1765-1766` (init, unchanged), `vault.sh:813` (delete in the re-init path, unchanged), and **new**: `_hub_data_repoint_vault`.
- readers: `vault.sh:348` (`_vault_collect_unseal_shards_from_secret`, reads every `shard-*` key sorted — so no stale extra key may remain, hence `replace`), `:375-397`, `:586-592` (re-unseal fallback), the watchdog mount (`shard-1` only).
- `key-shares` / `key-threshold`: written only by `vault.sh:1758-1759`; no reader (`grep -rn "key-threshold" scripts bin`), so setting both to the shard count is safe.
- Callers of `_hub_data_repoint_vault`: `hub_data.sh:619` (public `hub_data_repoint_vault [context]`, operator-run) and `:1186` (`hub_data_recover` step 6).

## Tests (`scripts/tests/plugins/hub_data.bats`, these names exactly)

Stub `_kubectl` so that `get secret vault-unseal` exits per a variable, `replace`/`create` record the verb and save stdin to a
file, and the `vault-root` apply saves its own payload; assert the fixture first (the stub was called, the payload file is the
one written by the vault-unseal call).

1. `recover S2-1: hub repoint rewrites vault-unseal from the restored shards` — count 2, shards `SHARD-A`, `SHARD-B`, Secret
   exists → one `replace -f -` call; payload has `metadata.name == "vault-unseal"`, `stringData["shard-1"] == "SHARD-A"`,
   `stringData["shard-2"] == "SHARD-B"`, `stringData["key-shares"] == "2"`, and no other `shard-*` key.
2. `recover S2-2: creates vault-unseal when it does not exist` — `get` fails → one `create -f -`, same payload.
3. `recover S2-3: no shard value in any kubectl argv or stderr` — every recorded `_kubectl` argv and the captured stderr contain
   neither `SHARD-A` nor `SHARD-B`; `--from-literal` never appears; stderr contains `vault-unseal Secret rewritten` and `2 shard(s)`.
   Positive control in the same test: the saved payload **does** contain `SHARD-A` (so the grep would see it if leaked).
4. `recover S2-4: drill target never writes vault-unseal` — `k3d-dr-drill`, and `K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1` → no
   `replace`/`create` call; `unseal_keys_cache` is `skipped` (existing K1 behaviour kept).
5. `recover S2-5: a failed Secret write fails the step` — `replace` exits 1 → `_hub_data_repoint_vault` non-zero, and the
   `vault-root` apply is not reached.

Update `recover B4-18` to the new order `config shards vault-unseal vault-root root`.

Pre-fix red: 1, 2, 3, 5 fail on today's code (4 passes: guard). Mutations (apply by hand, run, revert; each must turn the
named test red): use `apply` in place of `replace` and a merge keeps `shard-2` from a pre-seeded old payload — or, simpler,
always call `create` (1); write `shard-1` only (1); pass a shard through `--from-literal` (3); move the write into the drill
branch too (4); drop `|| return 1` on the write (5).

## What NOT to Do

- Do NOT change the init path (`vault.sh:1750-1770`, including its existing `--from-literal`), the watchdog template,
  `_vault_cache_unseal_keys`, `hub_data_unseal_dr`, or the drill branch.
- Do NOT print, log or pass a shard in argv; do NOT use `--from-literal` or `kubectl patch -p`.
- Do NOT touch a live cluster, the Keychain, or `security`.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`). Do NOT update `memory-bank/`.
- Do NOT modify files outside the Files table.

## Rules

- LF endings; keep existing indentation, quoting and naming; no unsolicited refactors; double-quote every expansion.
- No test calls a real `kubectl`, `security` or `vault`; stubs only.
- If the spec contradicts the code, stop and say so; do not guess.

## Gates

`bats scripts/tests/plugins/hub_data.bats scripts/tests/plugins/vault_k8s_auth_config.bats`, `shellcheck scripts/plugins/hub_data.sh`,
then `make test`.

## Definition of Done

- [ ] Fix 1-3; `git status` shows only the two files.
- [ ] Pre-fix red for tests 1, 2, 3, 5 pasted (command, rc, failing lines).
- [ ] Gates green; mutation table (mutation → test → red).
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: after a hub recovery, the vault-unseal Secret holds exactly the restored shards (shard-1..N, no older extra key), so the unseal watchdog can open the restored Vault
  - id: M2
    text: the Secret is written from stdin JSON; no shard appears in any argv, log line or stderr
must_not:
  - id: N1
    text: hub recovery leaves vault-unseal holding the shard of the replaced Vault — red today
  - id: N2
    text: a drill recovery writes vault-unseal on the drill or hub cluster
  - id: N3
    text: a failed Secret write is ignored and recovery carries on as if it worked — red today
evidence:
  - id: E1
    proves: [M1, N1, N3]
    kind: offline
    command: bats scripts/tests/plugins/hub_data.bats -f "recover S2-1|recover S2-2|recover S2-5|recover B4-18"
    intent: After a disaster-recovery restore, the cluster's unseal Secret is replaced with the restored keys, so a later Vault restart unseals by itself instead of staying sealed as it did on 2026-11-15.
  - id: E2
    proves: [M2]
    kind: offline
    command: bats scripts/tests/plugins/hub_data.bats -f "recover S2-3|recover B4-D3"
    intent: The unseal keys never show up on a command line or in a log while being written.
  - id: E3
    proves: [N2]
    kind: offline
    command: bats scripts/tests/plugins/hub_data.bats -f "recover S2-4|recover K1"
    intent: A practice (drill) restore still leaves the real hub's unseal Secret alone.
  - id: E4
    proves: [M1]
    kind: live
    command: "next real hub recovery or DR drill run against the hub (operator present): read-only, compare SHA-256 prefixes of Keychain k3d-manager-vault-unseal shard1 and secrets/vault-unseal shard-1 (values never printed); then a Vault pod restart auto-unseals via the watchdog"
    intent: The next time the hub is restored for real, the Secret and the Keychain hold the same shard and a Vault restart unseals without you.
interface:
  - "scripts/plugins/hub_data.sh: _hub_data_repoint_vault <context> [run_dir]"
  - "Secret secrets/vault-unseal (shard-1..N, key-shares, key-threshold)"
```

E4 cannot run until a real recovery happens (recovery replaces the hub's data; it is never run just to test). The release
can ship with E1-E3 offline and E4 recorded as pending in the bug doc, as for other DR-only paths.

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "go for what you suggested" (stage 2 in v1.44.2, 2026-11-17) and "you can go ahead to write 2 specs and dispatch to Flash and Luna" with "Stage 2 + OOB M1" chosen (2026-11-17).
