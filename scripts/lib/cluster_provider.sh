#!/usr/bin/env bash

# cluster_provider.sh - Lightweight abstraction for selecting the active
# Kubernetes provider used by k3d-manager plugins.  Call
# _cluster_provider_get_active to retrieve the provider name.  The helper keeps a
# cache to avoid repeated detection work but still honours overrides.

# Cache for the detected provider.  Use _cluster_provider_set_active to override
# explicitly (e.g., within tests) or _cluster_provider_reset_active to clear the
# cache.
CLUSTER_PROVIDER_ACTIVE="${CLUSTER_PROVIDER_ACTIVE:-}"

function _orbstack_cli_available() {
    command -v orb >/dev/null 2>&1
}

function _orbstack_detect() {
    if ! _is_mac 2>/dev/null; then
        return 1
    fi

    if ! _orbstack_cli_available; then
        return 1
    fi

    orb status >/dev/null 2>&1
}

function _orbstack_find_docker_context() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi

    local context
    context=$(docker context ls --format '{{.Name}}\t{{.Description}}' 2>/dev/null \
        | awk 'tolower($0) ~ /orbstack/ {print $1; exit}')

    if [[ -z "$context" ]]; then
        return 1
    fi

    printf '%s\n' "$context"
}

function _cluster_provider_set_active() {
    local provider="${1:-}"
    CLUSTER_PROVIDER_ACTIVE="$provider"
}

function _cluster_provider_reset_active() {
    CLUSTER_PROVIDER_ACTIVE=""
}

function _cluster_provider_guess_default() {
    local provider="${1:-}"

    if [[ -n "$provider" ]]; then
        printf '%s\n' "$provider"
        return 0
    fi

    if _orbstack_detect; then
        printf 'orbstack\n'
        return 0
    fi

    if command -v k3d >/dev/null 2>&1; then
        printf 'k3d\n'
        return 0
    fi

    if command -v k3s >/dev/null 2>&1; then
        printf 'k3s\n'
        return 0
    fi

    if command -v kubectl >/dev/null 2>&1; then
        printf 'kubeconfig\n'
        return 0
    fi

    printf 'k3d\n'
}

function _cluster_provider_get_active() {
    if [[ -n "${CLUSTER_PROVIDER_ACTIVE:-}" ]]; then
        printf '%s\n' "$CLUSTER_PROVIDER_ACTIVE"
        return 0
    fi

    local provider="${CLUSTER_PROVIDER:-${K3D_MANAGER_PROVIDER:-}}"
    provider=$(_cluster_provider_guess_default "$provider") || return 1
    CLUSTER_PROVIDER_ACTIVE="$provider"
    printf '%s\n' "$provider"
}

function _cluster_provider_is() {
    local expected="${1:-}"
    local provider
    provider=$(_cluster_provider_get_active) || return 1
    [[ "$provider" == "$expected" ]]
}
