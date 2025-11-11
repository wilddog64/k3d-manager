#!/usr/bin/env bash
set -euo pipefail

# Jenkins Smoke Test - SSL/TLS and Authentication Validation
# Usage: smoke-test-jenkins.sh [namespace] [host] [port] [auth_mode]

# Parameters
NAMESPACE="${1:-jenkins}"
HOST="${2:-jenkins.dev.local.me}"
PORT="${3:-443}"
AUTH_MODE="${4:-default}"  # default|ldap|ad
VERBOSE="${VERBOSE:-0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Shared variables
IP=""
TEMP_CERT="/tmp/jenkins-smoke-$$.crt"

# Cleanup function
cleanup() {
  rm -f "$TEMP_CERT" /tmp/ldap-pf.log
}
trap cleanup EXIT

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((TESTS_FAILED++))
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_skip() {
  echo -e "${YELLOW}[SKIP]${NC} $*"
  ((TESTS_SKIPPED++))
}

verbose() {
  if [[ "$VERBOSE" == "1" ]]; then
    echo -e "${BLUE}[DEBUG]${NC} $*"
  fi
}

# ============================================================================
# SSL/TLS Testing Functions
# ============================================================================

test_ssl_connectivity() {
  log_info "Testing HTTPS connectivity to $HOST:$PORT..."

  # Get istio-ingressgateway IP
  IP=$(kubectl get -n istio-system service istio-ingressgateway \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

  if [[ -z "$IP" ]]; then
    log_fail "Could not get istio-ingressgateway IP"
    return 1
  fi

  verbose "Using ingress IP: $IP"

  # Test TLS handshake
  if openssl s_client -servername "$HOST" -connect "$IP:$PORT" \
       </dev/null 2>/dev/null | grep -q "CONNECTED"; then
    verbose "TLS connection established successfully"
  else
    log_fail "TLS connection failed"
    return 1
  fi

  # Check verification status (informational only, self-signed certs expected)
  local verify_output
  verify_output=$(openssl s_client -servername "$HOST" -connect "$IP:$PORT" \
    </dev/null 2>&1 | grep "Verify return code" || echo "")

  if [[ "$verify_output" =~ "Verify return code: 0" ]]; then
    verbose "Certificate verification: OK (trusted)"
  else
    verbose "Certificate verification: self-signed (expected)"
    verbose "$verify_output"
  fi

  log_pass "TLS connection established to $HOST:$PORT"
  return 0
}

test_ssl_certificate_validity() {
  log_info "Validating certificate properties..."

  if [[ -z "$IP" ]]; then
    log_fail "IP address not available (run connectivity test first)"
    return 1
  fi

  # Extract live certificate
  if ! openssl s_client -showcerts -servername "$HOST" -connect "$IP:$PORT" \
       </dev/null 2>/dev/null \
       | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' \
       | head -n 100 > "$TEMP_CERT"; then
    log_fail "Failed to extract certificate"
    return 1
  fi

  if [[ ! -s "$TEMP_CERT" ]]; then
    log_fail "Certificate file is empty"
    return 1
  fi

  verbose "Certificate extracted to $TEMP_CERT"

  # Verify CN/SAN matches expected host
  local subject san
  subject=$(openssl x509 -in "$TEMP_CERT" -noout -subject 2>/dev/null || echo "")
  san=$(openssl x509 -in "$TEMP_CERT" -noout -ext subjectAltName 2>/dev/null || echo "")

  verbose "Subject: $subject"
  verbose "SAN: $san"

  if [[ "$subject" =~ $HOST ]] || [[ "$san" =~ $HOST ]]; then
    log_pass "Certificate matches expected host: $HOST"
  else
    log_fail "Certificate mismatch - expected $HOST"
    echo "  Subject: $subject"
    echo "  SAN: $san"
    return 1
  fi

  # Check expiration
  local not_after
  not_after=$(openssl x509 -in "$TEMP_CERT" -noout -enddate 2>/dev/null | cut -d= -f2)
  verbose "Certificate expires: $not_after"

  if openssl x509 -in "$TEMP_CERT" -noout -checkend 86400 2>/dev/null; then
    verbose "Certificate valid for >24 hours"
  else
    log_warn "Certificate expires within 24 hours"
  fi

  # Display certificate fingerprint
  local fingerprint
  fingerprint=$(openssl x509 -in "$TEMP_CERT" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  verbose "SHA256 Fingerprint: $fingerprint"

  return 0
}

test_ssl_pinning() {
  log_info "Testing certificate pinning..."

  if [[ -z "$IP" ]]; then
    log_fail "IP address not available (run connectivity test first)"
    return 1
  fi

  # Generate pin from live endpoint
  local pin
  pin=$(openssl s_client -servername "$HOST" -connect "$IP:$PORT" \
    </dev/null 2>/dev/null \
    | openssl x509 -pubkey -noout \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary | base64)

  if [[ -z "$pin" ]]; then
    log_fail "Failed to generate certificate pin"
    return 1
  fi

  verbose "Certificate pin: sha256//$pin"

  # Verify curl with pinning succeeds
  local http_code
  http_code=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    --pinnedpubkey "sha256//$pin" \
    -w "%{http_code}" -o /dev/null \
    "https://$HOST:$PORT/login" 2>/dev/null || echo "000")

  verbose "HTTP response code: $http_code"

  if [[ "$http_code" =~ ^[23] ]]; then
    log_pass "Certificate pinning validated (HTTP $http_code)"
    return 0
  else
    log_fail "Certificate pinning failed (HTTP $http_code)"
    return 1
  fi
}

# ============================================================================
# Authentication Testing Functions
# ============================================================================

test_login_default_auth() {
  log_info "Testing default authentication..."

  if [[ -z "$IP" ]]; then
    log_fail "IP address not available (run connectivity test first)"
    return 1
  fi

  # Get credentials from K8s secret
  local admin_user admin_pass
  admin_user=$(kubectl -n "$NAMESPACE" get secret jenkins-admin \
    -o jsonpath='{.data.jenkins-admin-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  admin_pass=$(kubectl -n "$NAMESPACE" get secret jenkins-admin \
    -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

  if [[ -z "$admin_user" ]] || [[ -z "$admin_pass" ]]; then
    log_fail "Could not retrieve Jenkins admin credentials from secret jenkins-admin"
    return 1
  fi

  verbose "Using admin user: $admin_user"

  # First try: Get crumb for CSRF protection
  local crumb crumb_field
  crumb=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    -u "$admin_user:$admin_pass" \
    "https://$HOST:$PORT/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" 2>/dev/null || echo "")

  if [[ -n "$crumb" ]]; then
    verbose "Got crumb: ${crumb:0:30}..."
    crumb_field="-H"
    crumb_header="$crumb"
  else
    verbose "No crumb required or crumb fetch failed"
    crumb_field=""
    crumb_header=""
  fi

  # Test login via Jenkins API with crumb if available
  local http_code response
  if [[ -n "$crumb_header" ]]; then
    response=$(curl -sk --max-time 10 \
      --resolve "$HOST:$PORT:$IP" \
      -u "$admin_user:$admin_pass" \
      -H "$crumb_header" \
      -w "\n%{http_code}" \
      "https://$HOST:$PORT/api/json" 2>/dev/null || echo "")
  else
    response=$(curl -sk --max-time 10 \
      --resolve "$HOST:$PORT:$IP" \
      -u "$admin_user:$admin_pass" \
      -w "\n%{http_code}" \
      "https://$HOST:$PORT/api/json" 2>/dev/null || echo "")
  fi

  http_code=$(echo "$response" | tail -1)
  verbose "HTTP response code: $http_code"

  if [[ "$http_code" == "200" ]]; then
    log_pass "Default authentication successful (HTTP $http_code)"
    return 0
  else
    log_fail "Default authentication failed (HTTP $http_code)"
    if [[ "$VERBOSE" == "1" ]]; then
      echo "$response" | head -20
    fi
    return 1
  fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
  echo "=========================================="
  echo "Jenkins Smoke Test"
  echo "=========================================="
  echo "Namespace:  $NAMESPACE"
  echo "Host:       $HOST"
  echo "Port:       $PORT"
  echo "Auth Mode:  $AUTH_MODE"
  echo "=========================================="
  echo

  # Phase 1: SSL/TLS Testing
  echo "=== SSL/TLS Tests ==="
  echo

  test_ssl_connectivity || true
  test_ssl_certificate_validity || true
  test_ssl_pinning || true

  echo
  # Phase 2: Authentication Testing
  echo "=== Authentication Tests ==="
  echo

  case "$AUTH_MODE" in
    default)
      test_login_default_auth || true
      ;;
    ldap|ad)
      log_skip "LDAP/AD authentication (Phase 3 - not yet implemented)"
      ;;
    *)
      log_warn "Unknown auth mode: $AUTH_MODE (defaulting to default auth test)"
      test_login_default_auth || true
      ;;
  esac

  echo
  echo "=========================================="
  echo "Test Summary"
  echo "=========================================="
  echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED"
  echo -e "${RED}Failed:${NC}  $TESTS_FAILED"
  echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
  echo "=========================================="

  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  fi

  exit 0
}

# Run main function
main "$@"
