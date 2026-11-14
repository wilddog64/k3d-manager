#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FIXHOME="$BATS_TEST_TMPDIR/home"
  FIXBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FIXHOME" "$FIXBIN" "$FIXHOME/.local/bin"
  [[ "$FIXHOME" == "$BATS_TEST_TMPDIR/"* && "$FIXHOME" != "$HOME" ]]
}

make_promtool() {
  local target="$1" value="$2"
  mkdir -p "${target%/*}"
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$value" > "$target"
  chmod +x "$target"
}

@test "k3dm_promtool prefers PROMTOOL over HOME and PATH" {
  make_promtool "$BATS_TEST_TMPDIR/configured/promtool" configured
  make_promtool "$FIXHOME/.local/bin/promtool" home
  make_promtool "$FIXBIN/promtool" path
  run env HOME="$FIXHOME" PROMTOOL="$BATS_TEST_TMPDIR/configured/promtool" PATH="$FIXBIN:/usr/bin:/bin" bash -c 'source "$1/scripts/tests/promtool.bash"; k3dm_promtool' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = configured ]
}

@test "k3dm_promtool prefers HOME before PATH" {
  make_promtool "$FIXHOME/.local/bin/promtool" home
  make_promtool "$FIXBIN/promtool" path
  run env -u PROMTOOL HOME="$FIXHOME" PATH="$FIXBIN:/usr/bin:/bin" bash -c 'source "$1/scripts/tests/promtool.bash"; k3dm_promtool' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = home ]
}

@test "k3dm_promtool falls back to PATH" {
  make_promtool "$FIXBIN/promtool" path
  run env -u PROMTOOL HOME="$FIXHOME" PATH="$FIXBIN:/usr/bin:/bin" bash -c 'source "$1/scripts/tests/promtool.bash"; k3dm_promtool' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = path ]
}

@test "k3dm_promtool fails with setup instruction when missing" {
  run env -u PROMTOOL HOME="$FIXHOME" PATH="$BATS_TEST_TMPDIR/empty-path:/usr/bin:/bin" bash -c 'source "$1/scripts/tests/promtool.bash"; k3dm_promtool' _ "$REPO_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *'promtool not found; run make machine-setup (installs promtool 3.1.0)'* ]]
}
