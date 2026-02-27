# Initialize common environment variables and stub commands
function init_test_env() {
  export SOURCE="${BATS_TEST_DIRNAME}/../../k3d-manager"
  export SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"

  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/provider.sh"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/core.sh"

  KUBECTL_EXIT_CODES=()
  HELM_EXIT_CODES=()
  RUN_EXIT_CODES=()

  KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  HELM_LOG="$BATS_TEST_TMPDIR/helm.log"
  RUN_LOG="$BATS_TEST_TMPDIR/run.log"
  export KUBECTL_LOG HELM_LOG RUN_LOG
  : > "$KUBECTL_LOG"
  : > "$HELM_LOG"
  : > "$RUN_LOG"

  _cleanup_on_success() { :; }

  stub_envsubst
  stub_kubectl
  stub_helm
  stub_run_command
  stub_vault

  _systemd_available() { return 0; }
  export -f _systemd_available
}

# Define kubectl stub that logs commands and uses scripted exit codes
function stub_kubectl() {
  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$KUBECTL_LOG"

    # Special handling for vault-root secret queries (for Vault integration tests)
    if [[ "$*" == *"get secret vault-root"* && "$*" == *"jsonpath"* ]]; then
      # Return a fake base64-encoded token
      echo "ZmFrZS12YXVsdC10b2tlbi1mb3ItdGVzdGluZw=="  # "fake-vault-token-for-testing" in base64
      return 0
    fi

    local rc=0
    if ((${#KUBECTL_EXIT_CODES[@]})); then
      rc=${KUBECTL_EXIT_CODES[0]}
      KUBECTL_EXIT_CODES=("${KUBECTL_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }
}

# Define helm stub that logs commands and uses scripted exit codes
function stub_helm() {
  _helm() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$HELM_LOG"
    local rc=0
    if ((${#HELM_EXIT_CODES[@]})); then
      rc=${HELM_EXIT_CODES[0]}
      HELM_EXIT_CODES=("${HELM_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }
}

# Define run_command stub that logs commands and uses scripted exit codes
function stub_run_command() {
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    local rc=0
    if ((${#RUN_EXIT_CODES[@]})); then
      rc=${RUN_EXIT_CODES[0]}
      RUN_EXIT_CODES=("${RUN_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }
}

# Define envsubst stub that uses the system envsubst for variable expansion
function stub_envsubst() {
  envsubst() { command envsubst "$@"; }
}

# Define vault function stubs for testing
function stub_vault() {
  _vault_login() {
    # Stub - just return success
    return 0
  }

  _vault_policy_exists() {
    # Stub - always return false (policy doesn't exist) to test policy creation
    return 1
  }

  _vault_exec_stream() {
    # Stub - log the command and return success
    local ns release
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit) shift ;;
        --pod) shift 2 ;;
        --) shift; break ;;
        *) ns="$1"; release="$2"; shift 2; break ;;
      esac
    done
    echo "vault $*" >> "$KUBECTL_LOG"

    # Special handling for vault token lookup (for Vault integration tests)
    if [[ "$*" == *"vault token lookup"* ]]; then
      # Return fake JSON token info
      echo '{"data":{"id":"fake-token","policies":["root"],"expire_time":null}}'
      return 0
    fi

    return 0
  }
}

# Read lines from a file into an array variable
function read_lines() {
  local file="$1"
  local array_name="$2"
  if (( BASH_VERSINFO[0] >= 4 )); then
    mapfile -t "$array_name" < "$file"
  else
    local line i=0 quoted
    unset "$array_name"
    [[ -r "$file" ]] || return 0
    while IFS= read -r line; do
      printf -v quoted '%q' "$line"
      eval "$array_name[$i]=$quoted"
      (( i++ ))
    done < "$file"
    return 0
  fi
}

# Export stub functions for visibility in subshells
function export_stubs() {
  export -f _cleanup_on_success
  export -f _kubectl
  export -f _helm
  export -f _run_command
  export -f envsubst
  export -f _vault_login
  export -f _vault_policy_exists
  export -f _vault_exec_stream
}
