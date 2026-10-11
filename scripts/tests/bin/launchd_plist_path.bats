#!/usr/bin/env bats

LAUNCHD_DIR="${BATS_TEST_DIRNAME}/../../etc/launchd"

_plist_path_value() {
  /usr/bin/awk '/<key>PATH<\/key>/ {getline; print; exit}' "$1"
}

@test "launchd templates rendered with {{HOME}} lead PATH with ~/.local/bin" {
  local _tmpl _value
  for _tmpl in com.k3d-manager.webhook \
               com.k3d-manager.cloud-bridge \
               com.k3d-manager.prometheus-credential-rotator; do
    _value="$(_plist_path_value "${LAUNCHD_DIR}/${_tmpl}.plist.tmpl")"
    if [[ "${_value}" != *'<string>{{HOME}}/.local/bin:'* ]]; then
      echo "${_tmpl}.plist.tmpl PATH does not lead with {{HOME}}/.local/bin: ${_value}"
      return 1
    fi
  done
}

@test "launchd template PATH keeps the homebrew and system entries" {
  local _tmpl _value
  for _tmpl in com.k3d-manager.webhook \
               com.k3d-manager.cloud-bridge \
               com.k3d-manager.prometheus-credential-rotator; do
    _value="$(_plist_path_value "${LAUNCHD_DIR}/${_tmpl}.plist.tmpl")"
    for _entry in /opt/homebrew/bin /usr/local/bin /usr/bin; do
      if [[ "${_value}" != *"${_entry}"* ]]; then
        echo "${_tmpl}.plist.tmpl PATH lost ${_entry}: ${_value}"
        return 1
      fi
    done
  done
}

@test "install-cloud-bridge substitutes the HOME placeholder" {
  run grep -F -- 's|{{HOME}}|$(HOME)|g' "${BATS_TEST_DIRNAME}/../../../Makefile"
  [ "${status}" -eq 0 ]
}

@test "k3dm-hermes normalizes PATH because its installer cannot substitute HOME" {
  local _agent="${BATS_TEST_DIRNAME}/../../../bin/k3dm-hermes"

  run grep -F -- '_LOCAL_BIN = str(Path.home() / ".local" / "bin")' "${_agent}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'os.environ["PATH"] = os.pathsep.join([_LOCAL_BIN' "${_agent}"
  [ "${status}" -eq 0 ]
}

@test "launchd Python templates use the pinned Homebrew interpreter" {
  local _tmpl _value
  for _tmpl in com.k3d-manager.hermes com.k3d-manager.webhook com.k3d-manager.cloud-bridge; do
    _value="$(/usr/bin/awk '/<key>ProgramArguments<\/key>/ {getline; getline; print; exit}' "${LAUNCHD_DIR}/${_tmpl}.plist.tmpl")"
    [[ "${_value}" == *'/opt/homebrew/opt/python@3.14/bin/python3.14'* ]]
  done
}

@test "launchd templates do not use the unversioned Homebrew Python" {
  run rg -l --fixed-strings '/opt/homebrew/bin/python3' "${LAUNCHD_DIR}"
  [ "${status}" -ne 0 ]
}

@test "install-cloud-bridge preflights the pinned Python before writing a plist" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/Library/LaunchAgents"
  run env HOME="${_home}" K3DM_PYTHON3_PATH="${BATS_TEST_TMPDIR}/missing-python" \
    make --no-print-directory install-cloud-bridge
  # The recipe exits 1; GNU Make reports a failed recipe as status 2.
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"python@3.14 is not installed; run: brew install python@3.14"* ]]
  [ ! -e "${_home}/Library/LaunchAgents/com.k3d-manager.cloud-bridge.plist" ]
}
