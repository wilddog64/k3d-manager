# Bug: `make update-webhook-slack-secret` puts the signing secret in argv and fails open

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN — assigned to Codex
**Files:** `Makefile`, `scripts/tests/bin/makefile_webhook_slack.bats`, `CHANGELOG.md`
**Follow-up to:** `docs/bugs/2026-09-15-update-webhook-slack-token-echo.md` (fixed `39ecff4d`)

## Problem

`update-webhook-slack-secret` (`Makefile`, the `## Inject SLACK_SIGNING_SECRET from Keychain ...` block) copies Keychain `k3dm-slack-signing-secret` into the webhook LaunchAgent plist:

1. **The secret is in argv.** `PlistBuddy -c "Add :EnvironmentVariables:SLACK_SIGNING_SECRET string $$_sig"` passes the Slack signing secret as a process argument, visible to `ps`. This breaks the CLAUDE.md secret-hygiene rule.
2. **It fails open.** The Keychain read uses `... || (echo "ERROR ..."; exit 1); \`. The `exit 1` only leaves the `( )` subshell, and `;` continues, so with a missing or locked Keychain item the recipe still runs `PlistBuddy Add ... string ` with an **empty** value and restarts the webhook. The webhook then has an empty `SLACK_SIGNING_SECRET`, and Slack signature verification breaks.
3. **It keeps no backup** of the plist before overwriting it.

### Accepted, not changed: `update-webhook-slack-roles`

`update-webhook-slack-roles` passes `K3DM_SLACK_ROLE_MAP` to `security add-generic-password -w "<map>"` in argv. The value is a Slack user-ID → role allowlist, not a credential, and `security` has no non-interactive way to take `-w` from stdin or env. This is accepted; do **not** modify that target.

## Fix

### S1 — `Makefile`: replace the `update-webhook-slack-secret` target

Replace the block from `## Inject SLACK_SIGNING_SECRET from Keychain into the webhook LaunchAgent plist and restart` through `@echo "SLACK_SIGNING_SECRET injected from Keychain — webhook restarted"` **exactly** with:

```make
## Inject SLACK_SIGNING_SECRET (Keychain k3dm-slack-signing-secret) into the webhook LaunchAgent plist and restart
update-webhook-slack-secret:
	@_sig="$$(security find-generic-password -s k3dm-slack-signing-secret -a k3dm -w 2>/dev/null)"; \
	[ -n "$$_sig" ] || { echo "[update-webhook-slack-secret] ERROR: k3dm-slack-signing-secret not in Keychain (locked? run: security unlock-keychain; to add, run: security add-generic-password -s k3dm-slack-signing-secret -a k3dm -w  and paste at the prompt)" >&2; exit 1; }; \
	_plist="$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist"; \
	[ -f "$$_plist" ] || { echo "[update-webhook-slack-secret] ERROR: $$_plist not found — run: make setup-worker" >&2; exit 1; }; \
	cp -p "$$_plist" "$$_plist.bak-$$(date +%Y%m%d%H%M%S)"; \
	SLACK_SIG="$$_sig" PLIST="$$_plist" python3 -c 'import os,plistlib; p=os.environ["PLIST"]; d=plistlib.load(open(p,"rb")); d.setdefault("EnvironmentVariables",{})["SLACK_SIGNING_SECRET"]=os.environ["SLACK_SIG"]; plistlib.dump(d,open(p,"wb")); print("[update-webhook-slack-secret] plist updated (SLACK_SIGNING_SECRET)")'
	@$(MAKE) --no-print-directory restart-webhook
	@echo "[update-webhook-slack-secret] webhook restarted"
```

Rules:
- One `@`-prefixed shell up to the python call; `exit 1` inside `{ ...; }` (not `( )`) so a missing secret stops make before the plist or restart.
- The secret reaches python only via the `SLACK_SIG` env var and is never printed.
- The python one-liner has no single quotes and no `$`.
- Do not change `.PHONY`, `restart-webhook`, `update-webhook-slack`, or `update-webhook-slack-roles`.

### S2 — `scripts/tests/bin/makefile_webhook_slack.bats`: append tests

Append these to the **end** of the existing file (keep the existing six tests and `_target` unchanged). The two behavioural tests run make with `HOME` pointed at a temp dir and **stub** `security` and `launchctl` first on `PATH`; they never touch the real Keychain, LaunchAgents, or launchd.

```bash
_secret_target() {
  awk '/^update-webhook-slack-secret:/{f=1} f&&/^$/{exit} f' "${MAKEFILE}"
}

_secret_stubs() {
  STUB_HOME="${BATS_TEST_TMPDIR}/home"
  STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${STUB_HOME}/Library/LaunchAgents" "${STUB_BIN}"
  printf '#!/bin/sh\necho called >> "%s/launchctl.calls"\nexit 0\n' "${BATS_TEST_TMPDIR}" > "${STUB_BIN}/launchctl"
  chmod +x "${STUB_BIN}/launchctl"
}

@test "update-webhook-slack-secret no longer passes the secret to PlistBuddy argv" {
  run _secret_target
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'PlistBuddy'* ]]
  [[ "${output}" == *'SLACK_SIG="$$_sig"'* ]]
  [[ "${output}" == *'plistlib'* ]]
  [[ "${output}" == *'cp -p "$$_plist" "$$_plist.bak-'* ]]
}

@test "update-webhook-slack-secret recipe commands are all @-silenced" {
  run awk '/^update-webhook-slack-secret:/{f=1;next} f&&/^$/{exit} f{ if (!c && $0 !~ /^\t@/) b++; c=($0 ~ /\\$/) } END{print b+0}' "${MAKEFILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "update-webhook-slack-secret fails closed when the Keychain item is missing" {
  _secret_stubs
  printf '#!/bin/sh\nexit 44\n' > "${STUB_BIN}/security"
  chmod +x "${STUB_BIN}/security"
  printf 'plist-sentinel\n' > "${STUB_HOME}/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  run env HOME="${STUB_HOME}" PATH="${STUB_BIN}:${PATH}" make --no-print-directory -f "${MAKEFILE}" update-webhook-slack-secret
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'not in Keychain'* ]]
  [ "$(cat "${STUB_HOME}/Library/LaunchAgents/com.k3d-manager.webhook.plist")" = "plist-sentinel" ]
  [ -e "${BATS_TEST_TMPDIR}/launchctl.calls" ] && return 1
  return 0
}

@test "update-webhook-slack-secret writes the secret via env without printing it" {
  _secret_stubs
  printf '#!/bin/sh\necho SIGSENTINEL-DO-NOT-PRINT\n' > "${STUB_BIN}/security"
  chmod +x "${STUB_BIN}/security"
  local plist="${STUB_HOME}/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  PLIST="${plist}" python3 -c 'import os,plistlib; plistlib.dump({"Label":"com.k3d-manager.webhook","EnvironmentVariables":{"SLACK_CHANNEL_ID":"C0KEEP"}},open(os.environ["PLIST"],"wb"))'
  run env HOME="${STUB_HOME}" PATH="${STUB_BIN}:${PATH}" make --no-print-directory -f "${MAKEFILE}" update-webhook-slack-secret
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'SIGSENTINEL-DO-NOT-PRINT'* ]]
  [[ "${output}" == *'plist updated (SLACK_SIGNING_SECRET)'* ]]
  run env PLIST="${plist}" python3 -c 'import os,plistlib; e=plistlib.load(open(os.environ["PLIST"],"rb"))["EnvironmentVariables"]; print("MATCH" if e["SLACK_SIGNING_SECRET"]=="SIGSENTINEL-DO-NOT-PRINT" and e["SLACK_CHANNEL_ID"]=="C0KEEP" else "MISMATCH")'
  [ "${output}" = "MATCH" ]
  ls "${plist}".bak-* >/dev/null
  [ -s "${BATS_TEST_TMPDIR}/launchctl.calls" ]
}
```

### S3 — `CHANGELOG.md`

Under `## [Unreleased]` → `### Fixed` (the existing heading in `[Unreleased]`, not a released version's), add directly below the `make update-webhook-slack` entry:

- `make update-webhook-slack-secret` no longer passes the Slack signing secret in argv (PlistBuddy) and now fails closed: a missing or locked Keychain `k3dm-slack-signing-secret` stops before touching the plist, where the old `( ...; exit 1)` subshell let it write an empty secret and restart the webhook; the plist is backed up and written via Python `plistlib` with the secret in env

## Verification

- `bats scripts/tests/bin/makefile_webhook_slack.bats` — all 10 pass.
- `bats scripts/tests/bin/makefile_platform_ops.bats` — still passes.
- `make -n update-webhook-slack-secret` expands without error.
- Operator acceptance (the user runs this; agents do NOT): `make update-webhook-slack-secret` prints only `[update-webhook-slack-secret]` lines plus the `restart-webhook` launchctl lines, and a signed Slack slash command still works.

## What NOT to do

- Do NOT run `make update-webhook-slack-secret`, `make restart-webhook`, the real `launchctl`, or any real `security` command. The BATS tests use PATH stubs and a temp `HOME` only.
- Do NOT print, echo, or log any secret value.
- Do NOT modify `update-webhook-slack`, `update-webhook-slack-roles`, `restart-webhook`, or `.PHONY`.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT `git add -A` or `git stash`; stage only the three files listed above.
