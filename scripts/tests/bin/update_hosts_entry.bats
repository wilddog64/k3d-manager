#!/usr/bin/env bats

setup() {
  export HOSTS_TEST_ROOT="${BATS_TEST_TMPDIR}/hosts-fixture"
  export HOSTS_HELPER_SOURCE="${BATS_TEST_DIRNAME}/../../../bin/update-hosts-entry.sh"
  mkdir -p "${HOSTS_TEST_ROOT}"
  export HOSTS_FIXTURE="${HOSTS_TEST_ROOT}/hosts"
  export HOSTS_HELPER_COPY="${HOSTS_TEST_ROOT}/update-hosts-entry.sh"
  cat > "${HOSTS_FIXTURE}" <<'EOF'
127.0.0.1 localhost
192.0.2.10 argocd.shopping-cart.local alias.example
192.0.2.11 other.example argocd.shopping-cart.local
EOF
  python3 - "${HOSTS_HELPER_SOURCE}" "${HOSTS_HELPER_COPY}" "${HOSTS_FIXTURE}" <<'PY'
import pathlib, sys
source, target, fixture = map(pathlib.Path, sys.argv[1:])
assert source.name == 'update-hosts-entry.sh' and source.is_file()
assert fixture.parent == target.parent and fixture.is_file()
text = source.read_text()
assert text.count('/etc/hosts') >= 2
target.write_text(text.replace('/etc/hosts', str(fixture)))
target.chmod(0o755)
PY
  [ -f "${HOSTS_FIXTURE}" ]
  [ -x "${HOSTS_HELPER_COPY}" ]
}

@test "hosts helper replaces only the validated hostname in the asserted scratch fixture" {
  [ "${HOSTS_FIXTURE}" = "${HOSTS_TEST_ROOT}/hosts" ]
  run bash "${HOSTS_HELPER_COPY}" argocd.shopping-cart.local 198.51.100.42
  [ "${status}" -eq 0 ]
  run python3 - "${HOSTS_FIXTURE}" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
assert path == pathlib.Path(__import__('os').environ['HOSTS_FIXTURE'])
lines = path.read_text().splitlines()
assert '127.0.0.1\tlocalhost' in lines
assert '192.0.2.10\talias.example' in lines
assert '192.0.2.11\tother.example' in lines
assert [line for line in lines if 'argocd.shopping-cart.local' in line] == [
    '198.51.100.42\targocd.shopping-cart.local']
PY
  [ "${status}" -eq 0 ]
}

@test "hosts helper rejects malformed input without changing the asserted scratch fixture" {
  local before="${HOSTS_TEST_ROOT}/before"
  cp "${HOSTS_FIXTURE}" "${before}"
  [ "${HOSTS_FIXTURE}" = "${HOSTS_TEST_ROOT}/hosts" ]
  run bash "${HOSTS_HELPER_COPY}" "valid.example;touch ${HOSTS_TEST_ROOT}/pwned" 198.51.100.42
  [ "${status}" -ne 0 ]
  run bash "${HOSTS_HELPER_COPY}" valid.example 198.51.100.999
  [ "${status}" -ne 0 ]
  run bash "${HOSTS_HELPER_COPY}" valid.example 198.51.100.42 extra
  [ "${status}" -ne 0 ]
  cmp -s "${before}" "${HOSTS_FIXTURE}"
  [ ! -e "${HOSTS_TEST_ROOT}/pwned" ]
}
