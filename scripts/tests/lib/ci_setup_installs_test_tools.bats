#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  CI_SETUP_ACTION="${CI_SETUP_ACTION:-$REPO_ROOT/.github/actions/setup/action.yml}"
  TEST_SUITES="$REPO_ROOT/scripts/tests"
}

has_apt_package() {
  awk '
    /- name: Install apt packages/ { in_step = 1; next }
    in_step && /- name:/ { exit }
    in_step && /apt-get install -y/ {
      for (i = 1; i <= NF; i++) {
        if ($i == package) found = 1
      }
    }
    END { exit !found }
  ' package="$2" "$1"
}

has_tool_test() {
  grep -rEl --include='*.bats' -- "$1" "$TEST_SUITES" >/dev/null
}

@test 'CI apt packages cover every tool called by BATS suites' {
  [[ -f "$CI_SETUP_ACTION" && -d "$TEST_SUITES" ]]
  local -a tool_patterns=(
    '(^|[;&|[:space:]])(age-keygen|age)([[:space:]]|$)'
    '(^|[;&|[:space:]])rg([[:space:]]|$)'
  )
  local -a apt_packages=(age ripgrep)
  local -a tool_names=('age or age-keygen' rg)
  local missing=0
  local index

  for index in "${!tool_patterns[@]}"; do
    if ! has_tool_test "${tool_patterns[$index]}"; then
      echo "scripts/tests contains no BATS call to ${tool_names[$index]}" >&2
      missing=1
    elif ! has_apt_package "$CI_SETUP_ACTION" "${apt_packages[$index]}"; then
      echo "CI Install apt packages step does not install ${apt_packages[$index]} for BATS calls to ${tool_names[$index]}" >&2
      missing=1
    fi
  done

  [ "$missing" -eq 0 ]
}

@test 'age package check rejects a fixture action without age' {
  fixture="$BATS_TEST_TMPDIR/action-without-age.yml"
  [[ "$fixture" == "$BATS_TEST_TMPDIR/"* ]]
  sed -E 's/(^|[[:space:]])age([[:space:]]|$)/\1\2/' "$CI_SETUP_ACTION" > "$fixture"
  [[ -f "$fixture" ]]
  if has_apt_package "$fixture" age; then
    echo "fixture unexpectedly passed without age" >&2
    return 1
  fi
}

@test 'ripgrep package check rejects a fixture action without ripgrep' {
  fixture="$BATS_TEST_TMPDIR/action-without-ripgrep.yml"
  [[ "$fixture" == "$BATS_TEST_TMPDIR/"* ]]
  sed -E 's/(^|[[:space:]])ripgrep([[:space:]]|$)/\1\2/' "$CI_SETUP_ACTION" > "$fixture"
  [[ -f "$fixture" ]]
  if has_apt_package "$fixture" ripgrep; then
    echo "fixture unexpectedly passed without ripgrep" >&2
    return 1
  fi
}
