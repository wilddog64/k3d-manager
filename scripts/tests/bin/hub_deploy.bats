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
  mkdir -p "$BATS_TEST_TMPDIR/guards"
  export HOME="${BATS_TEST_TMPDIR}/home" XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  export K3DM_REPO_SYNC_STATE_DIR="${BATS_TEST_TMPDIR}/repo-sync" K3DM_HUB_DEPLOY_CHECKOUT_WAIT=0
  export K3DM_JOB_DIR="$BATS_TEST_TMPDIR/jobs" K3DM_HUB_DEPLOY_AGENT_WAIT=0
  mkdir -p "$WORK/bin" "$WORK/scripts/lib/foundation/scripts/lib" "$WORK/scripts/etc/argocd/applicationsets" "$HOME" "$XDG_CONFIG_HOME/k3d-manager" "${BATS_TEST_TMPDIR}/stubs"
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  printf 'fixture\n' > "$WORK/.fixture-root"
  cp "${TEST_HUB_DEPLOY:-$REPO/bin/k3dm-hub-deploy}" "$WORK/bin/k3dm-hub-deploy"
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
[[ "${FAIL_REMOTE:-0}" != 1 || "$*" != *ls-remote* ]] || exit "${REMOTE_FAIL_CODE:-43}"
[[ "$("$REAL_GIT" -C "$TEST_WORK" remote get-url origin)" == "$TEST_ORIGIN" ]]
if [[ "${FAKE_CLEAN:-0}" == 1 && "$*" == *"status --porcelain --untracked-files=no"* ]]; then exit 0; fi
exec "$REAL_GIT" "$@"
EOF
  cat > "$WORK/bin/k3dm-hub-promote" <<'EOF'
#!/usr/bin/env bash
[[ -f "$FIXTURE_ROOT" ]] || exit 98
printf 'promote %s\n' "$*" >> "$CALLS"
printf 'skip=%s reason=%s\n' "${SKIP_CHECK_RUNS:-0}" "${SKIP_CHECK_RUNS_REASON:-}" >> "$CALLS"
if [[ " $* " == *" --approval "* ]]; then
  printf 'approval-argv %s\n' "$*" >> "$CALLS"
  if [[ -e "$HOME/.local/share/k3d-manager/hub-deploy/state" ]]; then printf 'approval-state present\n' >> "$CALLS"; else printf 'approval-state absent\n' >> "$CALLS"; fi
  [[ -n "${APPROVAL_NEW_SHA:-}" && -n "${APPROVAL_OLD_SHA:-}" ]] || exit 97
  [[ "${APPROVAL_PROMOTE_FAIL:-0}" == 0 ]] || exit "$APPROVAL_PROMOTE_FAIL"
  "$REAL_GIT" -C "$TEST_WORK" push --quiet origin "$APPROVAL_NEW_SHA:refs/heads/deploy/hub"
  if [[ "${APPROVAL_MOVE_AFTER_PROMOTE:-0}" == 1 ]]; then
    "$REAL_GIT" -C "$TEST_WORK" push --quiet origin "+$OTHER_SHA:refs/heads/deploy/hub" || { echo 'fixture deploy/hub move failed' >&2; exit 96; }
  fi
  if [[ "${APPROVAL_BAD_OUTPUT:-0}" == 1 ]]; then printf 'approved-sha %s\n' "$APPROVAL_NEW_SHA"; else printf 'approved-sha %s\napproved-old %s\n' "$APPROVAL_NEW_SHA" "$APPROVAL_OLD_SHA"; fi
  exit 0
fi
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
  "$REAL_GIT" -C "$TEST_WORK" branch -f "$2" "$PROMOTE_TO_SHA" 2>/dev/null || :
  "$REAL_GIT" -C "$TEST_WORK" push --quiet origin "$PROMOTE_TO_SHA:refs/heads/deploy/hub"
fi
printf '%s\n' "${PROMOTE_OUTPUT:-promoted}"
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/make" <<'EOF'
#!/usr/bin/env bash
[[ -f "$FIXTURE_ROOT" && "$HOME" == "$BATS_TEST_TMPDIR/home" ]] || exit 98
target="${*: -1}"
if [[ "$target" == restart-webhook ]]; then
  printf 'restart-webhook\n' >> "$CALLS"
  [[ ! -e /dev/fd/9 ]] || exit 96
  [[ "$(cat "$K3DM_REPO_SYNC_STATE_DIR/lock/pid")" == "$PPID" ]] || exit 97
  [[ -z "${K3DM_AGENT_LOAD+x}" ]] || exit 95
  [[ "$("$REAL_GIT" -C "$TEST_WORK" rev-parse HEAD)" == "$(awk '$1 == "appsets" { print $2; exit }' "$HOME/.local/share/k3d-manager/hub-deploy/state")" && -z "$("$REAL_GIT" -C "$TEST_WORK" status --porcelain --untracked-files=no)" ]] || exit 94
  [[ "${FAIL_STEP:-}" != restart-webhook ]] || exit "${FAIL_CODE:-23}"
  if [[ "${NO_PID_BUMP:-0}" != 1 ]]; then
    mkdir -p "$HOME/.test-launchctl"
    for label in com.k3d-manager.webhook com.k3d-manager.cloud-bridge; do
      [[ "$label" != com.k3d-manager.cloud-bridge || -e "$HOME/Library/LaunchAgents/$label.plist" ]] || continue
      previous=999
      [[ ! -r "$HOME/.test-launchctl/$label.pid" ]] || previous="$(cat "$HOME/.test-launchctl/$label.pid")"
      touch "$HOME/.test-launchctl/$label"
      printf '%s\n' "$((previous + 1))" > "$HOME/.test-launchctl/$label.pid"
    done
  fi
  exit 0
fi
if [[ "${E4_MAKE_MODE:-0}" == 1 ]]; then
  printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/e4-make-args"
  if [[ ! -e "$BATS_TEST_TMPDIR/e4-state-at-make" ]]; then
    cp "$HOME/.local/share/k3d-manager/hub-deploy/state" "$BATS_TEST_TMPDIR/e4-state-at-make"
  fi
  for arg in "$@"; do
    case "$arg" in
      appsets-reapply|platform-ops) target="$arg" ;;
      APPSETS_SHA=*) printf 'APPSETS_SHA=%s\n' "${arg#APPSETS_SHA=}" >> "$BATS_TEST_TMPDIR/e4-make-env" ;;
      PLATFORM_OPS_SHA=*) printf 'PLATFORM_OPS_SHA=%s\n' "${arg#PLATFORM_OPS_SHA=}" >> "$BATS_TEST_TMPDIR/e4-make-env" ;;
      K3DM_SUPERSEDED_OUT=*) printf 'K3DM_SUPERSEDED_OUT=%s\n' "${arg#K3DM_SUPERSEDED_OUT=}" >> "$BATS_TEST_TMPDIR/e4-make-env"; export E4_SUPERSEDED_FILE="${arg#K3DM_SUPERSEDED_OUT=}" ;;
    esac
  done
  e4_failure_target="${E4_MAKE_STEP:-$target}"
  if [[ "$target" == "$e4_failure_target" && "${E4_MAKE_SUPERSEDED:-0}" == 1 ]]; then
    printf 'superseded %s %s\n' "${E4_GOT_SHA:-$CHANGED_SHA}" "$CHANGED_SHA" > "$E4_SUPERSEDED_FILE"
    exit 2
  fi
  if [[ "$target" == "$e4_failure_target" ]]; then [[ "${E4_MAKE_FAIL:-0}" == 0 ]] || exit "$E4_MAKE_FAIL"; fi
fi
state="$HOME/.local/share/k3d-manager/hub-deploy/state"
if [[ -e "$state" ]]; then
  [[ -r "$state" ]] || exit 94
  [[ "$(grep -c '^appsets ' "$state")" == 1 && "$(grep -c '^launchd ' "$state")" == 1 ]] || exit 93
  printf '%s\n' "state-at-$target" >> "$BATS_TEST_TMPDIR/state-snapshots"
  cat "$state" >> "$BATS_TEST_TMPDIR/state-snapshots"
fi
printf '%s\n' "$target" >> "$CALLS"
if [[ "$target" == appsets-check ]]; then printf 'child-prev=%s\n' "${K3DM_HUB_DEPLOY_PREV:-unset}" >> "$CALLS"; fi
[[ "${FAIL_STEP:-}" != "$target" ]] || exit "${FAIL_CODE:-23}"
if [[ "$target" == install-* ]]; then
  [[ "$K3DM_REPO_SYNC_STATE_DIR" == "$BATS_TEST_TMPDIR/repo-sync" && "$HOME" == "$BATS_TEST_TMPDIR/home" ]] || exit 98
  [[ "$(cat "$K3DM_REPO_SYNC_STATE_DIR/lock/pid")" == "$PPID" ]] || exit 97
  [[ "${LATE_INSTALL:-0}" == 1 || -e /dev/fd/9 ]] || exit 96
  [[ -z "${K3DM_AGENT_LOAD+x}" ]] || exit 95
  head_sha="$("$REAL_GIT" -C "$TEST_WORK" rev-parse HEAD)"
  dirty="$("$REAL_GIT" -C "$TEST_WORK" status --porcelain --untracked-files=no)"
  printf 'head %s\nclean %s\nlock-owner %s\nagent-load unset\nfd9 open\n' "$head_sha" "${dirty:+no}" "$(cat "$K3DM_REPO_SYNC_STATE_DIR/lock/pid")" >> "$BATS_TEST_TMPDIR/install-details"
  if [[ "${LATE_INSTALL:-0}" == 1 ]]; then
    cp "$TEST_WORK/scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl" "$BATS_TEST_TMPDIR/late-render"
    (
      for unused in {1..100}; do
        [[ ! -e "$BATS_TEST_TMPDIR/installer-go" ]] || break
        sleep 0.1
      done
      cp "$BATS_TEST_TMPDIR/late-render" "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
      touch "$BATS_TEST_TMPDIR/installer-done"
    ) &
    touch "$BATS_TEST_TMPDIR/installer-ready"
    wait
    exit 0
  fi
  if [[ "${NO_REWRITE:-0}" != 1 ]]; then
    plist="$HOME/Library/LaunchAgents/com.k3d-manager.${target#install-}.plist"
    if [[ "${RESTORE_MTIME:-0}" == 1 ]]; then cp -p "$plist" "$BATS_TEST_TMPDIR/original-stamp"; fi
    cp "$TEST_WORK/scripts/etc/launchd/com.k3d-manager.${target#install-}.plist.tmpl" "$plist"
    if [[ "${RESTORE_MTIME:-0}" == 1 ]]; then touch -r "$BATS_TEST_TMPDIR/original-stamp" "$plist"; fi
  fi
  mkdir -p "$HOME/.test-launchctl"
  touch "$HOME/.test-launchctl/com.k3d-manager.${target#install-}"
  if [[ "${MOVE_HEAD:-0}" == 1 ]]; then "$REAL_GIT" -C "$TEST_WORK" checkout -q "$MOVE_TO"; fi
  if [[ "${BREAK_PID:-0}" == 1 ]]; then printf '99999999\n' > "$K3DM_REPO_SYNC_STATE_DIR/lock/pid"; fi
  if [[ "${KILL_DEPLOY:-0}" == 1 ]]; then kill -9 "$PPID"; fi
fi
if [[ "$target" == platform-ops ]]; then
  if [[ "${SLEEP_CHILD:-0}" == 1 ]]; then
    sleep 20 &
    printf '%s\n' "$!" > "$BATS_TEST_TMPDIR/sleeper-pid"
    printf '%s\n' "$$" > "$BATS_TEST_TMPDIR/make-pid"
    touch "$BATS_TEST_TMPDIR/sleeper-ready"
    wait
  fi
  mkdir -p "$HOME/.local/share/k3d-manager/repo-sync"
  "$REAL_GIT" -C "$TEST_WORK" ls-remote origin refs/heads/deploy/hub | cut -f1 > "$HOME/.local/share/k3d-manager/repo-sync/deployed-platform-ops"
  [[ -z "${PIN_OVERRIDE:-}" ]] || printf '%s\n' "$PIN_OVERRIDE" > "$HOME/.local/share/k3d-manager/repo-sync/deployed-platform-ops"
  if [[ "${PIN_MISSING:-0}" == 1 ]]; then rm "$HOME/.local/share/k3d-manager/repo-sync/deployed-platform-ops"; fi
fi
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/launchctl" <<'EOF'
#!/usr/bin/env bash
# Output shape captured read-only from m5-air.local on 2026-11-27.
[[ "$HOME" == "$BATS_TEST_TMPDIR/home" ]] || exit 98
printf 'launchctl %s\n' "$*" >> "$CALLS"
[[ "$1" == print && "${PRINT_FAIL:-0}" == 0 ]] || exit 113
[[ -f "$HOME/.test-launchctl/${2##*/}" ]] || exit 113
label="${2##*/}"
if [[ -r "$HOME/.test-launchctl/$label.pid" ]]; then printf 'pid = %s\n' "$(cat "$HOME/.test-launchctl/$label.pid")"; fi
if [[ -r "$HOME/.test-launchctl/$label.port" ]]; then printf 'K3DM_WEBHOOK_PORT => %s\n' "$(cat "$HOME/.test-launchctl/$label.port")"; fi
EOF
  cat > "$BATS_TEST_TMPDIR/stubs/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/curl.args"
printf '%s' "${CURL_CODE:-401}"
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
  mkdir -p "$WORK/scripts/etc/launchd"
  printf 'base\n' > "$WORK/scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl"
  printf 'base\n' > "$WORK/scripts/etc/launchd/com.k3d-manager.cleanup.plist.tmpl"
  printf 'base\n' > "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  "$REAL_GIT" -C "$WORK" add .
  "$REAL_GIT" -C "$WORK" commit -qm base
  BASE_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" remote add origin "$ORIGIN"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$BASE_SHA:refs/heads/deploy/hub"
  "$REAL_GIT" -C "$WORK" checkout -qb changed "$BASE_SHA"
  printf 'changed\n' > "$WORK/scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl"
  printf 'changed\n' > "$WORK/scripts/etc/launchd/com.k3d-manager.cleanup.plist.tmpl"
  printf 'changed\n' > "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  "$REAL_GIT" -C "$WORK" commit -qam changed
  CHANGED_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  # The promoted commit runs this script as stage 2 and records the exact
  # arguments and handoff value before entering the real implementation.
  # shellcheck disable=SC2016
  { sed -n '1p' "$WORK/bin/k3dm-hub-deploy"; printf 'printf "stage2 %%s prev=%%s\\n" "$*" "${K3DM_HUB_DEPLOY_PREV:-}" >> "$CALLS"\n'; sed -n '2,$p' "$WORK/bin/k3dm-hub-deploy"; } > "$WORK/bin/k3dm-hub-deploy.tmp"
  mv "$WORK/bin/k3dm-hub-deploy.tmp" "$WORK/bin/k3dm-hub-deploy"
  chmod +x "$WORK/bin/k3dm-hub-deploy"
  "$REAL_GIT" -C "$WORK" add bin/k3dm-hub-deploy
  "$REAL_GIT" -C "$WORK" commit -qm 'fixture promoted handoff'
  CHANGED_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$CHANGED_SHA:refs/heads/fixture-changed"
  "$REAL_GIT" -C "$WORK" branch fixture-changed "$CHANGED_SHA"
  "$REAL_GIT" -C "$WORK" branch fixture-base "$BASE_SHA"
  "$REAL_GIT" -C "$WORK" branch base "$BASE_SHA"
  "$REAL_GIT" -C "$WORK" checkout -qb other "$BASE_SHA"
  printf 'other\n' > "$WORK/other.txt"
  "$REAL_GIT" -C "$WORK" add other.txt
  "$REAL_GIT" -C "$WORK" commit -qm other
  OTHER_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" branch fixture-other "$OTHER_SHA"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$OTHER_SHA:refs/heads/fixture-other"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$BASE_SHA"
  : > "$BATS_TEST_TMPDIR/sudo.hit"; : > "$BATS_TEST_TMPDIR/launchctl.hit"
  cat > "$BATS_TEST_TMPDIR/guards/sudo" <<'GUARD'
#!/bin/sh
: > "$BATS_TEST_TMPDIR/sudo.hit"
exit 1
GUARD
  cat > "$BATS_TEST_TMPDIR/guards/launchctl" <<'GUARD'
#!/bin/sh
: > "$BATS_TEST_TMPDIR/launchctl.hit"
exit 1
GUARD
  chmod +x "$BATS_TEST_TMPDIR/guards/"*
  export PATH="$BATS_TEST_TMPDIR/guards:$BATS_TEST_TMPDIR/stubs:$PATH"
  [[ "$(command -v sudo)" == "$BATS_TEST_TMPDIR/guards/sudo" && "$(command -v launchctl)" == "$BATS_TEST_TMPDIR/guards/launchctl" ]]
  # LaunchAgent behavior is simulated by this suite's launchctl stub. Keep it
  # ahead of the fail-closed guard after verifying the guard resolution above.
  export PATH="$BATS_TEST_TMPDIR/stubs:$BATS_TEST_TMPDIR/guards:$PATH"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/home" && "$K3DM_REPO_SYNC_STATE_DIR" == "$BATS_TEST_TMPDIR/repo-sync" ]]
  [[ -d "$WORK/.git" && "$(command -v make)" == "$BATS_TEST_TMPDIR/stubs/make" && "$(command -v launchctl)" == "$BATS_TEST_TMPDIR/stubs/launchctl" && "$(command -v curl)" == "$BATS_TEST_TMPDIR/stubs/curl" ]]
  [[ "$K3DM_JOB_DIR" == "$BATS_TEST_TMPDIR"/* ]]
}

teardown() {
  [ ! -s "$BATS_TEST_TMPDIR/sudo.hit" ] || { echo 'sudo guard was hit' >&2; return 1; }
  [ ! -s "$BATS_TEST_TMPDIR/launchctl.hit" ] || { echo 'launchctl guard was hit' >&2; return 1; }
}

_prepare_e4_approval() {
  : > "$BATS_TEST_TMPDIR/e4-make-args"
  : > "$BATS_TEST_TMPDIR/e4-make-env"
  export APPROVAL_NEW_SHA="$CHANGED_SHA" APPROVAL_OLD_SHA="$BASE_SHA" E4_MAKE_MODE=1 E4_GOT_SHA="$OTHER_SHA" CHANGED_SHA OTHER_SHA
}

_prepare_agent_change() {
  "$REAL_GIT" -C "$WORK" checkout -q changed
  mkdir -p "$WORK/scripts/lib/webhook"
  printf 'changed agent code\n' > "$WORK/scripts/lib/webhook/agent.py"
  "$REAL_GIT" -C "$WORK" add scripts/lib/webhook/agent.py
  "$REAL_GIT" -C "$WORK" commit -qm 'fixture webhook code change'
  CHANGED_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  export CHANGED_SHA
  "$REAL_GIT" -C "$WORK" push --quiet origin "$CHANGED_SHA:refs/heads/agent-change"
  "$REAL_GIT" -C "$WORK" branch -f agent-change "$CHANGED_SHA"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$BASE_SHA"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.test-launchctl"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  touch "$HOME/.test-launchctl/com.k3d-manager.webhook"
  printf '700\n' > "$HOME/.test-launchctl/com.k3d-manager.webhook.pid"
}

_prepare_agent_docs_change() {
  "$REAL_GIT" -C "$WORK" checkout -q changed
  printf 'docs only\n' > "$WORK/agent-docs.md"
  "$REAL_GIT" -C "$WORK" add agent-docs.md
  "$REAL_GIT" -C "$WORK" commit -qm 'fixture docs only'
  CHANGED_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  export CHANGED_SHA
  "$REAL_GIT" -C "$WORK" push --quiet origin "+$CHANGED_SHA:refs/heads/agent-docs"
  "$REAL_GIT" -C "$WORK" branch -f agent-docs "$CHANGED_SHA"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$BASE_SHA"
}

_write_agent_state() {
  local sha="$1"
  mkdir -p "$HOME/.local/share/k3d-manager/hub-deploy"
  printf 'appsets %s\nlaunchd %s\nagents %s\n' "$sha" "$sha" "$sha" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents: changed webhook code restarts once and records the promoted sha' {
  _prepare_agent_change
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" == *'restarted webhook (pid 701)'* && "$output" == *'; agents restarted'* ]]
  [[ "$output" != *'cloud-bridge'* ]]
  [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
  grep -qx "agents $CHANGED_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
  grep -q 'http://127.0.0.1:7443/api/v1/health' "$BATS_TEST_TMPDIR/curl.args"
  run ! grep -q -- '-H\|Authorization' "$BATS_TEST_TMPDIR/curl.args"
}

@test 'agents: a fresh queued job defers without advancing state' {
  _prepare_agent_change
  mkdir -p "$K3DM_JOB_DIR/job-queued"
  printf ' queued \n' > "$K3DM_JOB_DIR/job-queued/status"
  run --separate-stderr env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 3 ]
  [[ "$output" == *'; agents pending'* && "$stderr" == *'webhook job job-queued is queued'* ]]
  [ "$(grep -cx restart-webhook "$CALLS" || true)" -eq 0 ]
  run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents M2: docs-only change advances agents without restarting' {
  _prepare_agent_docs_change
  _write_agent_state "$BASE_SHA"
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-docs
  [ "$status" -eq 0 ]
  [[ "$output" == *'agents unchanged between '* ]]
  [[ "$output" == *'; agents unchanged' ]]
  [ "$(grep -cx restart-webhook "$CALLS" || true)" -eq 0 ]
  grep -qx "agents $CHANGED_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents M3: two-line state is accepted and agent change restarts' {
  _prepare_agent_change
  mkdir -p "$HOME/.local/share/k3d-manager/hub-deploy"
  printf 'appsets %s\nlaunchd %s\n' "$BASE_SHA" "$BASE_SHA" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" != *'state unreadable'* && "$output" == *'; agents restarted' ]]
  [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
}

@test 'agents M3: garbage line after agents state triggers recovery and restart' {
  _prepare_agent_change
  mkdir -p "$HOME/.local/share/k3d-manager/hub-deploy"
  printf 'appsets %s\nlaunchd %s\nagents %s\ngarbage\n' "$BASE_SHA" "$BASE_SHA" "$BASE_SHA" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" == *'state unreadable; full launchd reconcile and appsets reapply owed'* && "$output" == *'; agents restarted' ]]
  [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
}

@test 'agents M3: invalid agents lines each force unreadable-state recovery' {
  _prepare_agent_change
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/share/k3d-manager/hub-deploy"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  for invalid_agent in full not-a-sha "$(printf 'z%.0s' {1..40})" "$(printf 'f%.0s' {1..40})"; do
    : > "$CALLS"
    if [[ "$invalid_agent" == full ]]; then
      printf 'appsets %s\nlaunchd %s\nagents full\n' "$BASE_SHA" "$BASE_SHA" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
    elif [[ "$invalid_agent" == not-a-sha ]]; then
      printf 'appsets %s\nlaunchd %s\nagents not-a-sha\n' "$BASE_SHA" "$BASE_SHA" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
    elif [[ "$invalid_agent" == "$(printf 'z%.0s' {1..40})" ]]; then
      printf 'appsets %s\nlaunchd %s\nagents %s\nagents %s\n' "$BASE_SHA" "$BASE_SHA" "$BASE_SHA" "$BASE_SHA" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
    else
      printf 'appsets %s\nlaunchd %s\nagents %s\n' "$BASE_SHA" "$BASE_SHA" "$invalid_agent" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
    fi
    run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
    [ "$status" -eq 0 ]
    [[ "$output" == *'state unreadable'* ]]
    [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
  done
}

@test 'agents M4: missing webhook plist records not-installed and skips restart' {
  _prepare_agent_change
  rm -f "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist" "$HOME/.test-launchctl/com.k3d-manager.webhook"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" == *'agents: webhook not installed on this host; skipping'* && "$output" == *'; agents not installed' ]]
  [ "$(grep -cx restart-webhook "$CALLS" || true)" -eq 0 ]
  grep -qx "agents $CHANGED_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents M5: fresh running job defers without advancing state' {
  _prepare_agent_change
  mkdir -p "$K3DM_JOB_DIR/job-running"
  printf 'running\n' > "$K3DM_JOB_DIR/job-running/status"
  run --separate-stderr env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 3 ]
  [[ "$output" == *'; agents pending'* && "$stderr" == *'webhook job job-running is running'* ]]
  [ "$(grep -cx restart-webhook "$CALLS" || true)" -eq 0 ]
  run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents M5: stale running and success jobs do not defer restart' {
  _prepare_agent_change
  mkdir -p "$K3DM_JOB_DIR/job-stale" "$K3DM_JOB_DIR/job-success"
  printf 'running\n' > "$K3DM_JOB_DIR/job-stale/status"
  printf 'success\n' > "$K3DM_JOB_DIR/job-success/status"
  touch -t 200001010000 "$K3DM_JOB_DIR/job-stale/status"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" == *'; agents restarted' ]]
  [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
}

@test 'agents M6 N6: rollback re-promote restarts when old-to-new includes agent code' {
  _prepare_agent_change
  _write_agent_state "$CHANGED_SHA"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$BASE_SHA:refs/heads/deploy/hub"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" == *'; agents restarted' && "$output" != *'agents unchanged'* ]]
  [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
}

@test 'agents N3: disabled load defers without advancing' {
  _prepare_agent_change
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  run --separate-stderr env K3DM_AGENT_LOAD=0 PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 3 ]
  [[ "$stderr" == *'agent load disabled (K3DM_AGENT_LOAD=0)'* ]]
  run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"

  run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents N3: checkout mismatch defers without advancing' {
  _prepare_agent_change
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  install_fixture
  run --separate-stderr env PROMOTE_TO_SHA="$CHANGED_SHA" MOVE_HEAD=1 MOVE_TO="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 3 ]
  [[ "$stderr" == *'hub checkout is not at '* ]]
  run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test 'agents N3: failed restart and confirmation timeouts preserve agents state' {
  _prepare_agent_change
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  run --separate-stderr env PROMOTE_TO_SHA="$CHANGED_SHA" FAIL_STEP=restart-webhook "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'stopped at agent-restart'* && "$stderr" == *'webhook is loaded (pid 700)'* && "$stderr" == *'cloud-bridge is not installed'* ]]
  run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"

  for knob in pid curl; do
    : > "$CALLS"
    if [[ "$knob" == pid ]]; then run --separate-stderr env PROMOTE_TO_SHA="$CHANGED_SHA" NO_PID_BUMP=1 "$WORK/bin/k3dm-hub-deploy" agent-change
    else run --separate-stderr env PROMOTE_TO_SHA="$CHANGED_SHA" CURL_CODE=000 "$WORK/bin/k3dm-hub-deploy" agent-change; fi
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'webhook is '* && "$stderr" == *'restore with make restart-webhook'* ]]
    run ! grep -q '^agents ' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  done
}

@test 'agents N5: launchctl prints only; restart-webhook handles the bridge and curl stays unauthenticated' {
  _prepare_agent_change
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.cloud-bridge.plist"
  touch "$HOME/.test-launchctl/com.k3d-manager.cloud-bridge"
  printf '800\n' > "$HOME/.test-launchctl/com.k3d-manager.cloud-bridge.pid"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-change
  [ "$status" -eq 0 ]
  [[ "$output" == *'restarted webhook (pid 701) and cloud-bridge (pid 801)'* ]]
  [ "$(grep -cx restart-webhook "$CALLS")" -eq 1 ]
  [ "$(grep '^launchctl ' "$CALLS" | grep -vc 'launchctl print ' || true)" -eq 0 ]
  [[ "$(<"$CALLS")" != *restart-cloud-bridge* ]]
  run ! grep -q '^launchctl kickstart ' "$CALLS"
  run ! grep -q -- '-H\|Authorization' "$BATS_TEST_TMPDIR/curl.args"
}

@test 'agents summary places agents after unwired launchd count' {
  _prepare_agent_docs_change
  _write_agent_state "$BASE_SHA"
  mkdir -p "$WORK/scripts/etc/launchd" "$HOME/Library/LaunchAgents"
  printf 'unknown\n' > "$WORK/scripts/etc/launchd/com.k3d-manager.unwired-fixture.plist.tmpl"
  "$REAL_GIT" -C "$WORK" add scripts/etc/launchd/com.k3d-manager.unwired-fixture.plist.tmpl
  "$REAL_GIT" -C "$WORK" commit -qm 'fixture unwired agent template'
  CHANGED_SHA="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"; export CHANGED_SHA
  "$REAL_GIT" -C "$WORK" push --quiet origin "+$CHANGED_SHA:refs/heads/agent-docs"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.unwired-fixture.plist"
  : > "$HOME/Library/LaunchAgents/com.k3d-manager.webhook.plist"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" agent-docs
  [ "$status" -eq 0 ]
  [[ "$output" == *'; launchd unwired 1; agents unchanged' ]]
}

@test "M1: changed ApplicationSets run every step in order" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" fixture-changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'reapply ran; appsets-check ok; platform-ops ok; exporter rolled out'* ]]
  [[ "$output" == *"continuing with the promoted copy at ${CHANGED_SHA:0:7}"* ]]
  grep -qx "stage2 $CHANGED_SHA prev=$BASE_SHA" "$CALLS"
  [ "$(grep -c '^promote ' "$CALLS")" -eq 1 ]
  [ "$(grep -cx appsets-check "$CALLS")" -eq 1 ]
  [ "$(grep -cx platform-ops "$CALLS")" -eq 1 ]
  [[ "$output" == *"${BASE_SHA:0:7}..${CHANGED_SHA:0:7}"* ]]
}

@test "M4: resolved promoted ref is bound before checkout catch-up" {
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" "$OTHER_SHA"
  [ "$status" -eq 1 ]
  [[ "$output" == *'not the promoted'*'superseded'* ]]
  [ "$(grep -cx appsets-check "$CALLS" || true)" -eq 0 ]
}

@test "M5: direct stage 2 validates inputs and never promotes" {
  run env K3DM_HUB_DEPLOY_PREV=bad "$WORK/bin/k3dm-hub-deploy" "$CHANGED_SHA"
  [ "$status" -eq 2 ]
  [[ "$output" == *'K3DM_HUB_DEPLOY_PREV must be a commit sha'* ]]
  run env K3DM_HUB_DEPLOY_PREV="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" not-a-sha
  [ "$status" -eq 2 ]
  [[ "$output" == *'K3DM_HUB_DEPLOY_PREV must be a commit sha'* ]]
  "$REAL_GIT" -C "$WORK" push --quiet origin "$CHANGED_SHA:refs/heads/deploy/hub"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$CHANGED_SHA"
  run env K3DM_HUB_DEPLOY_PREV="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" "$CHANGED_SHA"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^promote ' "$CALLS" || true)" -eq 0 ]
  grep -qx 'child-prev=unset' "$CALLS"
  : > "$CALLS"
  "$REAL_GIT" -C "$WORK" push --quiet origin "+$OTHER_SHA:refs/heads/deploy/hub"
  run env K3DM_HUB_DEPLOY_PREV="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" "$CHANGED_SHA"
  [ "$status" -eq 1 ]
  [[ "$output" == *'before the promoted copy ran; superseded'* ]]
  [ "$(grep -cx appsets-check "$CALLS" || true)" -eq 0 ]
  "$REAL_GIT" -C "$WORK" push --quiet origin "+$CHANGED_SHA:refs/heads/deploy/hub"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$BASE_SHA"
  run env K3DM_HUB_DEPLOY_PREV="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" "$CHANGED_SHA"
  [ "$status" -eq 1 ]
  [[ "$output" == *'before the promoted copy ran; superseded'* ]]
  [ "$(grep -cx appsets-check "$CALLS" || true)" -eq 0 ]
}

@test "M2: dirty checkout stops before apply and preserves appsets state" {
  mkdir -p "$HOME/.local/share/k3d-manager/hub-deploy"
  printf 'appsets %s\nlaunchd %s\n' "$BASE_SHA" "$BASE_SHA" > "$HOME/.local/share/k3d-manager/hub-deploy/state"
  printf 'dirty\n' >> "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" fixture-changed
  [ "$status" -eq 1 ]
  [[ "$output" == *'nothing applied'*'stopped at checkout-catch-up'* ]]
  [ "$(grep -cx appsets-check "$CALLS" || true)" -eq 0 ]
  [ "$(grep -cx platform-ops "$CALLS" || true)" -eq 0 ]
  grep -qx "appsets $BASE_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
  [ ! -e "$K3DM_REPO_SYNC_STATE_DIR/lock" ]
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

@test "M3: promoted revision without handoff continues in the running copy" {
  "$REAL_GIT" -C "$WORK" checkout -q fixture-changed
  sed 's/K3DM_HUB_DEPLOY_PREV/OLD_STAGE_HANDOFF/g' "$WORK/bin/k3dm-hub-deploy" > "$WORK/bin/k3dm-hub-deploy.tmp"
  mv "$WORK/bin/k3dm-hub-deploy.tmp" "$WORK/bin/k3dm-hub-deploy"
  chmod +x "$WORK/bin/k3dm-hub-deploy"
  "$REAL_GIT" -C "$WORK" add bin/k3dm-hub-deploy
  "$REAL_GIT" -C "$WORK" commit -qm 'fixture revision without handoff'
  no_handoff_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  "$REAL_GIT" -C "$WORK" push --quiet origin "$no_handoff_sha:refs/heads/deploy/hub"
  : > "$CALLS"
  "$REAL_GIT" -C "$WORK" checkout -q --detach "$BASE_SHA"
  run "$WORK/bin/k3dm-hub-deploy" "$no_handoff_sha"
  [ "$status" -eq 0 ]
  [[ "$output" == *'promoted copy has no handoff; continuing with the running copy'* ]]
  [ "$(grep -cx appsets-check "$CALLS")" -eq 1 ]
  [ "$(grep -c '^stage2 ' "$CALLS" || true)" -eq 0 ]
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
  # shellcheck disable=SC2016
  grep -q 'k3dm-hub-promote.*promote.*"\$ref"' "$WORK/bin/k3dm-hub-deploy"
  grep -q "confirmation requires a TTY" "$REPO/bin/k3dm-hub-promote"
  grep -q 'answer.*promote' "$REPO/bin/k3dm-hub-promote"
}

@test "promoter's confirmation details appear before its prompt and stdin reaches it" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  # shellcheck disable=SC2016
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
  # shellcheck disable=SC2016
  [[ "$output" == *'bin/k3dm-hub-deploy "$REF"'* ]]
  grep -q '^\.PHONY:.*hub-deploy' "$WORK/Makefile"
  [[ "$output" == *'usage: make hub-deploy REF='* ]] || grep -q 'hub-deploy REF=\.\.\.' "$WORK/Makefile"
}

@test "hub-deploy passes check-run outage environment" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env SKIP_CHECK_RUNS=1 SKIP_CHECK_RUNS_REASON=outage PROMOTE_TO_SHA="$OTHER_SHA" "$WORK/bin/k3dm-hub-deploy" fixture-other
  [ "$status" -eq 0 ]
  grep -qx 'skip=1 reason=outage' "$CALLS"
}

@test "P1 superseded stops before rollout" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run env PROMOTE_TO_SHA="$CHANGED_SHA" PIN_OVERRIDE="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" fixture-changed
  [ "$status" -eq 1 ]
  [[ "$output" == *'deploy/hub has moved on; superseded'* ]]
  [ "$(grep -cx rollout "$CALLS" || true)" -eq 0 ]
}

@test "P1 first run writes complete state" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  run "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 0 ]
  [[ "$output" == *'no reconcile state yet; full launchd reconcile owed'* ]]
  grep -qx "appsets $BASE_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
  grep -qx "launchd $BASE_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test "P1 docs teach the deployment and old copies fail" {
  [[ "$(cat "$FIXTURE_ROOT")" == fixture ]]
  grep -q 'make hub-deploy REF=<commit-ish>' "$REPO/CLAUDE.md"
  grep -q 'make hub-deploy REF=<commit-ish>' "$REPO/docs/process/rules.md"
  grep -q 'pending reinstall is retried' "$REPO/docs/howto/hub-promote.md"
  grep -q 'reinstalls changed launchd agents' "$REPO/Makefile"
  old_docs="$REPO/scripts/tests/fixtures/remote-promote-1-docs"
  [ "$(grep -c 'make hub-deploy REF=<commit-ish>' "$old_docs/CLAUDE.md" || true)" -eq 0 ]
  [ "$(grep -c 'make hub-deploy REF=<commit-ish>' "$old_docs/docs/process/rules.md" || true)" -eq 0 ]
  [ "$(grep -c 'pending reinstall is retried' "$old_docs/docs/howto/hub-promote.md" || true)" -eq 0 ]
  [ "$(grep -c 'reinstalls changed launchd agents' "$old_docs/help.txt" || true)" -eq 0 ]
}

install_fixture() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.test-launchctl"
  printf 'old plist\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  touch "$HOME/.test-launchctl/com.k3d-manager.sandbox-reaper"
  "$REAL_GIT" -C "$WORK" checkout -q changed
}

@test "P1 reinstall journals and verifies a real rewrite" {
  install_fixture
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'launchd ran 0'* ]]
  grep -qx install-sandbox-reaper "$CALLS"
  grep -qx "head $CHANGED_SHA" "$BATS_TEST_TMPDIR/install-details"
  grep -qx 'clean ' "$BATS_TEST_TMPDIR/install-details"
  grep -qx 'agent-load unset' "$BATS_TEST_TMPDIR/install-details"
  grep -qx 'fd9 open' "$BATS_TEST_TMPDIR/install-details"
  grep -q '^state-at-install-sandbox-reaper$' "$BATS_TEST_TMPDIR/state-snapshots"
  grep -qx 'pending sandbox-reaper' "$BATS_TEST_TMPDIR/state-snapshots"
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
  grep -qx changed "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
}

@test "P1 dirty checkout is pending while clean checkout installs" {
  install_fixture
  printf 'dirty\n' >> "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 1 ]
  [[ "$output" == *'nothing applied'*'checkout-catch-up'* ]]
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 0 ]
  [ "$(grep -cx appsets-check "$CALLS" || true)" -eq 0 ]
  "$REAL_GIT" -C "$WORK" checkout -- scripts/etc/argocd/applicationsets/test.yaml
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test "P1 disabled load persists and later retries" {
  install_fixture
  run env K3DM_AGENT_LOAD=0 PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'agent load disabled (K3DM_AGENT_LOAD=0)'* ]]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 0 ]
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test "P1 unchanged plist and failed load stay pending, successful rewrite clears it" {
  install_fixture
  touch -t 203501010000 "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  run env NO_REWRITE=1 PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'plist not rewritten'* ]]
  run env RESTORE_MTIME=1 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'plist not rewritten'* ]]
  run env PRINT_FAIL=1 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'plist written but not loaded'* ]]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
}

@test "P1 failed reapply retains its base and retries" {
  run env PROMOTE_TO_SHA="$CHANGED_SHA" FAIL_STEP=appsets-reapply "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 23 ]
  grep -qx "appsets $BASE_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [ "$(grep -cx appsets-reapply "$CALLS")" -eq 2 ]
  grep -qx "appsets $CHANGED_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test "P1 exit 75 from TTY-path child is remapped" {
  run env PROMOTE_FAIL=75 "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 1 ]
  [[ "$output" == *'(child exit 75)'* ]]
  run env FAIL_REMOTE=1 REMOTE_FAIL_CODE=75 "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 1 ]
  [[ "$output" == *'(child exit 75)'* ]]
  run env FAIL_STEP=appsets-check FAIL_CODE=75 "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 1 ]
  [[ "$output" == *'(child exit 75)'* ]]
  run "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 0 ]
}

@test "P1 lost state forces reapply while a valid state skips it" {
  state_dir="$HOME/.local/share/k3d-manager/hub-deploy"
  mkdir -p "$state_dir"
  printf 'partial\n' > "$state_dir/state.tmp.12345"
  run "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 0 ]
  [[ "$output" == *'state unreadable; full launchd reconcile and appsets reapply owed'* ]]
  grep -qx appsets-reapply "$CALLS"
  : > "$CALLS"
  run "$WORK/bin/k3dm-hub-deploy" fixture-base
  [ "$status" -eq 0 ]
  [ "$(grep -cx appsets-reapply "$CALLS" || true)" -eq 0 ]
}

@test "P1 excluded and unwired agents are skipped while wired agent installs" {
  install_fixture
  mkdir -p "$HOME/Library/LaunchAgents"
  for name in webhook-token-rotate dispatch-stall-watch dispatch-metrics webhook hermes heartbeat prometheus-auth-proxy vault-failover; do
    printf 'template\n' > "$WORK/scripts/etc/launchd/com.k3d-manager.$name.plist.tmpl"
    printf 'installed\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.$name.plist"
  done
  "$REAL_GIT" -C "$WORK" add scripts/etc/launchd
  "$REAL_GIT" -C "$WORK" commit -qm 'extra templates'
  fixture_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  run env PROMOTE_TO_SHA="$fixture_sha" "$WORK/bin/k3dm-hub-deploy" extra
  [ "$status" -eq 0 ]
  [[ "$output" == *'launchd unwired 5'* ]]
  [[ "$output" == *'launchd webhook-token-rotate is excluded'* ]]
  grep -qx install-sandbox-reaper "$CALLS"
  [ "$(grep -Ec '^(install-token-rotator|install-dispatch|install-webhook|install-hermes|install-heartbeat|install-prometheus-auth-proxy|install-vault-failover)' "$CALLS" || true)" -eq 0 ]
}

@test "P1 fresh pidless lock is retained and dead owner lock is recovered" {
  install_fixture
  mkdir -p "$K3DM_REPO_SYNC_STATE_DIR/lock"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 1 ]
  [[ "$output" == *'checkout-catch-up'* ]]
  [ -d "$K3DM_REPO_SYNC_STATE_DIR/lock" ]
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 0 ]
  printf '99999999\n' > "$K3DM_REPO_SYNC_STATE_DIR/lock/pid"
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test "P1 superseded run records the applied appsets base" {
  run env PROMOTE_TO_SHA="$CHANGED_SHA" PIN_OVERRIDE="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 1 ]
  grep -qx "appsets $CHANGED_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
  grep -qx 'launchd full' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  : > "$CALLS"
  "$REAL_GIT" -C "$WORK" checkout -q changed
  "$REAL_GIT" -C "$WORK" checkout "$BASE_SHA" -- scripts/etc/argocd/applicationsets/test.yaml
  "$REAL_GIT" -C "$WORK" commit -qm revert
  revert_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  run env PROMOTE_TO_SHA="$revert_sha" "$WORK/bin/k3dm-hub-deploy" revert
  [ "$status" -eq 0 ]
  grep -qx appsets-reapply "$CALLS"
  printf 'again\n' > "$WORK/scripts/etc/argocd/applicationsets/test.yaml"
  "$REAL_GIT" -C "$WORK" commit -qam again
  again_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  run env PROMOTE_TO_SHA="$again_sha" "$WORK/bin/k3dm-hub-deploy" again
  [ "$status" -eq 0 ]
  "$REAL_GIT" -C "$WORK" checkout "$revert_sha" -- scripts/etc/argocd/applicationsets/test.yaml
  "$REAL_GIT" -C "$WORK" commit -qm revert-again
  last_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  : > "$CALLS"
  run env PROMOTE_TO_SHA="$last_sha" "$WORK/bin/k3dm-hub-deploy" revert-again
  [ "$status" -eq 0 ]
  grep -qx appsets-reapply "$CALLS"
}

@test "P1 installer keeps run lock after deploy is killed" {
  install_fixture
  env PROMOTE_TO_SHA="$CHANGED_SHA" LATE_INSTALL=1 "$WORK/bin/k3dm-hub-deploy" changed > "$BATS_TEST_TMPDIR/first-output" 2>&1 &
  deploy_pid=$!
  # shellcheck disable=SC2034
  for unused in {1..100}; do
    [[ ! -e "$BATS_TEST_TMPDIR/installer-ready" ]] || break
    sleep 0.1
  done
  [ -e "$BATS_TEST_TMPDIR/installer-ready" ]
  kill -9 "$deploy_pid"
  wait "$deploy_pid" 2>/dev/null || true
  "$REAL_GIT" -C "$WORK" checkout "$BASE_SHA" -- scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl
  "$REAL_GIT" -C "$WORK" commit -qm revert-template
  revert_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  run env PROMOTE_TO_SHA="$revert_sha" "$WORK/bin/k3dm-hub-deploy" revert
  [ "$status" -eq 75 ]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  touch "$BATS_TEST_TMPDIR/installer-go"
  for unused in {1..100}; do
    [[ ! -e "$BATS_TEST_TMPDIR/installer-done" ]] || break
    sleep 0.1
  done
  [ -e "$BATS_TEST_TMPDIR/installer-done" ]
  for unused in {1..100}; do
    run env PROMOTE_TO_SHA="$revert_sha" "$WORK/bin/k3dm-hub-deploy" revert
    [[ "$status" == 75 ]] || break
    sleep 0.1
  done
  [ "$status" -eq 0 ]
  grep -qx base "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
}

@test "P1 unrelated child does not keep run lock after deploy is killed" {
  env SLEEP_CHILD=1 "$WORK/bin/k3dm-hub-deploy" base > "$BATS_TEST_TMPDIR/first-output" 2>&1 &
  deploy_pid=$!
  # shellcheck disable=SC2034
  for unused in {1..100}; do
    [[ ! -e "$BATS_TEST_TMPDIR/sleeper-ready" ]] || break
    sleep 0.1
  done
  [ -e "$BATS_TEST_TMPDIR/sleeper-ready" ]
  run "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 75 ]
  kill -9 "$deploy_pid"
  wait "$deploy_pid" 2>/dev/null || true
  run "$WORK/bin/k3dm-hub-deploy" base
  result="$status"
  kill "$(cat "$BATS_TEST_TMPDIR/make-pid")" "$(cat "$BATS_TEST_TMPDIR/sleeper-pid")" 2>/dev/null || true
  [ "$result" -eq 0 ]
}

@test "P1 journal survives death after rewrite and a template revert" {
  mkdir -p "$HOME/Library/LaunchAgents"
  printf 'old plist\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  "$REAL_GIT" -C "$WORK" checkout -qb original "$BASE_SHA"
  run "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 0 ]
  "$REAL_GIT" -C "$WORK" checkout -q changed
  run env PROMOTE_TO_SHA="$CHANGED_SHA" KILL_DEPLOY=1 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -ne 0 ]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  "$REAL_GIT" -C "$WORK" checkout "$BASE_SHA" -- scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl
  "$REAL_GIT" -C "$WORK" commit -qm revert-template
  revert_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  : > "$CALLS"
  run env PROMOTE_TO_SHA="$revert_sha" "$WORK/bin/k3dm-hub-deploy" revert
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
  grep -qx base "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
}

@test "P1 moved checkout and lost lock after install are pending" {
  install_fixture
  run env PROMOTE_TO_SHA="$CHANGED_SHA" MOVE_HEAD=1 MOVE_TO="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'checkout moved during install'* ]]
  "$REAL_GIT" -C "$WORK" checkout -q changed
  run env BREAK_PID=1 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'checkout lock lost'* ]]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  rm -rf "$K3DM_REPO_SYNC_STATE_DIR/lock"
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
}

@test "P1 template blob check rejects edited bytes even if status reports clean" {
  install_fixture
  printf 'edited\n' >> "$WORK/scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl"
  run env FAKE_CLEAN=1 PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 0 ]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  "$REAL_GIT" -C "$WORK" checkout -- scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test "P1 failed install stays soft but failed platform step stops" {
  install_fixture
  run env PROMOTE_TO_SHA="$CHANGED_SHA" FAIL_STEP=install-sandbox-reaper FAIL_CODE=7 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" == *'install failed (exit 7)'* ]]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  run env FAIL_STEP=platform-ops FAIL_CODE=37 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 37 ]
  [[ "$output" == *'stopped at platform-ops'* ]]
}

@test "P1 first failed install retries at the same ref" {
  install_fixture
  run env PROMOTE_TO_SHA="$CHANGED_SHA" FAIL_STEP=install-sandbox-reaper FAIL_CODE=7 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  : > "$CALLS"
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
}

@test "P1 invalid state forces recovery and valid state avoids it" {
  state_dir="$HOME/.local/share/k3d-manager/hub-deploy"
  mkdir -p "$state_dir"
  for bad in garbage duplicate-launchd duplicate-pending invalid-sha; do
    case "$bad" in
      garbage) printf 'appsets %s\nlaunchd %s\ngarbage\n' "$BASE_SHA" "$BASE_SHA" > "$state_dir/state" ;;
      duplicate-launchd) printf 'appsets %s\nlaunchd %s\nlaunchd %s\n' "$BASE_SHA" "$BASE_SHA" "$BASE_SHA" > "$state_dir/state" ;;
      duplicate-pending) printf 'appsets %s\nlaunchd %s\npending sandbox-reaper\npending sandbox-reaper\n' "$BASE_SHA" "$BASE_SHA" > "$state_dir/state" ;;
      invalid-sha) printf 'appsets %040d\nlaunchd %s\n' 0 "$BASE_SHA" > "$state_dir/state" ;;
    esac
    : > "$CALLS"
    run "$WORK/bin/k3dm-hub-deploy" base
    [ "$status" -eq 0 ]
    [[ "$output" == *'state unreadable; full launchd reconcile and appsets reapply owed'* ]]
    grep -qx appsets-reapply "$CALLS"
  done
  : > "$CALLS"
  run "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 0 ]
  [ "$(grep -cx appsets-reapply "$CALLS" || true)" -eq 0 ]
}

@test "P1 checkout behind and ahead both wait until the promoted commit" {
  mkdir -p "$HOME/Library/LaunchAgents"
  printf 'old plist\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  "$REAL_GIT" -C "$WORK" checkout -qb original "$BASE_SHA"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 1 ]
  [ "$("$REAL_GIT" -C "$WORK" rev-parse HEAD)" = "$CHANGED_SHA" ]
  "$REAL_GIT" -C "$WORK" checkout -q changed
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
  : > "$CALLS"
  "$REAL_GIT" -C "$WORK" checkout "$BASE_SHA" -- scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl
  "$REAL_GIT" -C "$WORK" commit -qm revert-template
  ahead_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  printf 'pending sandbox-reaper\n' >> "$HOME/.local/share/k3d-manager/hub-deploy/state"
  run "$WORK/bin/k3dm-hub-deploy" "$CHANGED_SHA"
  [ "$status" -eq 1 ]
  [[ "$output" == *'checkout-catch-up'* ]]
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 0 ]
  run env PROMOTE_TO_SHA="$ahead_sha" "$WORK/bin/k3dm-hub-deploy" "$ahead_sha"
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test "P1 checkout catches up by the short deadline" {
  mkdir -p "$HOME/Library/LaunchAgents"
  printf 'old plist\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  "$REAL_GIT" -C "$WORK" checkout -qb original "$BASE_SHA"
  ( sleep 1; "$REAL_GIT" -C "$WORK" checkout -q changed ) &
  checkout_pid=$!
  run env PROMOTE_TO_SHA="$CHANGED_SHA" K3DM_HUB_DEPLOY_CHECKOUT_WAIT=2 "$WORK/bin/k3dm-hub-deploy" changed
  wait "$checkout_pid"
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test "P1 two-line state is valid and writes retain private modes" {
  install_fixture
  state_dir="$HOME/.local/share/k3d-manager/hub-deploy"
  mkdir -p "$state_dir"
  printf 'appsets %s\nlaunchd full\n' "$BASE_SHA" > "$state_dir/state"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  [[ "$output" != *'state unreadable'* ]]
  grep -qx install-sandbox-reaper "$CALLS"
  if [[ "$(uname -s)" == Darwin ]]; then
    [ "$(/usr/bin/stat -f '%Lp' "$state_dir")" == 700 ]
    [ "$(/usr/bin/stat -f '%Lp' "$state_dir/state")" == 600 ]
  else
    [ "$(/usr/bin/stat -c '%a' "$state_dir")" == 700 ]
    [ "$(/usr/bin/stat -c '%a' "$state_dir/state")" == 600 ]
  fi
}

@test "P1 partial success then revert reinstalls both changed and pending agents" {
  mkdir -p "$HOME/Library/LaunchAgents"
  for name in cleanup sandbox-reaper; do printf 'old\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.$name.plist"; done
  "$REAL_GIT" -C "$WORK" checkout -qb original "$BASE_SHA"
  run "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 0 ]
  "$REAL_GIT" -C "$WORK" checkout -q changed
  run env PROMOTE_TO_SHA="$CHANGED_SHA" FAIL_STEP=install-sandbox-reaper FAIL_CODE=7 "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx changed "$HOME/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
  grep -qx 'pending sandbox-reaper' "$HOME/.local/share/k3d-manager/hub-deploy/state"
  "$REAL_GIT" -C "$WORK" checkout "$BASE_SHA" -- scripts/etc/launchd/com.k3d-manager.cleanup.plist.tmpl
  "$REAL_GIT" -C "$WORK" commit -qm revert-cleanup
  revert_sha="$("$REAL_GIT" -C "$WORK" rev-parse HEAD)"
  : > "$CALLS"
  run env PROMOTE_TO_SHA="$revert_sha" "$WORK/bin/k3dm-hub-deploy" revert
  [ "$status" -eq 0 ]
  grep -qx install-cleanup "$CALLS"
  grep -qx install-sandbox-reaper "$CALLS"
  grep -qx base "$HOME/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
  grep -qx changed "$HOME/Library/LaunchAgents/com.k3d-manager.sandbox-reaper.plist"
  [ "$(grep -c '^pending ' "$HOME/.local/share/k3d-manager/hub-deploy/state" || true)" -eq 0 ]
}

@test "P1 first run remains first after failure before state write" {
  run env FAIL_REMOTE=1 "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 43 ]
  [ ! -e "$HOME/.local/share/k3d-manager/hub-deploy/state" ]
  [ -e "$HOME/.local/share/k3d-manager/hub-deploy/run.lock" ]
  run "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 0 ]
  [[ "$output" == *'no reconcile state yet; full launchd reconcile owed'* ]]
  grep -qx "appsets $BASE_SHA" "$HOME/.local/share/k3d-manager/hub-deploy/state"
}

@test "P1 missing platform pin stops before rollout and valid pin proceeds" {
  run env PIN_MISSING=1 "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 1 ]
  [[ "$output" == *'stopped at platform-ops-pin'* ]]
  [ "$(grep -cx rollout "$CALLS" || true)" -eq 0 ]
  run "$WORK/bin/k3dm-hub-deploy" base
  [ "$status" -eq 0 ]
  grep -qx rollout "$CALLS"
}

@test "P1 launchd table covers the templates and exclusions match setup" {
  expected='alertmanager-auth-proxy alertmanager-port-forward cleanup cloud-bridge dispatch-metrics dispatch-stall-watch heartbeat hermes hub-data-export hub-loki-port-forward hub-pushgateway-port-forward hub-snapshot node-health-watch password-bundle prometheus-auth-proxy prometheus-credential-rotator prometheus-port-forward repo-sync sandbox-reaper test-metrics vault-failover vault-port-forward web-console-sshd web-console-totp webhook webhook-token-rotate'
  actual="$(for path in "$REPO"/scripts/etc/launchd/com.k3d-manager.*.plist.tmpl; do
    name="${path##*/com.k3d-manager.}"
    printf '%s\n' "${name%.plist.tmpl}"
  done | sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$actual" = "$expected" ]
  for name in webhook-token-rotate dispatch-stall-watch dispatch-metrics; do
    grep -q "^$name|" "$REPO/scripts/etc/machine/not-installed.list"
    grep -q "$name" "$REPO/bin/k3dm-hub-deploy"
  done
  for name in repo-sync prometheus-credential-rotator test-metrics hub-data-export cleanup node-health-watch sandbox-reaper vault-port-forward prometheus-port-forward hub-pushgateway-port-forward hub-loki-port-forward alertmanager-port-forward alertmanager-auth-proxy cloud-bridge hub-snapshot password-bundle; do
    grep -q "$name" "$REPO/bin/k3dm-hub-deploy"
  done
}

@test "P1 checkout moving during one install blocks later installs" {
  install_fixture
  printf 'old\n' > "$HOME/Library/LaunchAgents/com.k3d-manager.cleanup.plist"
  run env PROMOTE_TO_SHA="$CHANGED_SHA" MOVE_HEAD=1 MOVE_TO="$BASE_SHA" "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-cleanup "$CALLS"
  [ "$(grep -cx install-sandbox-reaper "$CALLS" || true)" -eq 0 ]
  [[ "$output" == *'checkout moved during install'* ]]
  "$REAL_GIT" -C "$WORK" checkout -q changed
  run "$WORK/bin/k3dm-hub-deploy" changed
  [ "$status" -eq 0 ]
  grep -qx install-sandbox-reaper "$CALLS"
}

@test 'E7 approval documentation describes the signed authority path and its limit' {
  files=(
    "$REPO/docs/process/rules.md"
    "$REPO/docs/howto/hub-promote.md"
    "$REPO/.github/copilot-instructions.md"
  )
  for file in "${files[@]}"; do [ -s "$file" ]; done
  rg -q 'Worker-signed envelope' "${files[0]}"
  rg -qi 'check value' "${files[0]}"
  rg -q 'Part 2e' "${files[0]}"
  rg -q 'gate on the honest path, not a barrier' "${files[0]}"
  rg -q 'Approved promote' "${files[1]}"
  rg -q 'signature' "${files[1]}"
  rg -q 'envelope_stale' "${files[1]}"
  rg -q 'bin/k3dm-hub-deploy <ref> --approval <id>' "${files[1]}"
  rg -qi 'exit 75' "${files[1]}"
  rg -q 'bin/k3dm-promote-client show' "${files[1]}"
  rg -q 'superseded' "${files[1]}"
  rg -q 'promote-authority\.md' "${files[1]}"
  rg -q 'promote authority' "${files[2]}"
}

@test 'E7 pre-change documentation copies fail the approval wording checks' {
  fixture="$REPO/scripts/tests/fixtures/remote-promote-2b-docs"
  for pattern in 'Worker-signed envelope' 'check value' 'Part 2e' 'gate on the honest path, not a barrier'; do
    run rg -qi -- "$pattern" "$fixture/rules.md"
    [ "$status" -ne 0 ] || { printf 'pre-change rules unexpectedly contains: %s\n' "$pattern" >&3; return 1; }
  done
  for pattern in 'Approved promote' 'signature' 'envelope_stale' 'bin/k3dm-hub-deploy <ref> --approval <id>' 'exit 75' 'bin/k3dm-promote-client show' 'superseded' 'promote-authority\.md'; do
    run rg -qi -- "$pattern" "$fixture/hub-promote.md"
    [ "$status" -ne 0 ] || { printf 'pre-change hub-promote unexpectedly contains: %s\n' "$pattern" >&3; return 1; }
  done
  run rg -q 'promote authority' "$fixture/copilot-instructions.md"
  [ "$status" -ne 0 ]
}

@test 'E4 approval takes both machine lines, seeds first-run state, and pins each make call' {
  _prepare_e4_approval
  run "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 0 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  grep -qx 'approval-state absent' "$CALLS"
  grep -q "skip=0 reason=" "$CALLS"
  [[ "$output" == *"no reconcile state yet; full launchd reconcile owed; appsets base ${BASE_SHA:0:7}"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/e4-state-at-make")" = $'appsets '"$BASE_SHA"$'\nlaunchd full' ]
  grep -q "APPSETS_SHA=$CHANGED_SHA" "$BATS_TEST_TMPDIR/e4-make-env"
  grep -q "PLATFORM_OPS_SHA=$CHANGED_SHA" "$BATS_TEST_TMPDIR/e4-make-env"
  [ "$(grep -c '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")" -eq 2 ]
  while IFS= read -r line; do path="${line#K3DM_SUPERSEDED_OUT=}"; [ ! -e "$path" ]; done < <(grep '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")
  grep -q 'appsets-reapply APPSETS_SHA=' "$BATS_TEST_TMPDIR/e4-make-args"
  grep -q 'platform-ops PLATFORM_OPS_SHA=' "$BATS_TEST_TMPDIR/e4-make-args"
}

@test 'E4 lost state with a temporary file requests full appsets and launchd work' {
  _prepare_e4_approval
  mkdir -p "$HOME/.local/share/k3d-manager/hub-deploy"
  : > "$HOME/.local/share/k3d-manager/hub-deploy/state.tmp.12345"
  run "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 0 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'state unreadable; full launchd reconcile and appsets reapply owed'* ]]
  grep -q "APPSETS_SHA=$CHANGED_SHA" "$BATS_TEST_TMPDIR/e4-make-env"
}

@test 'E4 remote moved after approval stops at superseded before make' {
  _prepare_e4_approval
  run env APPROVAL_MOVE_AFTER_PROMOTE=1 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 1 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'has been superseded'*'stopped at superseded'* ]]
  [ ! -s "$BATS_TEST_TMPDIR/e4-make-args" ]
}

@test 'E4 superseded make maps to 1 and removes its file while ordinary make failure stays 2' {
  _prepare_e4_approval
  run env E4_MAKE_SUPERSEDED=1 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 1 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'stopped at superseded'* ]]
  while IFS= read -r line; do path="${line#K3DM_SUPERSEDED_OUT=}"; [ ! -e "$path" ]; done < <(grep '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")

  _prepare_e4_approval
  run env E4_MAKE_FAIL=2 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 2 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'stopped at appsets-reapply'* ]]
  while IFS= read -r line; do path="${line#K3DM_SUPERSEDED_OUT=}"; [ ! -e "$path" ]; done < <(grep '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")

  _prepare_e4_approval
  run env E4_MAKE_FAIL=75 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 1 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'stopped at appsets-reapply (child exit 75)'* ]]
  while IFS= read -r line; do path="${line#K3DM_SUPERSEDED_OUT=}"; [ ! -e "$path" ]; done < <(grep '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")
}

@test 'E4 platform-ops superseded maps to 1 and removes its recorded file' {
  _prepare_e4_approval
  run --separate-stderr env E4_MAKE_STEP=platform-ops E4_MAKE_SUPERSEDED=1 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 1 ]
  grep -q 'platform-ops PLATFORM_OPS_SHA=' "$BATS_TEST_TMPDIR/e4-make-args"
  [[ "$stderr" == *'has been superseded'* ]]
  [[ "$stderr" == *'stopped at superseded'* ]]
  while IFS= read -r line; do path="${line#K3DM_SUPERSEDED_OUT=}"; [ ! -e "$path" ]; done < <(grep '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")
}

@test 'E4 platform-ops ordinary failures retain step mapping without superseded' {
  for code in 2 75; do
    _prepare_e4_approval
    run --separate-stderr env E4_MAKE_STEP=platform-ops E4_MAKE_FAIL="$code" "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
    if [[ "$code" == 2 ]]; then
      [ "$status" -eq 2 ]
      [[ "$stderr" == *'stopped at platform-ops:'* ]]
    else
      [ "$status" -eq 1 ]
      [[ "$stderr" == *'stopped at platform-ops (child exit 75)'* ]]
    fi
    [[ "$stderr" != *'has been superseded'* ]]
    grep -q 'platform-ops PLATFORM_OPS_SHA=' "$BATS_TEST_TMPDIR/e4-make-args"
    while IFS= read -r line; do path="${line#K3DM_SUPERSEDED_OUT=}"; [ ! -e "$path" ]; done < <(grep '^K3DM_SUPERSEDED_OUT=' "$BATS_TEST_TMPDIR/e4-make-env")
  done
}

@test 'E4 malformed promote machine output and ls-remote failure map to 75 after client call' {
  _prepare_e4_approval
  run env APPROVAL_BAD_OUTPUT=1 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 75 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'stopped at promote'* ]]
  [[ "$output" == *"rerun bin/k3dm-hub-deploy $CHANGED_SHA --approval p123-abcdef12"* ]]

  _prepare_e4_approval
  run env FAIL_REMOTE=1 REMOTE_FAIL_CODE=43 "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-abcdef12
  [ "$status" -eq 75 ]
  grep -qx "approval-argv promote fixture-changed --approval p123-abcdef12" "$CALLS"
  [[ "$output" == *'stopped at read-promoted-ref'* ]]
  [[ "$output" == *"rerun bin/k3dm-hub-deploy $CHANGED_SHA --approval p123-abcdef12"* ]]
}

@test 'E4 malformed approval id and misplaced approval exit 2 before hub-promote' {
  run "$WORK/bin/k3dm-hub-deploy" fixture-changed --approval p123-bad
  [ "$status" -eq 2 ]
  [[ "$output" == *'usage: k3dm-hub-deploy <ref> [--approval <id>]'* ]]
  [ "$(grep -c '^promote ' "$CALLS" || true)" -eq 0 ]
  run "$WORK/bin/k3dm-hub-deploy" fixture-changed extra --approval p123-abcdef12
  [ "$status" -eq 2 ]
  [ "$(grep -c '^promote ' "$CALLS" || true)" -eq 0 ]
}
