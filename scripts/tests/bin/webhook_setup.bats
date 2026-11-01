#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR}/webhook-setup.XXXXXX")"
  export HOME="$WORK/home" PATH="$WORK/stub:/usr/bin:/bin"
  mkdir -p "$HOME/Library/LaunchAgents" "$WORK/stub"
  cat > "$WORK/stub/security" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat > "$WORK/stub/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$WORK/stub/security" "$WORK/stub/gh"
  [[ "$HOME" == "$WORK/home" && "$(command -v security)" == "$WORK/stub/security" ]]
}

teardown() { rm -rf "$WORK"; }

@test "webhook setup: preserves Slack values without printing them" {
  plist="$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  python3 - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'EnvironmentVariables': {'SLACK_BOT_TOKEN': 'xoxb-QZ7K-fixture-secret-token', 'SLACK_CHANNEL_ID': 'C123', 'K3DM_STATUS_CHANNEL_ID': 'C456'}}, f)
PY
  run env K3DM_AGENT_LOAD=0 K3DM_PYTHON3_PATH=/bin/sh "$REPO/bin/k3dm-webhook-setup"
  [ "$status" -eq 0 ]
  [[ "$output" != *xoxb-QZ7K-fixture-secret-token* ]]
  [[ "$output" != *xoxb-QZ7* ]]
  [[ "$output" != *QZ7K* ]]
  python3 - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: env = plistlib.load(f)['EnvironmentVariables']
assert env['SLACK_BOT_TOKEN'] == 'xoxb-QZ7K-fixture-secret-token'
assert env['SLACK_CHANNEL_ID'] == 'C123'
assert env['K3DM_STATUS_CHANNEL_ID'] == 'C456'
PY
}
