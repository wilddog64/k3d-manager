#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/install-pytest-venv.XXXXXX")"
  SCRATCH_HOME="$WORK/home"
  STUB_DIR="$WORK/bin"
  CALL_LOG="$WORK/calls.log"

  mkdir -p "$SCRATCH_HOME" "$STUB_DIR"
  : > "$CALL_LOG"

  # Stub python3 on PATH
  cat > "$STUB_DIR/python3" <<'EOF'
#!/usr/bin/env bash
echo "python3: $*" >> "${CALL_LOG:-/dev/null}"
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
  target="${@: -1}"
  mkdir -p "$target/bin"
  cat > "$target/bin/python" <<'VENV_EOF'
#!/usr/bin/env bash
echo "venv-python: $*" >> "${CALL_LOG:-/dev/null}"
if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then
  exit 0
elif [ "$1" = "-m" ] && [ "$2" = "pytest" ] && [ "$3" = "--version" ]; then
  echo "pytest 9.1.1"
  exit 0
fi
exit 0
VENV_EOF
  chmod +x "$target/bin/python"
  exit 0
fi
exit 0
EOF
  chmod +x "$STUB_DIR/python3"

  # Stub sudo to catch any unauthorized sudo invocation
  cat > "$STUB_DIR/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo: $*" >> "${CALL_LOG:-/dev/null}"
exit 1
EOF
  chmod +x "$STUB_DIR/sudo"
}

teardown() {
  rm -rf "$WORK"
}

@test "Y-N3: install target does not touch sudo, pip --user, or the real HOME" {
  export CALL_LOG
  real_home="$HOME"
  run env -i HOME="$SCRATCH_HOME" PATH="$STUB_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" \
    make -C "$REPO_ROOT" install-pytest-venv || true
  run ! grep -q "sudo:" "$CALL_LOG"
  run ! grep -q -- "--user" "$CALL_LOG"
  [ ! -e "$real_home/.local/share/k3d-manager/pytest-venv" ]
}

@test "Y-M2: make install-pytest-venv creates venv with pinned packages" {
  export CALL_LOG
  run env -i HOME="$SCRATCH_HOME" PATH="$STUB_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" \
    make -C "$REPO_ROOT" install-pytest-venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"pytest 9.1.1"* ]]

  # Verifies python3 -m venv was invoked targeting the expected path
  grep -Fq "python3: -m venv $SCRATCH_HOME/.local/share/k3d-manager/pytest-venv" "$CALL_LOG"

  # Verifies pip install was invoked with exactly the pinned packages
  grep -Fq "venv-python: -m pip install pytest==9.1.1 PyYAML==6.0.3" "$CALL_LOG"

  # Verifies pytest --version was invoked
  grep -Fq "venv-python: -m pytest --version" "$CALL_LOG"
}

@test "Y-M2: make install-pytest-venv is idempotent and reuses existing venv" {
  export CALL_LOG
  # First run creates the venv
  run env -i HOME="$SCRATCH_HOME" PATH="$STUB_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" \
    make -C "$REPO_ROOT" install-pytest-venv
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH_HOME/.local/share/k3d-manager/pytest-venv/bin/python" ]

  # Clear call log before second run
  : > "$CALL_LOG"

  # Second run should reuse existing venv and reinstall pins
  run env -i HOME="$SCRATCH_HOME" PATH="$STUB_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" \
    make -C "$REPO_ROOT" install-pytest-venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"pytest 9.1.1"* ]]

  # python3 -m venv should not be called again because venv already exists
  run ! grep -q "python3: -m venv" "$CALL_LOG"

  # But pip install and pytest --version should run
  grep -Fq "venv-python: -m pip install pytest==9.1.1 PyYAML==6.0.3" "$CALL_LOG"
  grep -Fq "venv-python: -m pytest --version" "$CALL_LOG"
}

@test "Y-M2: a venv whose interpreter no longer starts is rebuilt with --clear" {
  export CALL_LOG
  venv="$SCRATCH_HOME/.local/share/k3d-manager/pytest-venv"
  mkdir -p "$venv/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$venv/bin/python"
  chmod +x "$venv/bin/python"
  run env -i HOME="$SCRATCH_HOME" PATH="$STUB_DIR:/usr/bin:/bin" CALL_LOG="$CALL_LOG" \
    make -C "$REPO_ROOT" install-pytest-venv
  [ "$status" -eq 0 ]
  grep -Fq "python3: -m venv --clear $venv" "$CALL_LOG"
  grep -Fq "venv-python: -m pip install pytest==9.1.1 PyYAML==6.0.3" "$CALL_LOG"
  [[ "$output" == *"broken interpreter"* ]]
}
