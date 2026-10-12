#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

bats_require_minimum_version 1.5.0

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"
  unset COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
}

@test "_copilot_auth_check passes when COPILOT_GITHUB_TOKEN is set" {
  export COPILOT_GITHUB_TOKEN=test_token
  run _copilot_auth_check
  [ "$status" -eq 0 ]
}

@test "_copilot_auth_check passes when GH_TOKEN is set" {
  export GH_TOKEN=test_token
  run _copilot_auth_check
  [ "$status" -eq 0 ]
}

@test "_copilot_auth_check passes when GITHUB_TOKEN is set" {
  export GITHUB_TOKEN=test_token
  run _copilot_auth_check
  [ "$status" -eq 0 ]
}

@test "_copilot_auth_check passes when apps.json has oauth_token" {
  mkdir -p "$BATS_TEST_TMPDIR/.config/github-copilot"
  printf '{"github.com":{"oauth_token":"test"}}\n' \
    > "$BATS_TEST_TMPDIR/.config/github-copilot/apps.json"
  HOME="$BATS_TEST_TMPDIR" run _copilot_auth_check
  [ "$status" -eq 0 ]
}

@test "_copilot_auth_check passes when gh auth status succeeds" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" HOME="$BATS_TEST_TMPDIR" run _copilot_auth_check
  [ "$status" -eq 0 ]
}

@test "_copilot_auth_check fails with clear error when no auth available" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" HOME="$BATS_TEST_TMPDIR" run _copilot_auth_check
  [ "$status" -ne 0 ]
  [[ "$output" == *"not authenticated"* ]]
}
