#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "test_jenkins trap removes auth file" {
  local script="$BATS_TEST_TMPDIR/run-test.sh"
  local cleanup_log="$BATS_TEST_TMPDIR/cleanup.log"
  local auth_path_log="$BATS_TEST_TMPDIR/auth-path.log"
  local deploy_log="$BATS_TEST_TMPDIR/deploy.log"

  cat <<'SCRIPT' > "$script"
#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ROOT:?}"
export PLUGINS_DIR="${PROJECT_ROOT}/scripts/plugins"
source "${PROJECT_ROOT}/scripts/lib/test.sh"

cleanup_log="${CLEANUP_LOG:-}"
auth_path_log="${AUTH_PATH_LOG:-}"

deploy_jenkins() {
  if [[ -n "${DEPLOY_LOG:-}" ]]; then
    printf '%s\n' "${3:-}" >> "${DEPLOY_LOG}"
  fi
  return 0
}
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
  local expected_vault_ns
  if [[ -n "${VAULT_NS:-}" ]]; then
    expected_vault_ns="$VAULT_NS"
  elif [[ -n "${VAULT_NS_DEFAULT_ENV:-}" ]]; then
    expected_vault_ns="$VAULT_NS_DEFAULT_ENV"
  else
    expected_vault_ns="${VAULT_NS_DEFAULT:-vault-test}"
  fi

  local expected_release
  if [[ -n "${VAULT_RELEASE:-}" ]]; then
    expected_release="$VAULT_RELEASE"
  elif [[ -n "${VAULT_RELEASE_DEFAULT_ENV:-}" ]]; then
    expected_release="$VAULT_RELEASE_DEFAULT_ENV"
  elif [[ -n "${VAULT_NS_DEFAULT_ENV:-}" && "$expected_vault_ns" == "$VAULT_NS_DEFAULT_ENV" ]]; then
    expected_release="$expected_vault_ns"
  else
    expected_release="${VAULT_RELEASE_DEFAULT:-vault}"
  fi

  local expected_pod="${expected_release}-0"
  if [[ "$cmd" == "get ns jenkins" ]]; then
    return 0
  elif [[ "$cmd" == "get ns ${expected_vault_ns}" ]]; then
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
  elif [[ "$cmd" == "-n ${expected_vault_ns} exec ${expected_pod} -- vault policy list" ]]; then
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

  run env PROJECT_ROOT="$PROJECT_ROOT" CLEANUP_LOG="$cleanup_log" AUTH_PATH_LOG="$auth_path_log" DEPLOY_LOG="$deploy_log" "$script"
  [ "$status" -eq 0 ]

  [ -f "$cleanup_log" ]
  grep -q 'cleanup' "$cleanup_log"

  [ -f "$auth_path_log" ]
  local auth_file
  auth_file="$(cat "$auth_path_log")"
  [ -n "$auth_file" ]
  [ ! -e "$auth_file" ]

  [ -f "$deploy_log" ]
  run tail -n 1 "$deploy_log"
  [ "$status" -eq 0 ]
  [[ "$output" == "vault" ]]

  : >"$deploy_log"
  run env PROJECT_ROOT="$PROJECT_ROOT" DEPLOY_LOG="$deploy_log" VAULT_RELEASE="explicit-release" "$script"
  [ "$status" -eq 0 ]
  run tail -n 1 "$deploy_log"
  [ "$status" -eq 0 ]
  [[ "$output" == "explicit-release" ]]

  : >"$deploy_log"
  run env PROJECT_ROOT="$PROJECT_ROOT" DEPLOY_LOG="$deploy_log" VAULT_RELEASE_DEFAULT="user-default" VAULT_NS_DEFAULT="vault-from-default" "$script"
  [ "$status" -eq 0 ]
  run tail -n 1 "$deploy_log"
  [ "$status" -eq 0 ]
  [[ "$output" == "user-default" ]]

  : >"$deploy_log"
  run env PROJECT_ROOT="$PROJECT_ROOT" DEPLOY_LOG="$deploy_log" VAULT_NS_DEFAULT="vault-derived" "$script"
  [ "$status" -eq 0 ]
  run tail -n 1 "$deploy_log"
  [ "$status" -eq 0 ]
  [[ "$output" == "vault-derived" ]]
}
