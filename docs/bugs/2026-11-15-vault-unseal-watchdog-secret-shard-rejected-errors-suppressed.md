# Bug: hub unseal watchdog replays a shard Vault rejects, and hides the error

**Status:** LANDED — stage 1 dd7c18ed on k3d-manager-v1.44.1, 2026-11-16 (Luna; Claude verified: 3 tests red pre-fix, green on fix; no set -e/pipefail in the pod script; envsubst limited to 3 vars; shard lines filtered before printing). Stage 2 (hub_data.sh) not started
**Priority:** P2 (proposed: a hub Vault restart stays sealed until the operator runs `deploy_vault --re-unseal` from the Keychain; workaround exists)
**Introduced by:** unknown (the `vault-unseal` Secret was created 2026-10-30T20:52:23Z, around the M5 hub cut-over)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-16 (E0 Keychain fingerprint vs f1bffbb8cc7e, E5 watchdog log on the hub; operator)
**Triage:** patch → v1.44.1 (P2, flagged: Vault stays sealed until a manual unseal; read-only investigation first) — operator grooming 2026-11-15 ("Accept as shown")
**Release:** v1.44.1 (bug; operator, 2026-11-15: "let's get those two done at v1.44.1" — out of the v1.44.0 cut)
**Prior art:** `docs/bugs/2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md` (exact-slug pass; `find-similar-docs` printed nothing) — read, different root cause (that bug is the boot-time retry; its fix ran correctly here)
**Severity:** high when it bites — every Vault restart on the hub (OrbStack update, node reboot) leaves Vault sealed, ESO refreshes fail, and nothing unseals it automatically

## What happened (Claude, 2026-11-15, M5 hub `k3d-k3d-cluster`)

To live-check the 2026-10-12 retry fix, Claude applied the fixed template (`vault_install_unseal_watchdog`) and deleted
`secrets/vault-0` at 15:24:45Z. Watchdog jobs at 15:25, 15:30 and 15:35 each logged `vault sealed — replaying shard`
then `unseal attempt complete (still sealed or unreachable)`. `vault status`: initialized, sealed, `t` 1, progress 0 —
the shard was rejected outright. Vault stayed sealed about 12 minutes. The operator then ran
`./scripts/k3d-manager deploy_vault --re-unseal --namespace secrets` on the M5 (login Keychain unlocked):
`applying 1 cached unseal shard(s)` → `now unsealed`. One ExternalSecret (`cicd/argocd-oidc-secret`) recorded
`SecretSyncedError` at 15:34 during the outage.

## Evidence so far

- SHA-256 prefix of the Secret's `shard-1` (CR/LF stripped): `f1bffbb8cc7e`. The Keychain comparison failed from a
  non-interactive ssh session (empty read), so "the Secret's shard is stale" is still a hypothesis, not proven.
- The Keychain shard opened Vault on the first try, and the Secret's shard did not, which is consistent with a stale Secret.
- `scripts/etc/vault/unseal-watchdog.yaml.tmpl:69`: `vault operator unseal "$(cat "$SHARD_FILE")" >/dev/null 2>&1 || true`
  discards the reason, so job logs cannot tell a bad shard from a network error.
- Side note: when `envsubst` is not on PATH, `vault_install_unseal_watchdog` (`scripts/plugins/vault.sh:1066`) writes an empty
  file and fails at `kubectl apply` with "no objects passed to apply" instead of naming envsubst.

## To investigate

1. On the M5 in a local terminal, compare the hashes of the Keychain `k3d-manager-vault-unseal` shard and the Secret's `shard-1` (never print values).
2. Find who writes the `vault-unseal` Secret and why it did not follow the current shard (cut-over restore? re-init?).
3. Log the unseal failure reason without printing the shard (for example, keep stderr but filter out the argument).

## Root cause (Claude, code read plus read-only probe, 2026-11-16)

Proven: the watchdog cannot say why it fails (`unseal-watchdog.yaml.tmpl:69` sends stdout and stderr to `/dev/null`).
Real capture, M4, 2026-11-16, `docker run hashicorp/vault:1.20.1 server` (file storage, initialised, 1 share) with a random
valid-form key: `vault operator unseal <key>` exits `rc=2`, writes 303 bytes to stderr and nothing to stdout, never
echoes the key, and the text includes `Code: 400. Errors:` and `* unable to retrieve stored keys: invalid key: failed to
decrypt keys from storage: error decrypting seal wrapped value`. The hub image is `hashicorp/vault:1.20.1`.
`sed`, `head`, `grep` and `cut` all exist in that image.

Probable, not proven: the `vault-unseal` Secret holds a shard that does not belong to the running Vault. Code facts:

- The only writer of the Secret is `vault.sh:1764-1765`, inside the init path (`deploy_vault` after `vault operator init`).
  Its `creationTimestamp` is `2026-10-30T20:52:23Z` (read-only `kubectl` on m5-air.local, 2026-11-16), so it was written
  once, at the init of a fresh Vault, and never again.
- Recovery rewrites the Keychain, not the Secret. `_hub_data_repoint_vault` (`hub_data.sh:850-871`) loads the DR shards from
  Keychain service `k3dm-vault-unseal-dr`, calls `_vault_cache_unseal_keys` (Keychain `k3d-manager-vault-unseal`), re-applies
  `vault-root`, and never touches `vault-unseal`. `hub_data_unseal_dr` (`hub_data.sh:588-615`, used by `k3dm-orbstack-upgrade:127`,
  `dr-drill:268` and recover step 5) only unseals. A Vault restored from backup keeps its old keys, so the
  Secret from the fresh init (before the restore) would be stale, and `deploy_vault --re-unseal` (Keychain first,
  `vault.sh:577-590`) works while the watchdog (Secret only) does not. This matches the observed asymmetry.
- Read-only probe (same host, redacted): the Secret's `shard-1` is 44 bytes, no CR, last byte `=` (valid base64 form),
  SHA-256 prefix `f1bffbb8cc7e` with or without CR/LF stripping, so a malformed or CRLF-damaged value is ruled out.
- Not provable here: whether that hash equals the Keychain shard (the Keychain is locked over ssh). That is E0.

## Plan: two stages

Stage 1 (dispatch after intent approval) makes the failure visible and removes the second trap. Stage 2 (the real fix)
is dispatched only after the operator runs E0 and it shows the hashes differ; if they are equal, the cause is something
else and Stage 2 is re-specced from the captured rejection reason that Stage 1 will expose on the next restart test.

### Stage 1 fix

1. `scripts/etc/vault/unseal-watchdog.yaml.tmpl:69` (inside the `command` block, 18-space indent), replace
   `vault operator unseal "$(cat "$SHARD_FILE")" >/dev/null 2>&1 || true` with:

   ```
   out="$(vault operator unseal "$(cat "$SHARD_FILE")" 2>&1)"
   unseal_rc=$?
   echo "[unseal-watchdog] unseal rc=$unseal_rc"
   printf '%s\n' "$out" | grep -F -v -- "$(cat "$SHARD_FILE")" | grep -E 'Error|error|Code:|^\* ' | head -5 | sed 's/^/[unseal-watchdog] /'
   ```

   The script has `set -u` only (no `-e`), so a non-zero rc does not exit. The shard stays out of the log twice over:
   Vault does not echo it (capture above) and `grep -F -v` drops any line that contains it. Keep the strings
   `vault operator unseal` and `$(cat "$SHARD_FILE")` and the final `unseal succeeded` / `still sealed` lines (existing tests read them).
2. `scripts/plugins/vault.sh`, in `vault_install_unseal_watchdog`, immediately above the `VAULT_NS="$ns" \` line
   (before `envsubst` at :1066), add
   `command -v envsubst >/dev/null 2>&1 || _err "[vault] envsubst not found on PATH (brew install gettext); not applying the unseal watchdog"`.

### Stage 2 fix (gated on E0; outline, final text written after E0)

In `_hub_data_repoint_vault` (`hub_data.sh`), in the non-drill branch next to `_vault_cache_unseal_keys "$ns" "$release" "${shards[@]}"`,
also rewrite the `vault-unseal` Secret on the hub context from the same validated shards, over stdin
(`jq` builds a Secret with `stringData` `key-shares`, `key-threshold`, `shard-N`, then `_no_trace _kubectl --context "$context" apply -f -`),
as `vault-root` is applied two lines below; never `--from-literal` (shard in argv, which `vault.sh:1765` still does and is out of scope).
A separate one-time repair of the live Secret from the Keychain on the M5 is an operator action (decision below), not code.

## Files

- Stage 1: `scripts/etc/vault/unseal-watchdog.yaml.tmpl`, `scripts/plugins/vault.sh` (one line), `scripts/tests/etc/vault_unseal_watchdog.bats`, `scripts/tests/plugins/vault_unseal_watchdog_context.bats` (envsubst test; extend if it is the harness that drives `vault_install_unseal_watchdog`)
- Stage 2 (later): `scripts/plugins/hub_data.sh`, `scripts/tests/plugins/hub_data.bats`

## Contract readers

- `unseal-watchdog.yaml.tmpl` job log lines (writer: the template). Readers, `grep -rn "unseal attempt complete\|replaying shard\|unseal succeeded" scripts bin` (2026-11-16): only `scripts/tests/etc/vault_unseal_watchdog.bats` (asserts `replaying shard`, absence of the shard text); no sensor, alert or dashboard reads the log text. Existing lines stay; new lines are added.
- Template text asserted by `scripts/tests/etc/vault_unseal_watchdog.bats` ("inline shell vars survived envsubst", `vault operator unseal`, `$(cat "$SHARD_FILE")`) and `scripts/tests/lib/hostinger_vault_watchdog_acceptance.bats:210-240` (schedule, TTL, history, namespace): unchanged by Stage 1.
- `vault-unseal` Secret writer `vault.sh:1764-1765`; readers `vault.sh:348`, `:395`, `:588`, the watchdog mount; Stage 1 changes none, Stage 2 adds a second writer (`_hub_data_repoint_vault`).
- `vault_install_unseal_watchdog` callers: `grep -rn vault_install_unseal_watchdog scripts bin` (run by the worker; `scripts/lib/providers/k3s-hostinger.sh` is one); the new guard only fires when `envsubst` is absent.

## Acceptance

```yaml
must:
  - id: M1
    text: "When vault operator unseal fails, the watchdog job log shows the exit code and the Vault error lines (for example the 'invalid key' reason), so a bad shard can be told from a network error."
  - id: M2
    text: "vault_install_unseal_watchdog without envsubst on PATH fails with a message that names envsubst and applies nothing."
  - id: M3
    text: "The existing watchdog behaviour tests (retry, unreachable skip, already unsealed, success, shard never logged) still pass."
  - id: M4
    text: "The shard value never appears in watchdog output, even when the stub vault echoes it inside its error text."
must_not:
  - id: N1
    text: "The failed unseal is not swallowed: with a stub vault that exits 2 with the captured error text, the log must not be limited to 'still sealed or unreachable' — red today (today it prints only that line)."
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: bats scripts/tests/etc/vault_unseal_watchdog.bats
    intent: "You will see a bats test run the rendered watchdog script with a stub vault that rejects the shard exactly as the real Vault 1.20.1 did (rc 2, the 'invalid key' error on stderr), and show the job log now carries the rc and the error lines; it fails on today's template."
  - id: E2
    proves: [M4]
    kind: offline
    command: bats scripts/tests/etc/vault_unseal_watchdog.bats
    intent: "You will see the same test make the stub vault echo the shard inside its error and show the shard text is still absent from the log, with a positive control showing the shard would appear if the filter were removed."
  - id: E3
    proves: [M2]
    kind: offline
    command: bats scripts/tests/plugins/vault_unseal_watchdog_context.bats
    intent: "You will see a bats test run vault_install_unseal_watchdog with envsubst hidden from PATH and see a message naming envsubst and no kubectl apply call; it fails on today's code, which applies an empty file."
  - id: E4
    proves: [M3]
    kind: offline
    command: bats scripts/tests/etc/vault_unseal_watchdog.bats scripts/tests/lib/hostinger_vault_watchdog_acceptance.bats scripts/tests/lib/hostinger_vault_unseal_watchdog.bats
    intent: "You will see the existing watchdog test suites pass unchanged."
  - id: E0
    proves: []
    kind: live
    command: "operator, M5 local terminal, login Keychain unlocked, prints hashes only (see Operator decisions in the report); Claude records the two 12-character prefixes"
    intent: "You compare a fingerprint of the Keychain unseal shard with the cluster Secret's fingerprint, without either secret being shown, to tell us whether the Secret is stale."
  - id: E5
    proves: [M1]
    kind: live
    command: "Claude, M5 hub, operator present to unseal by hand if needed: after promote, delete secrets/vault-0, read the next watchdog job log"
    intent: "After the fix, a real Vault restart shows in the watchdog log whether the shard was accepted or why it was refused, with no shard value printed (host, time, Vault version)."
interface:
  - "scripts/etc/vault/unseal-watchdog.yaml.tmpl (rendered CronJob command block)"
  - "scripts/plugins/vault.sh: vault_install_unseal_watchdog [ns] [context]"
mutants:
  - "m1: restore '>/dev/null 2>&1 || true' on the unseal line — E1 red"
  - "m2: remove the grep -F -v filter — E2 red"
  - "m3: delete the envsubst guard — E3 red"
```

Test notes for the worker: stub `vault operator unseal` to print, on stderr, exactly the captured text
(`Error unsealing: Error making API request.` / blank / `URL: PUT http://127.0.0.1:8200/v1/sys/unseal` / `Code: 400. Errors:` / blank /
`* unable to retrieve stored keys: invalid key: failed to decrypt keys from storage: error decrypting seal wrapped value` /
`error decrypting using seal shamir: cipher: message authentication failed`) and exit 2; put a comment above it:
`# captured 2026-11-16, M4, hashicorp/vault:1.20.1 (file storage, random key); rc=2, stderr only`. Assert the fixture first
(the PATH `vault` is the stub, `SHARD_FILE` is the temp file) before the negative checks.

## Worker definition of done

- Stage 1 only. Change only the template, the one `vault.sh` line, and the named test files. Show E1-E3 red on today's code,
  then green; apply m1-m3 and paste the red runs; run the E4 suites and `make test`. Paste command, rc and proving lines.
  Never print a shard. Leave changes uncommitted; Claude reviews and lands. Never touch a live cluster.

**Intent approved:** operator, 2026-11-16
**Approval note:** ("Approve all 9") — stage 1 only; E0 fingerprint deferred to live verify
