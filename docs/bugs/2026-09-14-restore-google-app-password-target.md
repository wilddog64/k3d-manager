# Bug: no make target restores the Alertmanager Gmail App Password from Keychain

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** IMPLEMENTED (Claude) — operator acceptance: `make restore-google-app-password`
**Files:** `Makefile`, `CHANGELOG.md`

## Problem

- The Alertmanager `sms-critical` route sends mail through Gmail. The account has 2FA, so the credential has to be a Google App Password (19 characters, including 3 spaces).
- The only Keychain backup is `k3dm-alertmanager-gmail-app-password` (account `$USER`, login keychain).
- If Vault KV `secret/k3d-manager/alertmanager` is lost or rotated, no target restores it from that backup. `make alertmanager-secret` asks for all three values again, and the operator has to retype the password, spaces included.
  - On 2026-09-15 a hand-built command stripped the spaces and caused a Keychain/Vault mismatch.
- `make alertmanager-secret` also does not update Kubernetes. `make observability` has to run afterwards to rebuild `alertmanager-smtp-secret`.

## Fix

### S1 — `Makefile`: new target `restore-google-app-password`

Place it directly after `alertmanager-secret`:

```make
## Restore the Alertmanager Gmail App Password from Keychain into Vault, then rebuild the Alertmanager Secret
restore-google-app-password:
	@_tok=$$(kubectl get secret vault-root -n secrets --context k3d-k3d-cluster \
	  -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d); \
	[ -n "$$_tok" ] || { echo "[restore-google-app-password] ERROR: cannot read Hub Vault root token" >&2; exit 1; }; \
	_pw=$$(security find-generic-password -a "$$USER" -s k3dm-alertmanager-gmail-app-password -w 2>/dev/null); \
	[ -n "$$_pw" ] || { echo "[restore-google-app-password] ERROR: k3dm-alertmanager-gmail-app-password not in Keychain (locked? run: security unlock-keychain)" >&2; exit 1; }; \
	VAULT_TOKEN="$$_tok" GMAIL_PW="$$_pw" python3 -c '<merge script>' && \
	echo "[restore-google-app-password] Vault updated — rebuilding Alertmanager Secret" && \
	$(MAKE) observability
```

The merge script, inline and without single quotes:
1. `GET http://127.0.0.1:18200/v1/secret/data/k3d-manager/alertmanager`, with the `X-Vault-Token` header taken from env.
2. Exit non-zero if `gmail_from` or `sms_gateway` is missing. Point the operator at `make alertmanager-secret`, because without those two fields a restore cannot be complete.
3. Replace only `gmail_app_pw` with `GMAIL_PW`, then `POST {"data": <merged>}`. This creates a new KV v2 version.
4. Never print any field value.

The script uses Python `urllib` rather than a GET/POST pair in curl, so neither the token nor the password appears in any process argv. That follows the CLAUDE.md secret-hygiene rule.

### S2 — `Makefile`: `.PHONY` + help

- Add `restore-google-app-password` to `.PHONY`.
- Add this help line after `alertmanager-secret`:
  `make restore-google-app-password   Restore Gmail App Password from Keychain → Vault → Alertmanager`

### S3 — `CHANGELOG.md`

Under `[Unreleased]` → `### Added`, add: `make restore-google-app-password` restores the Alertmanager Gmail App Password from the Keychain backup into Vault, then runs `make observability`.

## Verification

- `make -n restore-google-app-password` expands without errors.
- Operator-run: `make restore-google-app-password` prints `Vault updated`, then `make observability` completes. The alertmanager logs after the reload show no `Notify attempt failed`.

## What NOT to do

- Do not print, echo or log the password or the token.
- Do not overwrite `gmail_from` or `sms_gateway`.
- Do not modify `alertmanager-secret`.
