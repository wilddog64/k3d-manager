# Bug: Vault tokens and a ServiceAccount JWT passed in `kubectl exec` argv (`test_eso`, `test_vault` login, `bin/get-ldap-password`)

**Status:** OPEN — captured 2026-11-15
**Priority:** P2 (proposed: A02 security-rule violation; tokens visible in process lists on the host and in the pod, and under xtrace; dev/test paths, no known leak)
**Introduced by:** pre-existing
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-16 (Luna, codex)
**Triage:** patch → v1.44.1; Claude's P2 kept over Argon P3 (breaks the CLAUDE.md secrets rule) — operator grooming 2026-11-15 ("Accept as shown")
**Prior art:** exact-slug pass, no match; `find-similar-docs` not run (needs context k3d-k3d-cluster from the M4) — found by the Fable spec review of `2026-11-15-vault-pod-restart-invalidates-token-reviewer-jwt-eso-403.md`, which fixes the `test_vault` root-token sites only

## What is wrong

CLAUDE.md security rules: no Vault tokens in arguments or `kubectl exec` strings (use env or stdin). These sites
still put a token value into the `sh -c` argument (line numbers re-read 2026-11-16 on `k3d-manager-v1.44.1`; the
`test_vault` root-token sites are already fixed by the token-reviewer bug, so the numbers in the first capture were stale):

- `scripts/lib/test.sh:581` (root token read into a plain variable), `:583` (`test_eso` EXIT trap string embeds the
  root token), `:587` (`vault kv put`), `:661` (`_cleanup_eso_test`, `vault kv delete`) — root token.
- `scripts/lib/test.sh:779-783` — ServiceAccount JWT in `vault write auth/kubernetes/login ... jwt=$sa_jwt`; `:786` —
  the Vault token from that login in `VAULT_TOKEN=$vault_token`.
- `bin/get-ldap-password:131-132`, `:137-138`, `:142-143` — `VAULT_TOKEN='$VAULT_TOKEN'` in three `kubectl exec` calls.

Search for other sites (2026-11-16): `grep -rn -E "VAULT_TOKEN=|token=\$|jwt=\$|-token=|X-Vault-Token" scripts bin`
(minus tests and `lib/foundation`). Every other hit already uses stdin (`hub_recovery.sh`, `hub-restore`, `hub_data.sh`,
`vault.sh:221,264`) or a mode-600 curl header file (`shopping_cart.sh`, `observability.sh`, `argocd.sh`, `vault.sh:1194`),
so these three files are the complete set.

## Evidence (Claude, 2026-11-16)

Vault CLI behaviour for `key=-` (Security Rules: external behaviour proved before dispatch). Captured on the M4,
`docker run hashicorp/vault:1.20.1 server -dev` (the hub's version), userpass mount as a stand-in for the Kubernetes
login (same CLI argument parser): `password=-` reads stdin **verbatim**. `printf '%s' pw | vault write ... password=-`
logged in; `printf '%s\n' pw | vault write ... password=-` failed `400 invalid username or password` (the newline is part
of the value). `read -r P; printf %s "$P" | vault write ... password=-` logged in. The same container showed
`read -r VAULT_TOKEN; export VAULT_TOKEN; vault auth list` working on stdin. So the JWT must be stripped of its newline
in the pod before `jwt=-`, never sent as a bare here-string. (`hub_data.sh:191` sends `printf '%s\n' "$jwt"` to `jwt=-`;
whether a Kubernetes-auth JWT tolerates the newline is unproven, and this spec does not touch it.)

## Fix

Same pattern as `_cleanup_vault_test` and `_hub_data_repoint_vault`: the token goes on stdin, the script text is a
constant, values reach it as positional parameters, and every call is wrapped in `_no_trace`.

1. `scripts/lib/test.sh:581`: replace `root_token=$(_kubectl -n "$vault_ns" get secret vault-root -o jsonpath='{.data.root_token}' | base64 -d)` with
   `_no_trace eval 'root_token=$(_kubectl -n "$vault_ns" get secret vault-root -o jsonpath="{.data.root_token}" | base64 -d)'`
   then `_no_trace eval '_VAULT_TEST_ROOT_TOKEN="$root_token"'` (as `test_vault` does at :703-704).
2. `:583`: the trap passes `''` where `'$root_token'` is now:
   `trap "_cleanup_eso_test '$vault_ns' '$vault_release' '$vault_secret_path' '' '$es_ns' '$es_name' '$store_name' '$vault_started'" EXIT TERM`.
3. `:586-587`: replace
   `sh -c "VAULT_TOKEN='$root_token' vault kv put secret/$vault_secret_path $secret_key='$secret_val'"` with
   `_no_trace _kubectl -n "$vault_ns" exec -i "$vault_pod" -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv put "secret/$1" "$2=$3"' sh "$vault_secret_path" "$secret_key" "$secret_val" <<<"$root_token"`.
4. `:649` `local root_token="$4"` becomes `local root_token="${4:-}"`; add under it
   `[[ -n "$root_token" ]] || _no_trace eval 'root_token="${_VAULT_TEST_ROOT_TOKEN:-}"'` (as `:798-799`); add
   `unset _VAULT_TEST_ROOT_TOKEN` as the last line of `_cleanup_eso_test`.
5. `:660-661`: replace `sh -c "VAULT_TOKEN='$root_token' vault kv delete secret/$vault_secret_path" >/dev/null 2>&1 || true` with
   `_no_trace _kubectl -n "$vault_ns" exec -i "$vault_pod" -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv delete "secret/$1"' sh "$vault_secret_path" <<<"$root_token" >/dev/null 2>&1 || true`.
6. `:779-783` (the JWT login): replace the `sa_jwt=...` assignment with
   `_no_trace eval 'sa_jwt=$(_kubectl create token "$sa" -n "$test_ns")'` and the login with
   `vault_token=$(_no_trace _kubectl -n "$vault_ns" exec -i "$vault_pod" -- sh -c 'read -r JWT; printf %s "$JWT" | vault write -field=token auth/kubernetes/login role="$1" jwt=-' sh "$sa" <<<"$sa_jwt")`.
7. `:785-786`: replace `sh -c "VAULT_TOKEN=$vault_token vault kv get -field=${secret_key} secret/${vault_secret_path}"` with
   `value=$(_no_trace _kubectl -n "$vault_ns" exec -i "$vault_pod" -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv get -field="$1" "secret/$2"' sh "$secret_key" "$vault_secret_path" <<<"$vault_token")`.
8. `bin/get-ldap-password:131-132`, `:137-138`, `:142-143`: each `kubectl exec -n "$VAULT_NS" vault-0 -- sh -c "VAULT_TOKEN='$VAULT_TOKEN' vault kv get ... $VAULT_PATH"`
   becomes `kubectl exec -i -n "$VAULT_NS" vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv get -format=json "$1"' sh "$VAULT_PATH" <<<"$VAULT_TOKEN"`
   (the field form uses `-field="$2"` with `sh "$VAULT_PATH" "$FIELD"`; the all-fields form has no flag). Keep each `2>/dev/null`, the `| jq -r '.data.data'` and `exit_code=$?`.
   Also removes the shell-injection path through `$FIELD` and `$VAULT_PATH` (A03). The usage hint at `:157-158` is
   printed text, not a command, and stays.

`_run_command` and `_args_have_sensitive_flag` are not involved (`_kubectl` is called, not `_run_command --token`) and
stay untouched. No lib-foundation change is needed: `_no_trace` and the stdin pattern already exist; do not edit
`scripts/lib/foundation/`. Out of scope: `secret_val` (`swordfish`, not a credential) stays in argv; `hub_data.sh:191` newline.

## Files

- `scripts/lib/test.sh`
- `bin/get-ldap-password`
- `scripts/tests/lib/test_sh_token_argv.bats` (new: `test_eso`, `_cleanup_eso_test`, `test_vault` login block)
- `scripts/tests/bin/get_ldap_password_argv.bats` (new)

## Contract readers

- `scripts/lib/test.sh:583` trap string and `:649` signature — writer/reader of the `_cleanup_eso_test` argument list;
  callers: `grep -rn "_cleanup_eso_test" scripts bin` (2026-11-16) finds only `test.sh:583` and the definition; arg 4 becomes
  `''` and falls back to `_VAULT_TEST_ROOT_TOKEN`.
- `_VAULT_TEST_ROOT_TOKEN` (env var, set at `test.sh:704`, read at `:799`) — `test_eso` becomes a second writer and
  `_cleanup_eso_test` a second reader; each cleanup unsets it; `test_eso` and `test_vault` never run concurrently.
- `scripts/tests/plugins/vault_k8s_auth_config.bats:229-300` (`test_vault` E2) — reader: its stub matches `auth/kubernetes/login`
  and `vault kv get` in `$*` and counts 5 root-token stdin lines; the new argv still contains both strings and the root
  token count stays 5. Must pass unchanged.
- `bin/get-ldap-password` readers: `grep -rn "get-ldap-password" scripts bin Makefile docs` finds docs only
  (`docs/howto/ldap-bulk-user-import.md:355` link); output format (stdout, exit code) is unchanged.
- No other reader or writer of the three call shapes.

## Acceptance

```yaml
must:
  - id: M1
    text: "test_eso and _cleanup_eso_test send the root token to every vault command on stdin and never inside a kubectl argument, the EXIT/TERM trap string or xtrace output."
  - id: M2
    text: "test_vault's Kubernetes-auth login sends the ServiceAccount JWT on stdin with its trailing newline removed (jwt=- fed by printf %s) and the login's Vault token on stdin; neither appears in a kubectl argument or xtrace output."
  - id: M3
    text: "bin/get-ldap-password sends the root token on stdin in all three kubectl exec calls, passes path and field as positional parameters, and prints the same output as before."
  - id: M4
    text: "The existing test_vault E2 test in vault_k8s_auth_config.bats and test_eso's happy path (ClusterSecretStore, ExternalSecret, value check) still pass."
must_not:
  - id: N1
    text: "No kubectl argument or trap string set by test_eso, _cleanup_eso_test or test_vault contains the root token, the JWT or the login token — red today (sites test.sh:583, :587, :661, :783, :786)."
  - id: N2
    text: "No kubectl argument in bin/get-ldap-password contains the root token, or an unquoted username/field/path — red today (lines 131-143)."
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: bats scripts/tests/lib/test_sh_token_argv.bats
    intent: "You will see a bats test run test_eso and its cleanup with a fake root token, record every kubectl argument and the trap text and an xtrace run, and fail if the fake token appears anywhere but stdin, while showing it arrives on stdin for the put and the delete; it fails on today's test.sh, and a planted-leak control shows the capture would notice a leak."
  - id: E2
    proves: [M2, N1]
    kind: offline
    command: bats scripts/tests/lib/test_sh_token_argv.bats
    intent: "You will see a bats test run test_vault's login block with a fake JWT and fake login token, check neither shows up in any kubectl argument or xtrace, and check the pod-side script strips the newline before jwt=- by running that script text with a stub vault that records its stdin bytes; it fails on today's test.sh."
  - id: E3
    proves: [M3, N2]
    kind: offline
    command: bats scripts/tests/bin/get_ldap_password_argv.bats
    intent: "You will see a bats test run bin/get-ldap-password with a stub kubectl and a fake root token for all three output modes, fail if the token is in any argument, and confirm it reaches stdin and the printed output is unchanged; it fails on today's script, and a positive control shows a token in argv is detected."
  - id: E4
    proves: [M4]
    kind: offline
    command: bats scripts/tests/plugins/vault_k8s_auth_config.bats
    intent: "You will see the existing test_vault argv/stdin test still pass unchanged after the edit."
  - id: E5
    proves: [M1, M2]
    kind: live
    command: "operator or Claude, on the M5 hub, after promote: ./scripts/k3d-manager test_eso and test_vault, then ps/kubectl audit not needed — read the printed result lines"
    intent: "After the fix, Claude shows both the ESO test and the Vault test still pass against the real hub Vault 1.20.1 (host, time, version), proving the stdin forms work with the real Vault CLI."
interface:
  - "scripts/lib/test.sh: test_eso, _cleanup_eso_test, test_vault"
  - "bin/get-ldap-password [--field F] [--namespace NS] [--json] <username>"
mutants:
  - "m1: put VAULT_TOKEN='$root_token' back in the test_eso kv put only — E1 red"
  - "m2: put '$root_token' back in the test_eso trap string only — E1 red"
  - "m3: put it back in _cleanup_eso_test's kv delete only — E1 red"
  - "m4: send jwt=$sa_jwt in argv in the test_vault login only — E2 red"
  - "m5: send the JWT to jwt=- with printf '%s\n' (newline kept) — E2 red"
  - "m6: put VAULT_TOKEN='$VAULT_TOKEN' back in the --field call of get-ldap-password only — E3 red"
```

Test notes for the worker: stub `_kubectl` as `vault_k8s_auth_config.bats` does (record `$*`, drain stdin to a log for `exec -i`);
stub `kubectl` on PATH for `get-ldap-password` (stub shape: `get secret ... -o jsonpath` prints base64 of the fake token, as
the hub's `kubectl get secret vault-root` does — read-only capture m5-air.local 2026-11-16, value redacted; `exec` prints
`{"password":"x"}`). For the newline check in E2, extract the constant script text from the `_kubectl` argv the stub recorded
and run it with `sh` against a PATH stub `vault` that writes its stdin to a file; assert the file has no `\n` and equals the JWT.
Assert the fixtures first (stub is the one on PATH; tmp HOME) before the negative checks.

## Worker definition of done

- Change only `scripts/lib/test.sh`, `bin/get-ldap-password` and the two new bats files. Show E1-E3 red on today's code,
  then green; apply each mutant m1-m6 and paste the red run; run `bats scripts/tests/plugins/vault_k8s_auth_config.bats`,
  `bash -n bin/get-ldap-password scripts/lib/test.sh`, `shellcheck` if present, and `make test`. Paste command, rc and
  proving lines. Never print or log a token. Leave changes uncommitted; Claude reviews and lands. Never touch a live cluster.

**Intent approved:** operator, 2026-11-16
**Approval note:** ("Approve all 9")
