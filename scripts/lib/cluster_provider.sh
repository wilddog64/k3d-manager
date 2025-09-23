#!/usr/bin/env bash

# cluster_provider.sh - Lightweight abstraction for selecting the active
# Kubernetes provider used by k3d-manager plugins.  Call
# cluster_provider_get_active to retrieve the provider name.  The helper keeps a
# cache to avoid repeated detection work but still honours overrides.

# Cache for the detected provider.  Use cluster_provider_set_active to override
# explicitly (e.g., within tests) or cluster_provider_reset_active to clear the
# cache.
CLUSTER_PROVIDER_ACTIVE="${CLUSTER_PROVIDER_ACTIVE:-}"

function cluster_provider_set_active() {
    local provider="${1:-}"
    CLUSTER_PROVIDER_ACTIVE="$provider"
}

function cluster_provider_reset_active() {
    CLUSTER_PROVIDER_ACTIVE=""
}

function _cluster_provider_guess_default() {
    local provider="${1:-}"

    if [[ -n "$provider" ]]; then
        printf '%s\n' "$provider"
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

    printf 'unknown\n'
}

function cluster_provider_get_active() {
    if [[ -n "${CLUSTER_PROVIDER_ACTIVE:-}" ]]; then
        printf '%s\n' "$CLUSTER_PROVIDER_ACTIVE"
        return 0
    fi

    local provider="${CLUSTER_PROVIDER:-${K3D_MANAGER_PROVIDER:-}}"
    provider=$(_cluster_provider_guess_default "$provider") || return 1
    CLUSTER_PROVIDER_ACTIVE="$provider"
    printf '%s\n' "$provider"
}

function cluster_provider_is() {
    local expected="${1:-}"
    local provider
    provider=$(cluster_provider_get_active) || return 1
    [[ "$provider" == "$expected" ]]
}
