#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${ARGOCD_PLUGIN_SOURCE:-${BATS_TEST_DIRNAME}/../../plugins/argocd.sh}"
  export ARGOCD_CONFIG_DIR="${BATS_TEST_DIRNAME}/../../etc/argocd"
  export SLACK_FIXTURE_KEY_PRESENT=0
}

@test "N1: deploy warns when notification Slack key is absent" {
  _argocd_keychain_value() { :; }
  _argocd_apply_credential_rotator() { :; }
  _kubectl() {
    printf '%s\n' "$*" >> "$KUBECTL_LOG"
    if [[ "$*" == *"get secret platform-ops-notifications"* ]]; then
      if [[ "$SLACK_FIXTURE_KEY_PRESENT" == 1 ]]; then
        printf '{"data":{"slack-incoming-webhook-url":"ZmFrZQ=="}}\n'
      else
        printf '{"data":{"notification-email":""}}\n'
      fi
      return 0
    fi
    return 0
  }
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"platform-ops-notifications has no slack-incoming-webhook-url — system notices will not be sent"* ]]
}

@test "deploy warns when the notification Slack key is empty" {
  _argocd_keychain_value() { :; }
  _argocd_apply_credential_rotator() { :; }
  _kubectl() {
    printf '%s\n' "$*" >> "$KUBECTL_LOG"
    if [[ "$*" == *"get secret platform-ops-notifications"* ]]; then
      printf '{"data":{"slack-incoming-webhook-url":""}}\n'
    fi
    return 0
  }
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"platform-ops-notifications has no slack-incoming-webhook-url — system notices will not be sent"* ]]
}

@test "N2: present Slack URL is never printed or passed to a command" {
  local secret='offline-slack-secret-fixture'
  _argocd_keychain_value() { printf '%s' "$secret"; }
  _argocd_apply_credential_rotator() { :; }
  _kubectl() {
    printf '%s\n' "$*" >> "$KUBECTL_LOG"
    if [[ "$*" == *"get secret platform-ops-notifications"* ]]; then
      printf '{"data":{"slack-incoming-webhook-url":"ZmFrZQ=="}}\n'
    fi
    return 0
  }
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [[ "$output" != *"$secret"* ]]
  [[ "$output" != *"has no slack-incoming-webhook-url"* ]]
  grep -F 'patch secret platform-ops-notifications' "$KUBECTL_LOG"
  run grep -F "$secret" "$KUBECTL_LOG"
  [ "$status" -ne 0 ]
}

@test "sync adds only the Slack key to the existing notification Secret" {
  local secret='offline-slack-secret-fixture'
  local payload="$BATS_TEST_TMPDIR/slack-secret-payload"
  _argocd_keychain_value() { printf '%s' "$secret"; }
  _no_trace() { "$@"; }
  _kubectl() {
    printf '%s\n' "$*" >> "$KUBECTL_LOG"
    if [[ "$*" == *"patch secret"* ]]; then
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == --patch-file=* ]]; then
          cp "${1#--patch-file=}" "$payload"
        fi
        shift
      done
      return 0
    fi
    return 0
  }
  run argocd_sync_notifications_slack_secret platform-ops
  [ "$status" -eq 0 ]
  [[ "$output" != *"$secret"* ]]
  run grep -F "$secret" "$KUBECTL_LOG"
  [ "$status" -ne 0 ]
  grep -F 'patch secret platform-ops-notifications --type=merge' "$KUBECTL_LOG"
  grep -F 'slack-incoming-webhook-url' "$payload"
  [ "$(jq -r '.data["slack-incoming-webhook-url"]' "$payload" | base64 -d)" = "$secret" ]
  [ "$(jq -r '.data | keys | join(",")' "$payload")" = "slack-incoming-webhook-url" ]
  [[ "$(cat "$payload")" != *"$secret"* ]]
  [[ "$output" != *"notification-email"* ]]
}

@test "Keychain sync reports missing record without failing" {
  _argocd_keychain_value() { :; }
  run argocd_sync_notifications_slack_secret platform-ops
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3dm-platform-ops-slack-url not in Keychain"* ]]
}

@test "hub secrets manifest includes the Slack URL record" {
  grep -F 'k3dm-platform-ops-slack-url|k3dm|' "${BATS_TEST_DIRNAME}/../../etc/machine/secrets.hub.list"
}
