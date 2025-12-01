#!/usr/bin/env bash
set -euo pipefail

# Setup Jenkins CLI SSL Trust - Import Vault CA into Java Truststore

# Default values
DEFAULT_VAULT_NAMESPACE="vault"
DEFAULT_VAULT_POD="vault-0"
DEFAULT_VAULT_PKI_PATH="pki"
DEFAULT_CACERTS_PASSWORD="changeit"
DEFAULT_CACERTS_ALIAS="vault-k3d-ca"

# Initialize variables from environment or defaults
VAULT_NAMESPACE="${VAULT_NAMESPACE:-$DEFAULT_VAULT_NAMESPACE}"
VAULT_POD="${VAULT_POD:-$DEFAULT_VAULT_POD}"
VAULT_PKI_PATH="${VAULT_PKI_PATH:-$DEFAULT_VAULT_PKI_PATH}"
CACERTS_PASSWORD="${CACERTS_PASSWORD:-$DEFAULT_CACERTS_PASSWORD}"
CACERTS_ALIAS="${CACERTS_ALIAS:-$DEFAULT_CACERTS_ALIAS}"
QUIET="${QUIET:-0}"
DRY_RUN="${DRY_RUN:-0}"
EXPORT_ONLY="${EXPORT_ONLY:-0}"
EXPORT_PATH="${EXPORT_PATH:-}"

# Show usage
usage() {
  cat <<EOF
Setup Jenkins CLI SSL Trust - Import Vault CA into Java Truststore

USAGE:
  $(basename "$0") [OPTIONS] [vault_namespace] [vault_pod]

OPTIONS:
  -n, --namespace NAME     Vault namespace (default: $DEFAULT_VAULT_NAMESPACE)
  -p, --pod NAME           Vault pod name (default: $DEFAULT_VAULT_POD)
  -k, --pki-path PATH      Vault PKI mount path (default: $DEFAULT_VAULT_PKI_PATH)
  -a, --alias ALIAS        Certificate alias in truststore (default: $DEFAULT_CACERTS_ALIAS)
  -w, --password PASS      Java cacerts password (default: $DEFAULT_CACERTS_PASSWORD)
  -e, --export [PATH]      Export certificate only (default: ./vault-ca.crt)
  -d, --dry-run            Preview operations without making changes
  -q, --quiet              Suppress informational output
  -v, --verbose            Enable verbose output
  -h, --help               Show this help message

ENVIRONMENT VARIABLES:
  JAVA_HOME                Override Java installation path
  VAULT_NAMESPACE          Vault namespace
  VAULT_POD                Vault pod name
  VAULT_PKI_PATH           Vault PKI mount path
  CACERTS_PASSWORD         Java cacerts password
  CACERTS_ALIAS            Certificate alias
  QUIET                    Suppress informational output (0 or 1)
  DRY_RUN                  Preview mode (0 or 1)
  EXPORT_ONLY              Export certificate only (0 or 1)
  EXPORT_PATH              Path to export certificate

EXAMPLES:
  # Use defaults
  $(basename "$0")

  # Custom namespace and pod (positional)
  $(basename "$0") vault vault-0

  # Using command-line options
  $(basename "$0") --namespace vault --pod vault-0

  # Preview operations
  $(basename "$0") --dry-run

  # Quiet mode for automation
  $(basename "$0") --quiet

  # Custom PKI path and alias
  $(basename "$0") -k pki_int -a my-vault-ca

  # Export certificate only (default path: ./vault-ca.crt)
  $(basename "$0") --export

  # Export certificate to custom path
  $(basename "$0") --export /tmp/my-ca.crt

EOF
  exit 0
}

# Parse command-line options
parse_args() {
  local positional_args=()

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        usage
        ;;
      -n|--namespace)
        VAULT_NAMESPACE="$2"
        shift 2
        ;;
      -p|--pod)
        VAULT_POD="$2"
        shift 2
        ;;
      -k|--pki-path)
        VAULT_PKI_PATH="$2"
        shift 2
        ;;
      -a|--alias)
        CACERTS_ALIAS="$2"
        shift 2
        ;;
      -w|--password)
        CACERTS_PASSWORD="$2"
        shift 2
        ;;
      -e|--export)
        EXPORT_ONLY=1
        if [[ $# -gt 1 ]] && [[ ! "$2" =~ ^- ]]; then
          EXPORT_PATH="$2"
          shift 2
        else
          EXPORT_PATH="./vault-ca.crt"
          shift
        fi
        ;;
      -d|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -q|--quiet)
        QUIET=1
        shift
        ;;
      -v|--verbose)
        QUIET=0
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
      *)
        positional_args+=("$1")
        shift
        ;;
    esac
  done

  # Handle positional arguments (for backward compatibility)
  if [[ ${#positional_args[@]} -ge 1 ]]; then
    VAULT_NAMESPACE="${positional_args[0]}"
  fi
  if [[ ${#positional_args[@]} -ge 2 ]]; then
    VAULT_POD="${positional_args[1]}"
  fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Temporary file
TEMP_CERT="/tmp/vault-ca-$$.crt"

# Cleanup function
cleanup() {
  if [[ "$EXPORT_ONLY" != "1" ]]; then
    rm -f "$TEMP_CERT"
  fi
}
trap cleanup EXIT

# Logging functions
log_info() {
  [[ "$QUIET" == "1" ]] && return 0
  echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
  local missing_deps=()

  if ! command_exists kubectl; then
    missing_deps+=("kubectl")
  fi

  if [[ "$EXPORT_ONLY" != "1" ]]; then
    if ! command_exists java; then
      missing_deps+=("java")
    fi

    if ! command_exists keytool; then
      missing_deps+=("keytool")
    fi
  fi

  if [ ${#missing_deps[@]} -gt 0 ]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_error "Please install the missing tools and try again"
    return 1
  fi

  return 0
}

# Find Java home directory
find_java_home() {
  local java_home_path

  if [[ -n "${JAVA_HOME:-}" ]] && [[ -d "${JAVA_HOME}/lib/security" ]]; then
    java_home_path="$JAVA_HOME"
    log_info "Using JAVA_HOME from environment: $java_home_path"
  else
    if [[ -n "${JAVA_HOME:-}" ]]; then
      log_warn "JAVA_HOME is set but invalid, auto-detecting Java installation..."
    fi
    java_home_path=$(java -XshowSettings:properties -version 2>&1 | grep "java.home" | awk '{print $3}')
    if [[ -z "$java_home_path" ]]; then
      log_error "Could not determine Java home directory"
      log_error "Try setting JAVA_HOME environment variable to a valid Java installation"
      return 1
    fi
    log_info "Detected Java home: $java_home_path"
  fi

  echo "$java_home_path"
}

# Get cacerts path
get_cacerts_path() {
  local java_home="$1"
  local cacerts_path="${java_home}/lib/security/cacerts"

  if [[ ! -f "$cacerts_path" ]]; then
    log_error "cacerts not found at expected location: $cacerts_path"
    return 1
  fi

  echo "$cacerts_path"
}

# Check if Vault pod is accessible
check_vault_access() {
  log_info "Checking access to Vault pod ${VAULT_NAMESPACE}/${VAULT_POD}..."

  if ! kubectl -n "$VAULT_NAMESPACE" get pod "$VAULT_POD" &>/dev/null; then
    log_error "Vault pod ${VAULT_NAMESPACE}/${VAULT_POD} not found"
    log_error "Ensure Vault is deployed and the pod name is correct"
    return 1
  fi

  log_info "Vault pod is accessible"
  return 0
}

# Check if Jenkins is deployed
check_jenkins_deployment() {
  log_info "Checking Jenkins deployment..."

  local jenkins_pods
  jenkins_pods=$(kubectl -n jenkins get pods -l app.kubernetes.io/name=jenkins -o name 2>/dev/null | wc -l)

  if [[ "$jenkins_pods" -eq 0 ]]; then
    log_warn "Jenkins is not deployed (no pods found in jenkins namespace)"
    log_warn "The SSL certificate has been configured, but you won't be able to use jenkins-cli until Jenkins is deployed"
    log_warn "Deploy Jenkins with: ./scripts/k3d-manager deploy_jenkins --enable-vault"
    return 1
  fi

  log_info "Jenkins deployment found"
  return 0
}

# Extract Vault CA certificate
extract_vault_ca() {
  log_info "Extracting Vault CA certificate from ${VAULT_PKI_PATH}/cert/ca..."

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would extract certificate to: $TEMP_CERT"
    echo "-----BEGIN CERTIFICATE-----" > "$TEMP_CERT"
    echo "MIIDwjCCAqqgAwIBAgIUQya8F5qhUbnetZxvRnRFqoS6zu4wDQYJKoZIhvcNAQEL" >> "$TEMP_CERT"
    echo "-----END CERTIFICATE-----" >> "$TEMP_CERT"
    return 0
  fi

  if ! kubectl -n "$VAULT_NAMESPACE" exec "$VAULT_POD" -- \
    vault read -field=certificate "${VAULT_PKI_PATH}/cert/ca" > "$TEMP_CERT" 2>/dev/null; then
    log_error "Failed to extract CA certificate from Vault"
    log_error "Ensure Vault PKI is enabled at path: ${VAULT_PKI_PATH}"
    return 1
  fi

  # Verify certificate format
  if ! grep -q "BEGIN CERTIFICATE" "$TEMP_CERT"; then
    log_error "Extracted data is not a valid certificate"
    return 1
  fi

  log_success "CA certificate extracted successfully"
  return 0
}

# Export certificate to file
export_certificate() {
  local export_file="$1"

  log_info "Exporting certificate to: $export_file"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would export certificate to: $export_file"
    return 0
  fi

  if ! cp "$TEMP_CERT" "$export_file"; then
    log_error "Failed to export certificate to: $export_file"
    return 1
  fi

  chmod 644 "$export_file"
  log_success "Certificate exported to: $export_file"

  # Show certificate details
  if [[ "$QUIET" != "1" ]]; then
    echo
    log_info "Certificate details:"
    openssl x509 -in "$export_file" -text -noout 2>/dev/null | grep -E "(Subject:|Issuer:|Not Before|Not After)" || \
      keytool -printcert -file "$export_file" 2>/dev/null | grep -E "(Owner|Issuer|Valid)" || true
  fi

  return 0
}

# Check if certificate already exists in truststore
check_cert_exists() {
  local cacerts_path="$1"

  if keytool -list -keystore "$cacerts_path" -storepass "$CACERTS_PASSWORD" \
    -alias "$CACERTS_ALIAS" &>/dev/null; then
    return 0
  fi
  return 1
}

# Remove existing certificate from truststore
remove_existing_cert() {
  local cacerts_path="$1"

  log_info "Removing existing certificate with alias: $CACERTS_ALIAS"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would delete certificate: $CACERTS_ALIAS"
    return 0
  fi

  if ! keytool -delete -keystore "$cacerts_path" -storepass "$CACERTS_PASSWORD" \
    -alias "$CACERTS_ALIAS" 2>/dev/null; then
    log_warn "Could not delete existing certificate (may not exist)"
  else
    log_success "Existing certificate removed"
  fi

  return 0
}

# Import certificate into truststore
import_cert() {
  local cacerts_path="$1"

  log_info "Importing CA certificate into Java truststore..."
  log_info "Truststore: $cacerts_path"
  log_info "Alias: $CACERTS_ALIAS"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would import certificate with alias: $CACERTS_ALIAS"
    return 0
  fi

  if ! keytool -importcert \
    -keystore "$cacerts_path" \
    -storepass "$CACERTS_PASSWORD" \
    -alias "$CACERTS_ALIAS" \
    -file "$TEMP_CERT" \
    -noprompt 2>&1; then
    log_error "Failed to import certificate into truststore"
    log_error "You may need to run this script with elevated privileges"
    log_error "Try: sudo JAVA_HOME=\$(java -XshowSettings:properties -version 2>&1 | grep 'java.home' | awk '{print \$3}') $0"
    return 1
  fi

  log_success "Certificate imported successfully"
  return 0
}

# Verify certificate import
verify_import() {
  local cacerts_path="$1"

  log_info "Verifying certificate import..."

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would verify certificate import"
    return 0
  fi

  if ! keytool -list -keystore "$cacerts_path" -storepass "$CACERTS_PASSWORD" \
    -alias "$CACERTS_ALIAS" &>/dev/null; then
    log_error "Certificate verification failed - alias not found in truststore"
    return 1
  fi

  log_success "Certificate verified in truststore"
  return 0
}

# Show certificate details
show_cert_details() {
  local cacerts_path="$1"

  if [[ "$QUIET" == "1" ]] || [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  log_info "Certificate details:"
  keytool -list -keystore "$cacerts_path" -storepass "$CACERTS_PASSWORD" \
    -alias "$CACERTS_ALIAS" -v 2>/dev/null | grep -E "(Owner|Issuer|Valid)" || true
}

# Main function
main() {
  # Parse command-line arguments
  parse_args "$@"

  echo "=================================================="
  if [[ "$EXPORT_ONLY" == "1" ]]; then
    echo "Vault CA Certificate Export"
  else
    echo "Jenkins CLI SSL Trust Setup"
  fi
  echo "=================================================="
  echo "Vault Namespace: $VAULT_NAMESPACE"
  echo "Vault Pod:       $VAULT_POD"
  echo "PKI Path:        $VAULT_PKI_PATH"
  if [[ "$EXPORT_ONLY" == "1" ]]; then
    echo "Export Path:     $EXPORT_PATH"
  else
    echo "Cert Alias:      $CACERTS_ALIAS"
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
  fi
  echo "=================================================="
  echo

  # Validate prerequisites
  if ! validate_prerequisites; then
    return 1
  fi

  # Check Vault access
  if ! check_vault_access; then
    return 1
  fi

  # Extract Vault CA certificate
  if ! extract_vault_ca; then
    return 1
  fi

  # Export mode - just export the certificate and exit
  if [[ "$EXPORT_ONLY" == "1" ]]; then
    if ! export_certificate "$EXPORT_PATH"; then
      return 1
    fi

    echo
    echo "=================================================="
    log_success "Certificate export complete!"
    echo "=================================================="
    echo
    echo "Certificate saved to: $EXPORT_PATH"
    echo
    echo "You can use this certificate to:"
    echo "  - Configure system trust stores"
    echo "  - Add to browser certificate stores"
    echo "  - Import into other Java keystores"
    echo "  - Use with curl: curl --cacert $EXPORT_PATH https://..."
    return 0
  fi

  # Check Jenkins deployment (warning only, not fatal)
  check_jenkins_deployment || true

  # Find Java home
  local java_home
  if ! java_home=$(find_java_home); then
    return 1
  fi

  # Get cacerts path
  local cacerts_path
  if ! cacerts_path=$(get_cacerts_path "$java_home"); then
    return 1
  fi

  # Check if certificate already exists
  if check_cert_exists "$cacerts_path"; then
    log_warn "Certificate with alias '$CACERTS_ALIAS' already exists"

    if [[ "$DRY_RUN" != "1" ]]; then
      read -p "Remove and re-import certificate? [y/N] " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing certificate"
        show_cert_details "$cacerts_path"
        return 0
      fi
    fi

    # Remove existing certificate
    if ! remove_existing_cert "$cacerts_path"; then
      return 1
    fi
  fi

  # Import certificate
  if ! import_cert "$cacerts_path"; then
    return 1
  fi

  # Verify import
  if ! verify_import "$cacerts_path"; then
    return 1
  fi

  # Show certificate details
  show_cert_details "$cacerts_path"

  echo
  echo "=================================================="
  log_success "Setup complete!"
  echo "=================================================="

  if [[ "$DRY_RUN" != "1" ]]; then
    echo
    echo "You can now use jenkins-cli without -noCertificateCheck:"
    echo "  java -jar jenkins-cli.jar -s https://jenkins.dev.local.me -auth user:pass version"
  fi

  return 0
}

# Run main function
main "$@"
