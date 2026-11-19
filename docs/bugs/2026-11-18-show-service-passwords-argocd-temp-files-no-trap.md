# Bug: `show-service-passwords` can leave the Vault root token and ArgoCD password in temp files

**Status:** LANDED — `51581c60` on `k3d-manager-v1.45.0` 2026-11-18 (Luna, 3 resumes; Claude verified: N1/N2 red on `12a14c9d`, 20/20 green, retry-probe and jq-argv mutants red); captured 2026-11-18
**Priority:** P2 (plaintext credential left in `$TMPDIR` only when one of three blocks is interrupted or fails mid-way; must be fixed before the travel-bundle LaunchAgent runs the target every 15 minutes)
**Introduced by:** v1.43.5 (`401e4eca`, squash merge #148)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-18 (E2 pre-promote baseline on the hub at `ebac0d8c`: rc 0, 31 lines, sha256 `08c95af9291bd9db…`, masked `4ffa096f3f528f11…`, TMPDIR entries 60→60)
**Prior art:** `docs/bugs/2026-09-21-show-service-passwords-keycloak-block-defeats-redaction.md` (slug match, no score; `find-similar-docs` not run: the vector store is on the hub) — read, different root cause
**Found by:** Luna (Codex), stopping the `v1.45.0-service-password-travel-bundle` dispatch on 2026-11-18 because its spec forbade plaintext in `TMPDIR`.

## Symptom

`make show-service-passwords` (`Makefile:1057` at `12a14c9d`; line refs in this section are from the filing commit) has two shell blocks. The first creates `_vault_hdr` with `mktemp`
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

0. **Every credential-bearing `curl` call** (the Vault reads and the ArgoCD session POST) gets `-q` as its **first**
   argument, so an operator's `~/.curlrc` (for example `trace-ascii`) cannot record the header or body.
1. **Liveness gate (`:1058-1070`).** Delete `_vault_hdr=$$(mktemp); trap 'rm -f "$$_vault_hdr"' EXIT; printf ... > "$$_vault_hdr"; \`.
   Both `lookup-self` probes (`:1061`, `:1067`) become
   `printf 'X-Vault-Token: %s\n' "$$_vault_tok" | curl -q -sf -H @- "http://127.0.0.1:18200/v1/auth/token/lookup-self" -o /dev/null 2>/dev/null`.
   The retry loop, port-forward restart and error messages stay as they are.
2. **ArgoCD block (`:1074-1100`).** The four `mktemp` calls sit on two lines, `:1076-1077` (the first also writes the
   header file); delete both lines and the `rm -f` line (`:1095`), keeping the Vault read that follows. Then:
   ```make
   	_argocd_vault_pw=$$(printf 'X-Vault-Token: %s\n' "$$_vault_tok" | curl -q -sf -H @- \
   	  "http://127.0.0.1:18200/v1/secret/data/argocd/admin" 2>/dev/null | \
   	  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["data"].get("password",""))' 2>/dev/null || true); \
   	_argocd_initial_pw=$$(kubectl get secret argocd-initial-admin-secret -n cicd \
   	  --context k3d-k3d-cluster -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true); \
   ```
   In the candidate loop, `_argocd_candidate_file` becomes `_argocd_candidate_pw` (set from the two variables),
   `[ -s "$$_argocd_candidate_file" ]` becomes `[ -n "$$_argocd_candidate_pw" ]`, and the payload and login become one pipe:
   ```make
   	    _argocd_code=$$(printf '%s' "$$_argocd_candidate_pw" | jq -Rs '{username:"admin",password:(.|rtrimstr("\n"))}' | curl -q -s -o /dev/null -w '%{http_code}' -H 'User-Agent: k3dm-show-service-passwords/1' -H 'Content-Type: application/json' --data @- "$$_argocd_url/api/v1/session" || true); \
   ```
   On 200, `_argocd="$$_argocd_candidate_pw"`. The fallback after the loop becomes
   `if [ -z "$$_argocd" ]; then _argocd="$$_argocd_vault_pw"; [ -n "$$_argocd" ] || _argocd="$$_argocd_initial_pw"; fi`.
   The echo lines and both `note:` conditions are unchanged.
3. **Grafana (`:1101-1111`) and Prometheus (`:1112-1119`) blocks.** Delete the `_vault_hdr=$$(mktemp); printf ... >` line
   and the `rm -f "$$_vault_hdr"` line; each `curl -sf -H "@$$_vault_hdr"` becomes
   `printf 'X-Vault-Token: %s\n' "$$_vault_tok" | curl -q -sf -H @-`.

**Intended differences (accepted, reviewers 2026-11-18).** `$(...)` strips every trailing newline and drops NUL bytes,
where the file form kept them and `rtrimstr` removed one newline. So:
- a Vault `secret/argocd/admin` with no `password` key, or `password: ""`, is today a 1-byte file that passes `-s` and
  POSTs an empty password; after the fix the candidate is empty and skipped;
- a candidate password that ends in a newline or contains a NUL byte is POSTed differently.
ArgoCD and Vault passwords here are generated alphanumeric strings, so neither case occurs in practice. For every other
input the output is byte-identical.

### Tests (`scripts/tests/bin/makefile_show_service_passwords.bats`)

**Harness (all tests).**
- **Scratch `HOME` and `TMPDIR`, asserted first.** `run_show_service_passwords` sets `HOME="$BATS_TEST_TMPDIR/home"` and
  `TMPDIR="$BATS_TEST_TMPDIR/tmp"` (both created empty) and asserts both are under `$BATS_TEST_TMPDIR` and empty before make
  runs. Otherwise the Alertmanager block (`Makefile:1126`) reads the real
  `~/.local/share/k3d-manager/alertmanager-basic-auth.env` into the output and the fixtures.
- **No real install.** Make runs with `MAKE="$bin/fake-make"`, a stub that appends its argv to
  `$BATS_TEST_TMPDIR/fake-make-calls` and exits 0. The liveness gate's `$(MAKE) install-vault-port-forward` then never
  writes `~/Library/LaunchAgents` or calls `bin/launchd-reload`, on pre-fix or post-fix code.
- **Distinctive token.** The `kubectl` stub returns base64 of `s3cr3t-root-tok` for `vault-root`. The test asserts on
  that string, never on `token` (the URL `/v1/auth/token/lookup-self` contains `token`).
- **`curl` stub.** It finds the URL as the argument starting with `http`, honours `-o FILE` (it writes the body there,
  or discards it for `/dev/null`, and prints only the `-w` code to stdout), and reads the header from stdin for `-H @-`
  or from the file for `-H @path`. The second form is kept so that the pre-fix head runs through the same stub. Vault
  URLs answer only when the header is exactly `X-Vault-Token: s3cr3t-root-tok`; otherwise the stub exits 22. For
  `api/v1/session` it reads the body from stdin (`--data @-`) or the file (`--data @path`) and appends it, one line per
  request, to `$BATS_TEST_TMPDIR/session-bodies`. Each mode's answer depends on that body, not on call order: `stale`
  answers 401 for `vault-pass` and 200 for `initial-pass`; `rotated` answers 200 for `vault-pass`; `unreachable` answers
  503. Every argv is appended to `curl-args`. A new mode `vault-flaky` makes the first `lookup-self` exit 7 and later ones
  succeed; `vault-down` makes every `lookup-self` exit 7.
- **Call recorders.** A `mktemp` stub appends to `mktemp-calls` and then runs `/usr/bin/mktemp "$@"`. A `jq` wrapper
  appends its argv to `jq-args` and `exec`s the jq found by `command -v jq` before the stub dir goes on `PATH`.
- **Raw stdout.** Make's stdout is written to a file and compared with `cmp`, never through bats `$output`, which strips
  trailing newlines. Make's exit status is checked on its own.

**Tests.**
- **N1, red on `12a14c9d`.** In each of `stale`, `rotated` and `unreachable`: `mktemp-calls` does not exist and the scratch
  `TMPDIR` is still empty after the run.
- **N2, red on `12a14c9d`.** Replaces "candidate passwords are passed through payload files" (`:101`). The target text
  contains none of `mktemp`, `--rawfile`, `--arg password`, `<<<`, `<<` (any here-doc or here-string), or a `>` or `>>`
  redirect to anything other than `/dev/null` or `&2`. It contains `--data @-` and `-H @-`. Positive control in the
  same test: the detector run on a fixture string with `x <<<"$$y"` and one with `printf ... > "$$f"` reports each.
- **M2 and M3, regression guard (green on `12a14c9d` too, which is expected: pre-fix argv held paths, not secrets).** In
  the three modes, `curl-args` and `jq-args` contain none of `s3cr3t-root-tok`, `vault-pass` or `initial-pass`.
- **M3 credentials, exact.** `session-bodies` equals, line for line,
  `{"username":"admin","password":"vault-pass"}` then `{"username":"admin","password":"initial-pass"}` in `stale` mode;
  the first line only in `rotated` mode; both lines in `unreachable` mode. The stub accepts a body only if it is this
  exact JSON, so posting a constant fails.
- **M4.** The fixtures `scripts/tests/fixtures/show-service-passwords/{stale,rotated,unreachable}.out` hold raw stdout
  only, captured with this harness on `12a14c9d`. Provenance (host, date, commit, command) goes in a sibling
  `README.md`, never inside the fixture. Post-fix stdout must `cmp` equal to each, and make exits 0.
- **M5.** In `vault-flaky` mode make exits 0, `fake-make-calls` contains `install-vault-port-forward` once, and stdout
  equals the `rotated` fixture. In `vault-down` mode make exits non-zero and stderr carries the existing
  `ERROR: Vault unreachable at 127.0.0.1:18200` error text (`Makefile:1068`). The `vault-flaky` test is red if the retry probe is not fed the header (`-H @-` without `printf |`).
- All other existing tests stay and must pass unchanged.

## Files

- `Makefile` (target `show-service-passwords` only)
- `scripts/tests/bin/makefile_show_service_passwords.bats`
- `scripts/tests/fixtures/show-service-passwords/stale.out` (new)
- `scripts/tests/fixtures/show-service-passwords/rotated.out` (new)
- `scripts/tests/fixtures/show-service-passwords/unreachable.out` (new)
- `scripts/tests/fixtures/show-service-passwords/README.md` (new)

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
- Do not add `set -x` or any trace output to the target.
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
    text: "the target text contains --rawfile, --arg password, a here-doc or here-string, or a > redirect other than /dev/null or &2 (red today: --rawfile password and > \"$$_vault_hdr\")"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2]
    kind: offline
    command: "bats scripts/tests/bin/makefile_show_service_passwords.bats; N1 and N2 red on 12a14c9d with the same harness (scratch HOME, fake MAKE), M2/M3 argv guard green on both; fixtures captured on 12a14c9d"
    intent: "Running the password listing never leaves the Vault root token or an ArgoCD password in a temp file, and it prints exactly what it printed before."
  - id: E2
    proves: [M4]
    kind: live
    command: "Claude, on the hub before and after the promote that carries the fix: make -s show-service-passwords > out; echo rc; shasum -a 256 out; rm out (both rc 0; hashes equal unless a password rotated in between, then compare with every password: value masked). M1 is proven offline; an equal $TMPDIR count is recorded only as a sanity check, since the pre-fix normal path also cleans up"
    intent: "On the hub, the password listing looks the same as before and adds nothing to the temp folder, so the travel bundle can run it every 15 minutes."
interface:
  - "make show-service-passwords stdout: unchanged"
```

## Spec review (Fable + Astra blind, 2026-11-18; Claude checked each finding against the code)

Both reviewers found the same three test-plan defects: the `token` substring ban fails on the URL; fixtures inherited
the real `HOME` (the Alertmanager password); a pre-fix run through the new stub would run the real
`install-vault-port-forward`. Fable also found that M5 had no behavioural test, that the claim "the new tests are red
pre-fix" was false for the argv test, and that the here-string ban had no test. Astra also found `.curlrc` exposure
(fixed with `-q`), order-dependent stub answers, the fixture provenance comment breaking byte compare, and that E2 did
not check make's status. Both noted the newline/NUL difference; it is accepted and named. Everything is folded in above;
no finding was refuted.

**Intent approved:** operator, 2026-11-18

Approval note: "approve those two", after Claude quoted the E1 and E2 intents.
