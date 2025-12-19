#!/usr/bin/env bash
# Setup Jenkins CLI SSL Trust - Wrapper for setup-vault-ca.sh
#
# This script is a compatibility wrapper that calls the unified setup-vault-ca.sh
# with the --import-java flag to import Vault CA certificate into Java truststore.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the unified script with --import-java flag and --service jenkins
exec "$SCRIPT_DIR/setup-vault-ca.sh" --import-java --service jenkins "$@"
