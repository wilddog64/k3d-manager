__CLUSTER_PROVIDER_MODULES_LOADED=""

function _default_cluster_provider() {
    local provider="${DEFAULT_CLUSTER_PROVIDER:-}"
    _cluster_provider_guess_default "$provider"
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
    local provider_slug="${provider//-/_}"
    local func="_provider_${provider_slug}_${action}"

    if ! declare -f "$func" >/dev/null 2>&1; then
        _err "Cluster provider '$provider' does not implement action '$action'"
    fi

    "$func" "$@"
}

_ACG_ACTIVE_PROVIDER_FILE="${_ACG_ACTIVE_PROVIDER_FILE:-${HOME}/.local/share/k3d-manager/active-provider}"

function _acg_normalize_provider() {
    case "${1:-}" in
        aws|k3s-aws)                 printf 'k3s-aws\n' ;;
        az|azure|k3s-az)             printf 'k3s-az\n' ;;
        gcp|k3s-gcp)                 printf 'k3s-gcp\n' ;;
        oci|k3s-oci)                 printf 'k3s-oci\n' ;;
        hostinger|k3s-hostinger)     printf 'k3s-hostinger\n' ;;
        *)                           printf '%s\n' "${1:-}" ;;
    esac
}

function _acg_provider_context() {
    case "$(_acg_normalize_provider "${1:-}")" in
        k3s-aws)       printf 'ubuntu-k3s\n' ;;
        k3s-az)        printf 'ubuntu-azure\n' ;;
        k3s-gcp)       printf 'ubuntu-gcp\n' ;;
        k3s-hostinger) printf 'ubuntu-hostinger\n' ;;
        *)             printf 'ubuntu-k3s\n' ;;
    esac
}

function _acg_record_provider() {
    local provider
    provider="$(_acg_normalize_provider "${1:-}")"
    [[ -z "${provider}" ]] && return 0
    mkdir -p "$(dirname "${_ACG_ACTIVE_PROVIDER_FILE}")"
    printf '%s\n' "${provider}" > "${_ACG_ACTIVE_PROVIDER_FILE}"
}

function _acg_resolve_provider() {
    local provider="${CLUSTER_PROVIDER:-}"
    if [[ -z "${provider}" && -f "${_ACG_ACTIVE_PROVIDER_FILE}" ]]; then
        provider="$(cat "${_ACG_ACTIVE_PROVIDER_FILE}" 2>/dev/null || true)"
    fi
    if [[ -z "${provider}" ]]; then
        local ctx
        for ctx in ubuntu-k3s ubuntu-azure ubuntu-gcp ubuntu-hostinger; do
            if kubectl --context "${ctx}" --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then
                case "${ctx}" in
                    ubuntu-k3s)       provider=k3s-aws ;;
                    ubuntu-azure)     provider=k3s-az ;;
                    ubuntu-gcp)       provider=k3s-gcp ;;
                    ubuntu-hostinger) provider=k3s-hostinger ;;
                esac
                break
            fi
        done
    fi
    _acg_normalize_provider "${provider:-k3s-aws}"
}
