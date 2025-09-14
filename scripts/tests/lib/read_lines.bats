#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
}

@test "read_lines reads file into array" {
  local file="$BATS_TEST_TMPDIR/sample"
  printf "a\nb\n" > "$file"
  read_lines "$file" lines
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "a" ]
  [ "${lines[1]}" = "b" ]
}

@test "read_lines falls back on bash <4" {
  local file="$BATS_TEST_TMPDIR/sample2"
  printf "c\nd\n" > "$file"
  local legacy_bash=""
  for candidate in bash3 bash-3 bash-3.2 bash-3.2.57 bash32 bash-3.1; do
    if command -v "$candidate" >/dev/null 2>&1; then
      legacy_bash=$(command -v "$candidate")
      break
    fi
  done
  [ -n "$legacy_bash" ] || skip "legacy bash not available"
  run "$legacy_bash" -c "source '$BATS_TEST_DIRNAME/../test_helpers.bash'; read_lines '$file' lines; printf '%s\n' \"\${lines[@]}\""
  [ "$status" -eq 0 ]
  [ "$output" = $'c\nd' ]
}
