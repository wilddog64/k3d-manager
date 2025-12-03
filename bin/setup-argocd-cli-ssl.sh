#!/usr/bin/env bash
# Setup ArgoCD CLI SSL Trust - Wrapper for setup-vault-ca.sh
#
# This script is a compatibility wrapper that calls the unified setup-vault-ca.sh
# with the --service argocd flag to provide ArgoCD-specific CLI examples.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the unified script with --service argocd
exec "$SCRIPT_DIR/setup-vault-ca.sh" --service argocd "$@"
