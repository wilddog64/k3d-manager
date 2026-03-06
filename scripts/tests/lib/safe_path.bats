#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
  OLD_PATH="$PATH"
}

teardown() {
  PATH="$OLD_PATH"
}

@test "_safe_path: world-writable dir is rejected" {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  chmod 777 "$tmp_dir"
  export PATH="${tmp_dir}:${PATH}"

  run _safe_path
  [ "$status" -ne 0 ]
  [[ "$output" == *"PATH contains unsafe entries"* ]]
  [[ "$output" == *"$tmp_dir"* ]]

  chmod 755 "$tmp_dir"
  rmdir "$tmp_dir"
}

@test "_safe_path: relative path entry is rejected" {
  export PATH="./bin:${PATH}"

  run _safe_path
  [ "$status" -ne 0 ]
  [[ "$output" == *"PATH contains unsafe entries"* ]]
  [[ "$output" == *"./bin (relative path entry)"* ]]
}

@test "_safe_path: empty PATH component is rejected" {
  export PATH=":/usr/bin:${PATH}"

  run _safe_path
  [ "$status" -ne 0 ]
  [[ "$output" == *"PATH contains unsafe entries"* ]]
  [[ "$output" == *"(relative path entry)"* ]]
}

@test "_safe_path: standard absolute non-writable dirs pass" {
  export PATH="/usr/local/bin:/usr/bin:/bin"
  # Stub out filesystem check — CI runners may have world-writable /usr/local/bin.
  # This test validates _safe_path logic (all entries absolute), not real permissions.
  _is_world_writable_dir() { return 1; }
  export -f _is_world_writable_dir

  run _safe_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_safe_path: sticky-bit world-writable dir is rejected" {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  chmod 1777 "$tmp_dir"
  export PATH="${tmp_dir}:${PATH}"

  run _safe_path
  [ "$status" -ne 0 ]
  [[ "$output" == *"PATH contains unsafe entries"* ]]
  [[ "$output" == *"$tmp_dir"* ]]

  chmod 755 "$tmp_dir"
  rmdir "$tmp_dir"
}
