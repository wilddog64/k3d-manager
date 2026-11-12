#!/usr/bin/env bats

setup_file() {
  REAL_HOME="$HOME"
  export REAL_HOME
  INITIAL_GITCONFIG_SHA="$(git config --file "$REAL_HOME/.gitconfig" --list 2>/dev/null | shasum)"
  export INITIAL_GITCONFIG_SHA
  GITCONFIG_SNAPSHOT="${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR:-${TMPDIR:-/tmp}}}/gitconfig_snapshot_${$}"
  export GITCONFIG_SNAPSHOT
  printf '%s' "$INITIAL_GITCONFIG_SHA" > "$GITCONFIG_SNAPSHOT"
}

teardown_file() {
  local current_sha expected_sha real_home
  real_home="${REAL_HOME:-$HOME}"
  current_sha="$(git config --file "$real_home/.gitconfig" --list 2>/dev/null | shasum)"
  expected_sha="${INITIAL_GITCONFIG_SHA:-}"
  if [ -z "$expected_sha" ] && [ -n "${GITCONFIG_SNAPSHOT:-}" ] && [ -f "$GITCONFIG_SNAPSHOT" ]; then
    expected_sha="$(cat "$GITCONFIG_SNAPSHOT")"
  fi
  if [ -n "${GITCONFIG_SNAPSHOT:-}" ]; then
    rm -f "$GITCONFIG_SNAPSHOT"
  fi
  [ -n "$expected_sha" ]
  [ "$current_sha" = "$expected_sha" ]
}

setup() {
  REAL_HOME="${REAL_HOME:-$HOME}"
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TEST_SYNC_BIN="${REPO_SYNC_BIN:-$PROJECT_ROOT/bin/k3dm-repo-sync}"
  SCRATCH="$BATS_TEST_TMPDIR/repo-sync-env"
  case "$SCRATCH" in "$BATS_TEST_TMPDIR"/*) ;; *) return 1 ;; esac
  [ "$SCRATCH" != "$PROJECT_ROOT" ]

  SCRATCH_HOME="$SCRATCH/home"
  AGENTS_DIR="$SCRATCH_HOME/Library/LaunchAgents"
  HB_STUB_DIR="$SCRATCH/hb_stubs"
  SPIES_DIR="$SCRATCH/spies"
  REAL_TOOLS_DIR="$SCRATCH/real_tools"
  CALLS_LOG="$SCRATCH/calls.log"

  mkdir -p "$AGENTS_DIR" "$SCRATCH_HOME/.local/share/k3d-manager/logs" "$SCRATCH/state"
  mkdir -p "$SCRATCH_HOME/.config/k3d-manager"
  mkdir -p "$HB_STUB_DIR" "$SPIES_DIR" "$REAL_TOOLS_DIR"
  touch "$CALLS_LOG"

  # Machine role set to hub so repo-sync runs appsets-check
  printf 'hub\n' > "$SCRATCH_HOME/.config/k3d-manager/machine-role"

  # Fence git environment to scratch BEFORE any git invocation
  export HOME="$SCRATCH_HOME"
  export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
  export GIT_AUTHOR_NAME="test"
  export GIT_AUTHOR_EMAIL="test@example.invalid"
  export GIT_COMMITTER_NAME="test"
  export GIT_COMMITTER_EMAIL="test@example.invalid"

  printf '[user]\n\tname = test\n\temail = test@example.invalid\n' > "$SCRATCH/gitconfig"

  # Assertions that HOME changed and git global config points into scratch
  [ "$HOME" != "$REAL_HOME" ]
  local origin_out
  origin_out="$(git config --show-origin --global --list 2>/dev/null || true)"
  if [ -n "$origin_out" ]; then
    [[ "$origin_out" == *"$SCRATCH"* ]]
  fi

  # Pass real host tools through via scratch symlinks (git, python3, make, bash, core utilities)
  local tool p
  for tool in git python3 make bash sed grep awk cat dirname uname id cut tr head tail; do
    p="$(command -v "$tool" || true)"
    if [ -n "$p" ] && [ -x "$p" ]; then
      ln -sf "$p" "$REAL_TOOLS_DIR/$tool"
    fi
  done

  # launchctl stub: records calls only, no output imitated
  cat > "$SPIES_DIR/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "launchctl" "$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "$SPIES_DIR/launchctl"

  # Installer spies for package managers (brew, apt-get, dnf, yum)
  for tool in brew apt-get dnf yum; do
    cat > "$SPIES_DIR/$tool" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "\${CALLS_LOG}"
exit 0
EOF
    chmod +x "$SPIES_DIR/$tool"
  done

  # sudo spy: intercept package manager invocations when resolved with absolute path
  cat > "$SPIES_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
while [[ "${1:-}" == -* ]]; do shift; done
prog="$(basename "${1:-}")"
shift || true
case "$prog" in
  brew|apt-get|dnf|yum)
    printf '%s %s\n' "$prog" "$*" >> "${CALLS_LOG}"
    exit 0
    ;;
  *)
    exec "$prog" "$@"
    ;;
esac
EOF
  chmod +x "$SPIES_DIR/sudo"

  # Stub network helpers invoked by Linux package manager setup
  for tool in curl gpg tee; do
    cat > "$SPIES_DIR/$tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SPIES_DIR/$tool"
  done

  # Stub kubectl in scratch Homebrew replacement directory with valid response
  cat > "$HB_STUB_DIR/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"get application"* ]]; then
  cat <<'JSON'
{"items": [{"metadata": {"name": "test-app"}, "spec": {"source": {"repoURL": "https://github.com/wilddog64/k3d-manager", "targetRevision": "deploy/hub"}}}]}
JSON
  exit 0
fi
exit 0
EOF
  chmod +x "$HB_STUB_DIR/kubectl"

  # Stub gh in scratch Homebrew replacement directory
  cat > "$HB_STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$HB_STUB_DIR/gh"

  # Build bare origin & hub checkout fixture as in repo_sync_promote_backlog.bats
  git -c init.defaultBranch=main init --bare "$SCRATCH/upstream.git" >/dev/null
  git clone "$SCRATCH/upstream.git" "$SCRATCH/seed" >/dev/null 2>&1
  git -C "$SCRATCH/seed" config user.email test@example.invalid
  git -C "$SCRATCH/seed" config user.name test
  git -C "$SCRATCH/seed" checkout -b main >/dev/null
  echo base > "$SCRATCH/seed/file"
  git -C "$SCRATCH/seed" add file
  git -C "$SCRATCH/seed" commit -m base >/dev/null
  git -C "$SCRATCH/seed" push -u origin HEAD:main >/dev/null 2>&1
  git -C "$SCRATCH/seed" push origin HEAD:refs/heads/deploy/hub >/dev/null 2>&1

  HUB_ROOT="$SCRATCH/hub-checkout"
  git clone -b main "$SCRATCH/upstream.git" "$HUB_ROOT" >/dev/null 2>&1
  git -C "$HUB_ROOT" config user.email test@example.invalid
  git -C "$HUB_ROOT" config user.name test
  mkdir -p "$HUB_ROOT/bin"
  cp "$TEST_SYNC_BIN" "$HUB_ROOT/bin/k3dm-repo-sync"
  chmod +x "$HUB_ROOT/bin/k3dm-repo-sync"
  ln -s "$PROJECT_ROOT/Makefile" "$HUB_ROOT/Makefile"
  ln -s "$PROJECT_ROOT/scripts" "$HUB_ROOT/scripts"

  # Fixture target assertions (scratch HOME, not ~/Library/LaunchAgents)
  [ -d "$SCRATCH_HOME" ]
  [ -d "$AGENTS_DIR" ]
  [ "$SCRATCH" != "$PROJECT_ROOT" ]
  [ -d "$SCRATCH/upstream.git" ]
  [ -d "$HUB_ROOT/.git" ]
}

teardown() {
  rm -rf "$SCRATCH"
}

_extract_plist_path() {
  local plist_path="$1"
  python3 -c '
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        pl = plistlib.load(f)
    env = pl.get("EnvironmentVariables", {})
    val = env.get("PATH", "")
    sys.stdout.write(val)
except Exception:
    pass
' "$plist_path"
}

_run_sync_with_path() {
  local sync_path="$1"
  run env -i \
    HOME="$SCRATCH_HOME" \
    XDG_CONFIG_HOME="$SCRATCH_HOME/.config" \
    K3DM_REPO_SYNC_STATE_DIR="$SCRATCH/state" \
    K3DM_REPO_SYNC_TIMEOUT=3 \
    K3DM_REPO_SYNC_REPOS="$HUB_ROOT" \
    PUSHGATEWAY_URL="http://127.0.0.1:9" \
    CALLS_LOG="$CALLS_LOG" \
    PATH="$sync_path" \
    "$HUB_ROOT/bin/k3dm-repo-sync"
}

@test "E1: the rendered repo-sync plist sets PATH with /opt/homebrew/bin ahead of /usr/bin (M1)" {
  local plist="$AGENTS_DIR/com.k3d-manager.repo-sync.plist"

  run env -i HOME="$SCRATCH_HOME" PATH="$SPIES_DIR:$REAL_TOOLS_DIR:/usr/bin:/bin" K3DM_AGENT_LOAD=0 \
    make -C "$PROJECT_ROOT" --no-print-directory install-repo-sync
  [ "$status" -eq 0 ]
  [ -f "$plist" ]

  local path_val
  path_val="$(_extract_plist_path "$plist")"
  [ -n "$path_val" ]

  [[ "$path_val" == *"/opt/homebrew/bin"* ]]
  [[ "$path_val" == *"/usr/bin"* ]]

  local hb_prefix="${path_val%%/opt/homebrew/bin*}"
  local ub_prefix="${path_val%%/usr/bin*}"
  [ "${#hb_prefix}" -lt "${#ub_prefix}" ]

  # Expected standard tool chain with Homebrew first
  [[ "$path_val" == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"* ]]
}

@test "E2: the job, run with only the rendered plist's environment, invokes no installer for kubectl or gh (N1)" {
  local plist="$AGENTS_DIR/com.k3d-manager.repo-sync.plist"

  run env -i HOME="$SCRATCH_HOME" PATH="$SPIES_DIR:$REAL_TOOLS_DIR:/usr/bin:/bin" K3DM_AGENT_LOAD=0 \
    make -C "$PROJECT_ROOT" --no-print-directory install-repo-sync
  [ "$status" -eq 0 ]
  [ -f "$plist" ]

  local rendered_path
  rendered_path="$(_extract_plist_path "$plist")"

  # Substitute /opt/homebrew/bin with scratch dir holding stub kubectl and gh
  local job_path
  if [ -n "$rendered_path" ]; then
    job_path="${rendered_path//\/opt\/homebrew\/bin/$HB_STUB_DIR}:$SPIES_DIR:$REAL_TOOLS_DIR"
  else
    # Default launchd PATH without Homebrew
    job_path="$SPIES_DIR:$REAL_TOOLS_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  fi

  : > "$CALLS_LOG"
  _run_sync_with_path "$job_path"
  [ "$status" -eq 0 ]

  # Assert no installer spy call for kubectl or gh
  run grep -Eq '(brew|apt-get|dnf|yum).*(kubectl|gh)' "$CALLS_LOG"
  [ "$status" -ne 0 ]

  # Assert launchctl was not called
  run grep -q '^launchctl' "$CALLS_LOG"
  [ "$status" -ne 0 ]

  # Assert no installer calls were made
  [ ! -s "$CALLS_LOG" ]
}

_no_brew_system_dir() {
  local sys_dir="$SCRATCH/system_no_brew" d f name
  mkdir -p "$sys_dir"
  for d in /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      name="${f##*/}"
      case "$name" in kubectl|gh) continue ;; esac
      [ -e "$sys_dir/$name" ] || ln -s "$f" "$sys_dir/$name"
    done
  done
  printf '%s\n' "$sys_dir"
}

@test "N1 positive control: default launchd PATH without Homebrew invokes installer for kubectl" {
  local sys_dir default_launchd_path
  sys_dir="$(_no_brew_system_dir)"
  default_launchd_path="$SPIES_DIR:$REAL_TOOLS_DIR:$sys_dir"
  if PATH="$default_launchd_path" command -v kubectl >/dev/null; then false; fi
  if PATH="$default_launchd_path" command -v gh >/dev/null; then false; fi

  : > "$CALLS_LOG"
  _run_sync_with_path "$default_launchd_path"

  # Under default launchd PATH, kubectl is missing and installer path is reached
  [ -s "$CALLS_LOG" ]
  grep -Eq '(brew|apt-get|dnf|yum).*install.*kubectl' "$CALLS_LOG"
}
