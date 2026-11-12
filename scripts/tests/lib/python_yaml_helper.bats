#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../python_yaml.bash"
  export K3DM_TEST_PYTHON3_CANDIDATES="${BATS_TEST_TMPDIR}/candidates"
  export PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
}

make_python() {
  local path="$1" supports_yaml="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"import yaml"* ]]; then
  [[ "$supports_yaml" == yes ]]
  exit \$?
fi
echo fake-python-ran
EOF
  chmod +x "$path"
}

@test "YAML interpreter finds PyYAML after the first PATH python lacks it" {
  local first="${BATS_TEST_TMPDIR}/bin/python3" capable="${BATS_TEST_TMPDIR}/capable-python"
  make_python "$first" no
  make_python "$capable" yes
  [ "$(command -v python3)" = "$first" ]
  [ -f "$first" ]
  export K3DM_TEST_PYTHON3_CANDIDATES="$first:$capable"
  run k3dm_python_yaml
  [ "$status" -eq 0 ]
  [ "$output" = "$capable" ]
}

@test "YAML interpreter fails clearly when no candidate has PyYAML" {
  local incapable="${BATS_TEST_TMPDIR}/incapable-python"
  make_python "$incapable" no
  [ -f "$incapable" ]
  export K3DM_TEST_PYTHON3_CANDIDATES="$incapable"
  run k3dm_python_yaml
  [ "$status" -ne 0 ]
  [[ "$output" == *"set K3DM_TEST_PYTHON3"* ]]

  local capable="${BATS_TEST_TMPDIR}/capable-control"
  make_python "$capable" yes
  export K3DM_TEST_PYTHON3_CANDIDATES="$capable"
  run k3dm_python_yaml
  [ "$status" -eq 0 ]
  [ "$output" = "$capable" ]
}

@test "K3DM_TEST_PYTHON3 takes precedence over PATH python3" {
  local first="${BATS_TEST_TMPDIR}/bin/python3" override="${BATS_TEST_TMPDIR}/override-python"
  make_python "$first" yes
  make_python "$override" yes
  [ "$(command -v python3)" = "$first" ]
  [ -f "$override" ]
  unset K3DM_TEST_PYTHON3_CANDIDATES
  export K3DM_TEST_PYTHON3="$override"
  run k3dm_python_yaml
  [ "$status" -eq 0 ]
  [ "$output" = "$override" ]
}
