# Bug: `show-service-passwords` can leave the Vault root token and ArgoCD password in temp files

**Status:** OPEN — captured 2026-11-18
**Priority:** P2 (plaintext credential left in `$TMPDIR` only when one of three blocks is interrupted or fails mid-way; must be fixed before the travel-bundle LaunchAgent runs the target every 15 minutes)
**Introduced by:** v1.43.5 (`401e4eca`, squash merge #148)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-18 (spec written; Fable + Astra blind review, then intent approval)
**Prior art:** `docs/bugs/2026-09-21-show-service-passwords-keycloak-block-defeats-redaction.md` (slug match, no score; `find-similar-docs` not run: the vector store is on the hub) — read, different root cause
**Found by:** Luna (Codex), stopping the `v1.45.0-service-password-travel-bundle` dispatch on 2026-11-18 because its spec forbade plaintext in `TMPDIR`.

## Symptom

`make show-service-passwords` (`Makefile:1038`) has two shell blocks. The first creates `_vault_hdr` with `mktemp`
and removes it with `trap 'rm -f "$$_vault_hdr"' EXIT`. The second block (`Makefile:1056-1076`) creates four more
`mktemp` files: `_vault_hdr` (the Vault root token as an `X-Vault-Token:` header), `_argocd_vault_file` and
`_argocd_initial_file` (ArgoCD admin password candidates in plaintext) and `_argocd_payload` (a JSON login body that
holds the password). It removes them with a plain `rm -f` (`:1076`), with no `trap`. The next two blocks do the same with the Vault
root token alone: `_vault_hdr` created at `:1084` and `:1095`, removed by a plain `rm -f` at `:1088` and `:1100`.

If one of those blocks is interrupted (Ctrl-C, a killed LaunchAgent, a timeout) before the `rm -f` line, the files stay in
`$TMPDIR`, readable by the operator account, until macOS cleans the temp directory.

## Why it matters now

Today the target only runs when the operator types it. The travel-bundle plan (`docs/plans/v1.45.0-service-password-travel-bundle.md`,
B3/B4) runs it from a LaunchAgent every 15 minutes, about 96 times a day, so an interrupted run becomes far more likely.

## Fix direction (not yet specced)

Smallest: a `trap 'rm -f …' EXIT` in each of the three blocks, like the first block's. Better: keep the token and
passwords in memory (`curl -H @-` from stdin, `jq --arg` instead of `--rawfile`) so nothing reaches disk. The output
of the target must not change.

## Workaround

None needed for manual runs beyond not interrupting them; do not run `make password-bundle-install` until this is fixed.

## Fix (operator chose option A, 2026-11-18: "let's do what you recommended")

Keep the Vault root token and the ArgoCD candidate passwords in shell variables and hand them to `curl` and `jq` on
stdin only. The target then calls `mktemp` nowhere and writes no secret to any file, so an interrupted or killed run
(including `SIGKILL`, which no `trap` can catch) leaves nothing behind. The fix direction above suggested
`jq --arg`; that is rejected: it puts the password in `jq`'s argv, visible to `ps`. Stdin is used instead.

Option B (a `trap` per block) was rejected because launchd's timeout and `kill -9` skip traps.

### External behaviour (proof, rule: prove external behaviour)

Live probe, m4-air, 2026-11-18T23:58Z, curl 8.7.1 (the hub m5-air runs the same curl 8.7.1, jq-1.7.1-apple, macOS
26.5.1; checked over ssh the same minute). A local HTTP listener received:
- `printf 'X-Vault-Token: %s\n' tok-123 | curl -sf -H @- URL` → header `X-Vault-Token: tok-123`, HTTP 200.
- `printf '%s' 'p@ss "w\ord' | jq -Rs '{username:"admin",password:(.|rtrimstr("\n"))}' | curl ... --data @- URL` → body
  `{"username":"admin","password":"p@ss \"w\\ord"}` (newlines stripped by `--data`, exactly as `--data @file` does
  today), HTTP 200.

`SHELL := /bin/bash` (`Makefile:16`) and no `.SHELLFLAGS`, so `printf` is the bash builtin (no argv exposure) and a
`printf ... | curl` pipe exits with `curl`'s status, as the file form does today.

### Change (`Makefile`, target `show-service-passwords` only, lines 1057-1120 at `12a14c9d`)

1. **Liveness gate (`:1058-1070`).** Delete `_vault_hdr=$$(mktemp); trap 'rm -f "$$_vault_hdr"' EXIT; printf ... > "$$_vault_hdr"; \`.
   Both `lookup-self` probes (`:1061`, `:1067`) become
   `printf 'X-Vault-Token: %s\n' "$$_vault_tok" | curl -sf -H @- "http://127.0.0.1:18200/v1/auth/token/lookup-self" -o /dev/null 2>/dev/null`.
   The retry loop, port-forward restart and error messages stay as they are.
2. **ArgoCD block (`:1074-1100`).** Delete the four `mktemp` lines and the `rm -f` line (`:1095`). Then:
   ```make
   	_argocd_vault_pw=$$(printf 'X-Vault-Token: %s\n' "$$_vault_tok" | curl -sf -H @- \
   	  "http://127.0.0.1:18200/v1/secret/data/argocd/admin" 2>/dev/null | \
   	  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"].get("password",""))' 2>/dev/null || true); \
   	_argocd_initial_pw=$$(kubectl get secret argocd-initial-admin-secret -n cicd \
   	  --context k3d-k3d-cluster -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true); \
   ```
   In the candidate loop, `_argocd_candidate_file` becomes `_argocd_candidate_pw` (set from the two variables),
   `[ -s "$$_argocd_candidate_file" ]` becomes `[ -n "$$_argocd_candidate_pw" ]`, and the payload and login become one pipe:
   ```make
   	    _argocd_code=$$(printf '%s' "$$_argocd_candidate_pw" | jq -Rs '{username:"admin",password:(.|rtrimstr("\n"))}' | curl -s -o /dev/null -w '%{http_code}' -H 'User-Agent: k3dm-show-service-passwords/1' -H 'Content-Type: application/json' --data @- "$$_argocd_url/api/v1/session" || true); \
   ```
   On 200, `_argocd="$$_argocd_candidate_pw"`. The fallback after the loop becomes
   `if [ -z "$$_argocd" ]; then _argocd="$$_argocd_vault_pw"; [ -n "$$_argocd" ] || _argocd="$$_argocd_initial_pw"; fi`.
   The echo lines and both `note:` conditions are unchanged.
3. **Grafana (`:1101-1107`) and Prometheus (`:1112-1119`) blocks.** Delete the `_vault_hdr=$$(mktemp); printf ... >` line
   and the `rm -f "$$_vault_hdr"` line; each `curl -sf -H "@$$_vault_hdr"` becomes
   `printf 'X-Vault-Token: %s\n' "$$_vault_tok" | curl -sf -H @-`.

**One intended difference.** When Vault `secret/argocd/admin` exists but has no `password` key, `python3` prints an empty
line. Today the file is then 1 byte, `-s` passes, and an empty password is POSTed to ArgoCD (rejected, so the stale note
can appear). After the fix `$(...)` strips the newline, the candidate is empty and skipped, as an empty password should
be. Every other input gives byte-identical output.

### Tests (`scripts/tests/bin/makefile_show_service_passwords.bats`)

- **Stub changes.** The `curl` stub reads stdin when an argument is `-H` followed by `@-` and answers `lookup-self` and
  the Vault reads only if stdin contained `X-Vault-Token: token` (else exit 22, as `curl -f` does on 403). For
  `api/v1/session` it reads the JSON body from stdin when `--data @-` is given (keep the `@file` path so the golden
  fixture can be captured from the pre-fix head). Add a `mktemp` stub that appends to
  `$BATS_TEST_TMPDIR/mktemp-calls` and then runs the real `/usr/bin/mktemp "$@"`, and a `jq` wrapper that appends its
  argv to `$BATS_TEST_TMPDIR/jq-args` and `exec`s the real jq (resolve it before the stub dir goes on `PATH`). Run make
  with `TMPDIR="$BATS_TEST_TMPDIR/tmp"` (created empty; the test asserts it exists and is empty first).
- **New: no temp files** (N1, M1), for each of `stale`, `rotated`, `unreachable`: `mktemp-calls` does not exist and
  `$BATS_TEST_TMPDIR/tmp` is empty after the run.
- **New: secrets only on stdin** (M2, M3), same three modes: `curl-args` and `jq-args` contain none of `token`,
  `vault-pass`, `initial-pass`. Positive control in the same test: the run printed `password: vault-pass` or
  `password: initial-pass` as the mode expects, which the stub only allows when the header and body arrived on stdin.
- **New: output unchanged** (M4): `scripts/tests/fixtures/show-service-passwords/{stale,rotated,unreachable}.txt`,
  captured by running the stubbed target on the pre-fix head `12a14c9d` (header comment: host, date, commit); the
  post-fix output must equal each fixture byte for byte.
- **Replace** "candidate passwords are passed through payload files" (`:101`) with "secrets never reach a file":
  the target text contains no `mktemp`, no `--rawfile`, no `--arg password`, and contains `--data @-` (N2).
- All other tests stay and must pass unchanged.

## Files

- `Makefile` (target `show-service-passwords` only)
- `scripts/tests/bin/makefile_show_service_passwords.bats`
- `scripts/tests/fixtures/show-service-passwords/stale.txt`, `rotated.txt`, `unreachable.txt` (new)

## Contract readers

The target's stdout is the contract, and it does not change.
- `scripts/plugins/password_bundle.sh:80`: reads `make -s show-service-passwords` stdout for the travel bundle. Unchanged.
- `scripts/tests/bin/webhook_make_targets.py:189,217`: refers to the target name only (the webhook refuses it). Unchanged.
- `scripts/etc/machine/not-installed.list:42-43`: says the password bundle stays uninstalled until this bug is fixed.
  Not changed by this fix; the operator decides on the install after live verification.
- Writers: none outside the target.

## What NOT to Do

- Do not touch any other target, the Keycloak or Alertmanager blocks, or the echo/`note:` lines.
- Do not pass a secret as a command argument (`--arg`, `-H "X-Vault-Token: ..."`, `-d '{...}'`), and do not write one to
  a file, a here-string or a here-doc (bash backs them with temp files).
- Do not add a `trap`; the point is that nothing needs cleaning up.
- Do not update `memory-bank/`, open a PR, or use `--no-verify`.

## Acceptance

```yaml
must:
  - id: M1
    text: make show-service-passwords never calls mktemp and leaves no file in TMPDIR, in every ArgoCD mode
  - id: M2
    text: the Vault root token reaches curl only on stdin (-H @-), never in any process's argv and never in a file
  - id: M3
    text: each ArgoCD candidate password reaches jq and curl only on stdin, never in argv and never in a file
  - id: M4
    text: the printed output is byte-identical to the pre-fix target for the stale, rotated and unreachable ArgoCD cases
  - id: M5
    text: the Vault liveness gate still probes lookup-self, restarts the port-forward and retries as before
must_not:
  - id: N1
    text: "the target calls mktemp (red today: seven mktemp calls across four blocks)"
  - id: N2
    text: "the target text contains --rawfile or a secret-file redirect (red today: --rawfile password)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2]
    kind: offline
    command: "bats scripts/tests/bin/makefile_show_service_passwords.bats (new tests red on 12a14c9d; fixtures captured there)"
    intent: "Running the password listing never leaves the Vault root token or an ArgoCD password in a temp file, and it prints exactly what it printed before."
  - id: E2
    proves: [M1, M4]
    kind: live
    command: "Claude, on the hub before and after the promote that carries the fix: make -s show-service-passwords | shasum -a 256 (equal unless a password rotated in between; then compare with every password: value masked), and the count of files in $TMPDIR is the same before and after the run"
    intent: "On the hub, the password listing looks the same as before and adds nothing to the temp folder, so the travel bundle can run it every 15 minutes."
interface:
  - "make show-service-passwords stdout: unchanged"
```

**Intent approved:** no
