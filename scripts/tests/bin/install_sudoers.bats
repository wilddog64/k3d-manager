#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/bin/install-sudoers.sh"
}

@test "install-sudoers.sh is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "install-sudoers.sh --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "install-sudoers.sh --dry-run validates sudoers syntax" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Syntax OK"* ]]
}

@test "sudoers keeps bootout scoped and delegates bootstrap to the validating helper" {
  run grep -F 'NOPASSWD: /bin/launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.*.plist' bin/install-sudoers.sh
  [ "$status" -ne 0 ]
  run grep -F 'NOPASSWD: /Library/PrivilegedHelperTools/k3dm-browser-listener-supervisor write *' bin/install-sudoers.sh
  [ "$status" -eq 0 ]
  run grep -F 'NOPASSWD: /bin/launchctl bootstrap system' bin/install-sudoers.sh
  [ "$status" -ne 0 ]
}

@test "sudoers content includes k3d-manager-update-hosts NOPASSWD rule" {
  run grep -F 'NOPASSWD: /Library/PrivilegedHelperTools/k3dm-update-hosts-entry *' bin/install-sudoers.sh
  [ "$status" -eq 0 ]
}

@test "install-sudoers.sh rejects unknown arguments" {
  run "$SCRIPT" --bogus-flag
  [ "$status" -ne 0 ]
}

@test "sudoers installer validates scratch policy and requests interactive installation" {
  local fixture="${BATS_TEST_TMPDIR}/install-case.sh" calls="${BATS_TEST_TMPDIR}/calls" daemon_dir="${BATS_TEST_TMPDIR}/LaunchDaemons"
  mkdir -p "${BATS_TEST_TMPDIR}/repo/bin" "${BATS_TEST_TMPDIR}/home"
  mkdir -p "${daemon_dir}"
  for label in com.k3d-manager.argocd-browser-https com.k3d-manager.keycloak-browser-http \
      com.k3d-manager.sandbox.frontend-browser-http com.k3d-manager.frontend-browser-http \
      com.k3d-manager.sandbox.loopback-alias com.k3d-manager.loopback-alias \
      com.k3d-manager.cloudflare-tunnel; do
    : > "${daemon_dir}/${label}.plist"
  done
  : > "${BATS_TEST_TMPDIR}/repo/bin/update-hosts-entry.sh"
  {
    sed -n '/^_launchctl_service_is_confirmed_absent()/,/^}/p' "$SCRIPT"
    sed -n '/^_retire_legacy_root_listeners()/,/^}/p' "$SCRIPT"
    sed -n '/^_remove_previous_sudoers_policy()/,/^}/p' "$SCRIPT"
    printf 'case install in\n'
    sed -n '/^  install)$/,/^    ;;$/p' "$SCRIPT"
    printf 'esac\n'
  } > "${fixture}"
  sed -i.bak "s#_retire_legacy_root_listeners \"\${_LEGACY_LAUNCH_DAEMON_DIR}\" || exit 1#_retire_legacy_root_listeners \"${daemon_dir}\" || exit 1#" "${fixture}"
  rm -f "${fixture}.bak"
  [ -s "${fixture}" ]
  run env HOME="${BATS_TEST_TMPDIR}/home" CA_TEST_ROOT="${BATS_TEST_TMPDIR}" \
    CA_TEST_CALLS="${calls}" bash -c '
      set -euo pipefail
      [[ "$HOME" == "$CA_TEST_ROOT/home" && -f "$CA_TEST_ROOT/repo/bin/update-hosts-entry.sh" ]]
      REPO_ROOT="$CA_TEST_ROOT/repo"
      _SUDOERS_FILE="$CA_TEST_ROOT/old-sudoers"
      : > "$_SUDOERS_FILE"
      _LEGACY_LAUNCH_DAEMON_DIR="$CA_TEST_ROOT/LaunchDaemons"
      _SUDO=sudo
      _SUDOERS_CONTENT="scratch sudoers policy"
      mktemp() { [[ "$1" == /tmp/k3d-manager-sudoers.XXXXXX ]]; command mktemp "$CA_TEST_ROOT/policy.XXXXXX"; }
      visudo() { [[ "$1" == -c && "$2" == -f && "$3" == "$CA_TEST_ROOT"/policy.* && "$(cat "$3")" == "$_SUDOERS_CONTENT" ]]; }
      _run_command() {
        [[ "$1 $2 $3" == "--interactive-sudo --quiet --soft" || "$1 $2" == "--interactive-sudo --" || "$1" == -- ]]
        printf "%s\n" "$*" >> "$CA_TEST_CALLS"
        if [[ "$2" == --quiet ]]; then shift 4
        elif [[ "$1" == --interactive-sudo ]]; then shift 2
        else shift 1
        fi
        if [[ "$1" == /bin/launchctl ]]; then
          local label="${3#system/}"
          if [[ "$2" == bootout ]]; then
            rm -f "$CA_TEST_ROOT/loaded/$label"
            return 0
          fi
          if [[ "$2" == print ]]; then
            if [[ -e "$CA_TEST_ROOT/loaded/$label" ]]; then
              echo "service $label"
              return 0
            fi
            echo "Could not find service \"$label\" in domain for system" >&2
            return 113
            return
          fi
          return 1
        fi
        if [[ "$1" == /bin/rm ]]; then
          rm -f "$3"
          return
        fi
        if [[ "$1" == /usr/bin/python3 ]]; then
          [[ "$2 $3 $4" == "-I $REPO_ROOT/bin/ensure_privileged_helper_dir.py /Library/PrivilegedHelperTools" || \
             "$2 $3 $4" == "-I $REPO_ROOT/bin/install_privileged_helpers.py $REPO_ROOT/bin" ]] || return 1
          return 0
        fi
        if [[ "$1" == /usr/bin/sudo ]]; then [[ "$2" == -v ]] || return 1; return 0; fi
        if [[ "$1" == /usr/bin/true ]]; then return 0; fi
        [[ "$1" == /usr/bin/install ]] || return 1
        case "$2" in
          -m) [[ "$3" == 0440 && "$4" == "$CA_TEST_ROOT"/policy.* && "$5" == "$_SUDOERS_FILE" ]] ;;
          *) return 1 ;;
        esac
      }
      mkdir -p "$CA_TEST_ROOT/loaded"
      for label in com.k3d-manager.argocd-browser-https com.k3d-manager.keycloak-browser-http \
          com.k3d-manager.sandbox.frontend-browser-http com.k3d-manager.frontend-browser-http \
          com.k3d-manager.sandbox.loopback-alias com.k3d-manager.loopback-alias \
          com.k3d-manager.cloudflare-tunnel; do : > "$CA_TEST_ROOT/loaded/$label"; done
      source "$1"
      [[ $(wc -l < "$CA_TEST_CALLS") -eq 34 ]]
      first_policy=$(grep -nF "/usr/bin/install -m 0440" "$CA_TEST_CALLS" | cut -d: -f1)
      first_helper=$(grep -nF "ensure_privileged_helper_dir.py" "$CA_TEST_CALLS" | cut -d: -f1)
      last_retirement=$(grep -nF "/bin/rm -f " "$CA_TEST_CALLS" | tail -n1 | cut -d: -f1)
      auth=$(grep -nF "/usr/bin/true" "$CA_TEST_CALLS" | cut -d: -f1)
      last_helper=$(grep -nF "install_privileged_helpers.py" "$CA_TEST_CALLS" | cut -d: -f1)
      old_policy_revoke=$(grep -nF "/bin/rm -f $CA_TEST_ROOT/old-sudoers" "$CA_TEST_CALLS" | cut -d: -f1)
      [[ "$auth" -lt "$old_policy_revoke" && "$old_policy_revoke" -lt "$last_retirement" && "$last_helper" -lt "$first_policy" ]]
      [[ ! -e "$CA_TEST_ROOT/old-sudoers" ]]
      [[ ! -e "$CA_TEST_ROOT/loaded/com.k3d-manager.argocd-browser-https" ]]
      [[ ! -e "$CA_TEST_ROOT/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" ]]
    ' bash "${fixture}"
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
    cat "${calls}" >&2 || true
  fi
  [ "${status}" -eq 0 ]
}

@test "revoked policy stays absent if authentication expires or staging fails" {
  local fixture="${BATS_TEST_TMPDIR}/upgrade-case.sh" mode
  mkdir -p "${BATS_TEST_TMPDIR}/upgrade-repo/bin" "${BATS_TEST_TMPDIR}/upgrade-home" "${BATS_TEST_TMPDIR}/upgrade-daemons"
  {
    sed -n '/^_launchctl_service_is_confirmed_absent()/,/^}/p' "$SCRIPT"
    sed -n '/^_retire_legacy_root_listeners()/,/^}/p' "$SCRIPT"
    sed -n '/^_remove_previous_sudoers_policy()/,/^}/p' "$SCRIPT"
    printf 'case install in\n'
    sed -n '/^  install)$/,/^    ;;$/p' "$SCRIPT"
    printf 'esac\n'
  } > "$fixture"
  [ -s "$fixture" ]
  for mode in success expired_during_retirement expired_before_stage stage_error expired_before_publish; do
    mkdir -p "${BATS_TEST_TMPDIR}/${mode}"
    run env HOME="${BATS_TEST_TMPDIR}/upgrade-home" UPGRADE_ROOT="${BATS_TEST_TMPDIR}" UPGRADE_MODE="$mode" bash -c '
      set -euo pipefail
      [[ "$HOME" == "$UPGRADE_ROOT/upgrade-home" && -d "$UPGRADE_ROOT/upgrade-repo/bin" ]]
      [[ "$UPGRADE_MODE" =~ ^(success|expired_during_retirement|expired_before_stage|stage_error|expired_before_publish)$ ]]
      REPO_ROOT="$UPGRADE_ROOT/upgrade-repo"
      _SUDOERS_FILE="$UPGRADE_ROOT/$UPGRADE_MODE/policy"
      _LEGACY_LAUNCH_DAEMON_DIR="$UPGRADE_ROOT/upgrade-daemons"
      _SUDOERS_CONTENT="validated scratch policy"
      _SUDO=sudo
      printf old > "$_SUDOERS_FILE"
      mktemp() { command mktemp "$UPGRADE_ROOT/$UPGRADE_MODE/input.XXXXXX"; }
      visudo() { [[ "$1" == -c && "$2" == -f && "$(cat "$3")" == "$_SUDOERS_CONTENT" ]]; }
      _run_command() {
        printf "%s\n" "$*" >> "$UPGRADE_ROOT/$UPGRADE_MODE/calls"
        if [[ "$1 $2 $3" == "-- /usr/bin/sudo -v" || "$1 $2 $3" == "--interactive-sudo -- /usr/bin/true" ]]; then return 0; fi
        if [[ "$1 $2 $3 $4" == "--interactive-sudo -- /bin/rm -f" ]]; then
          [[ "$5" == "$_SUDOERS_FILE" ]]
          command rm -f -- "$5"
          return
        fi
        if [[ "$1 $2 $3 $4 $5" == "--interactive-sudo --quiet --soft -- /bin/launchctl" ]]; then
          [[ ! -e "$_SUDOERS_FILE" && ! -L "$_SUDOERS_FILE" ]]
          if [[ "$UPGRADE_MODE" == expired_during_retirement ]]; then echo "sudo authentication expired" >&2; return 1; fi
          [[ "$6" == print && "$7" == system/com.k3d-manager.* ]]
          printf "Could not find service \"%s\" in domain for system\n" "${7#system/}" >&2
          return 113
        fi
        if [[ "$1 $2 $3" == "--interactive-sudo -- /usr/bin/python3" ]]; then
          [[ ! -e "$_SUDOERS_FILE" && ! -L "$_SUDOERS_FILE" ]]
          if [[ "$UPGRADE_MODE" == expired_before_stage ]]; then echo "sudo authentication expired" >&2; return 1; fi
          if [[ "$5" == "$REPO_ROOT/bin/install_privileged_helpers.py" ]]; then
            if [[ "$UPGRADE_MODE" == stage_error ]]; then echo "staging failed" >&2; return 1; fi
            : > "$UPGRADE_ROOT/$UPGRADE_MODE/staged"
          else
            [[ "$5" == "$REPO_ROOT/bin/ensure_privileged_helper_dir.py" ]]
          fi
          return 0
        fi
        if [[ "$1 $2 $3" == "--interactive-sudo -- /usr/bin/install" ]]; then
          [[ -f "$UPGRADE_ROOT/$UPGRADE_MODE/staged" && ! -e "$_SUDOERS_FILE" ]]
          if [[ "$UPGRADE_MODE" == expired_before_publish ]]; then echo "sudo authentication expired" >&2; return 1; fi
          [[ "$4 $5" == "-m 0440" && "$7" == "$_SUDOERS_FILE" ]]
          cp "$6" "$7"
          return
        fi
        echo "unexpected command: $*" >&2
        return 1
      }
      source "$1"
    ' bash "$fixture"
    if [[ "$mode" == success ]]; then
      [ "$status" -eq 0 ]
      [ "$(cat "${BATS_TEST_TMPDIR}/${mode}/policy")" = "validated scratch policy" ]
      [ -f "${BATS_TEST_TMPDIR}/${mode}/staged" ]
    else
      [ "$status" -ne 0 ]
      [ ! -e "${BATS_TEST_TMPDIR}/${mode}/policy" ]
      if [[ "$mode" == expired_before_publish ]]; then
        [ -f "${BATS_TEST_TMPDIR}/${mode}/staged" ]
      else
        [ ! -e "${BATS_TEST_TMPDIR}/${mode}/staged" ]
      fi
    fi
  done
}

@test "sudo authentication failure leaves prior policy and helpers untouched" {
  local fixture="${BATS_TEST_TMPDIR}/auth-failure-case.sh" calls="${BATS_TEST_TMPDIR}/auth-failure-calls"
  mkdir -p "${BATS_TEST_TMPDIR}/auth-repo/bin" "${BATS_TEST_TMPDIR}/auth-home"
  : > "${BATS_TEST_TMPDIR}/auth-repo/bin/update-hosts-entry.sh"
  {
    sed -n '/^_launchctl_service_is_confirmed_absent()/,/^}/p' "$SCRIPT"
    sed -n '/^_retire_legacy_root_listeners()/,/^}/p' "$SCRIPT"
    sed -n '/^_remove_previous_sudoers_policy()/,/^}/p' "$SCRIPT"
    printf 'case install in\n'
    sed -n '/^  install)$/,/^    ;;$/p' "$SCRIPT"
    printf 'esac\n'
  } > "$fixture"
  sed -i.bak "s#_retire_legacy_root_listeners \"\${_LEGACY_LAUNCH_DAEMON_DIR}\" || exit 1#_retire_legacy_root_listeners \"${BATS_TEST_TMPDIR}/auth-launch-daemons\" || exit 1#" "$fixture"
  rm -f "$fixture.bak"
  run env HOME="${BATS_TEST_TMPDIR}/auth-home" AUTH_ROOT="${BATS_TEST_TMPDIR}" AUTH_CALLS="$calls" bash -c '
    set -euo pipefail
    [[ "$HOME" == "$AUTH_ROOT/auth-home" ]]
    REPO_ROOT="$AUTH_ROOT/auth-repo"
    _SUDOERS_FILE="$AUTH_ROOT/old-policy"
    _LEGACY_LAUNCH_DAEMON_DIR="$AUTH_ROOT/auth-launch-daemons"
    _SUDOERS_CONTENT="scratch policy"
    : > "$_SUDOERS_FILE"
    mktemp() { command mktemp "$AUTH_ROOT/sudoers.XXXXXX"; }
    visudo() { [[ "$1" == -c && "$2" == -f && -f "$3" ]]; }
    _run_command() {
      printf "%s\n" "$*" >> "$AUTH_CALLS"
      if [[ "$1 $2 $3" == "-- /usr/bin/sudo -v" ]]; then
        echo "sudo authentication denied" >&2
        return 1
      fi
      : > "$AUTH_ROOT/unexpected-mutation"
      return 0
    }
    source "$1"
  ' bash "$fixture"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sudo authentication denied"* ]]
  [[ "$(cat "$calls")" == "-- /usr/bin/sudo -v" ]]
  [ -f "${BATS_TEST_TMPDIR}/old-policy" ]
  [ ! -e "${BATS_TEST_TMPDIR}/unexpected-mutation" ]
}

@test "sudoers revocation removes dangling symlinks and blocks publication after removal failure" {
  local helper_fixture="${BATS_TEST_TMPDIR}/remove-policy.sh"
  sed -n '/^_remove_previous_sudoers_policy()/,/^}/p' "$SCRIPT" > "${helper_fixture}"
  [ -s "${helper_fixture}" ]
  run env POLICY_SCRATCH="${BATS_TEST_TMPDIR}" bash -c '
    set -euo pipefail
    source "$1"
    _SUDOERS_FILE="$POLICY_SCRATCH/policy"
    : > "$POLICY_SCRATCH/target"
    ln -s "$POLICY_SCRATCH/missing-target" "$_SUDOERS_FILE"
    [[ -L "$_SUDOERS_FILE" && ! -e "$_SUDOERS_FILE" ]]
    _run_command() {
      [[ "$1 $2 $3" == "--interactive-sudo -- /bin/rm" && "$4" == -f && "$5" == "$POLICY_SCRATCH/policy" ]]
      command rm -f -- "$5"
    }
    _remove_previous_sudoers_policy
    [[ ! -e "$_SUDOERS_FILE" && ! -L "$_SUDOERS_FILE" ]]
    : > "$POLICY_SCRATCH/published"
    [[ -f "$POLICY_SCRATCH/published" ]]
  ' bash "${helper_fixture}"
  [ "$status" -eq 0 ]

  run env POLICY_SCRATCH="${BATS_TEST_TMPDIR}" bash -c '
    set -euo pipefail
    source "$1"
    _SUDOERS_FILE="$POLICY_SCRATCH/policy-failed"
    ln -s "$POLICY_SCRATCH/missing-target" "$_SUDOERS_FILE"
    _run_command() { return 1; }
    if _remove_previous_sudoers_policy; then
      : > "$POLICY_SCRATCH/failed-publish"
      exit 1
    fi
    [[ -L "$_SUDOERS_FILE" && ! -e "$POLICY_SCRATCH/failed-publish" ]]
  ' bash "${helper_fixture}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not remove previous sudoers policy"* ]]
}

@test "sudoers installer refuses helper migration while a legacy root job remains loaded" {
  local function_fixture="${BATS_TEST_TMPDIR}/retire-function.sh" daemon_dir="${BATS_TEST_TMPDIR}/LaunchDaemons"
  mkdir -p "${daemon_dir}" "${BATS_TEST_TMPDIR}/loaded"
  : > "${daemon_dir}/com.k3d-manager.argocd-browser-https.plist"
  : > "${BATS_TEST_TMPDIR}/loaded/com.k3d-manager.argocd-browser-https"
  {
    sed -n '/^_launchctl_service_is_confirmed_absent()/,/^}/p' "$SCRIPT"
    sed -n '/^_retire_legacy_root_listeners()/,/^}/p' "$SCRIPT"
  } > "${function_fixture}"
  [ -s "${function_fixture}" ]
  run env RETIRE_SCRATCH="${BATS_TEST_TMPDIR}" bash -c '
    set -euo pipefail
    source "$1"
    _run_command() {
      shift 4
      case "$2" in
        bootout) return 0 ;;
        print)
          if [[ -e "$RETIRE_SCRATCH/loaded/${3#system/}" ]]; then
            echo "service ${3#system/}"
            return 0
          fi
          echo "Could not find service \"${3#system/}\" in domain for system" >&2
          return 113 ;;
        *) return 1 ;;
      esac
    }
    if _retire_legacy_root_listeners "$RETIRE_SCRATCH/LaunchDaemons"; then
      echo "migration unexpectedly continued" >&2
      exit 1
    fi
    [[ -e "$RETIRE_SCRATCH/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" ]]
    [[ -e "$RETIRE_SCRATCH/loaded/com.k3d-manager.argocd-browser-https" ]]
  ' bash "${function_fixture}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"legacy root listener remains loaded"* ]]
}

@test "legacy listener cleanup accepts confirmed absence and fails closed on launchctl errors" {
  local function_fixture="${BATS_TEST_TMPDIR}/retire-function.sh"
  {
    sed -n '/^_launchctl_service_is_confirmed_absent()/,/^}/p' "$SCRIPT"
    sed -n '/^_retire_legacy_root_listeners()/,/^}/p' "$SCRIPT"
  } > "${function_fixture}"
  [ -s "${function_fixture}" ]
  run env RETIRE_SCRATCH="${BATS_TEST_TMPDIR}" bash -c '
    set -euo pipefail
    source "$1"
    _run_command() {
      shift 4
      case "$2" in
        bootout) echo "unexpected bootout for confirmed-absent service" >&2; return 1 ;;
        print) echo "Could not find service \"${3#system/}\" in domain for system" >&2; return 113 ;;
        *) return 1 ;;
      esac
    }
    _retire_legacy_root_listeners "$RETIRE_SCRATCH/LaunchDaemons"
  ' bash "${function_fixture}"
  [ "$status" -eq 0 ]

  for failure in bootout-denial bootout-error; do
    run env RETIRE_SCRATCH="${BATS_TEST_TMPDIR}" RETIRE_FAILURE="$failure" bash -c '
      set -euo pipefail
      source "$1"
      _run_command() {
        shift 4
        case "$2" in
          bootout)
            if [[ "$RETIRE_FAILURE" == bootout-denial ]]; then echo "Operation not permitted" >&2; return 1; fi
            echo "launchctl internal error" >&2; return 5 ;;
          print) echo "service ${3#system/}"; return 0 ;;
          *) return 1 ;;
        esac
      }
      if _retire_legacy_root_listeners "$RETIRE_SCRATCH/LaunchDaemons"; then
        echo "cleanup unexpectedly accepted $RETIRE_FAILURE" >&2
        exit 1
      fi
    ' bash "${function_fixture}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not retire legacy root listener"* ]]
  done

  for failure in print-denial print-error print-mismatch print-status-mismatch; do
    run env RETIRE_SCRATCH="${BATS_TEST_TMPDIR}" RETIRE_FAILURE="$failure" bash -c '
      set -euo pipefail
      source "$1"
      rm -f "$RETIRE_SCRATCH/print-count-done"
      _run_command() {
        shift 4
        case "$2" in
          bootout) return 0 ;;
          print)
            if [[ ! -e "$RETIRE_SCRATCH/print-count-done" ]]; then
              : > "$RETIRE_SCRATCH/print-count-done"
              echo "service ${3#system/}"
              return 0
            fi
            case "$RETIRE_FAILURE" in
              print-denial) echo "Operation not permitted" >&2; return 1 ;;
              print-error) echo "launchctl internal error" >&2; return 5 ;;
              print-mismatch) echo "Could not find service \"wrong.label\" in domain for system" >&2; return 113 ;;
              print-status-mismatch) echo "Could not find service \"${3#system/}\" in domain for system" >&2; return 5 ;;
            esac ;;
        esac
        return 1
      }
      if _retire_legacy_root_listeners "$RETIRE_SCRATCH/LaunchDaemons"; then
        echo "cleanup unexpectedly accepted $RETIRE_FAILURE" >&2
        exit 1
      fi
    ' bash "${function_fixture}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not determine legacy root listener state"* ]]
  done
}

@test "legacy plist cleanup removes dangling symlinks and verifies removal" {
  local function_fixture="${BATS_TEST_TMPDIR}/retire-function.sh"
  {
    sed -n '/^_launchctl_service_is_confirmed_absent()/,/^}/p' "$SCRIPT"
    sed -n '/^_retire_legacy_root_listeners()/,/^}/p' "$SCRIPT"
  } > "${function_fixture}"
  [ -s "${function_fixture}" ]
  local plist="${BATS_TEST_TMPDIR}/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist"
  mkdir -p "${BATS_TEST_TMPDIR}/LaunchDaemons"
  ln -s "${BATS_TEST_TMPDIR}/does-not-exist" "$plist"
  [[ -L "$plist" && ! -e "$plist" ]]
  run env RETIRE_SCRATCH="${BATS_TEST_TMPDIR}" bash -c '
    set -euo pipefail
    source "$1"
    _run_command() {
      shift 4
      case "$1" in
        /bin/launchctl)
          [[ "$2" == print ]]
          echo "Could not find service \"${3#system/}\" in domain for system" >&2
          return 113 ;;
        /bin/rm)
          [[ "$2" == -f && "$3" == "$RETIRE_SCRATCH/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" ]]
          command rm -f -- "$3" ;;
        *) return 1 ;;
      esac
    }
    _retire_legacy_root_listeners "$RETIRE_SCRATCH/LaunchDaemons"
    [[ ! -e "$RETIRE_SCRATCH/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" && ! -L "$RETIRE_SCRATCH/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" ]]
  ' bash "${function_fixture}"
  [ "$status" -eq 0 ]

  ln -s "${BATS_TEST_TMPDIR}/does-not-exist" "$plist"
  run env RETIRE_SCRATCH="${BATS_TEST_TMPDIR}" bash -c '
    set -euo pipefail
    source "$1"
    _run_command() {
      shift 4
      case "$1" in
        /bin/launchctl)
          [[ "$2" == print ]]
          echo "Could not find service \"${3#system/}\" in domain for system" >&2
          return 113 ;;
        /bin/rm)
          [[ "$2" == -f && "$3" == "$RETIRE_SCRATCH/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" ]]
          return 0 ;;
        *) return 1 ;;
      esac
    }
    if _retire_legacy_root_listeners "$RETIRE_SCRATCH/LaunchDaemons"; then
      echo "cleanup accepted a plist that remained" >&2
      exit 1
    fi
    [[ -L "$RETIRE_SCRATCH/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" ]]
  ' bash "${function_fixture}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy root listener plist remains"* ]]
}

@test "privileged helper staging replaces symlink entries without following them" {
  run env HELPER_STAGE_SCRATCH="${BATS_TEST_TMPDIR}" python3 - "$SCRIPT" <<'PY'
import importlib.util, os, pathlib, stat, sys
script = pathlib.Path(sys.argv[1])
scratch = pathlib.Path(os.environ['HELPER_STAGE_SCRATCH']).resolve()
assert script.name == 'install-sudoers.sh' and scratch.is_dir()
spec = importlib.util.spec_from_file_location('install_privileged_helpers', script.parent / 'install_privileged_helpers.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = scratch / 'helper-source'
parent = scratch / 'trusted-parent'
destination = parent / 'PHT'
outside = scratch / 'outside-target'
source.mkdir(mode=0o700)
parent.mkdir(mode=0o755)
destination.mkdir(mode=0o755)
outside.write_text('sentinel')
for source_name, destination_name in module.HELPERS:
    (source / source_name).write_text(f'fixture:{source_name}\n')
target_name = module.HELPERS[0][1]
(destination / target_name).symlink_to(outside)
module.install_helpers(str(source), str(destination), os.getuid(), os.getgid())
assert outside.read_text() == 'sentinel', 'staging followed a destination symlink'
installed = destination / target_name
assert installed.is_file() and not installed.is_symlink()
assert installed.read_text() == 'fixture:update-hosts-entry.sh\n'
assert {name for _, name in module.HELPERS} == {path.name for path in destination.iterdir() if not path.name.startswith('.k3dm-stage-')}
info = installed.stat(follow_symlinks=False)
assert info.st_uid == os.getuid() and info.st_gid == os.getgid()
assert stat.S_IMODE(info.st_mode) == 0o755
print('scratch PHT symlink destination replaced atomically; sentinel preserved; metadata validated')
PY
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "binary install sudoers rule cannot replace a privileged helper through path traversal" {
  run python3 - "$SCRIPT" <<'PY'
import ctypes, pathlib, sys
script = pathlib.Path(sys.argv[1])
assert script.name == 'install-sudoers.sh' and script.is_file()
prefix = '%admin  ALL=(root) NOPASSWD: /usr/bin/install '
lines = [line for line in script.read_text().splitlines() if line.startswith(prefix)]
baseline = b'-m [0-9][0-9][0-9] * /usr/local/bin/*'
fnmatch = ctypes.CDLL(None).fnmatch
fnmatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
fnmatch.restype = ctypes.c_int
legitimate = b'-m 755 /tmp/source /usr/local/bin/kubectl'
traversal = b'-m 755 /tmp/source /usr/local/bin/../../../Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor'
assert fnmatch(baseline, legitimate, 0) == 0, 'positive control did not match'
assert fnmatch(baseline, traversal, 0) == 0, 'traversal control did not match'
matched = any(fnmatch(line[len(prefix):].encode(), traversal, 0) == 0 for line in lines)
print('legitimate install matches: True')
print('traversal matches existing rule:', matched)
assert not matched, 'existing rule permits a traversal destination'
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}

@test "sudoers self-update does not permit a user-controlled policy without authentication" {
  run python3 - "$SCRIPT" <<'PY'
import ctypes, pathlib, sys
script = pathlib.Path(sys.argv[1])
assert script.name == 'install-sudoers.sh' and script.is_file()
prefix = '%admin  ALL=(root) NOPASSWD: /usr/bin/install '
lines = [line for line in script.read_text().splitlines() if line.startswith(prefix)]
fnmatch = ctypes.CDLL(None).fnmatch
fnmatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
fnmatch.restype = ctypes.c_int
intended = b'-m 0440 /tmp/k3d-manager-sudoers.fixture /etc/sudoers.d/k3d-manager'
traversal = b'-m 440 /tmp/k3d-manager-sudoers.fixture /usr/local/bin/../../../etc/sudoers.d/k3d-manager'
baseline = b'-m 0440 /tmp/k3d-manager-sudoers.* /etc/sudoers.d/k3d-manager'
assert fnmatch(baseline, intended, 0) == 0, 'positive control did not match'
matched = any(fnmatch(line[len(prefix):].encode(), args, 0) == 0
              for line in lines for args in (intended, traversal))
print('user-controlled policy source matches:', matched)
assert not matched, 'passwordless rule permits a user-controlled sudoers source'
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}

@test "passwordless plist removal cannot remove an unrelated file" {
  run python3 - "$SCRIPT" <<'PY'
import ctypes, pathlib, sys
script = pathlib.Path(sys.argv[1])
assert script.name == 'install-sudoers.sh' and script.is_file()
prefix = '%admin  ALL=(root) NOPASSWD: /bin/rm '
rules = [line[len(prefix):].encode() for line in script.read_text().splitlines() if line.startswith(prefix)]
fnmatch = ctypes.CDLL(None).fnmatch
fnmatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
fnmatch.restype = ctypes.c_int
args = b'-f /Library/LaunchDaemons/com.k3d-manager.fixture.plist /etc/sudoers.d/k3d-manager'
baseline = b'-f /Library/LaunchDaemons/com.k3d-manager.*.plist *'
assert fnmatch(baseline, args, 0) == 0, 'positive control did not match'
matched = any(fnmatch(rule, args, 0) == 0 for rule in rules)
print('unrelated removal matches:', matched)
assert not matched, 'passwordless plist removal accepts an unrelated operand'
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}

@test "passwordless plist removal permits the known listener and legacy paths" {
  run python3 - "$SCRIPT" <<'PY'
import pathlib, sys
script = pathlib.Path(sys.argv[1])
assert script.name == 'install-sudoers.sh' and script.is_file()
rules = set(script.read_text().splitlines())
prefix = '%admin  ALL=(root) NOPASSWD: /bin/rm -f /Library/LaunchDaemons/'
for label in ('argocd-browser-https', 'keycloak-browser-http',
              'sandbox.frontend-browser-http', 'frontend-browser-http', 'cloudflare-tunnel'):
    assert prefix + 'com.k3d-manager.' + label + '.plist' in rules, label
PY
  [ "${status}" -eq 0 ]
}

@test "passwordless binary installation cannot replace the privileged hosts helper" {
  run python3 - "$SCRIPT" <<'PY'
import ctypes, pathlib, sys
script = pathlib.Path(sys.argv[1])
assert script.name == 'install-sudoers.sh' and script.is_file()
prefix = '%admin  ALL=(root) NOPASSWD: /usr/bin/install '
rules = [line[len(prefix):].encode() for line in script.read_text().splitlines() if line.startswith(prefix)]
fnmatch = ctypes.CDLL(None).fnmatch
fnmatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
fnmatch.restype = ctypes.c_int
args = b'-m 755 /tmp/caller-controlled /Library/PrivilegedHelperTools/k3dm-update-hosts-entry'
baseline = b'-m 755 * /Library/PrivilegedHelperTools/*'
assert fnmatch(baseline, args, 0) == 0, 'positive control did not match'
matched = any(fnmatch(rule, args, 0) == 0 for rule in rules)
print('caller-controlled hosts helper matches:', matched)
assert not matched, 'passwordless installation can replace the root-executed hosts helper'
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}

@test "caller-controlled launch daemon install and bootstrap require authentication" {
  run env CA_RULE_SCRATCH="${BATS_TEST_TMPDIR}" python3 - "$SCRIPT" <<'PY'
import ctypes, os, pathlib, plistlib, sys
script = pathlib.Path(sys.argv[1])
scratch = pathlib.Path(os.environ['CA_RULE_SCRATCH'])
assert script.name == 'install-sudoers.sh' and script.is_file() and scratch.is_dir()
fixture = scratch / 'daemon.plist'
with fixture.open('wb') as stream:
    plistlib.dump({'Label': 'com.k3d-manager.fixture', 'UserName': 'root',
                   'ProgramArguments': ['/bin/sh', '-c', 'exit 0'], 'RunAtLoad': True}, stream)
with fixture.open('rb') as stream:
    assert plistlib.load(stream)['ProgramArguments'] == ['/bin/sh', '-c', 'exit 0']
lines = script.read_text().splitlines()
install_prefix = '%admin  ALL=(root) NOPASSWD: /usr/bin/install '
launch_prefix = '%admin  ALL=(root) NOPASSWD: /bin/launchctl '
install_rules = [line[len(install_prefix):] for line in lines if line.startswith(install_prefix) and '/Library/LaunchDaemons/' in line]
launch_rules = [line[len(launch_prefix):] for line in lines if line.startswith(launch_prefix) and 'bootstrap system' in line]
fnmatch = ctypes.CDLL(None).fnmatch
fnmatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
fnmatch.restype = ctypes.c_int
dest = '/Library/LaunchDaemons/com.k3d-manager.fixture.plist'
install_allowed = any(fnmatch(rule.encode(), f'-m 644 {fixture} {dest}'.encode(), 0) == 0 for rule in install_rules)
launch_allowed = any(fnmatch(rule.encode(), f'bootstrap system {dest}'.encode(), 0) == 0 for rule in launch_rules)
print('scratch plist install matches passwordless rule:', install_allowed)
print('system bootstrap matches passwordless rule:', launch_allowed)
assert not install_allowed and not launch_allowed, 'caller-controlled daemon installation/bootstrap is passwordless'
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}

@test "sudoers removes passwordless Linux wildcard root command families" {
  run python3 - "$SCRIPT" <<'PY'
import ctypes, pathlib, sys
script = pathlib.Path(sys.argv[1])
assert script.name == 'install-sudoers.sh' and script.is_file()
lines = script.read_text().splitlines()
patterns = {
    '/usr/local/bin/k3s': (b'*', b'server --config /tmp/user.yaml'),
    '/usr/local/bin/k3s-uninstall.sh': (b'', b''),
    '/usr/local/bin/k3s-killall.sh': (b'', b''),
    '/usr/bin/systemctl': (b'*', b'edit ssh.service'),
    '/usr/bin/apt-get': (b'*', b'install -y attacker-package'),
    '/usr/bin/dnf': (b'*', b'-y install attacker-package'),
    '/usr/bin/yum': (b'*', b'install attacker-package'),
    '/usr/bin/microdnf': (b'*', b'install attacker-package'),
}
fnmatch = ctypes.CDLL(None).fnmatch
fnmatch.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
fnmatch.restype = ctypes.c_int
for path, (rule_args, attack_args) in patterns.items():
    baseline = f'{path} {rule_args.decode()}'.rstrip().encode()
    candidate = path.encode() + (b' ' + attack_args if attack_args else b'')
    assert fnmatch(baseline, candidate, 0) == 0, f'negative control did not match {path}'
    allowed = any(line.startswith('%admin  ALL=(root) NOPASSWD: ' + path) for line in lines)
    print(path, 'legacy wildcard can match:', True, 'policy still allows:', allowed)
    assert not allowed, f'passwordless root command remains for {path}'
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}
