#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TEST_SYNC_BIN="${REPO_SYNC_BIN:-$PROJECT_ROOT/bin/k3dm-repo-sync}"
  SCRATCH="$BATS_TEST_TMPDIR/repo-sync"
  case "$SCRATCH" in "$BATS_TEST_TMPDIR"/*) ;; *) return 1 ;; esac
  mkdir -p "$SCRATCH/bin" "$SCRATCH/home/.config/k3d-manager" "$SCRATCH/state"
  printf 'worker\n' > "$SCRATCH/home/.config/k3d-manager/machine-role"
  export HOME="$SCRATCH/home" XDG_CONFIG_HOME="$SCRATCH/home/.config"
  export K3DM_REPO_SYNC_STATE_DIR="$SCRATCH/state" K3DM_REPO_SYNC_TIMEOUT=3
  export K3DM_REPO_SYNC_REPOS="$SCRATCH/clone"
  REAL_GIT="$(command -v git)"
  REAL_MAKE="$(command -v make)"
  export REAL_GIT REAL_MAKE
  git init --bare "$SCRATCH/upstream.git" >/dev/null
  git clone "$SCRATCH/upstream.git" "$SCRATCH/seed" >/dev/null 2>&1
  git -C "$SCRATCH/seed" config user.email test@example.invalid
  git -C "$SCRATCH/seed" config user.name test
  git -C "$SCRATCH/seed" checkout -b main >/dev/null
  echo base > "$SCRATCH/seed/file"
  mkdir -p "$SCRATCH/seed/scripts/etc/argocd/platform-ops"
  echo baseline > "$SCRATCH/seed/scripts/etc/argocd/platform-ops/base.yaml"
  git -C "$SCRATCH/seed" add file scripts
  git -C "$SCRATCH/seed" commit -m base >/dev/null
  git -C "$SCRATCH/seed" push -u origin HEAD:main >/dev/null 2>&1
  git -C "$SCRATCH/seed" branch --set-upstream-to=origin/main main >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  git clone -b main "$SCRATCH/upstream.git" "$SCRATCH/clone" >/dev/null 2>&1
  git -C "$SCRATCH/clone" config user.email test@example.invalid
  git -C "$SCRATCH/clone" config user.name test
  assert_scratch_repo "$SCRATCH/clone"
}

assert_scratch_repo() {
  local path="$1"
  case "$path" in "$BATS_TEST_TMPDIR"/*) ;; *) return 1 ;; esac
  [ "$path" != "$PROJECT_ROOT" ]
}

install_stubs() {
  mkdir -p "$SCRATCH/stubs"
  cat > "$SCRATCH/stubs/git" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_LOG"
exec "$REAL_GIT" "$@"
SH
  cat > "$SCRATCH/stubs/ssh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_LOG"
printf 'prompt=%s\nssh=%s\n' "${GIT_TERMINAL_PROMPT:-unset}" "${GIT_SSH_COMMAND:-unset}" >> "$SSH_ENV_LOG"
if [[ "${SSH_MODE:-success}" == fail ]]; then exit 255; fi
if [[ -n "${SSH_REMOTE_SCRIPT:-}" ]]; then
  "$SSH_REMOTE_SCRIPT" >/dev/null
  exec "$SSH_REMOTE_SCRIPT" --hub-summary
fi
cat "$SSH_RESPONSE"
SH
  cat > "$SCRATCH/stubs/make" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MAKE_LOG"
case "${APPCHECK_MODE:-clean}" in
  drift)
    printf '%s\n' 'INFO: [argocd] Expected values branch: deploy/hub'
    printf '%s\n' '[argocd] checked 1 k3d-manager references (0 tracking HEAD, ignored)' 'WARN: [argocd] Applications on a stale values branch:' '  hub-dashboard k3d-manager-v1.43.15' 'WARN: [argocd] Fix: reapply the ApplicationSets with K3D_MANAGER_BRANCH=deploy/hub' >&2
    exit 1 ;;
  clean)
    printf '%s\n' 'INFO: [argocd] Expected values branch: deploy/hub' 'INFO: [argocd] All Applications reference values branch deploy/hub'
    printf '%s\n' '[argocd] checked 1 k3d-manager references (0 tracking HEAD, ignored)' >&2 ;;
  degraded)
    printf '%s\n' '[argocd] Expected values branch: deploy/hub' '[argocd] Applications Degraded on the expected branch (health, not a values-branch problem):' >&2
    exit 1 ;;
  slow)
    sleep 2
    printf '%s\n' 'INFO: [argocd] All Applications reference values branch deploy/hub' ;;
  fail)
    printf '%s\n' '[argocd] Could not read Applications from k3d-k3d-cluster/cicd' >&2
    exit 1 ;;
esac
SH
  cat > "$SCRATCH/stubs/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
while (($#)); do
  if [[ "$1" == --data-binary ]]; then shift; printf '%s\n' "$1" > "$CURL_BODY"; fi
  shift
done
SH
  # launchctl print gui/<uid>/com.k3d-manager.webhook shows a tab-indented "pid = 42174" line and
  # ps -o lstart= shows "Sun Nov  8 17:12:36 2026" (captured read-only on m5-air, 2026-11-10).
  cat > "$SCRATCH/stubs/launchctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
printf '%s\n' "launchctl $*" >> "$SIDE_EFFECT_LOG"
printf 'pid = 4321\n'
SH
  cat > "$SCRATCH/stubs/ps" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PS_LOG"
printf '%s\n' "$WEBHOOK_START_LSTART"
SH
  for tool in kubectl kill; do
    cat > "$SCRATCH/stubs/$tool" <<SH
#!/usr/bin/env bash
printf '%s\\n' '$tool' "\$@" >> "\$SIDE_EFFECT_LOG"
SH
  done
  chmod +x "$SCRATCH/stubs"/*
  export PATH="$SCRATCH/stubs:$PATH"
  export GIT_LOG="$SCRATCH/git.log" SSH_LOG="$SCRATCH/ssh.log" SSH_ENV_LOG="$SCRATCH/ssh-env.log"
  export MAKE_LOG="$SCRATCH/make.log" CURL_LOG="$SCRATCH/curl.log" CURL_BODY="$SCRATCH/curl.body"
  export LAUNCHCTL_LOG="$SCRATCH/launchctl.log" PS_LOG="$SCRATCH/ps.log"
  export SIDE_EFFECT_LOG="$SCRATCH/side-effects.log"
  touch "$GIT_LOG" "$SSH_LOG" "$SSH_ENV_LOG" "$MAKE_LOG" "$CURL_LOG" "$SIDE_EFFECT_LOG" "$LAUNCHCTL_LOG" "$PS_LOG"
  [ "$(command -v git)" = "$SCRATCH/stubs/git" ]
  [ "$(command -v ssh)" = "$SCRATCH/stubs/ssh" ]
  [ "$(command -v make)" = "$SCRATCH/stubs/make" ]
  [ "$(command -v kubectl)" = "$SCRATCH/stubs/kubectl" ]
  [ "$(command -v curl)" = "$SCRATCH/stubs/curl" ]
  [ "$(command -v launchctl)" = "$SCRATCH/stubs/launchctl" ]
  [ "$(command -v ps)" = "$SCRATCH/stubs/ps" ]
}

prepare_hub_checkout() {
  HUB_ROOT="$SCRATCH/hub-checkout"
  git clone -b main "$SCRATCH/upstream.git" "$HUB_ROOT" >/dev/null 2>&1
  assert_scratch_repo "$HUB_ROOT"
  git -C "$HUB_ROOT" config user.email test@example.invalid
  git -C "$HUB_ROOT" config user.name test
  mkdir -p "$HUB_ROOT/bin" "$HUB_ROOT/scripts/lib/foundation/scripts/lib" "$HUB_ROOT/scripts/etc/machine"
  cp "$TEST_SYNC_BIN" "$HUB_ROOT/bin/k3dm-repo-sync"
  cp "$PROJECT_ROOT/scripts/lib/system.sh" "$HUB_ROOT/scripts/lib/system.sh"
  cp "$PROJECT_ROOT/scripts/lib/foundation/scripts/lib/system.sh" "$HUB_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
  cp "$PROJECT_ROOT/scripts/etc/machine/deploy-paths.tsv" "$HUB_ROOT/scripts/etc/machine/deploy-paths.tsv"
  chmod +x "$HUB_ROOT/bin/k3dm-repo-sync"
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  export K3DM_REPO_SYNC_REPOS="$HUB_ROOT"
  assert_scratch_repo "$K3DM_REPO_SYNC_REPOS"
}

run_sync() {
  local repo="${1:-$K3DM_REPO_SYNC_REPOS}"
  assert_scratch_repo "$repo"
  if [[ -n "${HUB_ROOT:-}" && "$repo" == "$HUB_ROOT" ]]; then
    run "$HUB_ROOT/bin/k3dm-repo-sync"
  else
    run "$TEST_SYNC_BIN"
  fi
}

@test "clean behind checkout fast-forwards and records behind counts" {
  echo next >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am next >/dev/null
  git -C "$SCRATCH/seed" push >/dev/null 2>&1
  run_sync
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$(git -C "$SCRATCH/seed" rev-parse HEAD)" ]
  grep -q '"result": "updated"' "$SCRATCH/state/state.json"
  grep -q '"behind_before": 1' "$SCRATCH/state/state.json"
  grep -q '"behind_after": 0' "$SCRATCH/state/state.json"
}

@test "unrelated local edits survive a fast-forward byte for byte" {
  printf 'local\000edit\n' > "$SCRATCH/clone/local-only"
  before="$(shasum "$SCRATCH/clone/local-only" | awk '{print $1}')"
  echo next >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am next >/dev/null
  git -C "$SCRATCH/seed" push >/dev/null 2>&1
  run_sync
  [ "$status" -eq 0 ]
  [ "$(shasum "$SCRATCH/clone/local-only" | awk '{print $1}')" = "$before" ]
}

@test "ahead and diverged local commits are untouched" {
  echo upstream >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am upstream >/dev/null
  git -C "$SCRATCH/seed" push >/dev/null 2>&1
  echo ahead > "$SCRATCH/clone/ahead"
  git -C "$SCRATCH/clone" add ahead && git -C "$SCRATCH/clone" commit -m ahead >/dev/null
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  before_index="$(git -C "$SCRATCH/clone" write-tree)"
  before_status="$(git -C "$SCRATCH/clone" status --porcelain)"
  run_sync
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$SCRATCH/clone" write-tree)" = "$before_index" ]
  [ "$(git -C "$SCRATCH/clone" status --porcelain)" = "$before_status" ]
  grep -q 'skipped:diverged' "$SCRATCH/state/state.json"
  grep -q '"behind_before": 1' "$SCRATCH/state/state.json"
  grep -q '"behind_after": 1' "$SCRATCH/state/state.json"
}

@test "ahead-only checkout reports skipped ahead" {
  echo ahead > "$SCRATCH/clone/ahead"
  git -C "$SCRATCH/clone" add ahead && git -C "$SCRATCH/clone" commit -m ahead >/dev/null
  run_sync
  [ "$status" -eq 0 ]
  grep -q 'skipped:ahead' "$SCRATCH/state/state.json"
}

@test "overlapping edits block fast-forward without changing checkout state" {
  printf 'local edit\n' > "$SCRATCH/clone/file"
  printf 'upstream edit\n' > "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am upstream >/dev/null
  git -C "$SCRATCH/seed" push >/dev/null 2>&1
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  before_index="$(git -C "$SCRATCH/clone" write-tree)"
  before_worktree="$(shasum "$SCRATCH/clone/file" | awk '{print $1}')"
  run_sync
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$SCRATCH/clone" write-tree)" = "$before_index" ]
  [ "$(shasum "$SCRATCH/clone/file" | awk '{print $1}')" = "$before_worktree" ]
  grep -q '"result": "blocked"' "$SCRATCH/state/state.json"
}

@test "detached HEAD and in-progress merge remain untouched" {
  git -C "$SCRATCH/clone" checkout --detach >/dev/null 2>&1
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  before_index="$(git -C "$SCRATCH/clone" write-tree)"
  before_worktree="$(shasum "$SCRATCH/clone/file" | awk '{print $1}')"
  run_sync
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$SCRATCH/clone" write-tree)" = "$before_index" ]
  [ "$(shasum "$SCRATCH/clone/file" | awk '{print $1}')" = "$before_worktree" ]
  grep -q 'skipped:detached' "$SCRATCH/state/state.json"
  rm "$SCRATCH/state/state.json"
  git -C "$SCRATCH/clone" checkout main >/dev/null 2>&1
  gitdir="$(git -C "$SCRATCH/clone" rev-parse --git-dir)"
  [[ "$gitdir" = /* ]] || gitdir="$SCRATCH/clone/$gitdir"
  touch "$gitdir/MERGE_HEAD"
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  run_sync
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  grep -q 'skipped:operation-in-progress' "$SCRATCH/state/state.json"
}

@test "hub pushes per-repository metrics to the stub endpoint" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9
  [[ "$PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q 'metrics/job/k3dm_repo_sync/instance/' "$CURL_LOG"
  grep -q 'k3dm_repo_sync_behind_commits{repo="k3d-manager"}' "$CURL_BODY"
  grep -q 'k3dm_repo_sync_last_success_timestamp_seconds{repo="k3d-manager"}' "$CURL_BODY"
  grep -q 'k3dm_repo_sync_result{repo="k3d-manager",result="current"} 1' "$CURL_BODY"
}

@test "webhook update sets restart pending and unrelated update does not" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=clean
  mkdir -p "$SCRATCH/seed/scripts/lib/webhook"
  echo webhook > "$SCRATCH/seed/scripts/lib/webhook/change.py"
  git -C "$SCRATCH/seed" add scripts/lib/webhook/change.py
  git -C "$SCRATCH/seed" commit -m webhook >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"webhook code changed; restart pending"* ]]
  grep -q '"webhook_restart_pending": true' "$SCRATCH/state/state.json"
  echo unrelated > "$SCRATCH/seed/unrelated"
  git -C "$SCRATCH/seed" add unrelated && git -C "$SCRATCH/seed" commit -m unrelated >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"restart pending"* ]]
  grep -q '"webhook_restart_pending": true' "$SCRATCH/state/state.json"
  grep -q '"step": "webhook-restart"' "$SCRATCH/state/state.json"
}

@test "unrelated update alone does not set webhook restart pending" {
  prepare_hub_checkout
  echo unrelated > "$SCRATCH/seed/unrelated"
  git -C "$SCRATCH/seed" add unrelated && git -C "$SCRATCH/seed" commit -m unrelated >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"restart pending"* ]]
  grep -q '"webhook_restart_pending": false' "$SCRATCH/state/state.json"
  if grep -q '"step": "webhook-restart"' "$SCRATCH/state/state.json"; then false; fi
}

@test "platform-ops drift is pending, marker current is clear, missing marker is unknown" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=clean
  base="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  printf '%s\n' "$base" > "$SCRATCH/state/deployed-platform-ops"
  : > "$GIT_LOG"
  : > "$MAKE_LOG"
  : > "$SIDE_EFFECT_LOG"
  echo changed > "$SCRATCH/seed/scripts/etc/argocd/platform-ops/new.yaml"
  git -C "$SCRATCH/seed" add scripts/etc/argocd/platform-ops/new.yaml
  git -C "$SCRATCH/seed" commit -m platform >/dev/null
  deployed="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  : > "$GIT_LOG"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"step": "platform-ops"' "$SCRATCH/state/state.json"
  grep -q '"since_commit": "'"$base"'"' "$SCRATCH/state/state.json"
  grep -q 'scripts/etc/argocd/platform-ops/new.yaml' "$SCRATCH/state/state.json"
  grep -q 'k3dm_repo_sync_deploy_pending{step="platform-ops"} 1' "$CURL_BODY"
  : > "$MAKE_LOG"
  : > "$SIDE_EFFECT_LOG"
  printf '%s\n' "$deployed" > "$SCRATCH/state/deployed-platform-ops"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  if grep -q '"step": "platform-ops"' "$SCRATCH/state/state.json"; then false; fi
  grep -q 'k3dm_repo_sync_deploy_pending{step="platform-ops"} 0' "$CURL_BODY"
  rm "$SCRATCH/state/deployed-platform-ops"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"platform-ops"' "$SCRATCH/state/state.json"
  if grep -q 'k3dm_repo_sync_deploy_pending{step="platform-ops"} 1' "$CURL_BODY"; then false; fi
  grep -q 'appsets-check' "$MAKE_LOG"
  if grep -Eq '(^|[[:space:]])(platform-ops|appsets-reapply|hub-promote|hub-rollback)([[:space:]]|$)' "$MAKE_LOG"; then
    return 1
  fi
  [ ! -s "$SIDE_EFFECT_LOG" ]
  if grep -Eq '(^|[[:space:]])push([[:space:]]|$)' "$GIT_LOG"; then
    return 1
  fi
}

@test "appsets drift is pending, clean output is not pending, and query failure is unknown" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9
  printf '%s\n' "$(git -C "$SCRATCH/seed" rev-parse HEAD)" > "$SCRATCH/state/deployed-platform-ops"
  # Read-only output captured on m4-air, 2026-11-10 with a kubectl stub targeting
  # repo-sync-scratch-context: make appsets-check delegates to
  # argocd_check_values_branch (Makefile:449; scripts/plugins/argocd.sh:2089,
  # 2098). The stale row is emitted by _argocd_values_branch_drift.
  export APPCHECK_MODE=drift
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"step": "appsets-reapply"' "$SCRATCH/state/state.json"
  grep -q 'hub-dashboard k3d-manager-v1.43.15' "$SCRATCH/state/state.json"
  grep -q 'k3dm_repo_sync_deploy_pending{step="appsets-reapply"} 1' "$CURL_BODY"
  export APPCHECK_MODE=clean
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  if grep -q '"step": "appsets-reapply"' "$SCRATCH/state/state.json"; then false; fi
  grep -q 'k3dm_repo_sync_deploy_pending{step="appsets-reapply"} 0' "$CURL_BODY"
  [[ "$output" != *"appsets-reapply"* ]]
  export APPCHECK_MODE=fail
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"appsets-reapply"' "$SCRATCH/state/state.json"
  if grep -q 'k3dm_repo_sync_deploy_pending{step="appsets-reapply"}' "$CURL_BODY"; then false; fi
}

@test "hub branch stops at deploy/hub while worker follows its upstream" {
  prepare_hub_checkout
  echo first >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am first >/dev/null
  first="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  echo second >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am second >/dev/null
  second="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  git -C "$SCRATCH/seed" push origin "$first:refs/heads/deploy/hub" >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$first" ]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" != "$second" ]
  [ -z "$(git -C "$HUB_ROOT" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
  printf 'worker\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  export K3DM_REPO_SYNC_REPOS="$SCRATCH/clone"
  run_sync "$SCRATCH/clone"
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$second" ]
  echo worker-local > "$SCRATCH/clone/worker-local"
  git -C "$SCRATCH/clone" add worker-local && git -C "$SCRATCH/clone" commit -m worker-local >/dev/null
  worker_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  echo upstream-next >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am upstream-next >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  run_sync "$SCRATCH/clone"
  [ "$status" -eq 0 ]
  grep -q 'skipped:diverged' "$SCRATCH/state/state.json"
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$worker_head" ]
}

@test "dirty non-fast-forward hub checkout is skipped without a backup ref" {
  install_stubs
  prepare_hub_checkout
  echo local-edit >> "$HUB_ROOT/file"
  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
  before_file="$(shasum "$HUB_ROOT/file" | awk '{print $1}')"
  echo promoted >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am promoted >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  git -C "$HUB_ROOT" branch side "$before_head"
  echo local-commit > "$HUB_ROOT/local-commit"
  git -C "$HUB_ROOT" add local-commit && git -C "$HUB_ROOT" commit -m local >/dev/null
  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q 'skipped:dirty' "$SCRATCH/state/state.json"
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$before_head" ]
  [ "$(shasum "$HUB_ROOT/file" | awk '{print $1}')" = "$before_file" ]
  [ -z "$(git -C "$HUB_ROOT" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
}

@test "hub role never resets a non-root repository with diverged commits" {
  install_stubs
  prepare_hub_checkout
  printf 'hub\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  export K3DM_REPO_SYNC_REPOS="$HUB_ROOT:$SCRATCH/clone" PUSHGATEWAY_URL=http://127.0.0.1:9
  echo local > "$SCRATCH/clone/local-only"
  git -C "$SCRATCH/clone" add local-only && git -C "$SCRATCH/clone" commit -m local-only >/dev/null
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  echo upstream > "$SCRATCH/seed/upstream-only"
  git -C "$SCRATCH/seed" add upstream-only && git -C "$SCRATCH/seed" commit -m upstream-only >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  grep -q 'skipped:diverged' "$SCRATCH/state/state.json"
  [ -z "$(git -C "$SCRATCH/clone" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
}

@test "untracked file at a path deploy/hub adds is protected from reset" {
  install_stubs
  prepare_hub_checkout
  git -C "$HUB_ROOT" branch local-branch
  git -C "$SCRATCH/seed" checkout -b add-path >/dev/null 2>&1
  echo promoted > "$SCRATCH/seed/will-be-added"
  git -C "$SCRATCH/seed" add will-be-added && git -C "$SCRATCH/seed" commit -m add-path >/dev/null
  promoted="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  git -C "$HUB_ROOT" checkout -qb local-divergence
  echo local > "$HUB_ROOT/local-change"
  git -C "$HUB_ROOT" add local-change && git -C "$HUB_ROOT" commit -m local-change >/dev/null
  printf 'keep me\n' > "$HUB_ROOT/will-be-added"
  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
  before_file="$(shasum "$HUB_ROOT/will-be-added" | awk '{print $1}')"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q 'skipped:dirty' "$SCRATCH/state/state.json"
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$before_head" ]
  [ "$(shasum "$HUB_ROOT/will-be-added" | awk '{print $1}')" = "$before_file" ]
  [ -z "$(git -C "$HUB_ROOT" for-each-ref --format='%(refname)' refs/k3dm/repo-sync-backup/)" ]
  [ "$promoted" != "$before_head" ]
}

@test "reset to a rollback ref counts as success and marks webhook restart pending" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=clean
  mkdir -p "$SCRATCH/seed/scripts/lib/webhook"
  echo first > "$SCRATCH/seed/scripts/lib/webhook/change.py"
  git -C "$SCRATCH/seed" add scripts/lib/webhook/change.py
  git -C "$SCRATCH/seed" commit -m webhook-first >/dev/null
  rollback_sha="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  python3 - "$SCRATCH/state/state.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["webhook_restart_pending"]=False; d["deploy_pending"]=[]
json.dump(d, open(p,"w"))
PY
  echo second >> "$SCRATCH/seed/scripts/lib/webhook/change.py"
  git -C "$SCRATCH/seed" commit -am webhook-second >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  python3 - "$SCRATCH/state/state.json" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["webhook_restart_pending"]=False; d["deploy_pending"]=[]
json.dump(d, open(p,"w"))
PY
  git --git-dir="$SCRATCH/upstream.git" update-ref refs/heads/deploy/hub "$rollback_sha"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  python3 - "$SCRATCH/state/state.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1])); r=next(x for x in d["repositories"] if x["path"].endswith("hub-checkout"))
assert r["result"] == "reset-to-deploy-hub"
assert r["last_success_timestamp_seconds"] == r["run_time"]
assert d["webhook_restart_pending"] is True
assert any(x["step"] == "webhook-restart" for x in d["deploy_pending"])
PY
}

@test "hub-sync prints the remote line and warns but succeeds on ssh failure" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=clean SSH_MODE=success K3DM_HUB_HOST=m5-scratch.local
  base="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  printf '%s\n' "$base" > "$SCRATCH/state/deployed-platform-ops"
  echo dashboard > "$SCRATCH/seed/scripts/etc/argocd/platform-ops/dashboard.yaml"
  git -C "$SCRATCH/seed" add scripts/etc/argocd/platform-ops/dashboard.yaml
  git -C "$SCRATCH/seed" commit -m promoted-candidate >/dev/null
  promoted="$(git -C "$SCRATCH/seed" rev-parse HEAD)"
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  echo backlog > "$SCRATCH/seed/backlog"
  git -C "$SCRATCH/seed" add backlog && git -C "$SCRATCH/seed" commit -m backlog >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:main >/dev/null 2>&1
  export SSH_REMOTE_SCRIPT="$HUB_ROOT/bin/k3dm-repo-sync"
  run "$REAL_MAKE" --no-print-directory -f "$PROJECT_ROOT/Makefile" hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == hub\ *": main at "* ]]
  expected_tail="(updated); deploy pending: platform-ops; deploy/hub ${promoted:0:7}; promote backlog: 1"
  [[ "$output" == *"$expected_tail" ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  grep -q 'BatchMode=yes' "$SSH_LOG"
  grep -q 'ConnectTimeout=10' "$SSH_LOG"
  export SSH_MODE=fail
  run "$REAL_MAKE" --no-print-directory -f "$PROJECT_ROOT/Makefile" hub-sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: hub sync failed over SSH"* ]]
}

@test "fetch is noninteractive, bounded, and invokes no forbidden git subcommand" {
  install_stubs
  git -C "$SCRATCH/clone" remote set-url origin ssh://git@127.0.0.1:9/no-network.git
  : > "$GIT_LOG"
  export SSH_MODE=fail
  started="$(date +%s)"
  run_sync "$SCRATCH/clone"
  elapsed="$(($(date +%s) - started))"
  [ "$status" -eq 0 ]
  [ "$elapsed" -le 13 ]
  grep -q '"result": "fetch_failed"' "$SCRATCH/state/state.json"
  grep -q 'prompt=0' "$SSH_ENV_LOG"
  grep -q 'BatchMode=yes' "$SSH_ENV_LOG"
  if grep -Eq '(^|[[:space:]])(reset|rebase|stash|checkout|clean|switch|push)([[:space:]]|$)' "$GIT_LOG"; then
    return 1
  fi
}

@test "hub clean non-fast-forward checkout backs up and follows deploy ref" {
  install_stubs
  prepare_hub_checkout
  echo local > "$HUB_ROOT/local-only"
  git -C "$HUB_ROOT" add local-only && git -C "$HUB_ROOT" commit -m local >/dev/null
  before_head="$(git -C "$HUB_ROOT" rev-parse HEAD)"
  git -C "$HUB_ROOT" remote rename origin upstream >/dev/null
  before_index="$(git -C "$HUB_ROOT" write-tree)"
  before_status="$(git -C "$HUB_ROOT" status --porcelain)"
  : > "$GIT_LOG"
  export PUSHGATEWAY_URL=http://127.0.0.1:9
  run "$HUB_ROOT/bin/k3dm-repo-sync" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"would-reset-to-deploy-hub"* ]]
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$before_head" ]
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  target="$(git -C "$HUB_ROOT" rev-parse upstream/deploy/hub)"
  [ "$(git -C "$HUB_ROOT" rev-parse HEAD)" = "$target" ]
  grep -q '"remote": "upstream"' "$SCRATCH/state/state.json"
  grep -q '"result": "reset-to-deploy-hub"' "$SCRATCH/state/state.json"
  grep -q '"backup_ref": "refs/k3dm/repo-sync-backup/' "$SCRATCH/state/state.json"
  [ "$(git -C "$HUB_ROOT" rev-parse "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"][0]["backup_ref"])' "$SCRATCH/state/state.json")")" = "$before_head" ]
  if grep -Eq '(^|[[:space:]])(push|hub-promote|hub-rollback)([[:space:]]|$)' "$GIT_LOG" "$MAKE_LOG"; then
    return 1
  fi
}

@test "missing or empty machine role fails before state or repository access" {
  rm "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  run "$TEST_SYNC_BIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"machine-role file missing or empty"* ]]
  [ ! -e "$SCRATCH/state/state.json" ]
  printf '\n' > "$XDG_CONFIG_HOME/k3d-manager/machine-role"
  run "$TEST_SYNC_BIN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"machine-role file missing or empty"* ]]
  [ ! -e "$SCRATCH/state/state.json" ]
}

@test "dead repo-sync lock is recovered and a live lock is preserved" {
  mkdir -p "$SCRATCH/state/lock"
  printf '2147483647\n' > "$SCRATCH/state/lock/pid"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" != *"already running"* ]]
  [ -e "$SCRATCH/state/state.json" ]
  [ ! -e "$SCRATCH/state/lock" ]
  mkdir -p "$SCRATCH/state/lock"
  printf '%s\n' "$$" > "$SCRATCH/state/lock/pid"
  python3 -c 'import os,sys,time; p=sys.argv[1]; t=time.time()-70; os.utime(p,(t,t))' "$SCRATCH/state/lock"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" != *"already running"* ]]
  [ ! -e "$SCRATCH/state/lock" ]
  mkdir -p "$SCRATCH/state/lock"
  printf '%s\n' "$$" > "$SCRATCH/state/lock/pid"
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  before_state="$(shasum "$SCRATCH/state/state.json" | awk '{print $1}')"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  [ "$(shasum "$SCRATCH/state/state.json" | awk '{print $1}')" = "$before_state" ]
}

@test "webhook restart pending persists until a later process start" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=clean
  export WEBHOOK_START_LSTART='Sat Jan  1 00:00:00 2000'
  mkdir -p "$SCRATCH/seed/scripts/lib/webhook"
  echo change > "$SCRATCH/seed/scripts/lib/webhook/change.py"
  git -C "$SCRATCH/seed" add scripts/lib/webhook/change.py
  git -C "$SCRATCH/seed" commit -m webhook >/dev/null
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"webhook_restart_pending": true' "$SCRATCH/state/state.json"
  grep -q '"step": "webhook-restart"' "$SCRATCH/state/state.json"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"webhook_restart_pending": true' "$SCRATCH/state/state.json"
  grep -q '"step": "webhook-restart"' "$SCRATCH/state/state.json"
  recorded="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["webhook_restart_pending_recorded_at"])' "$SCRATCH/state/state.json")"
  WEBHOOK_START_LSTART="$(python3 -c 'from datetime import datetime,timedelta; print((datetime.now()+timedelta(hours=1)).strftime("%a %b %e %H:%M:%S %Y"))')"
  export WEBHOOK_START_LSTART
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"webhook_restart_pending": false' "$SCRATCH/state/state.json"
  if grep -q '"step": "webhook-restart"' "$SCRATCH/state/state.json"; then false; fi
  [ -n "$recorded" ]
  grep -q 'gui/.*/com.k3d-manager.webhook' "$LAUNCHCTL_LOG"
  grep -q 'lstart=' "$PS_LOG"
}

@test "appsets query timeout records unknown and still writes state" {
  install_stubs
  prepare_hub_checkout
  export PUSHGATEWAY_URL=http://127.0.0.1:9 APPCHECK_MODE=slow K3DM_REPO_SYNC_APPSETS_TIMEOUT=1
  printf '%s\n' "$(git -C "$SCRATCH/seed" rev-parse HEAD)" > "$SCRATCH/state/deployed-platform-ops"
  run_sync "$HUB_ROOT"
  [ "$status" -eq 0 ]
  [ -e "$SCRATCH/state/state.json" ]
  grep -q '"appsets-reapply"' "$SCRATCH/state/state.json"
  if grep -q '"step": "appsets-reapply"' "$SCRATCH/state/state.json"; then false; fi
}

@test "--check reports an already-fetched behind checkout without changing it" {
  install_stubs
  git -C "$SCRATCH/clone" fetch origin >/dev/null 2>&1
  echo next >> "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" commit -am next >/dev/null
  git -C "$SCRATCH/seed" push >/dev/null 2>&1
  git -C "$SCRATCH/clone" fetch origin >/dev/null 2>&1
  : > "$GIT_LOG"
  before_head="$(git -C "$SCRATCH/clone" rev-parse HEAD)"
  run "$TEST_SYNC_BIN" --check
  [ "$status" -eq 0 ]
  grep -q '"result": "would-update"' "$SCRATCH/state/state.json"
  grep -q '"behind_before": 1' "$SCRATCH/state/state.json"
  [ "$(git -C "$SCRATCH/clone" rev-parse HEAD)" = "$before_head" ]
  if grep -Eq '(^|[[:space:]])(fetch|merge)([[:space:]]|$)' "$GIT_LOG"; then
    return 1
  fi
}
