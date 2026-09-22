#!/usr/bin/env bats

setup() {
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  export PLUGINS_DIR="$SCRIPT_DIR/plugins"
  export K3DM_SNAPSHOT_HOST=stub-m2
  export K3DM_SNAPSHOT_DIR="$BATS_TEST_TMPDIR/remote"
  export K3DM_SNAPSHOT_TIMESTAMP=20260922T000000Z
  export TMPDIR="$BATS_TEST_TMPDIR/staging"
  export SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
  export DOCKER_FAIL=0 NO_BOUND= SHA_MISMATCH=0
  mkdir -p "$K3DM_SNAPSHOT_DIR" "$TMPDIR" "$BATS_TEST_TMPDIR/bin"
  : > "$SSH_LOG"
  _err() { printf '%s\n' "$*" >&2; }
  _warn() { printf '%s\n' "$*" >&2; }
  _info() { printf '%s\n' "$*"; }
  _run_command() { shift; "$@"; }
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
      [[ "$args" == *"prometheus-kube-prometheus"* ]] && printf 'agent-1\n' || printf 'agent-0\n'
      return 0
    fi
    if [[ "$args" == *"get pv"* && "$args" == *".spec.local.path"* ]]; then
      claim="${args#*get pv }"; claim="${claim%% *}"
      printf '/data/%s\n' "$claim"; return 0
    fi
    return 0
  }
  cat > "$BATS_TEST_TMPDIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
[[ "${DOCKER_FAIL:-0}" == 1 ]] && exit 1
destination="${@: -1}"
source_path="${@: -2:1}"
if [[ "$source_path" == *:/var/lib/rancher/k3s/server/token ]]; then
  printf 'server-token-stub\n' > "$destination"
else
  mkdir -p "$destination"
  if [[ "$source_path" == *:/var/lib/rancher/k3s/server/db/. ]]; then
    printf 'captured-data\n' > "$destination/state.db"
  else
    printf 'captured-data\n' > "$destination/data"
  fi
fi
EOF
  cat > "$BATS_TEST_TMPDIR/bin/rsync" <<'EOF'
#!/usr/bin/env bash
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
if [[ "$command_text" == df\ * ]]; then
  printf '100000\n'; exit 0
fi
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
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  source "$SCRIPT_DIR/plugins/hub_snapshot.sh"
}

capture_snapshot() {
  run hub_snapshot_capture
  [ "$status" -eq 0 ]
  export CAPTURED="$K3DM_SNAPSHOT_DIR/$K3DM_SNAPSHOT_TIMESTAMP"
}

@test "hub snapshot: capture emits the restore layout" {
  capture_snapshot
  for path in server-db/state.db server-token pv-pvc.yaml; do [ -e "$CAPTURED/$path" ]; done
  while IFS='|' read -r _node namespace claim storage; do
    [ "$(find "$CAPTURED/$storage" -mindepth 1 -maxdepth 1 -type d -name "pvc-*_${namespace}_${claim}" | wc -l | tr -d ' ')" -eq 1 ]
  done < <(_hub_recovery_records)
}

@test "hub snapshot: tree names satisfy hub recovery claim tree" {
  capture_snapshot
  while IFS='|' read -r _node namespace claim storage; do
    run _hub_recovery_claim_tree "$CAPTURED" "$namespace" "$claim" "$storage"
    [ "$status" -eq 0 ]
  done < <(_hub_recovery_records)
}

@test "hub snapshot: node placement comes from the PV" {
  capture_snapshot
  run grep -F $'agent-1\tmonitoring\tprometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0' "$CAPTURED/MANIFEST.tsv"
  [ "$status" -eq 0 ]
}

@test "hub snapshot: unbound claim fails closed" {
  export NO_BOUND=storage-loki-0
  run hub_snapshot_capture
  [ "$status" -ne 0 ]; [[ "$output" == *"storage-loki-0"* ]]
}

@test "hub snapshot: checksum mismatch marks incomplete" {
  export SHA_MISMATCH=1
  run hub_snapshot_capture
  [ "$status" -ne 0 ]; [ -d "$K3DM_SNAPSHOT_DIR/${K3DM_SNAPSHOT_TIMESTAMP}.INCOMPLETE" ]
}

@test "hub snapshot: insufficient space reports required and available" {
  cat > "$BATS_TEST_TMPDIR/bin/ssh" <<'EOF'
#!/usr/bin/env bash
[[ "${@: -1}" == df\ * ]] && { echo 1; exit 0; }
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  run hub_snapshot_capture
  [ "$status" -ne 0 ]; [[ "$output" == *"required"* ]]; [[ "$output" == *"available 1 KiB"* ]]
  [ ! -e "$K3DM_SNAPSHOT_DIR/$K3DM_SNAPSHOT_TIMESTAMP" ]
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
