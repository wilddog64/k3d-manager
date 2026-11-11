#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/makefile-agent-load.XXXXXX")"
  STUB_DIR="$WORK/stub"
  SCRATCH_HOME="$WORK/home"
  AGENTS_DIR="$SCRATCH_HOME/Library/LaunchAgents"
  CALLS="$WORK/calls"

  mkdir -p "$STUB_DIR" "$AGENTS_DIR" "$SCRATCH_HOME/Library/Logs" "$SCRATCH_HOME/.local/share/k3d-manager/logs"

  cat > "$STUB_DIR/launchctl" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "launchctl" "\$*" >> "$CALLS"
exit 0
EOF
  chmod +x "$STUB_DIR/launchctl"

  cat > "$STUB_DIR/security" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB_DIR/security"

  cat > "$STUB_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ls-remote"* ]]; then
  printf 'c0ffee\trefs/heads/cloud-requests\n'
  exit 0
fi
exec /usr/bin/git "$@"
EOF
  chmod +x "$STUB_DIR/git"

  cat > "$STUB_DIR/id" <<'EOF'
#!/usr/bin/env bash
echo 501
EOF
  chmod +x "$STUB_DIR/id"

  export HOME="$SCRATCH_HOME"
  export PATH="$STUB_DIR:$PATH"
  export K3DM_PYTHON3_PATH="${K3DM_PYTHON3_PATH:-/usr/bin/python3}"

  # Fixture assertion
  [ -d "$AGENTS_DIR" ]
  [ "$(command -v launchctl)" = "$STUB_DIR/launchctl" ]
  [ "$HOME" = "$SCRATCH_HOME" ]
}

teardown() {
  rm -rf "$WORK"
}

@test "E1: with K3DM_AGENT_LOAD=0 each in-scope install target writes plist and calls no launchctl (N1, M2)" {
  local targets=(repo-sync cleanup node-health-watch sandbox-reaper cloud-bridge test-metrics)
  local target

  for target in "${targets[@]}"; do
    : > "$CALLS"
    K3DM_AGENT_LOAD=0 make -s -C "$REPO" "install-${target}"
    [ -s "$AGENTS_DIR/com.k3d-manager.${target}.plist" ]

    run grep -E '^launchctl (bootout|unload|bootstrap|load|kickstart)' "$CALLS"
    [ "$status" -eq 1 ]
  done
}

@test "E2: with K3DM_AGENT_LOAD unset each in-scope install target boots out then bootstraps (M1)" {
  local targets=(repo-sync cleanup node-health-watch sandbox-reaper cloud-bridge test-metrics)
  local target

  for target in "${targets[@]}"; do
    rm -f "$CALLS"
    unset K3DM_AGENT_LOAD
    make -s -C "$REPO" "install-${target}"
    [ -s "$AGENTS_DIR/com.k3d-manager.${target}.plist" ]

    grep -q "^launchctl bootout gui/501/com.k3d-manager.${target}" "$CALLS"
    grep -q "^launchctl bootstrap gui/501 $AGENTS_DIR/com.k3d-manager.${target}.plist" "$CALLS"
  done
}
