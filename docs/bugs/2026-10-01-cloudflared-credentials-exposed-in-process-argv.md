# Cloudflared tunnel credentials and the Vault root token are passed in process argv

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** medium. Any local process can read argv (`ps -ww`, `/proc` on Linux) while the
command runs. The values are the Cloudflare tunnel credentials JSON, `cert.pem` (account-level
tunnel management), and the Vault root token. This violates CLAUDE.md Secret Hygiene: "Vault
tokens must never appear in script arguments".
**Status:** OPEN
**Related:** `2026-10-01-no-standalone-cloudflared-config-render-or-drift-check.md` (queued after
this one; it touches the same Makefile region)

## Observed (code read, 2026-10-01)

### Defect 1 — `make cloudflared-backup` (`Makefile`, target `cloudflared-backup`)

- `security add-generic-password … -w "$$_creds" -U` and `… -w "$$_cert" -U` put both secrets in
  `security`'s argv.
- `curl -H "X-Vault-Token: $$_tok"` puts the Vault **root** token in curl's argv.
- `curl -d "$$(… python3 …)"` puts the whole JSON payload (creds + cert) in curl's argv.

### Defect 2 — `bin/cluster-up`, Keychain → Vault restore (around lines 540–570)

- `python3 -c "…" "${_kc_creds}" "${_kc_cert}"` passes both secrets as python argv.
- `curl -H "X-Vault-Token: ${_vault_tok}"` (the probe GET and the POST) and
  `-d "${_cf_payload}"` put the root token and payload in curl's argv.

### Defect 3 — `bin/cluster-up`, Keychain → file restore (around lines 1810–1830)

- `cert.pem` is multi-line. `security find-generic-password -w` **hex-encodes** a multi-line value
  on read (see memory `reference_security_w_hex_encodes_multiline`), so the restored `cert.pem`
  would be a hex string, not PEM. The credentials JSON is affected too if it contains a newline.
- Both restored files are written with the default umask; they must be `0600`.

## Fix

Touch only `Makefile` (target `cloudflared-backup`), `bin/cluster-up` (the two blocks above), a
new helper file if you need one (see below), the tests, `CHANGELOG.md` (`Security` or `Fixed`
bullet), and this doc (Resolution section, Status FIXED).

### Keychain write without argv

`security` has no stdin flag for `-w`. Use its interactive mode, which reads the command from
**stdin**, so the value is never in any process's argv:

```bash
printf 'add-generic-password -U -a cloudflared -s %s -w %s\n' "$service" "$b64" | security -i
```

- `printf` is a shell builtin, so it does not create an argv either.
- Store the value **base64-encoded on one line** (`base64 | tr -d '\n'`). This avoids quoting and
  newline problems in `security -i` and the hex-encoding on read.
- Check that the write worked: read it back, decode it, and compare it to the source file
  (`cmp`). On a mismatch, error and exit 1. Never print a value.

### Keychain read: one decoder used by every reader

Add one shared function, e.g. `_cloudflared_keychain_read <service>` (put it in
`scripts/lib/cloudflared_keychain.sh`, sourced by `bin/cluster-up`). It prints the decoded value:

1. Read it with `security find-generic-password -a cloudflared -s <service> -w`.
2. **base64** (new format): if it decodes cleanly and the result starts with `{` (creds) or
   `-----BEGIN` (cert), use it.
3. **hex** (legacy multi-line items): if the raw value is only `[0-9a-f]` and even-length, and it
   decodes (`xxd -r -p`) to something that starts with `{` or `-----BEGIN`, use it.
4. Otherwise use the raw value (legacy single-line JSON).
5. Empty or missing → print nothing, return 1.

Both `bin/cluster-up` restore blocks use it. Restored files are created `0600`: `umask 077` in a
subshell, or `install -m 600`.

### Vault calls without argv

- **Token:** `curl -H @<(printf 'X-Vault-Token: %s\n' "$tok")`. curl ≥ 7.55 reads headers from a
  file. Process substitution is a `/dev/fd` path, so the token is not in argv. The Makefile already
  uses `SHELL := /bin/bash`; confirm that before relying on `<( )`.
- **Payload:** build the JSON in python reading **env vars** (not argv), and pipe it to
  `curl --data-binary @-`. Do not use `-d "$payload"`.
- The `cluster-up` probe GET gets the same header treatment.

### Out of scope

- Do not change the Vault path, the Keychain service/account names, the tunnel ID, or any other
  target.
- Do not rotate anything.

## Tests

Add `scripts/tests/bin/cloudflared_secret_argv.bats`. Put stub `security`, `curl`, `kubectl`,
`python3` (only if you must; prefer the real one) on `PATH`. Each stub appends its argv **and**
its stdin to a log. Point `HOME` at `$BATS_TEST_TMPDIR`, with fake `cert.pem` (multi-line) and
creds JSON containing a sentinel string such as `SENTINEL_CREDS_9f3`.

- `make cloudflared-backup`:
  - The sentinel creds, sentinel cert, and sentinel Vault token appear in **no** argv line of any
    stub.
  - The `security` stub receives `add-generic-password` on stdin.
  - curl receives the payload on stdin.
- The decoder: base64 item → original bytes; hex-encoded multi-line item → original PEM; raw
  single-line JSON → unchanged; missing → rc 1 and no output.
- The cluster-up restore path: if the blocks can't be run in isolation, extract each block into a
  function in the new lib and test that function. The restored `cert.pem` is real PEM (starts with
  `-----BEGIN`), its mode is `600`, and no sentinel appears in any argv.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) put `-w "$value"` back in the backup → argv test red;
(b) put `-H "X-Vault-Token: $tok"` back → argv test red;
(c) drop the hex branch from the decoder → hex test red;
(d) drop the `0600` mode → mode test red.

## Rules

- `shellcheck` adds no new warnings on `bin/cluster-up` and the new lib. The new bats file is
  green.
- `make check-doc-links` passes.
- Linux-portable where the code runs on Linux; the Keychain parts are macOS-only by nature, so
  tests stub `security`.
- Never read the real `~/.cloudflared/*.json` or `cert.pem`. Never call the real `security`,
  Vault, or kubectl. No live cluster.

## Operator step after the fix

Run `make cloudflared-backup` once to rewrite both Keychain items in the base64 format. The
operator runs it; agents do not.
