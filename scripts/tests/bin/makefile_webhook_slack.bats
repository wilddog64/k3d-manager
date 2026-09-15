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
