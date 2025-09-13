# Initialize common environment variables and stub commands
function init_test_env() {
  export SOURCE="${BATS_TEST_DIRNAME}/../../k3d-manager"
  export SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"

  KUBECTL_EXIT_CODES=()
  HELM_EXIT_CODES=()

  KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  HELM_LOG="$BATS_TEST_TMPDIR/helm.log"
  : > "$KUBECTL_LOG"
  : > "$HELM_LOG"

  cleanup_on_success() { :; }

  stub_kubectl
  stub_helm
}

# Define kubectl stub that logs commands and uses scripted exit codes
function stub_kubectl() {
  _kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
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
    echo "$*" >> "$HELM_LOG"
    local rc=0
    if ((${#HELM_EXIT_CODES[@]})); then
      rc=${HELM_EXIT_CODES[0]}
      HELM_EXIT_CODES=("${HELM_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }
}

# Export stub functions for visibility in subshells
function export_stubs() {
  export -f cleanup_on_success
  export -f _kubectl
  export -f _helm
}
