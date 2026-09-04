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
_ACG_ACTIVE_PROVIDERS_DIR="${_ACG_ACTIVE_PROVIDERS_DIR:-${HOME}/.local/share/k3d-manager/active-providers}"

function _acg_normalize_provider() {
    case "${1:-}" in
        aws|k3s-aws)                 printf 'k3s-aws\n' ;;
        az|azure|k3s-az)             printf 'k3s-az\n' ;;
        gcp|k3s-gcp)                 printf 'k3s-gcp\n' ;;
        oci|k3s-oci)                 printf 'k3s-oci\n' ;;
        hostinger|hostiger|k3s-hostinger|k3s-hostiger) printf 'k3s-hostinger\n' ;;
        *)                           printf '%s\n' "${1:-}" ;;
    esac
}

function _acg_provider_context() {
    case "$(_acg_normalize_provider "${1:-}")" in
        k3s-aws)       printf 'ubuntu-k3s\n' ;;
        k3s-az)        printf 'ubuntu-azure\n' ;;
        k3s-gcp)       printf 'ubuntu-gcp\n' ;;
        k3s-hostinger) printf 'ubuntu-hostinger\n' ;;
        k3s-oci)       printf 'k3s-oci\n' ;;
        *)             printf 'ubuntu-k3s\n' ;;
    esac
}

function _acg_record_provider() {
    local provider
    provider="$(_acg_normalize_provider "${1:-}")"
    [[ -z "${provider}" ]] && return 0
    mkdir -p "${_ACG_ACTIVE_PROVIDERS_DIR}"
    : > "${_ACG_ACTIVE_PROVIDERS_DIR}/${provider}"
    mkdir -p "$(dirname "${_ACG_ACTIVE_PROVIDER_FILE}")"
    printf '%s\n' "${provider}" > "${_ACG_ACTIVE_PROVIDER_FILE}"
}

function _acg_unrecord_provider() {
    local provider
    provider="$(_acg_normalize_provider "${1:-}")"
    [[ -z "${provider}" ]] && return 0
    rm -f "${_ACG_ACTIVE_PROVIDERS_DIR}/${provider}"
    if [[ -f "${_ACG_ACTIVE_PROVIDER_FILE}" ]]; then
        local cur
        cur="$(_acg_normalize_provider "$(cat "${_ACG_ACTIVE_PROVIDER_FILE}" 2>/dev/null || true)")"
        [[ "${cur}" == "${provider}" ]] && rm -f "${_ACG_ACTIVE_PROVIDER_FILE}"
    fi
    return 0
}

function _acg_lock_acquire() {
    # Portable advisory lock (macOS has no flock(1)). Serializes the shared-hub
    # bootstrap across concurrent per-provider bring-ups. mkdir is atomic; a pid
    # file lets a later run reclaim a lock whose owner died. Bounded wait then
    # proceeds without the lock rather than deadlocking.
    # Usage: _acg_lock_acquire <lock-dir> [timeout-seconds]
    local lockdir="${1:-}" timeout="${2:-120}" waited=0
    [[ -z "${lockdir}" ]] && return 0
    while ! mkdir "${lockdir}" 2>/dev/null; do
        if [[ -f "${lockdir}/pid" ]]; then
            local owner
            owner="$(cat "${lockdir}/pid" 2>/dev/null || true)"
            if [[ -n "${owner}" ]] && ! kill -0 "${owner}" 2>/dev/null; then
                rm -rf "${lockdir}"
                continue
            fi
        fi
        if [[ "${waited}" -ge "${timeout}" ]]; then
            _warn "[lock] timed out after ${timeout}s waiting for ${lockdir}; proceeding without it"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    printf '%s\n' "$$" > "${lockdir}/pid"
    return 0
}

function _acg_lock_release() {
    local lockdir="${1:-}"
    [[ -z "${lockdir}" ]] && return 0
    rm -rf "${lockdir}"
    return 0
}

function _acg_provider_port_offset() {
    # Deterministic per-provider local-port offset so concurrent app-cluster
    # port-forwards do not collide. k3s-aws (cluster-up's default) = 0 so
    # single-cloud users keep the historical fixed ports unchanged.
    case "$(_acg_normalize_provider "${1:-}")" in
        k3s-aws)       printf '0\n' ;;
        k3s-hostinger) printf '10\n' ;;
        k3s-az)        printf '20\n' ;;
        k3s-gcp)       printf '30\n' ;;
        k3s-oci)       printf '40\n' ;;
        *)             printf '0\n' ;;
    esac
}

function _acg_migrate_flat_state() {
    # One-time migration: pre-scoping runs kept a single flat state dir under $1.
    # If flat state exists and no scoped dir claims it yet, move it under the
    # provider named by the legacy active-provider marker (its rightful owner),
    # else this run's provider ($2, already normalized).
    local base="${1:-}" run_provider="${2:-}"
    [[ -z "${base}" || -z "${run_provider}" ]] && return 0
    [[ -d "${base}/run" || -d "${base}/logs" || -d "${base}/checkpoints" ]] || return 0
    local owner="${run_provider}"
    if [[ -f "${base}/active-provider" ]]; then
        local marked
        marked="$(_acg_normalize_provider "$(cat "${base}/active-provider" 2>/dev/null || true)")"
        [[ -n "${marked}" ]] && owner="${marked}"
    fi
    local target="${base}/${owner}"
    [[ -d "${target}" ]] && return 0
    mkdir -p "${target}"
    local sub
    for sub in run logs bin checkpoints; do
        [[ -e "${base}/${sub}" ]] && mv "${base}/${sub}" "${target}/${sub}"
    done
    [[ -e "${base}/acg-state.json" ]] && mv "${base}/acg-state.json" "${target}/acg-state.json"
    return 0
}

function _acg_list_active_providers() {
    if [[ -d "${_ACG_ACTIVE_PROVIDERS_DIR}" ]]; then
        local _f _n=0
        for _f in "${_ACG_ACTIVE_PROVIDERS_DIR}"/*; do
            [[ -e "${_f}" ]] || continue
            printf '%s\n' "$(basename "${_f}")"
            _n=$((_n + 1))
        done
        [[ "${_n}" -gt 0 ]] && return 0
    fi
    [[ -f "${_ACG_ACTIVE_PROVIDER_FILE}" ]] && \
        _acg_normalize_provider "$(cat "${_ACG_ACTIVE_PROVIDER_FILE}" 2>/dev/null || true)"
    return 0
}

# Reachability preflight: true only if the kube-context answers /readyz within a
# short timeout. Selecting a resolvable-but-dead context (e.g. an expired ACG
# sandbox whose kubeconfig entry outlived the cluster) then fails fast instead of
# hanging against a dead endpoint.
function _acg_context_reachable() {
    local ctx="${1:-}"
    [[ -z "${ctx}" ]] && return 1
    kubectl --context "${ctx}" --request-timeout=5s get --raw=/readyz >/dev/null 2>&1
}

function _acg_resolve_provider() {
    local provider="${CLUSTER_PROVIDER:-}"
    if [[ -z "${provider}" ]]; then
        local ctx
        for ctx in ubuntu-hostinger ubuntu-k3s ubuntu-azure ubuntu-gcp; do
            if _acg_context_reachable "${ctx}"; then
                case "${ctx}" in
                    ubuntu-hostinger) provider=k3s-hostinger ;;
                    ubuntu-k3s)       provider=k3s-aws ;;
                    ubuntu-azure)     provider=k3s-az ;;
                    ubuntu-gcp)       provider=k3s-gcp ;;
                esac
                break
            fi
        done
    fi
    if [[ -z "${provider}" ]]; then
        local -a _live=()
        mapfile -t _live < <(_acg_list_active_providers)
        if [[ "${#_live[@]}" -eq 1 ]]; then
            provider="${_live[0]}"
        elif [[ "${#_live[@]}" -gt 1 && -f "${_ACG_ACTIVE_PROVIDER_FILE}" ]]; then
            provider="$(cat "${_ACG_ACTIVE_PROVIDER_FILE}" 2>/dev/null || true)"
        fi
    fi
    _acg_normalize_provider "${provider:-k3s-hostinger}"
}
