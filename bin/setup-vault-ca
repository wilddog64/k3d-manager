#!/usr/bin/env bash
set -euo pipefail

# Setup Vault CA Certificate - Universal SSL Trust Configuration
#
# This script extracts the Vault PKI CA certificate and provides platform-specific
# installation instructions for various services (Jenkins, ArgoCD, or generic use).
# For Jenkins, it can also import the certificate into Java's truststore.

# Default values
DEFAULT_VAULT_NAMESPACE="vault"
DEFAULT_VAULT_POD="vault-0"
DEFAULT_VAULT_PKI_PATH="pki"
DEFAULT_EXPORT_PATH="./vault-ca.crt"
DEFAULT_SERVICE="generic"
DEFAULT_CACERTS_PASSWORD="changeit"
DEFAULT_CACERTS_ALIAS="vault-k3d-ca"

# Initialize variables from environment or defaults
VAULT_NAMESPACE="${VAULT_NAMESPACE:-$DEFAULT_VAULT_NAMESPACE}"
VAULT_POD="${VAULT_POD:-$DEFAULT_VAULT_POD}"
VAULT_PKI_PATH="${VAULT_PKI_PATH:-$DEFAULT_VAULT_PKI_PATH}"
EXPORT_PATH="${EXPORT_PATH:-$DEFAULT_EXPORT_PATH}"
SERVICE="${SERVICE:-$DEFAULT_SERVICE}"
QUIET="${QUIET:-0}"
DRY_RUN="${DRY_RUN:-0}"
IMPORT_JAVA="${IMPORT_JAVA:-0}"
IMPORT_KEYCHAIN="${IMPORT_KEYCHAIN:-0}"
IMPORT_FILE="${IMPORT_FILE:-}"
SHOW_ALL_SERVICES="${SHOW_ALL_SERVICES:-0}"
CACERTS_PASSWORD="${CACERTS_PASSWORD:-$DEFAULT_CACERTS_PASSWORD}"
CACERTS_ALIAS="${CACERTS_ALIAS:-$DEFAULT_CACERTS_ALIAS}"

# Show usage
usage() {
  cat <<EOF
Setup Vault CA Certificate - Universal SSL Trust Configuration

USAGE:
  $(basename "$0") [OPTIONS] [export_path]

OPTIONS:
  -s, --service NAME       Service type for CLI examples (jenkins|argocd|generic) (default: $DEFAULT_SERVICE)
      --all                Show usage examples for all services
  -i, --import FILE        Import certificate from file instead of extracting from Vault
  -n, --namespace NAME     Vault namespace (default: $DEFAULT_VAULT_NAMESPACE)
  -p, --pod NAME           Vault pod name (default: $DEFAULT_VAULT_POD)
  -k, --pki-path PATH      Vault PKI mount path (default: $DEFAULT_VAULT_PKI_PATH)
  -o, --output PATH        Certificate export path (default: $DEFAULT_EXPORT_PATH)
  -j, --import-java        Import certificate into Java truststore (requires java/keytool)
  -m, --import-keychain    Import certificate into macOS Keychain (macOS only)
  -a, --alias ALIAS        Certificate alias for Java truststore (default: $DEFAULT_CACERTS_ALIAS)
  -w, --password PASS      Java cacerts password (default: $DEFAULT_CACERTS_PASSWORD)
  -d, --dry-run            Preview operations without making changes
  -q, --quiet              Suppress informational output
  -v, --verbose            Enable verbose output
  -h, --help               Show this help message

ENVIRONMENT VARIABLES:
  VAULT_NAMESPACE          Vault namespace
  VAULT_POD                Vault pod name
  VAULT_PKI_PATH           Vault PKI mount path
  EXPORT_PATH              Path to export certificate
  SERVICE                  Service type (jenkins|argocd|generic)
  IMPORT_JAVA              Import into Java truststore (0 or 1)
  CACERTS_PASSWORD         Java cacerts password
  CACERTS_ALIAS            Certificate alias
  QUIET                    Suppress informational output (0 or 1)
  DRY_RUN                  Preview mode (0 or 1)

EXAMPLES:
  # Export CA certificate for generic use
  $(basename "$0")

  # Export for Jenkins with CLI examples
  $(basename "$0") --service jenkins

  # Export for ArgoCD with CLI examples
  $(basename "$0") --service argocd

  # Show usage examples for all services
  $(basename "$0") --all

  # Export and import into Java truststore (for Jenkins CLI)
  $(basename "$0") --service jenkins --import-java

  # Import from Vault to macOS Keychain
  $(basename "$0") --import-keychain

  # Import certificate from file and install to Java truststore
  $(basename "$0") --import ~/my-ca.crt --import-java

  # Import certificate from file to macOS Keychain
  $(basename "$0") --import vault-ca.crt --import-keychain

  # Export to custom path
  $(basename "$0") --output ~/vault-ca.crt

  # Custom namespace and pod
  $(basename "$0") --namespace vault --pod vault-0

  # Preview operations
  $(basename "$0") --dry-run

  # Quiet mode for automation
  $(basename "$0") --quiet --service jenkins

PLATFORM-SPECIFIC INSTALLATION:
  macOS - Add to system keychain (requires sudo):
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./vault-ca.crt

  macOS - Add to user keychain only:
    security add-trusted-cert -d -r trustAsRoot -k ~/Library/Keychains/login.keychain-db ./vault-ca.crt

  Linux (Ubuntu/Debian) - System-wide trust:
    sudo cp ./vault-ca.crt /usr/local/share/ca-certificates/vault-ca.crt
    sudo update-ca-certificates

  Java - Import into truststore:
    $(basename "$0") --import-java

SERVICE-SPECIFIC USAGE:
  Use --service flag to get CLI usage examples for specific services.
  Supported services: jenkins, argocd, generic (default)

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
      -s|--service)
        SERVICE="$2"
        shift 2
        ;;
      --all)
        SHOW_ALL_SERVICES=1
        shift
        ;;
      -i|--import)
        IMPORT_FILE="$2"
        shift 2
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
      -o|--output)
        EXPORT_PATH="$2"
        shift 2
        ;;
      -j|--import-java)
        IMPORT_JAVA=1
        shift
        ;;
      -m|--import-keychain)
        IMPORT_KEYCHAIN=1
        shift
        ;;
      -a|--alias)
        CACERTS_ALIAS="$2"
        shift 2
        ;;
      -w|--password)
        CACERTS_PASSWORD="$2"
        shift 2
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

  # Handle positional argument (export path)
  if [[ ${#positional_args[@]} -ge 1 ]]; then
    EXPORT_PATH="${positional_args[0]}"
  fi

  # Validate service parameter
  case "$SERVICE" in
    jenkins|argocd|generic)
      : # valid
      ;;
    *)
      echo "Invalid service: $SERVICE" >&2
      echo "Must be one of: jenkins, argocd, generic" >&2
      exit 1
      ;;
  esac
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
  if [[ -f "$TEMP_CERT" ]] && [[ "$TEMP_CERT" != "$EXPORT_PATH" ]]; then
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

# Validate imported certificate file
validate_import_file() {
  local cert_file="$1"

  if [[ ! -f "$cert_file" ]]; then
    log_error "Certificate file not found: $cert_file"
    return 1
  fi

  if ! command_exists openssl; then
    log_warn "openssl not found, skipping certificate validation"
    return 0
  fi

  # Validate it's a valid certificate
  if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
    log_error "Invalid certificate file: $cert_file"
    return 1
  fi

  log_success "Validated certificate file: $cert_file"
  return 0
}

# Import certificate to macOS Keychain
import_to_keychain() {
  local cert_file="$1"

  log_info "Importing certificate to macOS Keychain..."
  log_info "Certificate: $cert_file"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would import certificate to macOS Keychain"
    return 0
  fi

  # Check if we're on macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    log_error "Keychain import is only supported on macOS"
    return 1
  fi

  # Check if security command exists
  if ! command_exists security; then
    log_error "security command not found (required for Keychain import)"
    return 1
  fi

  # Get certificate subject hash/name for checking existence
  local cert_name
  if command_exists openssl; then
    cert_name=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
  fi

  # Check if certificate already exists in System keychain
  if [[ -n "$cert_name" ]]; then
    if sudo security find-certificate -c "$cert_name" /Library/Keychains/System.keychain >/dev/null 2>&1; then
      log_warn "Certificate already exists in System Keychain"
      log_info "Removing existing certificate to allow re-import..."

      # Remove the existing certificate
      if ! sudo security delete-certificate -c "$cert_name" /Library/Keychains/System.keychain 2>/dev/null; then
        log_warn "Could not remove existing certificate (may not exist or permission denied)"
      else
        log_success "Removed existing certificate"
      fi
    fi
  fi

  # Import to System keychain (requires admin privileges)
  log_info "Importing to System Keychain (may require password)..."
  if ! sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain "$cert_file"; then
    log_error "Failed to import certificate to System Keychain"
    return 1
  fi

  log_success "Certificate imported to macOS System Keychain"

  # Verify the import
  if [[ -n "$cert_name" ]]; then
    if sudo security find-certificate -c "$cert_name" /Library/Keychains/System.keychain >/dev/null 2>&1; then
      log_success "Verified certificate is present in Keychain"
    fi
  fi

  return 0
}

# Validate prerequisites
validate_prerequisites() {
  local missing_deps=()

  if ! command_exists kubectl; then
    missing_deps+=("kubectl")
  fi

  if [[ "$IMPORT_JAVA" == "1" ]]; then
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

# Show certificate details from Java truststore
show_java_cert_details() {
  local cacerts_path="$1"

  if [[ "$QUIET" == "1" ]] || [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  log_info "Certificate details:"
  keytool -list -keystore "$cacerts_path" -storepass "$CACERTS_PASSWORD" \
    -alias "$CACERTS_ALIAS" -v 2>/dev/null | grep -E "(Owner|Issuer|Valid)" || true
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

  # If export_file is a directory, append default filename
  if [[ -d "$export_file" ]]; then
    export_file="${export_file%/}/vault-ca.crt"
    log_info "Export path is a directory, using: $export_file"
  fi

  # Check if trying to copy to itself
  if [[ "$(realpath "$TEMP_CERT" 2>/dev/null)" == "$(realpath "$export_file" 2>/dev/null)" ]]; then
    log_error "Cannot export to same file as temp certificate"
    log_error "Temp cert: $TEMP_CERT"
    log_error "Export path: $export_file"
    return 1
  fi

  log_info "Exporting certificate to: $export_file"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] Would export certificate to: $export_file"
    return 0
  fi

  # Create directory if it doesn't exist
  local export_dir
  export_dir=$(dirname "$export_file")
  if [[ ! -d "$export_dir" ]]; then
    if ! mkdir -p "$export_dir"; then
      log_error "Failed to create directory: $export_dir"
      return 1
    fi
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
    if command_exists openssl; then
      openssl x509 -in "$export_file" -text -noout 2>/dev/null | grep -E "(Subject:|Issuer:|Not Before|Not After)" || true
    fi
  fi

  return 0
}

# Detect operating system
detect_os() {
  case "$(uname -s)" in
    Darwin*)
      echo "macos"
      ;;
    Linux*)
      echo "linux"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Show platform-specific installation instructions
show_install_instructions() {
  local cert_path="$1"
  local os_type
  os_type=$(detect_os)

  echo
  echo "=================================================="
  log_info "Platform-specific Installation Instructions"
  echo "=================================================="
  echo

  case "$os_type" in
    macos)
      echo "macOS - Add to System Keychain (requires sudo):"
      echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"$cert_path\""
      echo
      echo "macOS - Add to User Keychain only:"
      echo "  security add-trusted-cert -d -r trustAsRoot -k ~/Library/Keychains/login.keychain-db \"$cert_path\""
      echo
      echo "macOS - GUI method:"
      echo "  1. Double-click: $cert_path"
      echo "  2. In Keychain Access, find the certificate"
      echo "  3. Double-click > Trust > Always Trust"
      ;;
    linux)
      echo "Linux (Ubuntu/Debian) - System-wide trust:"
      echo "  sudo cp \"$cert_path\" /usr/local/share/ca-certificates/vault-ca.crt"
      echo "  sudo update-ca-certificates"
      echo
      echo "Linux (RHEL/CentOS/Fedora) - System-wide trust:"
      echo "  sudo cp \"$cert_path\" /etc/pki/ca-trust/source/anchors/vault-ca.crt"
      echo "  sudo update-ca-trust"
      ;;
    *)
      echo "Unknown OS - Manual installation required"
      echo "Refer to your operating system's documentation for importing CA certificates"
      ;;
  esac

  echo
}

# Show Jenkins-specific CLI usage
show_jenkins_usage() {
  local cert_path="$1"

  echo "=================================================="
  log_info "Jenkins CLI Usage"
  echo "=================================================="
  echo
  echo "After installing the certificate, use Jenkins CLI without --insecure:"
  echo "  java -jar jenkins-cli.jar -s https://jenkins.dev.local.me:32653/ who-am-i"
  echo
  echo "Or specify the CA certificate explicitly:"
  echo "  java -jar jenkins-cli.jar -s https://jenkins.dev.local.me:32653/ \\"
  echo "      -noCertificateCheck -noKeyAuth who-am-i"
  echo
  echo "Web browser access:"
  echo "  https://jenkins.dev.local.me:32653/"
  echo
  echo "API access with curl:"
  echo "  curl --cacert \"$cert_path\" https://jenkins.dev.local.me:32653/api/json"
  echo
}

# Show ArgoCD-specific CLI usage
show_argocd_usage() {
  local cert_path="$1"

  echo "=================================================="
  log_info "ArgoCD CLI Usage"
  echo "=================================================="
  echo
  echo "After installing the certificate, use argocd CLI without --insecure:"
  echo "  argocd login argocd.dev.local.me:32653 --username admin"
  echo
  echo "Or specify the CA certificate explicitly:"
  echo "  argocd login argocd.dev.local.me:32653 --username admin \\"
  echo "      --grpc-web-root-path / --server-crt \"$cert_path\""
  echo
  echo "Verify connection:"
  echo "  argocd version"
  echo "  argocd app list"
  echo
  echo "Web browser access:"
  echo "  https://argocd.dev.local.me:32653/"
  echo
}

# Show generic CLI usage
show_generic_usage() {
  local cert_path="$1"

  echo "=================================================="
  log_info "Generic Usage"
  echo "=================================================="
  echo
  echo "Use the exported CA certificate with any tool that supports custom CA:"
  echo
  echo "curl:"
  echo "  curl --cacert \"$cert_path\" https://your-service.dev.local.me:PORT/"
  echo
  echo "wget:"
  echo "  wget --ca-certificate=\"$cert_path\" https://your-service.dev.local.me:PORT/"
  echo
  echo "Python requests:"
  echo "  import requests"
  echo "  requests.get('https://your-service.dev.local.me:PORT/', verify='$cert_path')"
  echo
  echo "Node.js https:"
  echo "  const https = require('https');"
  echo "  const options = { ca: fs.readFileSync('$cert_path') };"
  echo "  https.get('https://your-service.dev.local.me:PORT/', options, ...);"
  echo
}

# Show service-specific usage instructions
show_service_usage() {
  local cert_path="$1"

  if [[ "$SHOW_ALL_SERVICES" == "1" ]]; then
    show_jenkins_usage "$cert_path"
    echo
    show_argocd_usage "$cert_path"
    echo
    show_generic_usage "$cert_path"
  else
    case "$SERVICE" in
      jenkins)
        show_jenkins_usage "$cert_path"
        ;;
      argocd)
        show_argocd_usage "$cert_path"
        ;;
      generic)
        show_generic_usage "$cert_path"
        ;;
    esac
  fi
}

# Main function
main() {
  # Show help if no arguments provided
  if [[ $# -eq 0 ]]; then
    usage
  fi

  # Parse command-line arguments
  parse_args "$@"

  echo "=================================================="
  if [[ -n "$IMPORT_FILE" ]]; then
    if [[ "$IMPORT_JAVA" == "1" ]]; then
      echo "Certificate Import - Java Truststore"
    elif [[ "$IMPORT_KEYCHAIN" == "1" ]]; then
      echo "Certificate Import - macOS Keychain"
    else
      echo "Certificate Import - File"
    fi
  elif [[ "$IMPORT_JAVA" == "1" ]]; then
    echo "Vault CA Certificate - Java Truststore Import"
  elif [[ "$IMPORT_KEYCHAIN" == "1" ]]; then
    echo "Vault CA Certificate - macOS Keychain Import"
  else
    echo "Vault CA Certificate - Export"
  fi
  echo "=================================================="

  if [[ -n "$IMPORT_FILE" ]]; then
    echo "Import File:     $IMPORT_FILE"
  else
    echo "Vault Namespace: $VAULT_NAMESPACE"
    echo "Vault Pod:       $VAULT_POD"
    echo "PKI Path:        $VAULT_PKI_PATH"
  fi

  if [[ "$IMPORT_JAVA" == "1" ]]; then
    echo "Cert Alias:      $CACERTS_ALIAS"
  elif [[ "$IMPORT_KEYCHAIN" == "1" ]]; then
    echo "Keychain:        System"
  elif [[ -z "$IMPORT_FILE" ]]; then
    echo "Export Path:     $EXPORT_PATH"
  fi

  echo "Service:         $SERVICE"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
  fi
  echo "=================================================="
  echo

  # Validate prerequisites
  if ! validate_prerequisites; then
    return 1
  fi

  # Handle certificate source (import from file OR extract from Vault)
  if [[ -n "$IMPORT_FILE" ]]; then
    # Import mode: validate and load from file
    log_info "Loading certificate from file: $IMPORT_FILE"

    if ! validate_import_file "$IMPORT_FILE"; then
      return 1
    fi

    # Copy to temp location for processing
    if ! cp "$IMPORT_FILE" "$TEMP_CERT"; then
      log_error "Failed to load certificate from: $IMPORT_FILE"
      return 1
    fi

    log_success "Certificate loaded from file"
  else
    # Vault mode: check access and extract
    if ! check_vault_access; then
      return 1
    fi

    if ! extract_vault_ca; then
      return 1
    fi
  fi

  # Java truststore import mode
  if [[ "$IMPORT_JAVA" == "1" ]]; then
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
          show_java_cert_details "$cacerts_path"
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
    show_java_cert_details "$cacerts_path"

    echo
    echo "=================================================="
    log_success "Java Truststore Import Complete!"
    echo "=================================================="

    if [[ "$DRY_RUN" != "1" ]]; then
      echo
      echo "You can now use Jenkins CLI without -noCertificateCheck:"
      echo "  java -jar jenkins-cli.jar -s https://jenkins.dev.local.me -auth user:pass version"
    fi

    return 0
  fi

  # macOS Keychain import mode
  if [[ "$IMPORT_KEYCHAIN" == "1" ]]; then
    if ! import_to_keychain "$TEMP_CERT"; then
      return 1
    fi

    echo
    echo "=================================================="
    log_success "macOS Keychain Import Complete!"
    echo "=================================================="

    if [[ "$DRY_RUN" != "1" ]]; then
      echo
      echo "The Vault CA certificate has been imported to System Keychain."
      echo "Applications and browsers will now trust certificates issued by Vault."
      echo
      echo "You may need to restart browsers or applications for changes to take effect."
    fi

    return 0
  fi

  # Export mode (default)
  # Export certificate
  if ! export_certificate "$EXPORT_PATH"; then
    return 1
  fi

  echo
  echo "=================================================="
  log_success "Certificate Export Complete!"
  echo "=================================================="
  echo
  echo "Certificate saved to: $EXPORT_PATH"

  return 0
}

# Run main function
main "$@"
