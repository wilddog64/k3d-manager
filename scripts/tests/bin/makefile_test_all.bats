#!/usr/bin/env bats
# Recursion guard: blocks nested test-all when K3DM_MAKEFILE_TEST_ALL_NESTED is set unless non-empty STAGE_* or K3DM_TESTS_DIR overrides are explicitly provided.

setup() {
  if [ "${K3DM_MAKEFILE_TEST_ALL_NESTED:-0}" -ge 2 ]; then
    skip "recursion guard: nested makefile_test_all.bats execution blocked"
  fi

  # Item 1: isolate environment from outer make flags or leaked variables
  unset MAKEFLAGS MAKELEVEL MFLAGS PARALLEL
  unset STAGE_TEST_FILES STAGE_TEST_BIN_FILES STAGE_TEST_PYTHON_FILES STAGE_TEST_PYTHON_UNIT_FILES STAGE_TEST_PYTEST_FILES
  unset K3DM_TESTS_DIR K3DM_JUNIT_XML
  unset PYTEST JOBS CLUSTER_ROLE XDG_CONFIG_HOME

  export K3DM_MAKEFILE_TEST_ALL_NESTED="$((${K3DM_MAKEFILE_TEST_ALL_NESTED:-0} + 1))"
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/makefile-test-all.XXXXXX")"
  SCRATCH_HOME="$WORK/home"
  STUB_DIR="$WORK/bin"
  FAKE_TESTS="$WORK/tests"
  CALLS="$WORK/calls"
  CACHE_DIR="$WORK/cache"
  FAKE_REPO="$WORK/fake_repo"

  mkdir -p "$SCRATCH_HOME" "$STUB_DIR" "$FAKE_TESTS" "$CACHE_DIR" "$FAKE_REPO" "$WORK/tmp"
  export TMPDIR="$WORK/tmp"
  : > "$CALLS"

  # Setup fake repo root so default invocations without STAGE_* never run real suites
  mkdir -p "$FAKE_REPO/bin" "$FAKE_REPO/scripts/tests/lib" "$FAKE_REPO/scripts/tests/core" "$FAKE_REPO/scripts/tests/plugins" "$FAKE_REPO/scripts/tests/etc" "$FAKE_REPO/scripts/tests/bin" "$FAKE_REPO/scripts/tests/hermes"
  ln -sf "$REPO_ROOT/Makefile" "$FAKE_REPO/Makefile"
  ln -sf "$REPO_ROOT/scripts/lib" "$FAKE_REPO/scripts/lib"
  ln -sf "$REPO_ROOT/scripts/tests/tripwire.sh" "$FAKE_REPO/scripts/tests/tripwire.sh"
  ln -sf "$REPO_ROOT/bin/k3dm-test-metrics" "$FAKE_REPO/bin/k3dm-test-metrics"
  cat > "$FAKE_REPO/scripts/tests/bin/makefile_test_all.bats" <<'EOF'
@test "nested guard placeholder" { true; }
EOF

  # Fake k3d-manager in FAKE_REPO
  cat > "$FAKE_REPO/scripts/k3d-manager" <<'EOF'
#!/usr/bin/env bash
echo "fake-k3d-manager: $*" >> "${CALLS:-/dev/null}"
if [ "${FAKE_TEST_STATUS:-pass}" = "fail" ]; then
  exit 1
elif [ "${FAKE_TEST_STATUS:-pass}" = "kill" ]; then
  kill -TERM $$
fi
exit 0
EOF
  chmod +x "$FAKE_REPO/scripts/k3d-manager"

  # Fake check-agent-docs in FAKE_REPO
  cat > "$FAKE_REPO/bin/k3dm-check-agent-docs" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_CHECK_AGENT_DOCS_RC:-0}"
EOF
  chmod +x "$FAKE_REPO/bin/k3dm-check-agent-docs"

  # Fast fixture tests inside fake_repo
  cat > "$FAKE_REPO/scripts/tests/lib/pass1.bats" <<'EOF'
@test "pass1" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/core/pass2.bats" <<'EOF'
@test "pass2" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/plugins/pass3.bats" <<'EOF'
@test "pass3" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/etc/pass4.bats" <<'EOF'
@test "pass4" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/bin/pass_bin.bats" <<'EOF'
@test "pass_bin" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/bin/pass_py.py" <<'EOF'
import unittest
class T(unittest.TestCase):
    def test_ok(self): pass
if __name__ == '__main__':
    unittest.main()
EOF
  cat > "$FAKE_REPO/scripts/tests/bin/test_pass.py" <<'EOF'
def test_ok(): pass
EOF

  # Stubs on PATH: stub pytest (resolves on CI before pytest is installed)
  cat > "$STUB_DIR/pytest" <<'EOF'
#!/usr/bin/env bash
echo "stub-pytest: $*" >> "${CALLS:-/dev/null}"
for arg in "$@"; do
  case "$arg" in
    *kill*) kill -TERM $$ ;;
    *fail*) exit 1 ;;
    *rc2*) exit 2 ;;
  esac
done
exec python3 -c "import importlib.util, sys
for arg in sys.argv[1:]:
  if arg.endswith('.py') and not arg.startswith('-'):
    try:
      spec = importlib.util.spec_from_file_location('m', arg)
      m = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(m)
      for k, v in vars(m).items():
        if k.startswith('test') and callable(v):
          v()
    except Exception:
      pass" "$@"
EOF
  chmod +x "$STUB_DIR/pytest"

  # Stub bats: if run without args or on fake tests, runs fast; delegates to real bats when needed
  cat > "$STUB_DIR/bats" <<'EOF'
#!/usr/bin/env bash
echo "stub-bats: $*" >> "${CALLS:-/dev/null}"
for arg in "$@"; do
  case "$arg" in
    *kill*) kill -TERM $$ ;;
    *fail*) exit 1 ;;
  esac
done
self="$(cd "$(dirname "$0")" && pwd)"
real_bats="$(type -ap bats | grep -v "$self" | grep -v "/private$self" | head -n 1)"
if [ -n "$real_bats" ] && [ -x "$real_bats" ]; then
  exec "$real_bats" "$@"
fi
exit 0
EOF
  chmod +x "$STUB_DIR/bats"

  cat > "$STUB_DIR/python3" <<'EOF'
#!/usr/bin/env bash
echo "stub-python3: $*" >> "${CALLS:-/dev/null}"
self="$(cd "$(dirname "$0")" && pwd)"
real_py="$(type -ap python3 | grep -v "$self" | grep -v "/private$self" | head -n 1)"
if [ -n "$real_py" ] && [ -x "$real_py" ]; then
  exec "$real_py" "$@"
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "$STUB_DIR/python3"

  cat > "$STUB_DIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "stub kubectl: $*"
exit 0
EOF
  chmod +x "$STUB_DIR/kubectl"

  cat > "$FAKE_TESTS/pass1.bats" <<'EOF'
@test "pass1" {
  true
}
EOF
  cat > "$FAKE_TESTS/fail1.bats" <<'EOF'
@test "fail1" {
  false
}
EOF
  cat > "$FAKE_TESTS/pass2.bats" <<'EOF'
@test "pass2" {
  true
}
EOF
  cat > "$FAKE_TESTS/pass_py.py" <<'EOF'
import unittest
class T(unittest.TestCase):
    def test_ok(self):
        print("fake pass_py running")
if __name__ == '__main__':
    unittest.main()
EOF
  cat > "$FAKE_TESTS/test_pytest_pass.py" <<'EOF'
def test_pytest_ok():
    pass
EOF
  cat > "$FAKE_TESTS/fail_unit.py" <<'EOF'
import unittest
class T(unittest.TestCase):
    def test_fail(self):
        self.assertTrue(False)
if __name__ == '__main__':
    unittest.main()
EOF
  cat > "$FAKE_TESTS/kill_unit.py" <<'EOF'
import os, signal, unittest
class T(unittest.TestCase):
    def test_kill(self):
        os.kill(os.getpid(), signal.SIGTERM)
if __name__ == '__main__':
    unittest.main()
EOF
  cat > "$FAKE_TESTS/test_pytest_fail.py" <<'EOF'
def test_pytest_fail():
    assert False
EOF
  cat > "$FAKE_TESTS/test_pytest_kill.py" <<'EOF'
import os, signal
def test_pytest_kill():
    os.kill(os.getpid(), signal.SIGTERM)
EOF
  cat > "$FAKE_TESTS/assert_tmpdir_unit.py" <<'EOF'
import os, unittest
class T(unittest.TestCase):
    def test_tmpdir(self):
        tmp = os.environ.get('TMPDIR', '')
        self.assertIn('/k3dm-job-', tmp)
        with open(os.environ['WORK'] + '/unit_tmpdir.log', 'w') as f:
            f.write(tmp)
if __name__ == '__main__':
    unittest.main()
EOF
  cat > "$FAKE_TESTS/test_assert_tmpdir_pytest.py" <<'EOF'
import os
def test_tmpdir():
    tmp = os.environ.get('TMPDIR', '')
    assert '/k3dm-job-' in tmp
    with open(os.environ['WORK'] + '/pytest_tmpdir.log', 'w') as f:
        f.write(tmp)
EOF
  cat > "$FAKE_TESTS/kill.sh" <<'EOF'
#!/usr/bin/env bash
kill -9 $$
EOF
  chmod +x "$FAKE_TESTS/kill.sh"

  cat > "$FAKE_TESTS/tripwire_mutating.bats" <<'EOF'
@test "blocked mutating tool bats" {
  kubectl delete pod fake-pod-12345
}
EOF
  cat > "$FAKE_TESTS/mutating_unit.py" <<'EOF'
import subprocess, unittest
class T(unittest.TestCase):
    def test_mutating(self):
        print("fake mutating unit running")
        subprocess.run(["kubectl", "delete", "pod", "fake-pod-12345"], check=False)
if __name__ == '__main__':
    unittest.main()
EOF
  cat > "$FAKE_TESTS/test_mutating_pytest.py" <<EOF
import pathlib, subprocess
def test_mutating_pytest():
    pathlib.Path("$WORK/pytest_mutating_marker").write_text("ran")
    subprocess.run(["kubectl", "delete", "pod", "fake-pod-12345"], check=False)
EOF

  export HOME="$SCRATCH_HOME"
  export K3DM_PUSHGATEWAY_URL="http://127.0.0.1:9"
  export PUSHGATEWAY_URL="http://127.0.0.1:9"
  export XDG_CACHE_HOME="$CACHE_DIR"
  export PATH="$STUB_DIR:$PATH"
  export CALLS
  export WORK
  export FAKE_REPO

  [ "$K3DM_PUSHGATEWAY_URL" = "http://127.0.0.1:9" ] || return 1
}

teardown() {
  if [ -n "${STREAM_MAKE_PID:-}" ]; then
    kill -9 "$STREAM_MAKE_PID" 2>/dev/null || true
  fi
  export K3DM_MAKEFILE_TEST_ALL_NESTED="$((${K3DM_MAKEFILE_TEST_ALL_NESTED:-1} - 1))"
  rm -rf "$WORK"
}

@test "N3: serial runs the same stages in the same order when all pass" {
  [ "$HOME" = "$SCRATCH_HOME" ]
  [[ "$PATH" == "$STUB_DIR:"* ]]
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  idx1=$(echo "$output" | grep -nE '^\[test-all\] stage-complete test seconds=[0-9]+$' | cut -d: -f1)
  idx2=$(echo "$output" | grep -nE '^\[test-all\] stage-complete test-bin seconds=[0-9]+$' | cut -d: -f1)
  idx3=$(echo "$output" | grep -nE '^\[test-all\] stage-complete test-python seconds=[0-9]+$' | cut -d: -f1)
  [ -n "$idx1" ] && [ -n "$idx2" ] && [ -n "$idx3" ]
  [ "$idx1" -lt "$idx2" ] && [ "$idx2" -lt "$idx3" ]
}

@test "M7, E5: serial runs every stage even when an earlier stage fails, and exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED FAKE_TEST_STATUS="fail" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0
  [ "$status" -ne 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$output" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "N5, E5: serial does not print stage-complete for a stage whose child is killed by a signal, but runs later stages" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED FAKE_TEST_STATUS="kill" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0
  [ "$status" -ne 0 ]
  local out="$output"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "N5: serial does not print stage-complete when stage aborts with exit 2 before runner, but runs later stages" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  NO_BATS_DIR="$WORK/no_bats_bin"
  mkdir -p "$NO_BATS_DIR"
  for d in /bin /usr/bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -x "$f" ] || continue
      b="$(basename "$f")"
      case "$b" in bats*) continue ;; esac
      [ -e "$NO_BATS_DIR/$b" ] || ln -sf "$f" "$NO_BATS_DIR/$b"
    done
  done
  for tool in make python3 bash; do
    t="$(command -v "$tool" 2>/dev/null || true)"
    if [ -n "$t" ] && [ -x "$t" ]; then
      ln -sf "$t" "$NO_BATS_DIR/$tool"
    fi
  done
  run env PATH="$NO_BATS_DIR" command -v bats
  [ "$status" -ne 0 ]
  run env PATH="$NO_BATS_DIR" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  local out="$output"
  echo "$out" | grep -q "bats not found"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-bin( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "M7, E5: parallel runs every stage even when an earlier stage fails, and exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/fail1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$output" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "N5: a killed parallel job does not print stage-complete, later stages run and print theirs" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/kill.sh" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  local out="$output"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 1: parallel pytest resolves command once via exact chain" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  PYTEST_STUB_DIR="$WORK/pytest_chain_bin"
  mkdir -p "$PYTEST_STUB_DIR"
  cat > "$PYTEST_STUB_DIR/pytest" <<EOF
#!/usr/bin/env bash
echo "resolved pytest stub ran with args: \$*" >> "$WORK/pytest_stub.log"
exit 0
EOF
  chmod +x "$PYTEST_STUB_DIR/pytest"
  cat > "$PYTEST_STUB_DIR/python3" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "pytest" ]; then
  exit 1
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "$PYTEST_STUB_DIR/python3"

  run env PATH="$PYTEST_STUB_DIR:$PATH" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -eq 0 ]
  [ -s "$WORK/pytest_stub.log" ]
  grep -q "resolved pytest stub ran" "$WORK/pytest_stub.log"
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 1: test-all runs metrics step in serial and parallel with expected exit code" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  rm -f "$FAKE_REPO/bin/k3dm-test-metrics"
  cat > "$FAKE_REPO/bin/k3dm-test-metrics" <<'EOF'
#!/usr/bin/env bash
echo "metrics: $*" >> "$WORK/metrics_calls"
exit 0
EOF
  chmod +x "$FAKE_REPO/bin/k3dm-test-metrics"

  # Serial mode
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  [ -s "$WORK/metrics_calls" ]
  grep -q -- "--target test-all" "$WORK/metrics_calls"
  grep -q -- "--exit-code 0" "$WORK/metrics_calls"

  # Parallel mode
  : > "$WORK/metrics_calls"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  [ -s "$WORK/metrics_calls" ]
  grep -q -- "--target test-all" "$WORK/metrics_calls"
  grep -q -- "--exit-code 0" "$WORK/metrics_calls"

  # Parallel mode with failure
  : > "$WORK/metrics_calls"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/fail1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  [ -s "$WORK/metrics_calls" ]
  grep -q -- "--target test-all" "$WORK/metrics_calls"
  grep -E -- "--exit-code [12]" "$WORK/metrics_calls"

  # Nested run does not publish metrics
  : > "$WORK/metrics_calls"
  run env K3DM_MAKEFILE_TEST_ALL_NESTED=1 make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  [ ! -s "$WORK/metrics_calls" ]
}

@test "Item 4/7: parallel check-agent-docs failure stops stage 3 and prints no marker" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  export FAKE_CHECK_AGENT_DOCS_RC=1
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  local out="$output"
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
}

@test "Item 4: parallel bare def test_ without main hook exits 2" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  cat > "$FAKE_TESTS/bare_test.py" <<'EOF'
def test_something():
    pass
EOF
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/bare_test.py"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "defines bare test functions but has no main hook"
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Item 5: K3DM_JUNIT_XML ignored in parallel mode" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     K3DM_JUNIT_XML="$WORK/junit.xml"     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -Fx "[test-all] K3DM_JUNIT_XML ignored in PARALLEL mode"
}

@test "Item 6: FLAKY and FAIL lines collected across stages and printed at end" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/fail1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -Fx "[test-all] failed:"
  echo "$output" | grep -E "^FAIL .*fail1\.bats"
}

@test "Item 7: missing pytest in parallel fails at stage 3 after stages 1 and 2 run" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  NO_PYTEST_DIR="$WORK/no_pytest_bin"
  mkdir -p "$NO_PYTEST_DIR"
  cat > "$NO_PYTEST_DIR/python3" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "pytest" ]; then
  exit 1
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "$NO_PYTEST_DIR/python3"

  real_bats="$(type -ap bats | grep -v "$WORK" | grep -v "/private$WORK" | head -n 1)"
  BATS_BIN_DIR="$(dirname "$real_bats")"
  run env PATH="$NO_PYTEST_DIR:$BATS_BIN_DIR:/usr/bin:/bin" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -eq 2 ]
  local out="$output"
  echo "$out" | grep -q "no pytest found"
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -Fx "[test-all] failed:"
}

@test "Item 7: parallel unittest prints [make] python3 prefix" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "\[make\] python3 .*pass_py\.py"
}

@test "Item 10: empty stage fails and prints no marker" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  EMPTY_DIR="$WORK/empty_tests"
  mkdir -p "$EMPTY_DIR"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-bin( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Item 11: PARALLEL=0 runs serial" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  local out="$output"
  run grep -q "SLOWEST" <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 12: partial run does not update times cache" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  [ ! -f "$CACHE_DIR/k3d-manager/test-times.txt" ]
}

@test "Item 12 positive control: full run without STAGE overrides writes times cache" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1
  [ "$status" -eq 0 ]
  [ -f "$CACHE_DIR/k3d-manager/test-times.txt" ]
}

@test "Mutant killer: BATS_SHELL is set and exported in parallel stage 1" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  cat > "$FAKE_TESTS/check_bats_shell.bats" <<'EOF'
@test "bats_shell present" {
  [ -n "$BATS_SHELL" ]
}
EOF
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/check_bats_shell.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok 1 bats_shell present"
}

@test "B2: scratch HOME with machine-role worker passes in parallel stage 1 and serial" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  mkdir -p "$SCRATCH_HOME/.config/k3d-manager"
  echo "worker" > "$SCRATCH_HOME/.config/k3d-manager/machine-role"
  cat > "$FAKE_TESTS/check_cluster_role.bats" <<'EOF'
@test "cluster_role is infra" {
  [ "$CLUSTER_ROLE" = "infra" ]
}
EOF
  # Serial
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/check_cluster_role.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'

  # Parallel
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/check_cluster_role.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
}

@test "Mutant killer: FLAKY test retry passes and is reported in end summary" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  STATE_FILE="$WORK/flaky_state"
  cat > "$FAKE_TESTS/flaky.bats" <<EOF
@test "flaky test" {
  if [ ! -f "$STATE_FILE" ]; then
    touch "$STATE_FILE"
    false
  fi
  true
}
EOF
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/flaky.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -Fx "[test-all] flaky:"
  echo "$output" | grep -E "^FLAKY .*flaky\.bats"
}

@test "Mutant killer: per-job TMPDIR is isolated and unique" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  TMPDIR_LOG="$WORK/tmpdirs.log"
  cat > "$FAKE_TESTS/check_tmpdir1.bats" <<EOF
@test "job tmpdir 1" {
  echo "\$TMPDIR" >> "$TMPDIR_LOG"
  echo "\$TMPDIR" | grep -q "/k3dm-job-"
}
EOF
  cat > "$FAKE_TESTS/check_tmpdir2.bats" <<EOF
@test "job tmpdir 2" {
  echo "\$TMPDIR" >> "$TMPDIR_LOG"
  echo "\$TMPDIR" | grep -q "/k3dm-job-"
}
EOF
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/check_tmpdir1.bats $FAKE_TESTS/check_tmpdir2.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_LOG" ]
  tmp1="$(head -n 1 "$TMPDIR_LOG")"
  tmp2="$(tail -n 1 "$TMPDIR_LOG")"
  [ "$tmp1" != "$tmp2" ]
  echo "$tmp1" | grep -q "/k3dm-job-"
  echo "$tmp2" | grep -q "/k3dm-job-"
}

@test "N2 (.bats): parallel runs jobs under tripwire and catches mutating tool calls" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/tripwire_mutating.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q '\[tripwire\] blocked .* call(s) to host tools'
}

@test "N2 (.py unittest): parallel runs jobs under tripwire and catches mutating tool calls" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/mutating_unit.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q '\[tripwire\] blocked .* call(s) to host tools'
}

@test "N2 (test_*.py pytest): parallel runs jobs under tripwire and catches mutating tool calls" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_mutating_pytest.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q '\[tripwire\] blocked .* call(s) to host tools'
}

@test "N2: parallel positive control passes under tripwire without mutating calls" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok 1 pass1"
  echo "$output" | grep -q "ok 1 pass2"
  echo "$output" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$output" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 1: test-python serial failing unittest runs pytest, prints stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  PYTEST_MARKER="$WORK/pytest_ran"
  cat > "$FAKE_TESTS/test_marker_pytest.py" <<EOF
import pathlib
def test_ran():
    pathlib.Path("$PYTEST_MARKER").write_text("1")
EOF
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/fail_unit.py $FAKE_TESTS/test_marker_pytest.py"
  [ "$status" -ne 0 ]
  [ -f "$PYTEST_MARKER" ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 1: test-python parallel failing unittest prints stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/fail_unit.py $FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 1: test-python serial killed unittest prints no stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/kill_unit.py $FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Item 1: test-python serial with make -k killed unittest prints no stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run make -k --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/kill_unit.py $FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Item 1: test-python parallel killed unittest prints no stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/kill_unit.py $FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Item 1: test-python serial failing pytest prints stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py $FAKE_TESTS/test_pytest_fail.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 1: test-python parallel failing pytest prints stage-complete, exits non-zero" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py $FAKE_TESTS/test_pytest_fail.py"
  [ "$status" -ne 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 2: missing bats in parallel prints no marker for stages 1 and 2" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  NO_BATS_DIR="$WORK/no_bats_parallel_bin"
  mkdir -p "$NO_BATS_DIR"
  for d in /bin /usr/bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -x "$f" ] || continue
      b="$(basename "$f")"
      case "$b" in bats*) continue ;; esac
      [ -e "$NO_BATS_DIR/$b" ] || ln -sf "$f" "$NO_BATS_DIR/$b"
    done
  done
  for tool in make python3 bash; do
    t="$(command -v "$tool" 2>/dev/null || true)"
    if [ -n "$t" ] && [ -x "$t" ]; then
      ln -sf "$t" "$NO_BATS_DIR/$tool"
    fi
  done
  run env PATH="$NO_BATS_DIR" command -v bats
  [ "$status" -ne 0 ]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED PATH="$NO_BATS_DIR" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  local out="$output"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-bin( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 3: serial killed test stage prints no stage-complete test" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  cat > "$FAKE_TESTS/kill_test.bats" <<'EOF'
@test "kill test" {
  kill -TERM $$
}
EOF
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/kill_test.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  local out="$output"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 3: serial killed test-pytest prints no stage-complete test-python" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_pytest_kill.py"
  [ "$status" -ne 0 ]
  local out="$output"
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
}

@test "Item 5: set K3DM_TESTS_DIR without STAGE overrides does not write times cache" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  TESTS_DIR="$WORK/cache_test_dir"
  mkdir -p "$TESTS_DIR"
  cp "$FAKE_TESTS/pass1.bats" "$TESTS_DIR/"
  cp "$FAKE_TESTS/pass_py.py" "$TESTS_DIR/"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    K3DM_TESTS_DIR="$TESTS_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$CACHE_DIR/k3d-manager/test-times.txt" ]
}

@test "Item 6: parallel per-job TMPDIR is isolated and unique for unittest and pytest" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/assert_tmpdir_unit.py $FAKE_TESTS/test_assert_tmpdir_pytest.py"
  [ "$status" -eq 0 ]
  [ -f "$WORK/unit_tmpdir.log" ] && [ -f "$WORK/pytest_tmpdir.log" ]
  unit_tmp="$(cat "$WORK/unit_tmpdir.log")"
  pytest_tmp="$(cat "$WORK/pytest_tmpdir.log")"
  [ "$unit_tmp" != "$pytest_tmp" ]
  echo "$unit_tmp" | grep -q "/k3dm-job-"
  echo "$pytest_tmp" | grep -q "/k3dm-job-"
}

@test "Item 0: serial with STAGE_* set runs only given fixture files, never real directories or makefile_test_all.bats" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  BATS_LOG="$WORK/bats_run.log"
  LOG_BATS_DIR="$WORK/log_bats_bin"
  mkdir -p "$LOG_BATS_DIR"
  cat > "$LOG_BATS_DIR/bats" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_LOG"
exit 0
EOF
  chmod +x "$LOG_BATS_DIR/bats"

  run env PATH="$LOG_BATS_DIR:$PATH" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0     STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  [ -f "$BATS_LOG" ]
  bats_args="$(cat "$BATS_LOG")"
  echo "$bats_args" | grep -q "pass1.bats"
  echo "$bats_args" | grep -q "pass2.bats"
  run grep -E "scripts/tests/bin|scripts/tests/lib|makefile_test_all\.bats" <<< "$bats_args"
  [ "$status" -ne 0 ]
}

@test "Item 0: recursion guard blocks nested test-all without STAGE_* overrides" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  # shellcheck disable=SC2016
  run env K3DM_MAKEFILE_TEST_ALL_NESTED=1 perl -MPOSIX -e '$t=shift; $p=fork; if(!$p){POSIX::setsid(); open STDIN,"<","/dev/null"; exec @ARGV} $SIG{ALRM}=sub{kill "KILL",-$p; exit 142}; alarm $t; waitpid($p,0); exit($?>>8)' 10 make --no-print-directory -C "$FAKE_REPO" test-all
  if [ "$status" -eq 142 ] || [ "$status" -eq 137 ]; then
    echo "FAILED: recursion guard test timed out (process group killed by alarm 10s)" >&2
    return 1
  fi
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "blocked by recursion guard"
}

@test "Parity: empty override fails stage with no marker in serial and parallel" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  # Serial
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  local out="$output"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'

  # Parallel
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  out="$output"
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Parity: missing test file fails stage with no marker in serial and parallel" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  # Serial
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0     STAGE_TEST_FILES="$FAKE_TESTS/nonexistent.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]

  # Parallel
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1     STAGE_TEST_FILES="$FAKE_TESTS/nonexistent.bats"     STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats"     STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Parity: Python classification treats test_*.py as pytest and others as unittest" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  SUB_DIR="$FAKE_TESTS/subdir"
  mkdir -p "$SUB_DIR"
  cat > "$SUB_DIR/test_two.py" <<'EOF'
def test_two():
    pass
EOF
  cat > "$FAKE_TESTS/unit_one.py" <<'EOF'
import unittest
class T(unittest.TestCase):
    def test_one(self): pass
if __name__ == '__main__':
    unittest.main()
EOF

  # Serial
  : > "$CALLS"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/unit_one.py $SUB_DIR/test_two.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "\[make\] python3 .*unit_one\.py"
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
  grep "stub-python3:" "$CALLS" | grep -q "unit_one\.py"
  grep "stub-pytest:" "$CALLS" | grep -q "test_two\.py"

  # Parallel
  : > "$CALLS"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/unit_one.py $SUB_DIR/test_two.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
  grep "stub-python3:" "$CALLS" | grep -q "unit_one\.py"
  grep "stub-pytest:" "$CALLS" | grep -q "test_two\.py"
}

@test "Parity: empty STAGE_TEST_PYTEST_FILES fails stage with no marker in serial and parallel" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  # Serial
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTEST_FILES=""
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]

  # Parallel
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTEST_FILES=""
  [ "$status" -ne 0 ]
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "B1: parallel stage 1 runs all bats files from lib, core, plugins and etc directories" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  cat > "$FAKE_REPO/scripts/tests/lib/t_lib.bats" <<'EOF'
@test "lib test" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/core/t_core.bats" <<'EOF'
@test "core test" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/plugins/t_plugins.bats" <<'EOF'
@test "plugins test" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/etc/t_etc.bats" <<'EOF'
@test "etc test" { true; }
EOF

  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok 1 lib test"
  echo "$output" | grep -q "ok 1 core test"
  echo "$output" | grep -q "ok 1 plugins test"
  echo "$output" | grep -q "ok 1 etc test"
}

@test "B1: parallel stage 1 discovery matches scripts/k3d-manager:439-443 discovery against fake repo" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  cat > "$FAKE_REPO/scripts/tests/lib/t_lib.bats" <<'EOF'
@test "lib test" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/core/t_core.bats" <<'EOF'
@test "core test" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/plugins/t_plugins.bats" <<'EOF'
@test "plugins test" { true; }
EOF
  cat > "$FAKE_REPO/scripts/tests/etc/t_etc.bats" <<'EOF'
@test "etc test" { true; }
EOF

  k3dm_list="$(
    cd "$FAKE_REPO" && \
    tests_root="scripts/tests" && \
    search_dirs=("${tests_root}/lib" "${tests_root}/core" "${tests_root}/plugins" "${tests_root}/etc") && \
    find "${search_dirs[@]}" -maxdepth 1 -type f -name '*.bats' | sort
  )"

  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1
  [ "$status" -eq 0 ]
  parallel_list="$(echo "$output" | grep -E '^PASS scripts/tests/(lib|core|plugins|etc)/' | awk '{print $2}' | sort)"

  [ -n "$parallel_list" ]
  [ "$parallel_list" = "$k3dm_list" ]
}

@test "M1: serial test-all prints no stage-complete when stage aborts with exit 2 before runner" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED FAKE_CHECK_AGENT_DOCS_RC=2 make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0
  [ "$status" -ne 0 ]
  local out="$output"
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
}

@test "M2: serial output streams live directly to log without per-stage buffering" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  STREAM_PY="$WORK/stream_stage.py"
  cat > "$STREAM_PY" <<'EOF'
import sys, time
print("STREAM_LINE_ALPHA", flush=True)
time.sleep(8)
print("STREAM_LINE_BETA", flush=True)
EOF
  OUT_LOG="$WORK/stream_stdout.log"
  make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$STREAM_PY" > "$OUT_LOG" 2>&1 &
  STREAM_MAKE_PID=$!

  found=0
  for _ in {1..300}; do
    if grep -q "STREAM_LINE_ALPHA" "$OUT_LOG" 2>/dev/null; then
      found=1
      break
    fi
    sleep 0.1
  done
  [ "$found" -eq 1 ]
  kill -0 "$STREAM_MAKE_PID" 2>/dev/null
  run grep -q "STREAM_LINE_BETA" "$OUT_LOG"
  [ "$status" -ne 0 ]

  wait "$STREAM_MAKE_PID"
  unset STREAM_MAKE_PID
  grep -q "STREAM_LINE_BETA" "$OUT_LOG"
  grep -Eq '^\[test-all\] stage-complete test-python seconds=[0-9]+$' "$OUT_LOG"
}

@test "M3: per-job TMPDIRs are cleaned up and do not leak under scratch TMPDIR" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  SCRATCH_TMP="$WORK/scratch_tmp"
  mkdir -p "$SCRATCH_TMP"

  run env TMPDIR="$SCRATCH_TMP" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]

  remaining="$(find "$SCRATCH_TMP" -maxdepth 1 -name "k3dm-job-*" | wc -l | tr -d ' ')"
  [ "$remaining" -eq 0 ]
}

@test "M4: conftest.py is excluded and only test_*.py classified for pytest" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  HERMES_DIR="$WORK/hermes"
  mkdir -p "$HERMES_DIR"
  cat > "$HERMES_DIR/conftest.py" <<'EOF'
raise RuntimeError("conftest.py must not be executed as a test script")
EOF
  cat > "$HERMES_DIR/test_sample.py" <<'EOF'
def test_sample(): pass
EOF

  : > "$CALLS"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$HERMES_DIR/conftest.py $HERMES_DIR/test_sample.py"
  [ "$status" -eq 0 ]
  run grep -E "conftest\.py" "$CALLS"
  [ "$status" -ne 0 ]
  grep "stub-pytest:" "$CALLS" | grep -q "test_sample\.py"
}

@test "M6: caller-exported PARALLEL=1 and MAKEFLAGS are neutralized by setup() keeping inner run serial" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  [ -z "${PARALLEL:-}" ]
  [ -z "${MAKEFLAGS:-}" ]

  : > "$CALLS"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all
  [ "$status" -eq 0 ]
  grep -q "fake-k3d-manager: test all" "$CALLS"
  run grep -q "ignored in PARALLEL mode" <<< "$output"
  [ "$status" -ne 0 ]
}

@test "Item 1: PARALLEL=1 without JOBS does not output command not found" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  unset JOBS
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  local out="$output"
  run grep -i "command not found" <<< "$out"
  [ "$status" -ne 0 ]
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-python seconds=[0-9]+$'
}

@test "Item 2: log name matches k3dm-test-all-<pid>-<epoch>" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/pass_py.py"
  [ "$status" -eq 0 ]
  log_line="$(echo "$output" | grep "^\[test-all\] metrics log:")"
  [ -n "$log_line" ]
  echo "$log_line" | grep -Eq "k3dm-test-all-[0-9]+-[0-9]+\.log"
}

@test "Item 8: pytest exit code 2 (collection error) suppresses stage-complete in serial and parallel" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  cat > "$FAKE_TESTS/test_rc2.py" <<'EOF'
import sys
sys.exit(2)
EOF

  # Serial
  run make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_rc2.py"
  [ "$status" -ne 0 ]
  local out="$output"
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]

  # Parallel
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_rc2.py"
  [ "$status" -ne 0 ]
  out="$output"
  echo "$out" | grep -E '^\[test-all\] stage-complete test seconds=[0-9]+$'
  echo "$out" | grep -E '^\[test-all\] stage-complete test-bin seconds=[0-9]+$'
  run grep -E '^\[test-all\] stage-complete test-python( seconds=[0-9]+)?$' <<< "$out"
  [ "$status" -ne 0 ]
}

@test "Item 11: drift pin asserting standalone targets and serial test-all parity on fake repo" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  mkdir -p "$FAKE_REPO/scripts/tests/hermes"
  cat > "$FAKE_REPO/scripts/tests/hermes/test_h.py" <<'EOF'
def test_h(): pass
EOF
  cat > "$FAKE_REPO/scripts/tests/bin/test_b.py" <<'EOF'
def test_b(): pass
EOF

  TRIPWIRE_LOG="$WORK/tripwire_drift.log"
  rm -f "$FAKE_REPO/scripts/tests/tripwire.sh"
  cat > "$FAKE_REPO/scripts/tests/tripwire.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TRIPWIRE_LOG"
exec "$REPO_ROOT/scripts/tests/tripwire.sh" "\$@"
EOF
  chmod +x "$FAKE_REPO/scripts/tests/tripwire.sh"

  # Standalone runs
  : > "$TRIPWIRE_LOG"
  make --no-print-directory -C "$FAKE_REPO" test
  make --no-print-directory -C "$FAKE_REPO" test-bin
  make --no-print-directory -C "$FAKE_REPO" test-python
  standalone_calls="$(cat "$TRIPWIRE_LOG")"

  # Serial test-all run
  : > "$TRIPWIRE_LOG"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0
  [ "$status" -eq 0 ]
  serial_calls="$(cat "$TRIPWIRE_LOG")"

  [ -n "$standalone_calls" ]
  [ -n "$serial_calls" ]
  [ "$serial_calls" = "$standalone_calls" ]

  # Test K3DM_RESOLVED_PYTEST is honoured in serial test-all
  cat > "$STUB_DIR/custom-pytest-override" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB_DIR/custom-pytest-override"
  : > "$TRIPWIRE_LOG"
  run env -u K3DM_MAKEFILE_TEST_ALL_NESTED K3DM_RESOLVED_PYTEST="custom-pytest-override" make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=0
  [ "$status" -eq 0 ]
  grep -q "^custom-pytest-override " "$TRIPWIRE_LOG"
}

@test "Y-N2/Y-M1: test-all resolves pytest via pytest-venv fallback when earlier lookups fail" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  rm -f "$STUB_DIR/pytest"

  VENV_PYTEST_DIR="$WORK/venv_pytest_bin"
  mkdir -p "$VENV_PYTEST_DIR"
  cat > "$VENV_PYTEST_DIR/python3" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "pytest" ]; then
  exit 1
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "$VENV_PYTEST_DIR/python3"

  # Setup working pytest-venv in SCRATCH_HOME
  VENV_DIR="$SCRATCH_HOME/.local/share/k3d-manager/pytest-venv/bin"
  mkdir -p "$VENV_DIR"
  cat > "$VENV_DIR/python" <<EOF
#!/usr/bin/env bash
echo "venv python ran with args: \$*" >> "$WORK/venv_pytest.log"
if [ "\$1" = "-m" ] && [ "\$2" = "pytest" ] && [ "\$3" = "--version" ]; then
  echo "pytest 9.1.1"
  exit 0
fi
exit 0
EOF
  chmod +x "$VENV_DIR/python"

  clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v 'pyenv' | paste -sd ':' -)"

  # Run test-all parallel with no PYTEST, no pytest on PATH, python3 failing pytest, no pyenv
  run env PATH="$VENV_PYTEST_DIR:$clean_path" HOME="$SCRATCH_HOME" \
    make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -eq 0 ]
  [ -s "$WORK/venv_pytest.log" ]
  grep -q "venv python ran with args:" "$WORK/venv_pytest.log"
  [[ "$output" != *"no pytest found"* ]]
}

@test "Y-N1: earlier lookup takes precedence over pytest-venv" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  PRECEDENCE_BIN="$WORK/precedence_bin"
  mkdir -p "$PRECEDENCE_BIN"
  cat > "$PRECEDENCE_BIN/pytest" <<EOF
#!/usr/bin/env bash
echo "path pytest ran with args: \$*" >> "$WORK/path_pytest.log"
exit 0
EOF
  chmod +x "$PRECEDENCE_BIN/pytest"

  # Setup working pytest-venv in SCRATCH_HOME
  VENV_DIR="$SCRATCH_HOME/.local/share/k3d-manager/pytest-venv/bin"
  mkdir -p "$VENV_DIR"
  cat > "$VENV_DIR/python" <<EOF
#!/usr/bin/env bash
echo "venv python ran with args: \$*" >> "$WORK/venv_precedence.log"
if [ "\$1" = "-m" ] && [ "\$2" = "pytest" ] && [ "\$3" = "--version" ]; then
  echo "pytest 9.1.1"
  exit 0
fi
exit 0
EOF
  chmod +x "$VENV_DIR/python"

  clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v 'pyenv' | paste -sd ':' -)"

  run env PATH="$PRECEDENCE_BIN:$clean_path" HOME="$SCRATCH_HOME" \
    make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -eq 0 ]
  [ -s "$WORK/path_pytest.log" ]
  [ ! -f "$WORK/venv_precedence.log" ]
}

@test "Y-M3: missing pytest error names make install-pytest-venv" {
  [ "$HOME" = "$SCRATCH_HOME" ] && [[ "$PATH" == "$STUB_DIR:"* ]]
  rm -f "$STUB_DIR/pytest"

  NO_PYTEST_DIR="$WORK/no_pytest_venv_bin"
  mkdir -p "$NO_PYTEST_DIR"
  cat > "$NO_PYTEST_DIR/python3" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "pytest" ]; then
  exit 1
fi
exec /usr/bin/python3 "$@"
EOF
  chmod +x "$NO_PYTEST_DIR/python3"

  clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v 'pyenv' | paste -sd ':' -)"

  run env PATH="$NO_PYTEST_DIR:$clean_path" HOME="$SCRATCH_HOME" \
    make --no-print-directory -C "$FAKE_REPO" test-all PARALLEL=1 \
    STAGE_TEST_FILES="$FAKE_TESTS/pass1.bats" \
    STAGE_TEST_BIN_FILES="$FAKE_TESTS/pass2.bats" \
    STAGE_TEST_PYTHON_FILES="$FAKE_TESTS/test_pytest_pass.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no pytest found"* ]]
  [[ "$output" == *"make install-pytest-venv"* ]]
}
