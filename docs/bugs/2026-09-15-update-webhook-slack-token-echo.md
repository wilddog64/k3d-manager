# Bug: `make update-webhook-slack` echoes the Slack bot token and ignores Keychain

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-15
**Status:** OPEN — assigned to Codex
**Files:** `Makefile`, `scripts/tests/bin/makefile_webhook_slack.bats` (new), `CHANGELOG.md`

## Problem

`update-webhook-slack` (`Makefile:399-412`) writes `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_ID` into the webhook LaunchAgent plist:

1. **It prints the token.** The `PlistBuddy ... Add :EnvironmentVariables:SLACK_BOT_TOKEN string $(SLACK_BOT_TOKEN)` recipe line has no `@`, so make echoes the full command, token included, to the terminal. `make -n` prints it too.
2. **The token is in argv.** `PlistBuddy -c "Add ... string <token>"` passes the token as a process argument, visible to `ps`. This breaks the CLAUDE.md secret-hygiene rule.
3. **It ignores Keychain.** It only reads `SLACK_BOT_TOKEN`/`SLACK_CHANNEL_ID` from the environment and fails with `ERROR: SLACK_BOT_TOKEN not set — export it first`. The working bot token lives in Keychain `k3d-manager-slack-bot-token-bot`. Exporting it into the shell to satisfy the target triggers problems 1 and 2.
4. **It needlessly requires `SLACK_CHANNEL_ID`,** even though the plist already holds the correct value.
5. **It keeps no backup** of the plist before overwriting it.

On 2026-09-15, deleting the old "k3dm" Slack app revoked the plist token (`account_inactive`). The recovery had to use a hand-written plistlib script instead of this target.

## Fix

### S1 — `Makefile`: replace the `update-webhook-slack` target

Replace lines 399-412 (the `## Inject SLACK_BOT_TOKEN ...` comment through the final `@echo`) **exactly** with:

```make
## Inject SLACK_BOT_TOKEN (Keychain k3d-manager-slack-bot-token-bot) and SLACK_CHANNEL_ID into the webhook LaunchAgent plist and restart
update-webhook-slack:
	@_tok="$${SLACK_BOT_TOKEN:-$$(security find-generic-password -s k3d-manager-slack-bot-token-bot -w 2>/dev/null)}"; \
	[ -n "$$_tok" ] || { echo "[update-webhook-slack] ERROR: k3d-manager-slack-bot-token-bot not in Keychain (locked? run: security unlock-keychain)" >&2; exit 1; }; \
	_plist="$(HOME)/Library/LaunchAgents/com.k3d-manager.webhook.plist"; \
	[ -f "$$_plist" ] || { echo "[update-webhook-slack] ERROR: $$_plist not found — run: make setup-worker" >&2; exit 1; }; \
	cp -p "$$_plist" "$$_plist.bak-$$(date +%Y%m%d%H%M%S)"; \
	SLACK_TOK="$$_tok" SLACK_CHAN="$${SLACK_CHANNEL_ID:-}" PLIST="$$_plist" python3 -c 'import os,plistlib,sys; p=os.environ["PLIST"]; d=plistlib.load(open(p,"rb")); e=d.setdefault("EnvironmentVariables",{}); c=os.environ["SLACK_CHAN"] or e.get("SLACK_CHANNEL_ID",""); c or sys.exit("[update-webhook-slack] ERROR: SLACK_CHANNEL_ID not set and not in plist - export SLACK_CHANNEL_ID first"); e["SLACK_BOT_TOKEN"]=os.environ["SLACK_TOK"]; e["SLACK_CHANNEL_ID"]=c; plistlib.dump(d,open(p,"wb")); print("[update-webhook-slack] plist updated (SLACK_BOT_TOKEN, SLACK_CHANNEL_ID)")'
	@$(MAKE) --no-print-directory restart-webhook
	@echo "[update-webhook-slack] webhook restarted"
```

Rules for the new recipe:
- The first recipe line is `@`-prefixed. Everything up to the python call is one shell (`; \` continuations), so no line is echoed.
- The token reaches python only through the `SLACK_TOK` env var, never argv, and is never printed.
- Token source: an exported `SLACK_BOT_TOKEN` if set, otherwise Keychain `k3d-manager-slack-bot-token-bot`.
- Channel source: an exported `SLACK_CHANNEL_ID` if set, otherwise the existing plist value. Fail only if neither exists.
- The python one-liner contains **no single quotes** (it is wrapped in `'...'`) and **no `$`**.
- Do not change `.PHONY`; `update-webhook-slack` is already listed.

### S2 — `scripts/tests/bin/makefile_webhook_slack.bats` (new)

Static assertions against the Makefile only (no Keychain, no launchctl), in the style of `scripts/tests/bin/makefile_platform_ops.bats`. Assert meaningful tokens, never a whole source line with `grep -F`. Do not use a bare `!`.

```bash
#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

_target() {
  awk '/^update-webhook-slack:/{f=1} f&&/^$/{exit} f' "${MAKEFILE}"
}

@test "update-webhook-slack reads the bot token from Keychain" {
  run _target
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'security find-generic-password -s k3d-manager-slack-bot-token-bot -w'* ]]
}

@test "update-webhook-slack no longer passes the token to PlistBuddy argv" {
  run _target
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'PlistBuddy'* ]]
  [[ "${output}" != *'$(SLACK_BOT_TOKEN)'* ]]
}

@test "update-webhook-slack hands the token to python via env" {
  run _target
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'SLACK_TOK="$$_tok"'* ]]
  [[ "${output}" == *'plistlib'* ]]
}

@test "update-webhook-slack recipe commands are all @-silenced" {
  run awk '/^update-webhook-slack:/{f=1;next} f&&/^$/{exit} f{ if (!c && $0 !~ /^\t@/) b++; c=($0 ~ /\\$/) } END{print b+0}' "${MAKEFILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "update-webhook-slack backs up the plist before writing" {
  run _target
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'cp -p "$$_plist" "$$_plist.bak-'* ]]
}

@test "make -n update-webhook-slack does not expand an exported token" {
  run env SLACK_BOT_TOKEN=xoxb-SENTINEL-DO-NOT-PRINT make -n -f "${MAKEFILE}" update-webhook-slack
  [[ "${output}" != *'xoxb-SENTINEL-DO-NOT-PRINT'* ]]
}
```

The "silenced" test counts recipe commands (lines not continuing a previous `\`-terminated line) that do not start with a tab + `@`; it must print `0`.

### S3 — `CHANGELOG.md`

Under `## [Unreleased]` → `### Fixed` (create the `### Fixed` heading directly after the `### Added` block of `[Unreleased]` if it does not exist; do not use a `### Fixed` from a released version), add:

- `make update-webhook-slack` no longer prints the Slack bot token or passes it in argv: it reads the token from Keychain `k3d-manager-slack-bot-token-bot` (or an exported `SLACK_BOT_TOKEN`), keeps the plist's existing `SLACK_CHANNEL_ID` unless one is exported, backs up the plist, and writes it via Python `plistlib` with the token in env

## Verification

- `bats scripts/tests/bin/makefile_webhook_slack.bats` — all pass.
- `bats scripts/tests/bin/makefile_platform_ops.bats` — still passes.
- `make -n update-webhook-slack` expands without error and shows no token.
- Operator acceptance (the user runs this; agents do NOT): `make update-webhook-slack` prints only the `[update-webhook-slack]` lines, then `auth.test` on the plist token returns ok.

## What NOT to do

- Do NOT run `make update-webhook-slack`, `make restart-webhook`, `launchctl`, or any `security ... -w` read. No live plist or Keychain access.
- Do NOT print, echo or log any token value.
- Do NOT modify `update-webhook-slack-secret` or `update-webhook-slack-roles` (they have a similar argv pattern; out of scope, possible follow-up).
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT `git add -A`; stage only the three files listed above.
