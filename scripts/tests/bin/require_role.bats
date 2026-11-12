#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/../../.."
  HOME="$BATS_TEST_TMPDIR/home"
  XDG_CONFIG_HOME="$HOME/config"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* && "$HOME" != /Users/cliang ]] || return 1
  export HOME XDG_CONFIG_HOME
  mkdir -p "$XDG_CONFIG_HOME/k3d-manager" "$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/calls"; export LOG
  : > "$LOG"
  for cmd in k3d kubectl aws ssh docker vault launchctl; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "${0##*/}" "$*" >> "$LOG"\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/$cmd"
    chmod +x "$BATS_TEST_TMPDIR/bin/$cmd"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "role gate: cluster-up refuses non-hub and missing roles before commands" {
  for role in control worker console missing; do
    rm -f "$XDG_CONFIG_HOME/k3d-manager/machine-role"
    [ "$role" = missing ] || printf '%s\n' "$role" > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
    run "$ROOT/bin/cluster-up"
    [ "$status" -ne 0 ]
    [[ "$output" == *"$XDG_CONFIG_HOME/k3d-manager/machine-role"*"$role"*"run acg-up on the hub"* ]]
    [ ! -s "$LOG" ]
  done
}

@test "role gate: hub and override pass the shared check" {
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  run "$ROOT/bin/k3dm-require-role" hub
  [ "$status" -eq 0 ]
  rm "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  run env K3DM_ALLOW_LOCAL_HUB=1 "$ROOT/bin/k3dm-require-role" hub
  [ "$status" -eq 0 ]
}

@test "role gate: release targets and local hub refuse before commands" {
  cd "$ROOT"
  for target in appsets-reapply platform-ops restart-webhook hub-up; do
    run make "$target" BRANCH=k3d-manager-v1.43.14
    [ "$status" -ne 0 ]
    [[ "$output" == *"run acg-up on the hub"* ]]
    [ ! -s "$LOG" ]
  done
}

@test "role gate: hub and override reach the stopped hub start path" {
  # k3d cluster list, read-only capture on m4-air.local, 2026-11-01.
  cat > "$BATS_TEST_TMPDIR/bin/k3d" <<'SH'
#!/bin/sh
printf 'k3d %s\n' "$*" >> "$LOG"
if [ "$*" = 'cluster list' ]; then
  printf 'NAME          SERVERS   AGENTS   LOADBALANCER\nk3d-cluster   0/1       0/3      true\n'
else
  touch "$LOG.started"
fi
SH
  cat > "$BATS_TEST_TMPDIR/bin/kubectl" <<'SH'
#!/bin/sh
[ -e "$LOG.started" ]
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/k3d"
  sed -n '/^if ! k3d cluster list/,/^_info "\[acg-up\] Local Hub cluster verified\."/p' "$ROOT/bin/cluster-up" > "$BATS_TEST_TMPDIR/hub-path"
  for role in hub override; do
    : > "$LOG"
    rm -f "$LOG.started"
    rm -f "$XDG_CONFIG_HOME/k3d-manager/machine-role"
    [ "$role" = override ] || printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
    run env ALLOW_TEST="$role" bash -c '
      if [[ "$ALLOW_TEST" == override ]]; then export K3DM_ALLOW_LOCAL_HUB=1; fi
      "$1/bin/k3dm-require-role" hub || exit
      _info() { :; }; _err() { :; }; _dry_guard() { shift; "$@"; }
      _HUB_CLUSTER_CTX=k3d-k3d-cluster
      source "$2"
    ' bash "$ROOT" "$BATS_TEST_TMPDIR/hub-path"
    grep -Fxq 'k3d cluster start k3d-cluster' "$LOG"
  done
}

@test "role gate: hub release targets reach their first command" {
  local fixture="$BATS_TEST_TMPDIR/project"
  mkdir -p "$fixture/bin" "$fixture/scripts"
  cp "$ROOT/Makefile" "$fixture/Makefile"
  cp "$ROOT/bin/k3dm-require-role" "$fixture/bin/"
  mkdir -p "$fixture/scripts/lib/foundation/scripts/lib"
  cp "$ROOT/scripts/lib/foundation/scripts/lib/system.sh" "$fixture/scripts/lib/foundation/scripts/lib/"
  cat > "$fixture/scripts/k3d-manager" <<'SH'
#!/bin/sh
printf 'dispatcher %s\n' "$*" >> "$LOG"
exit 1
SH
  chmod +x "$fixture/scripts/k3d-manager"
  printf '#!/bin/sh\nprintf "git %%s\\n" "$*" >> "$LOG"\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/git"
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  cd "$fixture"
  for target in appsets-reapply platform-ops restart-webhook; do
    : > "$LOG"
    run make "$target" BRANCH=k3d-manager-v1.43.14
    [ -s "$LOG" ]
  done
}
