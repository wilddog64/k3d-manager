#!/usr/bin/env bats

setup() {
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  export PLUGINS_DIR="$SCRIPT_DIR/plugins"
  export K3DM_SNAPSHOT_HOST=stub-m2
  export K3DM_SNAPSHOT_DIR="$BATS_TEST_TMPDIR/remote"
  export K3DM_SNAPSHOT_TIMESTAMP=20260922T000000Z
  export K3DM_SNAPSHOT_STAMP="$BATS_TEST_TMPDIR/hub-snapshot-last"
  export K3DM_SNAPSHOT_MAX_AGE_HOURS=24
  export TMPDIR="$BATS_TEST_TMPDIR/staging"
  export SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
  export RSYNC_LOG="$BATS_TEST_TMPDIR/rsync.log"
  export DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
  export DOCKER_FAIL=0 NO_BOUND= SHA_MISMATCH=0
  mkdir -p "$K3DM_SNAPSHOT_DIR" "$TMPDIR" "$BATS_TEST_TMPDIR/bin"
  : > "$SSH_LOG"
  : > "$RSYNC_LOG"
  _err() { printf '%s\n' "$*" >&2; }
  _warn() { printf '%s\n' "$*" >&2; }
  _info() { printf '%s\n' "$*"; }
  _run_command() {
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --probe) shift 2 ;;
        --) shift; break ;;
        *) shift ;;
      esac
    done
    "$@"
  }
  _kubectl() {
    local args="$*" claim
    if [[ "$args" == *"get pv,pvc -A -o yaml"* ]]; then
      printf 'apiVersion: v1\nkind: List\n'; return 0
    fi
    if [[ "$args" == *"get pvc"* && "$args" == *".spec.volumeName"* ]]; then
      claim="${args#*get pvc }"; claim="${claim%% *}"
      [[ "$claim" != "$NO_BOUND" ]] || { return 0; }
      printf 'pv-%s\n' "$claim"; return 0
    fi
    if [[ "$args" == *"get pvc"* && "$args" == *".metadata.uid"* ]]; then
      claim="${args#*get pvc }"; claim="${claim%% *}"
      printf 'uid-%s\n' "$claim"; return 0
    fi
    if [[ "$args" == *"get pv"* && "$args" == *"matchExpressions"* ]]; then
      [[ "$args" == *"prometheus-kube-prometheus"* ]] && printf 'k3d-k3d-cluster-agent-1\n' || printf 'k3d-k3d-cluster-agent-0\n'
      return 0
    fi
    if [[ "$args" == *"get pv"* && "$args" == *".spec.local.path"* ]]; then
      claim="${args#*get pv }"; claim="${claim%% *}"
      printf '/data/%s\n' "$claim"; return 0
    fi
    if [[ "$args" == *"get pv"* && "$args" == *"persistentVolumeReclaimPolicy"* ]]; then
      claim="${args#*get pv }"; claim="${claim%% *}"
      [[ "$claim" == "${PV_RETAIN:-}" ]] && printf 'Retain\n' || printf 'Delete\n'
      return 0
    fi
    if [[ "$args" == *"patch pv"* ]]; then
      printf '%s\n' "$args" >> "$PATCH_LOG"
      return 0
    fi
    return 0
  }
  cat > "$BATS_TEST_TMPDIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "docker $*" >> "$DOCKER_LOG"
[[ "${DOCKER_FAIL:-0}" == 1 ]] && exit 1
if [[ "${1:-}" == exec && "${3:-}" == tar ]]; then
  source_path="${5:-}"
  fixture="${TAR_FIXTURE_DIR:-}"
  [[ -n "$fixture" ]] || { echo "missing tar fixture" >&2; exit 1; }
  fixture="${fixture}/${source_path##*/}"
  fixture="${fixture/pv-/}"
  tar -C "$fixture" -cf - .
elif [[ "${1:-}" == exec && "${3:-}" == cat ]]; then
  printf 'server-token-stub\n'
else
  echo "unexpected docker command" >&2
  exit 1
fi
EOF
  cat > "$BATS_TEST_TMPDIR/bin/rsync" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${@: -1}" >> "$RSYNC_LOG"
[[ "${RSYNC_RC:-0}" == 1 ]] && exit 1
source_path="${@: -2:1}"
destination="${@: -1}"
destination="${destination#*:}"
mkdir -p "${destination%/}"
cp -R "${source_path%/}/." "${destination%/}/"
EOF
  cat > "$BATS_TEST_TMPDIR/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_LOG"
command_text="${@: -1}"
[[ "${SSH_RC:-0}" == 1 ]] && exit 1
[[ "$command_text" == true ]] && exit 0
if [[ "$command_text" == mkdir\ * || "$command_text" == mv\ *INCOMPLETE* || "$command_text" == rm\ * ]]; then
  eval "$command_text"; exit $?
fi
if [[ "$command_text" == cd\ *sha256sum* ]]; then
  [[ "${SHA_MISMATCH:-0}" == 1 ]] && exit 1
  remote="${command_text#cd }"; remote="${remote%% &&*}"
  remote="${remote#\'}"; remote="${remote%\'}"
  (cd "$remote" && sha256sum -c SHA256SUMS); exit $?
fi
if [[ "$command_text" == find\ * ]]; then
  for entry in "$K3DM_SNAPSHOT_DIR"/20*; do
    [[ -d "$entry" ]] && basename "$entry"
  done | sort; exit 0
fi
if [[ "$command_text" == du\ * ]]; then
  target="${command_text#du -sh }"; target="${target%% |*}"
  target="${target#\'}"; target="${target%\'}"
  du -sh "$target"; exit $?
fi
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin"/*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" PATCH_LOG="$BATS_TEST_TMPDIR/patch.log"
  export TAR_FIXTURE_DIR="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$TAR_FIXTURE_DIR/db" "$TAR_FIXTURE_DIR/data-vault-0" "$TAR_FIXTURE_DIR/postgres-keycloak-pvc" "$TAR_FIXTURE_DIR/ldap-data-pvc" "$TAR_FIXTURE_DIR/data-openldap-0" "$TAR_FIXTURE_DIR/ldap-config-pvc" "$TAR_FIXTURE_DIR/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0" "$TAR_FIXTURE_DIR/storage-loki-0"
  printf 'db fixture\n' > "$TAR_FIXTURE_DIR/db/state.db"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/data-vault-0/raft"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/postgres-keycloak-pvc/data"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/ldap-data-pvc/data"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/data-openldap-0/data"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/ldap-config-pvc/data"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0/data"
  printf 'claim fixture\n' > "$TAR_FIXTURE_DIR/storage-loki-0/data"
  : > "$PATCH_LOG"
  source "$SCRIPT_DIR/plugins/hub_snapshot.sh"
}

capture_snapshot() {
  run hub_snapshot_capture
  [ "$status" -eq 0 ]
  export CAPTURED="$K3DM_SNAPSHOT_DIR/$K3DM_SNAPSHOT_TIMESTAMP"
}

snapshot_name_hours_ago() {
  python3 - "$1" <<'PY'
import datetime, sys
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=int(sys.argv[1]))).strftime("%Y%m%dT%H%M%SZ"))
PY
}

@test "hub snapshot: guard accepts a fresh verified snapshot" {
  mkdir -p "$K3DM_SNAPSHOT_DIR/$(snapshot_name_hours_ago 2)"
  run hub_snapshot_guard_delete
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest verified snapshot"* ]]
}

@test "hub snapshot: guard reads verified snapshots during dry-run" {
  export DRY_RUN=1
  mkdir -p "$K3DM_SNAPSHOT_DIR/$(snapshot_name_hours_ago 2)"
  run hub_snapshot_guard_delete
  [ "$status" -eq 0 ]
  [[ "$output" == *"latest verified snapshot"* ]]
  [[ "$output" != *"[dry-run]"* ]]
}

@test "hub snapshot: guard refuses an old verified snapshot" {
  mkdir -p "$K3DM_SNAPSHOT_DIR/$(snapshot_name_hours_ago 30)"
  run hub_snapshot_guard_delete
  [ "$status" -ne 0 ]
  [[ "$output" == *"DISCARD_HUB_DATA=1"* ]]
}

@test "hub snapshot: guard refuses incomplete-only snapshots" {
  mkdir -p "$K3DM_SNAPSHOT_DIR/$(snapshot_name_hours_ago 2).INCOMPLETE"
  run hub_snapshot_guard_delete
  [ "$status" -ne 0 ]
  [[ "$output" == *"no verified snapshot"* ]]
}

@test "hub snapshot: guard refuses an unreachable M2" {
  _hub_snapshot_ssh() { return 255; }
  run hub_snapshot_guard_delete
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreachable"* ]]
  [[ "$output" == *"DISCARD_HUB_DATA=1"* ]]
}

@test "hub snapshot: malformed age name fails" {
  run _hub_snapshot_age_hours malformed
  [ "$status" -eq 1 ]
}

@test "hub snapshot: capture emits the restore layout" {
  capture_snapshot
  for path in server-db.tar server-token pv-pvc.yaml; do [ -e "$CAPTURED/$path" ]; done
  while IFS='|' read -r _node namespace claim storage; do
    [ "$(find "$CAPTURED/$storage" -mindepth 1 -maxdepth 1 -type f -name "pvc-*_${namespace}_${claim}.tar" | wc -l | tr -d ' ')" -eq 1 ]
  done < <(_hub_recovery_records)
}

@test "hub snapshot: tree names satisfy hub recovery claim tree" {
  capture_snapshot
  while IFS='|' read -r _node namespace claim storage; do
    run test -f "$CAPTURED/$storage/$(find "$CAPTURED/$storage" -mindepth 1 -maxdepth 1 -type f -name "pvc-*_${namespace}_${claim}.tar" -exec basename {} \;)"
    [ "$status" -eq 0 ]
  done < <(_hub_recovery_records)
}

@test "hub snapshot: claim archive lists fixture files" {
  capture_snapshot
  run tar -tf "$CAPTURED/node-server-0-storage/pvc-uid-data-vault-0_secrets_data-vault-0.tar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"./raft"* ]]
}

@test "hub snapshot: node placement comes from the PV" {
  capture_snapshot
  run grep -F $'agent-1\tmonitoring\tprometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0' "$CAPTURED/MANIFEST.tsv"
  [ "$status" -eq 0 ]
}

@test "hub snapshot: PV hostname maps to one logical docker container" {
  capture_snapshot
  run grep -F 'docker exec k3d-k3d-cluster-agent-1 tar' "$DOCKER_LOG"
  [ "$status" -eq 0 ]
  run grep -F 'k3d-k3d-cluster-k3d-' "$DOCKER_LOG"
  [ "$status" -ne 0 ]
  run grep -c 'docker cp' "$DOCKER_LOG"
  [ "$output" -eq 0 ]
}

@test "hub snapshot: unbound claim fails closed" {
  export NO_BOUND=storage-loki-0
  run hub_snapshot_capture
  [ "$status" -ne 0 ]; [[ "$output" == *"storage-loki-0"* ]]
}

@test "hub snapshot: capture probes no remote free space" {
  capture_snapshot
  run command grep -c 'df ' "$SSH_LOG"
  [ "$output" -eq 0 ]
}

@test "hub snapshot: checksum mismatch marks incomplete" {
  export SHA_MISMATCH=1
  run hub_snapshot_capture
  [ "$status" -ne 0 ]; [ -d "$K3DM_SNAPSHOT_DIR/${K3DM_SNAPSHOT_TIMESTAMP}.INCOMPLETE" ]
  [ ! -e "$K3DM_SNAPSHOT_STAMP" ]
}

@test "hub snapshot: rsync stages under incomplete and renames after verification" {
  capture_snapshot
  run grep -F ":${K3DM_SNAPSHOT_DIR}/${K3DM_SNAPSHOT_TIMESTAMP}.INCOMPLETE/" "$RSYNC_LOG"
  [ "$status" -eq 0 ]
  run grep -n -E "sha256sum -c|mv --" "$SSH_LOG"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p' | cut -d: -f1)" -lt "$(printf '%s\n' "$output" | sed -n '2p' | cut -d: -f1)" ]
}

@test "hub snapshot: failing rsync leaves incomplete without rename or stamp" {
  export RSYNC_RC=1
  run hub_snapshot_capture
  [ "$status" -ne 0 ]
  [[ "$output" == *"rsync upload failed"* ]]
  [ -d "$K3DM_SNAPSHOT_DIR/${K3DM_SNAPSHOT_TIMESTAMP}.INCOMPLETE" ]
  run grep -F "mv -- '${K3DM_SNAPSHOT_DIR}/${K3DM_SNAPSHOT_TIMESTAMP}.INCOMPLETE' '${K3DM_SNAPSHOT_DIR}/${K3DM_SNAPSHOT_TIMESTAMP}'" "$SSH_LOG"
  [ "$status" -ne 0 ]
  [ ! -e "$K3DM_SNAPSHOT_STAMP" ]
}

@test "hub snapshot: capture writes stamp after verification" {
  capture_snapshot
  [ "$(cat "$K3DM_SNAPSHOT_STAMP")" = "$K3DM_SNAPSHOT_TIMESTAMP" ]
}

@test "hub snapshot: prune keeps the configured verified snapshots" {
  for name in 20260919T000000Z 20260920T000000Z 20260921T000000Z 20260922T000000Z; do mkdir -p "$K3DM_SNAPSHOT_DIR/$name"; done
  export K3DM_SNAPSHOT_KEEP=3
  run hub_snapshot_prune
  [ "$status" -eq 0 ]; [ "$(find "$K3DM_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 3 ]
}

@test "hub snapshot: prune removes incomplete snapshots first" {
  mkdir -p "$K3DM_SNAPSHOT_DIR/20260920T000000Z" "$K3DM_SNAPSHOT_DIR/20260921T000000Z" "$K3DM_SNAPSHOT_DIR/20260922T000000Z.INCOMPLETE"
  export K3DM_SNAPSHOT_KEEP=2
  run hub_snapshot_prune
  [ "$status" -eq 0 ]
  run test -d "$K3DM_SNAPSHOT_DIR/20260922T000000Z.INCOMPLETE"
  [ "$status" -ne 0 ]
  [ "$(find "$K3DM_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 2 ]
}

@test "hub snapshot: prune refuses zero verified snapshots" {
  mkdir -p "$K3DM_SNAPSHOT_DIR/20260922T000000Z.INCOMPLETE"
  run hub_snapshot_prune
  [ "$status" -ne 0 ]; [[ "$output" == *"no verified snapshots"* ]]
}

@test "hub snapshot: unreachable M2 names the host and leaves no remote directory" {
  export SSH_RC=1
  run hub_snapshot_capture
  [ "$status" -ne 0 ]; [[ "$output" == *"stub-m2"* ]]
  [ "$(find "$K3DM_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 0 ]
}

@test "hub snapshot: staging is removed after a mid-capture failure" {
  export DOCKER_FAIL=1
  _hub_snapshot_copy() { return 1; }
  run hub_snapshot_capture
  [ "$status" -ne 0 ]
  run find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d -print
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "hub snapshot: staging directory is 0700" {
  _hub_snapshot_checksums() {
    local stage="$1"
    [ "$(stat -c '%a' "$stage" 2>/dev/null || stat -f '%Lp' "$stage")" = 700 ]
    : > "$stage/SHA256SUMS"
    while IFS= read -r file; do
      printf '%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "${file#"$stage/"}" >> "$stage/SHA256SUMS"
    done < <(find "$stage" -type f ! -name SHA256SUMS -print)
  }
  capture_snapshot
}

@test "hub snapshot: Loki record is present" {
  run _hub_recovery_records
  [ "$status" -eq 0 ]; [[ "$output" == *"monitoring|storage-loki-0"* ]]
}

@test "hub snapshot: remote dir default survives single-quoting on the remote shell" {
  run bash -c '
    unset K3DM_SNAPSHOT_DIR
    source "'"$PWD"'/scripts/plugins/hub_snapshot.sh" 2>/dev/null || true
    printf "%s\n" "$K3DM_SNAPSHOT_DIR"
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"~"* ]]
}

@test "hub snapshot: retain patches Delete and skips Retain" {
  export PV_RETAIN=pv-postgres-keycloak-pvc
  run hub_snapshot_retain_pvs
  [ "$status" -eq 0 ]
  run grep -F "patch pv pv-data-vault-0" "$PATCH_LOG"
  [ "$status" -eq 0 ]
  run grep -F "patch pv pv-postgres-keycloak-pvc" "$PATCH_LOG"
  [ "$status" -ne 0 ]
}

@test "hub snapshot: retain processes remaining claims after missing PVC" {
  export NO_BOUND=data-vault-0
  run hub_snapshot_retain_pvs
  [ "$status" -ne 0 ]
  run grep -F "patch pv pv-postgres-keycloak-pvc" "$PATCH_LOG"
  [ "$status" -eq 0 ]
}
