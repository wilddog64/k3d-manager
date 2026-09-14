# Bug: `make alertmanager-secret` stores empty credentials and reports success

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-14
**Status:** FIXED (Claude; BATS)
**Files:** `Makefile`, `scripts/plugins/observability.sh`, `scripts/tests/plugins/alertmanager_config_secret.bats`, `CHANGELOG.md`
**Related:** `docs/bugs/2026-09-14-alertmanager-configsecret-wrong-values-path.md` (exposed this)

## Problem

On 2026-09-14 the user ran `make alertmanager-secret` through Claude Code's `! <command>` prefix. That has no interactive stdin, so all three `read -r -p` prompts got EOF and empty strings. The target never checks, POSTs `{"gmail_from":"","gmail_app_pw":"","sms_gateway":""}` to Vault and prints `Credentials stored in Vault`.

`deploy_observability` then rendered `alertmanager-smtp-secret` with an empty `smtp_from`, `smtp_auth_password` and `to`. Once `de83d01f` pointed the Alertmanager CR at that secret, prometheus-operator rejected it on every sync:

```
provision alertmanager configuration: failed to initialize from secret: missing to address in email config
```

The running Alertmanager keeps its previous generated config, so this is not an outage, but SMS alerting stays off and the operator stays in an error loop.

## Fix

### S1 — `Makefile` `alertmanager-secret`: reject empty input before the Vault POST

After the three `read` lines:

```make
	if [ -z "$$_gmail" ] || [ -z "$$_pw" ] || [ -z "$$_sms" ]; then \
	  echo "[alertmanager-secret] ERROR: all three values are required (run in an interactive terminal)" >&2; exit 1; \
	fi; \
```

### S2 — `scripts/plugins/observability.sh`: treat empty Vault values as absent (hub and ACG paths)

Old:

```bash
        print(d['gmail_from']+'|'+d['gmail_app_pw']+'|'+d['sms_gateway'])" 2>/dev/null); then
```

New:

```bash
        v=[d['gmail_from'],d['gmail_app_pw'],d['sms_gateway']]; all(v) or sys.exit(1); print('|'.join(v))" 2>/dev/null); then
```

The existing `Alertmanager Vault secret not found — skipping SMS config` warning then fires instead of rendering a broken secret.

### S3 — tests

- Piping empty input into `make alertmanager-secret`, with `kubectl`/`curl` stubbed on `PATH`, exits non-zero and never calls `curl`.
- Both parse lines in `observability.sh` contain `all(v) or sys.exit(1)`.

## Operator recovery

1. User runs `make alertmanager-secret` in a real terminal (not `!`).
2. `make observability` re-renders `alertmanager-smtp-secret`.
3. Verify: the operator log shows no `missing to address` error, and the generated config has routes `null` (Trivy), then `sms-critical`.

## What NOT to Do

- Do NOT print or log credential values.
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
