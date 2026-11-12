#!/usr/bin/env bats

# Fixture capture: `git ls-remote origin refs/heads/deploy/hub` is actual
# read-only output from each test's fake bare origin; host m4-air.local,
# 2026-11-12. No live origin is contacted.
setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  REAL_MAKE="$(command -v make)"
  REAL_GIT="$(command -v git)"
  WORK="${BATS_TEST_TMPDIR}/scratch-repo"
  ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
  export HOME="${BATS_TEST_TMPDIR}/home" XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$WORK/bin" "$WORK/scripts/lib/foundation/scripts/lib" "$WORK/scripts/etc/argocd/applicationsets" "$HOME" "$XDG_CONFIG_HOME/k3d-manager" "${BATS_TEST_TMPDIR}/stubs"
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  printf 'fixture\n' > "$WORK/.fixture-root"
  cp "$REPO/bin/k3dm-hub-deploy" "$WORK/bin/"
  cp "$REPO/bin/k3dm-require-role" "$WORK/bin/"
  cp "$REPO/scripts/lib/foundation/scripts/lib/system.sh" "$WORK/scripts/lib/foundation/scripts/lib/"
  cp "$REPO/Makefile" "$WORK/Makefile"
  chmod +x "$WORK/bin/k3dm-hub-deploy"
  : > "$BATS_TEST_TMPDIR/calls"
  export CALLS="$BATS_TEST_TMPDIR/calls" FIXTURE_ROOT="$WORK/.fixture-root" TEST_WORK="$WORK" TEST_ORIGIN="$ORIGIN" REAL_GIT
  cat > "$BATS_TEST_TMPDIR/stubs/git" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"-C $TEST_WORK "* ]] || { echo "git escaped fixture: $*" >&2; exit 97; }
[[ -f "$FIXTURE_ROOT" ]] || exit 98
printf 'git %s\n' "$*" >> "$CALLS"
[[ "$("$REAL_GIT" -C "$TEST_WORK" remote get-url origin)" == "$TEST_ORIGIN" ]]
exec "$REAL_GIT" "$@"
EOF
  cat > "$WORK/bin/k3dm-hub-promote" <<'EOF'
#!/usr/bin/env bash
[[ -f "$FIXTURE_ROOT" ]] || exit 98
printf 'promote %s\n' "$*" >> "$CALLS"
if [[ "${REQUIRE_TTY:-0}" == 1 && "$1" == promote ]]; then
  [[ -t 0 ]] || { printf 'confirmation requires a TTY\n' >&2; exit 1; }
  printf "Type 'promote' to continue: " >&2
  IFS= read -r answer || exit 1
  [[ "$answer" == promote ]] || exit 1
fi
if [[ "${CONFIRM_CAPTURE:-0}" == 1 && "$1" == promote ]]; then
  printf 'SHOWN old..new\n'
  printf "Type 'promote' to continue:\n" >&2
  IFS= read -r answer || exit 1
  printf 'confirmation=%s\n' "$answer" >> "$CALLS"
  [[ "$answer" == promote ]] || exit 1
fi
[[ "${PROMOTE_FAIL:-0}" == 0 ]] || exit "$PROMOTE_FAIL"
if [[ -n "${PROMOTE_TO_SHA:-}" ]]; then
  "$REAL_GIT" -C "$TEST_WORK" push --quiet origin "$PROMOTE_TO_SHA:refs/heads/deploy/hub"
fi
printf '%s\n' "${PROMOTE_OUTPUT:-promoted}"
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/make" <<'EOF'
#!/usr/bin/env bash
[[ -f "$FIXTURE_ROOT" ]] || exit 98
target="${*: -1}"
printf '%s\n' "$target" >> "$CALLS"
[[ "${FAIL_STEP:-}" != "$target" ]] || exit "${FAIL_CODE:-23}"
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/kubectl" <<'EOF'
#!/usr/bin/env bash
[[ -f "$FIXTURE_ROOT" ]] || exit 98
printf 'rollout\n' >> "$CALLS"
[[ "${FAIL_STEP:-}" != rollout ]] || exit "${FAIL_CODE:-24}"
EOF
  chmod +x "$WORK/bin/k3dm-hub-promote" "$BATS_TEST_TMPDIR/stubs/"*
  "$REAL_GIT" init --bare -q "$ORIGIN"
  "$REAL_GIT" -C "$WORK" init -q
  "$REAL_GIT" -C "$WORK" config user.name 'Hub deploy tests'
  "$REAL_GIT" -C "$WORK" config user.email 'hub-deploy-tests@example.invalid'
  printf 'base\n' > "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  "$REAL_GIT" -C "$WORK" add .
  "$REAL_GIT" -C "$WORK" commit -qm base
  BASE_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" remote add origin "$ORIGIN"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$BASE_SHA:refs/heads/deploy/hub"
  "$REAL_GIT" -C "$WORK" checkout -qb changed "$BASE_SHA"
  printf 'changed\n' > "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  "$REAL_GIT" -C "$WORK" commit -qam changed
  CHANGED_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$CHANGED_SHA:refs/heads/fixture-changed"
  "$REAL_GIT" -C "$WORK" checkout -qb other "$BASE_SHA"
  printf 'other\n' > "$WORK/other.txt"
  "$REAL_GIT" -C "$WORK" add other.txt
  "$REAL_GIT" -C "$WORK" commit -qm other
  OTHER_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$OTHER_SHA:refs/heads/fixture-other"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
}

@test "M1: changed ApplicationSets run every step in order" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" fixture-changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'reapply ran; appsets-check ok; platform-ops ok; exporter rolled out'* ]]
  [ "$(grep -E '^(promote|appsets-|platform-ops|rollout)' "$CALLS")" = $'promote promote fixture-changed\nappsets-reapply\nappsets-check\nplatform-ops\nrollout' ]
}

@test "M2 and N2: unchanged ApplicationSets skip reapply" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env PROMOTE_TO_SHA="$OTHER_SHA" "$WORK/bin/k3dm-hub-deploy" fixture-other
  [ "$status" -eq 0 ]
  [[ "$output" == *'appsets unchanged between '*'; skipping reapply'* ]]
  [[ "$output" == *'reapply skipped;'* ]]
  [ "$(grep -cx appsets-reapply "$CALLS" || true)" -eq 0 ]
  grep -qx appsets-check "$CALLS"
}

@test "M3: already-current promote continues without a second move" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env PROMOTE_OUTPUT="deploy/hub is already at $BASE_SHA; nothing to promote" "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 0 ]
  [ "$(grep -c '^promote ' "$CALLS")" -eq 1 ]
  [[ "$output" == *'exporter rolled out'* ]]
}

@test "M4: failure stops at the failing step and preserves its exit code" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env PROMOTE_TO_SHA="$CHANGED_SHA" FAIL_STEP=appsets-check FAIL_CODE=37 "$WORK/bin/k3dm-hub-deploy" fixture-changed
  [ "$status" -eq 37 ]
  [[ "$output" == *'stopped at appsets-check'* ]]
  [ "$(grep -cx platform-ops "$CALLS" || true)" -eq 0 ]
  [ "$(grep -cx rollout "$CALLS" || true)" -eq 0 ]
}

@test "N3: role gate refuses before git or kubectl" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  printf 'worker\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  run "$WORK/bin/k3dm-hub-deploy" release
  [ "$status" -ne 0 ]
  [ ! -s "$CALLS" ]
}

@test "N1: existing promoter requires a TTY and typed confirmation" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env REQUIRE_TTY=1 "$WORK/bin/k3dm-hub-deploy" release < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *'confirmation requires a TTY'* ]]
  [ "$(grep -cx rollout "$CALLS" || true)" -eq 0 ]
  grep -q 'k3dm-hub-promote.*promote.*"\$ref"' "$WORK/bin/k3dm-hub-deploy"
  grep -q "confirmation requires a TTY" "$REPO/bin/k3dm-hub-promote"
  grep -q 'answer.*promote' "$REPO/bin/k3dm-hub-promote"
}

@test "promoter's confirmation details appear before its prompt and stdin reaches it" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env CONFIRM_CAPTURE=1 bash -c 'exec "$1" fixture-base 2>&1' _ "$WORK/bin/k3dm-hub-deploy" <<< promote
  [ "$status" -eq 0 ]
  shown_line="$(grep -n '^SHOWN old\.\.new$' <<< "$output" | cut -d: -f1)"
  prompt_line="$(grep -n "^Type 'promote' to continue:$" <<< "$output" | cut -d: -f1)"
  if (( shown_line >= prompt_line )); then
    printf '%s\n' "$output" >&3
    false
  fi
  grep -qx 'confirmation=promote' "$CALLS"
}

@test "Makefile exposes hub-deploy as phony and forwards REF" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run "$REAL_MAKE" --no-print-directory -C "$WORK" -n hub-deploy REF=release
  [ "$status" -eq 0 ]
  [[ "$output" == *'bin/k3dm-hub-deploy "$REF"'* ]]
  grep -q '^\.PHONY:.*hub-deploy' "$WORK/Makefile"
  [[ "$output" == *'usage: make hub-deploy REF='* ]] || grep -q 'hub-deploy REF=\.\.\.' "$WORK/Makefile"
}
