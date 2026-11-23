#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  REAL_GIT="$(command -v git)"
  REAL_MAKE="$(command -v make)"
  WORK="$BATS_TEST_TMPDIR/repo"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  export HOME="$BATS_TEST_TMPDIR/home" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$WORK/bin" "$WORK/scripts/lib/foundation/scripts/lib" "$WORK/scripts/etc/argocd/platform-ops" "$WORK/scripts/etc/argocd/applicationsets" "$XDG_CONFIG_HOME/k3d-manager" "$HOME" "$BATS_TEST_TMPDIR/stubs"
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  : > "$BATS_TEST_TMPDIR/sudo.hit"; : > "$BATS_TEST_TMPDIR/launchctl.hit"
  cat > "$BATS_TEST_TMPDIR/stubs/sudo" <<'STUB'
#!/bin/sh
: > "$BATS_TEST_TMPDIR/sudo.hit"
exit 1
STUB
  cat > "$BATS_TEST_TMPDIR/stubs/launchctl" <<'STUB'
#!/bin/sh
: > "$BATS_TEST_TMPDIR/launchctl.hit"
exit 1
STUB
  cat > "$BATS_TEST_TMPDIR/stubs/git" <<'STUB'
#!/usr/bin/env bash
fixture=0 previous=''
for arg in "$@"; do
  if [[ "$previous" == -C && "$arg" -ef "$WORK" ]]; then fixture=1; fi
  if [[ "$arg" == --git-dir=* && "${arg#--git-dir=}" -ef "$ORIGIN" ]]; then fixture=1; fi
  previous="$arg"
done
[[ "$fixture" == 1 ]] || { echo "git escaped fixture: $* (WORK=${WORK:-unset})" >&2; exit 97; }
if [[ "${INJECT_FETCH_RACE:-0}" == 1 && " $* " == *" rev-parse --verify FETCH_HEAD^{commit} "* && ! -e "$BATS_TEST_TMPDIR/fetch-race-fired" ]]; then
  "$REAL_GIT" "$@" || exit $?
  : > "$BATS_TEST_TMPDIR/fetch-race-fired"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$RACE_NEWER_SHA:refs/heads/deploy/hub" || exit 96
  "$REAL_GIT" -C "$WORK" fetch --quiet --no-tags origin refs/heads/deploy/hub || exit 95
  exit 0
fi
exec "$REAL_GIT" "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/"*
  export BATS_TEST_TMPDIR
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  [ "$(command -v sudo)" = "$BATS_TEST_TMPDIR/stubs/sudo" ]
  [ "$(command -v launchctl)" = "$BATS_TEST_TMPDIR/stubs/launchctl" ]
  "$REAL_GIT" init --bare -q "$ORIGIN"
  "$REAL_GIT" -C "$WORK" init -q
  "$REAL_GIT" -C "$WORK" config user.name fixture
  "$REAL_GIT" -C "$WORK" config user.email fixture@example.invalid
  cp "${TEST_MAKEFILE:-$REPO/Makefile}" "$WORK/Makefile"
  sed -i.bak 's/@set -eo pipefail;/@set -x; set -eo pipefail;/' "$WORK/Makefile"
  cp "$REPO/bin/k3dm-require-role" "$WORK/bin/"
  cp "$REPO/scripts/lib/foundation/scripts/lib/system.sh" "$WORK/scripts/lib/foundation/scripts/lib/"
  cat > "$WORK/scripts/k3d-manager" <<'DISPATCH'
#!/bin/sh
revision="$(cat REVISION)"
if [ "${CHECK_NO_GIT:-0}" = 1 ]; then
  [ ! -e .git ] || exit 94
  revision="$revision no-git"
fi
printf '%s\n' "$revision" >> "$DISPATCH_LOG"
DISPATCH
  chmod +x "$WORK/scripts/k3d-manager"
  printf 'base\n' > "$WORK/REVISION"
  : > "$WORK/scripts/etc/argocd/platform-ops/a.yaml"
  : > "$WORK/scripts/etc/argocd/applicationsets/a.yaml"
  "$REAL_GIT" -C "$WORK" add .
  "$REAL_GIT" -C "$WORK" commit -qm base
  "$REAL_GIT" -C "$WORK" branch -M deploy/hub
  "$REAL_GIT" -C "$WORK" remote add origin "$ORIGIN"
  "$REAL_GIT" -C "$WORK" push -q origin deploy/hub
  PIN="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  export PIN WORK ORIGIN REAL_GIT DISPATCH_LOG="$BATS_TEST_TMPDIR/dispatch.log"
  : > "$DISPATCH_LOG"
  chmod +x "$BATS_TEST_TMPDIR/stubs/"*
}

teardown() {
  [ ! -s "$BATS_TEST_TMPDIR/sudo.hit" ] || { echo 'sudo guard was hit' >&2; return 1; }
  [ ! -s "$BATS_TEST_TMPDIR/launchctl.hit" ] || { echo 'launchctl guard was hit' >&2; return 1; }
}

_prepare_fetch_head_race() {
  "$REAL_GIT" -C "$WORK" checkout -qb race-newer "$PIN"
  printf 'newer\n' > "$WORK/REVISION"
  "$REAL_GIT" -C "$WORK" add REVISION
  "$REAL_GIT" -C "$WORK" commit -qm newer
  RACE_NEWER_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$PIN"
  export RACE_NEWER_SHA INJECT_FETCH_RACE=1 CHECK_NO_GIT=1
}

@test 'E5 platform-ops archives the pinned commit and writes marker' {
  run "$REAL_MAKE" -C "$WORK" platform-ops "PLATFORM_OPS_SHA=$PIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$DISPATCH_LOG")" = base ]
  [ "$(cat "$HOME/.local/share/k3d-manager/repo-sync/deployed-platform-ops")" = "$PIN" ]
}

@test 'E5 appsets-reapply runs from pinned archive without .git' {
  run "$REAL_MAKE" -C "$WORK" appsets-reapply "APPSETS_SHA=$PIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$DISPATCH_LOG")" = base ]
}

@test 'E5 mismatch records superseded before dispatcher runs' {
  wrong="$(printf '%040d' 1)"
  marker="$BATS_TEST_TMPDIR/superseded"
  run env K3DM_SUPERSEDED_OUT="$marker" "$REAL_MAKE" -C "$WORK" platform-ops "PLATFORM_OPS_SHA=$wrong"
  [ "$status" -eq 2 ]
  [ "$(cat "$marker")" = "superseded $PIN $wrong" ]
  [ ! -s "$DISPATCH_LOG" ]
}

@test 'E5 unset pins retain checkout behavior' {
  run "$REAL_MAKE" -C "$WORK" appsets-reapply
  [ "$status" -eq 0 ]
  [ "$(cat "$DISPATCH_LOG")" = base ]
}

@test 'E5 platform-ops archive stays at approved SHA when FETCH_HEAD moves after comparison' {
  _prepare_fetch_head_race
  run "$REAL_MAKE" -C "$WORK" platform-ops "PLATFORM_OPS_SHA=$PIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$DISPATCH_LOG")" = 'base no-git' ]
  [ "$(cat "$HOME/.local/share/k3d-manager/repo-sync/deployed-platform-ops")" = "$PIN" ]
  [ -e "$BATS_TEST_TMPDIR/fetch-race-fired" ]
}

@test 'E5 appsets archive stays at approved SHA when FETCH_HEAD moves after comparison' {
  _prepare_fetch_head_race
  run "$REAL_MAKE" -C "$WORK" appsets-reapply "APPSETS_SHA=$PIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$DISPATCH_LOG")" = 'base no-git' ]
  [ -e "$BATS_TEST_TMPDIR/fetch-race-fired" ]
}
