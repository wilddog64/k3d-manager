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
