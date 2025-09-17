#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "test_jenkins trap removes auth file" {
  local script="$BATS_TEST_TMPDIR/run-test.sh"
  local cleanup_log="$BATS_TEST_TMPDIR/cleanup.log"
  local auth_path_log="$BATS_TEST_TMPDIR/auth-path.log"

  cat <<'SCRIPT' > "$script"
#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ROOT:?}"
export PLUGINS_DIR="${PROJECT_ROOT}/scripts/plugins"
source "${PROJECT_ROOT}/scripts/lib/test.sh"

cleanup_log="${CLEANUP_LOG:-}"
auth_path_log="${AUTH_PATH_LOG:-}"

deploy_jenkins() { :; }
_wait_for_jenkins_ready() { :; }
_wait_for_port_forward() { :; }
sleep() { :; }

_cleanup_jenkins_test() {
  if [[ -n "${cleanup_log}" ]]; then
    echo "cleanup" >> "${cleanup_log}"
  fi
}

_kubectl() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-exit|--quiet|--prefer-sudo|--require-sudo)
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  local cmd="$*"
  local expected_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
  local expected_pod="${expected_release}-0"
  if [[ "$cmd" == "get ns jenkins" ]]; then
    return 0
  elif [[ "$cmd" == "get ns vault" ]]; then
    return 0
  elif [[ "$cmd" == get\ pod\ jenkins-0\ -n\ *\ -o\ jsonpath={..persistentVolumeClaim.claimName} ]]; then
    printf '%s' 'jenkins-home'
    return 0
  elif [[ "$cmd" == "get gateway jenkins-gw -n istio-system" ]]; then
    return 0
  elif [[ "$cmd" == get\ virtualservice\ jenkins\ -n\ * ]]; then
    return 0
  elif [[ "$cmd" == get\ destinationrule\ jenkins\ -n\ * ]]; then
    return 0
  elif [[ "$cmd" == "-n jenkins port-forward svc/jenkins 8080:8080" ]]; then
    sleep 0.01
    return 0
  elif [[ "$cmd" == "-n vault exec ${expected_pod} -- vault policy list" ]]; then
    printf '%s\n' 'jenkins-admin' 'jenkins-jcasc-read' 'jenkins-jcasc-write'
    return 0
  elif [[ "$cmd" == "-n jenkins get secret jenkins-admin -o jsonpath={.data.username}" ]]; then
    printf '%s' 'YWRtaW4='
    return 0
  elif [[ "$cmd" == "-n jenkins get secret jenkins-admin -o jsonpath={.data.password}" ]]; then
    printf '%s' 'c2VjcmV0'
    return 0
  fi

  return 0
}

_curl() {
  local output_file=""
  local url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o)
        output_file="$2"
        shift 2
        ;;
      -w|-u)
        shift 2
        ;;
      --resolve|-s|--insecure|-v)
        shift
        ;;
      *)
        url="$1"
        shift
        ;;
    esac
  done

  if [[ "$url" == "http://127.0.0.1:8080/whoAmI/api/json" ]]; then
    if [[ -n "$auth_path_log" && -n "$output_file" ]]; then
      printf '%s' "$output_file" > "$auth_path_log"
    fi
    if [[ -n "$output_file" ]]; then
      printf '%s' '{"authenticated":true}' > "$output_file"
    fi
    printf '%s' '200'
    return 0
  fi

  if [[ "$url" == "https://jenkins.dev.local.me:8443/" ]]; then
    printf '%s' 'subject: CN=jenkins.dev.local.me'
    return 0
  fi

  if [[ "$url" == "https://jenkins.dev.local.me:8443/login" ]]; then
    printf '%s' 'Jenkins'
    return 0
  fi

  return 0
}

test_jenkins
SCRIPT

  chmod +x "$script"

  run env PROJECT_ROOT="$PROJECT_ROOT" CLEANUP_LOG="$cleanup_log" AUTH_PATH_LOG="$auth_path_log" "$script"
  [ "$status" -eq 0 ]

  [ -f "$cleanup_log" ]
  grep -q 'cleanup' "$cleanup_log"

  [ -f "$auth_path_log" ]
  local auth_file
  auth_file="$(cat "$auth_path_log")"
  [ -n "$auth_file" ]
  [ ! -e "$auth_file" ]
}
