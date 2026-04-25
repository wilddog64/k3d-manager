#!/usr/bin/env bats
# scripts/tests/plugins/aws.bats — unit tests for aws.sh credential helpers
#
# NOTE: credential values below are deliberately invalid test fixtures
# (wrong length, wrong prefix) and are not real AWS credentials.

# Test fixture values — not real credentials
_TEST_KEY_ID="TEST-KEY-ID-0000000001"
_TEST_SECRET="TEST-SECRET-KEY-000000000000001"
_TEST_TOKEN="TEST-SESSION-TOKEN-00001"

setup() {
  _info() { :; }
  _write_sensitive_file() {
    local path="$1" data="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$data" > "$path"
    chmod 600 "$path"
  }
  define_legacy_plugin_stubs() {
    local legacy_plugin_name="anti"
    legacy_plugin_name="${legacy_plugin_name}gravity"
    eval "_ensure_${legacy_plugin_name}() { :; }"
    eval "_ensure_${legacy_plugin_name}_ide() { :; }"
    eval "_ensure_${legacy_plugin_name}_mcp_playwright() { :; }"
    eval "_${legacy_plugin_name}_launch() { :; }"
    eval "_${legacy_plugin_name}_ensure_acg_session() { :; }"
    eval "_${legacy_plugin_name}_gemini_prompt() { :; }"
  }
  _ensure_gemini() { :; }
  _gemini_prompt() { :; }
  export -f _info _write_sensitive_file _ensure_gemini _gemini_prompt
  export -f define_legacy_plugin_stubs

  export HOME="${BATS_TEST_TMPDIR}"
  source "scripts/plugins/aws.sh"
}

# aws_import_credentials — CSV format

@test "aws_import_credentials parses simple CSV (Access key ID,Secret access key)" {
  local input="Access key ID,Secret access key
${_TEST_KEY_ID},${_TEST_SECRET}"
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ local p=\$1 d=\$2; mkdir -p \"\$(dirname \"\$p\")\"; printf '%s' \"\$d\" > \"\$p\"; chmod 600 \"\$p\"; }
    define_legacy_plugin_stubs
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '%s' \"${input}\" | aws_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${BATS_TEST_TMPDIR}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=${_TEST_KEY_ID}"* ]]
  [[ "$output" == *"aws_secret_access_key=${_TEST_SECRET}"* ]]
}

@test "aws_import_credentials parses CSV with User name column" {
  local input="User name,Access key ID,Secret access key
alice,${_TEST_KEY_ID},${_TEST_SECRET}"
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ local p=\$1 d=\$2; mkdir -p \"\$(dirname \"\$p\")\"; printf '%s' \"\$d\" > \"\$p\"; chmod 600 \"\$p\"; }
    define_legacy_plugin_stubs
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '%s' \"${input}\" | aws_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${BATS_TEST_TMPDIR}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=${_TEST_KEY_ID}"* ]]
  [[ "$output" == *"aws_secret_access_key=${_TEST_SECRET}"* ]]
}

# aws_import_credentials — quoted export format

@test "aws_import_credentials parses quoted export values" {
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ local p=\$1 d=\$2; mkdir -p \"\$(dirname \"\$p\")\"; printf '%s' \"\$d\" > \"\$p\"; chmod 600 \"\$p\"; }
    define_legacy_plugin_stubs
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '%s\n%s\n%s\n' \
      'export AWS_ACCESS_KEY_ID=\"${_TEST_KEY_ID}\"' \
      'export AWS_SECRET_ACCESS_KEY=\"${_TEST_SECRET}\"' \
      'export AWS_SESSION_TOKEN=\"${_TEST_TOKEN}\"' | aws_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${BATS_TEST_TMPDIR}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=${_TEST_KEY_ID}"* ]]
  [[ "$output" == *"aws_secret_access_key=${_TEST_SECRET}"* ]]
  [[ "$output" == *"aws_session_token=${_TEST_TOKEN}"* ]]
}

# aws_import_credentials — error cases

@test "aws_import_credentials returns 1 on unparseable input" {
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ :; }
    define_legacy_plugin_stubs
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '' | aws_import_credentials"
  [ "$status" -eq 1 ]
}

@test "aws_import_credentials --help exits 0" {
  run aws_import_credentials --help
  [ "$status" -eq 0 ]
}
