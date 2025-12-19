__CLUSTER_PROVIDER_MODULES_LOADED=""

function _default_cluster_provider() {
    if _is_mac 2>/dev/null; then
        echo "k3d"
        return 0
    fi

    if [[ -n "${DEFAULT_CLUSTER_PROVIDER:-}" ]]; then
        echo "$DEFAULT_CLUSTER_PROVIDER"
        return 0
    fi

    # Auto-detect based on available binaries
    if command -v k3d >/dev/null 2>&1; then
        echo "k3d"
    elif command -v k3s >/dev/null 2>&1; then
        echo "k3s"
    else
        echo "k3d"  # Final fallback
    fi
}

function _cluster_provider_module_path() {
    local provider="$1"
    echo "${SCRIPT_DIR}/lib/providers/${provider}.sh"
}

function _cluster_provider_module_loaded() {
    local provider="$1"
    [[ ":${__CLUSTER_PROVIDER_MODULES_LOADED}:" == *":${provider}:"* ]]
}

function _cluster_provider_mark_loaded() {
    local provider="$1"
    if [[ -z "${__CLUSTER_PROVIDER_MODULES_LOADED}" ]]; then
        __CLUSTER_PROVIDER_MODULES_LOADED="$provider"
    else
        __CLUSTER_PROVIDER_MODULES_LOADED+=":${provider}"
    fi
}

function _ensure_cluster_provider() {
    local provider="${CLUSTER_PROVIDER:-}"

    if [[ -z "$provider" && -n "${K3D_MANAGER_CLUSTER_PROVIDER:-}" ]]; then
        provider="$K3D_MANAGER_CLUSTER_PROVIDER"
    fi

    if [[ -z "$provider" ]]; then
        provider="$(_default_cluster_provider)"
    fi

    if [[ -z "$provider" ]]; then
        echo "No cluster provider configured. Set CLUSTER_PROVIDER to continue." >&2
        exit 1
    fi

    export CLUSTER_PROVIDER="$provider"

    if _cluster_provider_module_loaded "$provider"; then
        return 0
    fi

    local module
    module="$(_cluster_provider_module_path "$provider")"

    if [[ ! -r "$module" ]]; then
        echo "Cluster provider module not found: $provider" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$module"
    _cluster_provider_mark_loaded "$provider"
}

function _cluster_provider_call() {
    local action="$1"
    shift

    _ensure_cluster_provider

    local provider="$CLUSTER_PROVIDER"
    local func="_provider_${provider}_${action}"

    if ! declare -f "$func" >/dev/null 2>&1; then
        _err "Cluster provider '$provider' does not implement action '$action'"
    fi

    "$func" "$@"
}
