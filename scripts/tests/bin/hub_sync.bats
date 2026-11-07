#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$BATS_TEST_TMPDIR/repo"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  HOME="$BATS_TEST_TMPDIR/home"
  XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  K3DM_JOB_DIR="$BATS_TEST_TMPDIR/jobs"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  REAL_MAKE="$(command -v make)"
  mkdir -p "$WORK" "$HOME" "$XDG_CONFIG_HOME/k3d-manager" "$K3DM_JOB_DIR" "$STUBS"
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  git init --bare -q "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || exit
  git config user.email test@example.invalid
  git config user.name test
  mkdir -p bin
  cp "$ROOT/bin/k3dm-hub-sync" bin/
  cp "$ROOT/bin/k3dm-require-role" bin/
  echo seed > file
  git add file bin
  git commit -qm seed
  git branch -M k3d-manager-v1.43.14
  git push -qu origin HEAD
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/k3d-manager-v1.43.14
  git branch --set-upstream-to=origin/k3d-manager-v1.43.14 >/dev/null
  cat > "$STUBS/make" <<'SH'
#!/usr/bin/env bash
printf 'make %s\n' "$*" >> "$STUB_LOG"
[[ "${FAIL_MAKE:-}" != "$1" ]]
SH
  cat > "$STUBS/launchctl" <<'SH'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >> "$STUB_LOG"
SH
  chmod +x "$STUBS/make" "$STUBS/launchctl"
  export HOME XDG_CONFIG_HOME K3DM_JOB_DIR STUB_LOG="$BATS_TEST_TMPDIR/stubs.log"
  export PATH="$STUBS:$PATH"
  : > "$STUB_LOG"
  [ -x "$WORK/bin/k3dm-hub-sync" ]
}

@test "fast forwards code and runs restart and appsets check" {
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/advance"
  cd "$BATS_TEST_TMPDIR/advance"
  git config user.email test@example.invalid; git config user.name test
  echo change >> file; git commit -qam code; git push -q
  cd "$WORK"
  run bin/k3dm-hub-sync
  [[ "$output" == *"repository: $WORK"* ]]
  [ "$status" -eq 0 ]
  [[ "$output" == *"old SHA:"* && "$output" == *"new SHA:"* ]]
  grep -q '^make restart-webhook$' "$STUB_LOG"
  grep -q '^launchctl kickstart -k gui/.*/com.k3d-manager.hermes$' "$STUB_LOG"
  grep -q '^make appsets-check$' "$STUB_LOG"
}

@test "doc-only changes skip restart and platform-ops, appsets check still runs" {
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/advance"
  cd "$BATS_TEST_TMPDIR/advance"
  git config user.email test@example.invalid; git config user.name test
  mkdir -p docs; echo doc > docs/readme; git add docs; git commit -qm docs; git push -q
  cd "$WORK"
  run bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  run grep -q '^make restart-webhook$' "$STUB_LOG"
  [ "$status" -ne 0 ]
  run grep -q '^make platform-ops$' "$STUB_LOG"
  [ "$status" -ne 0 ]
  grep -q '^make appsets-check$' "$STUB_LOG"
}

@test "dirty and wrong-role fixtures refuse without invoking stubs" {
  echo dirty >> file
  run bin/k3dm-hub-sync
  [ "$status" -ne 0 ]
  [ ! -s "$STUB_LOG" ]
  git checkout -- file
  printf 'console\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  run bin/k3dm-hub-sync
  [ "$status" -ne 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "non-release target and a recent queued job refuse before stubs" {
  run env BRANCH=main bin/k3dm-hub-sync
  [ "$status" -eq 2 ]
  mkdir -p "$K3DM_JOB_DIR/job-123"
  printf 'queued\n' > "$K3DM_JOB_DIR/job-123/status"
  run bin/k3dm-hub-sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"job-123"* ]]
  [ ! -s "$STUB_LOG" ]
  rm -rf "$K3DM_JOB_DIR/job-123"
  run bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  grep -q '^make appsets-check$' "$STUB_LOG"
}

@test "older active jobs and successful jobs do not refuse" {
  mkdir -p "$K3DM_JOB_DIR/old-running" "$K3DM_JOB_DIR/success"
  printf 'running\n' > "$K3DM_JOB_DIR/old-running/status"
  printf 'success\n' > "$K3DM_JOB_DIR/success/status"
  touch -t 202601010000 "$K3DM_JOB_DIR/old-running/status"
  run bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  grep -q '^make appsets-check$' "$STUB_LOG"
}

@test "platform and launchd changes run only their required follow-ups" {
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/advance"
  cd "$BATS_TEST_TMPDIR/advance"
  git config user.email test@example.invalid; git config user.name test
  mkdir -p scripts/etc/argocd/platform-ops scripts/etc/launchd
  echo config > scripts/etc/argocd/platform-ops/test.yaml
  echo plist > scripts/etc/launchd/test.plist
  git add scripts; git commit -qm platform-and-launchd; git push -q
  cd "$WORK"
  run bin/k3dm-hub-sync
  [[ "$output" == *"repository: $WORK"* ]]
  [ "$status" -eq 0 ]
  grep -q '^make platform-ops$' "$STUB_LOG"
  [[ "$output" == *"needed: make machine-setup ROLE=hub"* ]]
  run grep -q 'machine-setup\|appsets-reapply' "$STUB_LOG"
  [ "$status" -ne 0 ]
}

@test "appsets-check failure is non-fatal and diverged commits survive" {
  run env FAIL_MAKE=appsets-check bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"appsets-check: ran (failed; non-fatal)"* ]]
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/advance"
  cd "$BATS_TEST_TMPDIR/advance"
  git config user.email test@example.invalid; git config user.name test
  echo remote >> file; git commit -qam remote; git push -q
  cd "$WORK"
  echo local > local.txt; git add local.txt; git commit -qm local
  local_head="$(git rev-parse HEAD)"
  run bin/k3dm-hub-sync
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$local_head" ]
  [ -f local.txt ]
}

@test "appsets-reapply is needed only when appsets-check fails and is never run" {
  run env FAIL_MAKE=appsets-check bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"appsets-reapply: needed: make appsets-reapply"* ]]
  run grep -q 'appsets-reapply' "$STUB_LOG"
  [ "$status" -ne 0 ]
  : > "$STUB_LOG"
  run bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"appsets-reapply: skipped"* ]]
}

@test "diverged BRANCH refusal restores original branch and preserves both heads" {
  git switch -q -c k3d-manager-v1.43.15
  echo local-only > target-local.txt
  git add target-local.txt; git commit -qm local-only
  local_target_head="$(git rev-parse HEAD)"
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/advance"
  cd "$BATS_TEST_TMPDIR/advance"
  git config user.email test@example.invalid; git config user.name test
  git switch -q -c k3d-manager-v1.43.15
  echo remote-only > target-remote.txt
  git add target-remote.txt; git commit -qm remote-only; git push -q origin HEAD
  cd "$WORK"
  git switch -q k3d-manager-v1.43.14
  original_head="$(git rev-parse HEAD)"
  : > "$STUB_LOG"
  run env BRANCH=k3d-manager-v1.43.15 bin/k3dm-hub-sync
  [ "$status" -eq 1 ]
  [ "$(git branch --show-current)" = k3d-manager-v1.43.14 ]
  [ "$(git rev-parse HEAD)" = "$original_head" ]
  [ "$(git rev-parse k3d-manager-v1.43.15)" = "$local_target_head" ]
  [ "$(git show k3d-manager-v1.43.15:target-local.txt)" = local-only ]
  [ ! -s "$STUB_LOG" ]
}

@test "fast-forward onto a local BRANCH switches there and applies remote commits" {
  git switch -q -c k3d-manager-v1.43.15
  git push -q -u origin HEAD
  git clone -q "$ORIGIN" "$BATS_TEST_TMPDIR/advance"
  cd "$BATS_TEST_TMPDIR/advance"
  git config user.email test@example.invalid; git config user.name test
  echo target-update > target-update.txt
  git add target-update.txt; git commit -qm target-update
  git push -q origin HEAD:refs/heads/k3d-manager-v1.43.15
  cd "$WORK"
  run env BRANCH=k3d-manager-v1.43.15 bin/k3dm-hub-sync
  [[ "$output" == *"new SHA:"* ]]
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = k3d-manager-v1.43.15 ]
  [ -f target-update.txt ]
}

@test "newer release is advisory until BRANCH explicitly selects it" {
  git push -q origin HEAD:refs/heads/k3d-manager-v1.43.100
  run bin/k3dm-hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"needed: make hub-sync BRANCH=k3d-manager-v1.43.100"* ]]
  [ "$(git branch --show-current)" = k3d-manager-v1.43.14 ]
  run env BRANCH=k3d-manager-v1.43.100 bin/k3dm-hub-sync
  [[ "$output" == *"repository: $WORK"* ]]
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = k3d-manager-v1.43.100 ]
}

@test "make hub-sync passes an explicit BRANCH but leaves the default unset" {
  cp "$ROOT/Makefile" "$WORK/Makefile"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/k3dm-hub-sync" <<'SH'
#!/usr/bin/env bash
printf 'BRANCH=<%s>\n' "${BRANCH-}"
SH
  chmod +x "$WORK/bin/k3dm-hub-sync"
  [ -f "$WORK/Makefile" ]
  [ "$(cd "$(dirname "$WORK/Makefile")" && pwd)" = "$WORK" ]
  run "$REAL_MAKE" -f "$WORK/Makefile" hub-sync BRANCH=k3d-manager-v9.9.9
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH=<k3d-manager-v9.9.9>"* ]]
  run env -u BRANCH "$REAL_MAKE" -f "$WORK/Makefile" hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH=<>"* ]]
}
