#!/usr/bin/env bash
set -euo pipefail

# Jenkins Smoke Test - SSL/TLS and Authentication Validation
# Usage: smoke-test-jenkins.sh [namespace] [host] [port] [auth_mode]
#
# Environment Variables:
#   VERBOSE=1              - Enable verbose/debug output
#   AD_TEST_USER=username  - AD username for production AD testing
#   AD_TEST_PASS=password  - AD password for production AD testing
#
# Examples:
#   ./smoke-test-jenkins.sh                                    # Default auth
#   ./smoke-test-jenkins.sh jenkins jenkins.dev.local.me 443 ldap  # LDAP auth
#   AD_TEST_USER=john.doe AD_TEST_PASS=secret ./smoke-test-jenkins.sh jenkins jenkins.example.com 443 ad

# Source vault plugin for _vault_exec helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../scripts/plugins/vault.sh" ]]; then
  # Source system.sh first for _kubectl helper
  source "${SCRIPT_DIR}/../scripts/lib/system.sh" 2>/dev/null || true
  source "${SCRIPT_DIR}/../scripts/plugins/vault.sh" 2>/dev/null || true
fi

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

  log_info "Testing authentication with Jenkins admin user: $admin_user"

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
    log_pass "Authentication successful with admin user '$admin_user' (HTTP $http_code)"
    return 0
  else
    log_fail "Authentication failed with admin user '$admin_user' (HTTP $http_code)"
    if [[ "$VERBOSE" == "1" ]]; then
      echo "$response" | head -20
    fi
    verbose "This may indicate:"
    verbose "  - Jenkins admin password incorrect or changed"
    verbose "  - Jenkins not fully initialized"
    verbose "  - CSRF protection or security realm misconfiguration"
    return 1
  fi
}

test_login_ldap() {
  log_info "Testing LDAP authentication..."

  if [[ -z "$IP" ]]; then
    log_fail "IP address not available (run connectivity test first)"
    return 1
  fi

  # Get LDAP credentials from K8s secret
  local ldap_user ldap_pass
  ldap_user=$(kubectl -n directory get secret openldap-admin \
    -o jsonpath='{.data.LDAP_ADMIN_USERNAME}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  ldap_pass=$(kubectl -n directory get secret openldap-admin \
    -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

  if [[ -z "$ldap_user" ]] || [[ -z "$ldap_pass" ]]; then
    log_skip "LDAP credentials not found (directory namespace may not be deployed)"
    return 0
  fi

  # Verify LDAP connectivity and check for users
  verbose "Testing LDAP server connectivity..."
  local pf_pid
  kubectl -n directory port-forward svc/openldap-openldap-bitnami 3389:389 \
    >/tmp/ldap-pf-$$.log 2>&1 &
  pf_pid=$!

  # Add to cleanup
  trap "kill $pf_pid 2>/dev/null || true; rm -f /tmp/ldap-pf-$$.log; rm -f \"$TEMP_CERT\"" EXIT

  sleep 2

  if ! LDAPTLS_REQCERT=never ldapsearch -x \
       -H "ldap://127.0.0.1:3389" \
       -D "cn=$ldap_user,dc=home,dc=org" \
       -w "$ldap_pass" \
       -b "dc=home,dc=org" -LLL >/dev/null 2>&1; then
    log_fail "LDAP server unreachable"
    kill $pf_pid 2>/dev/null || true
    return 1
  fi

  verbose "LDAP server connectivity: OK"

  # Check if any users exist in the directory
  local user_count search_result
  search_result=$(LDAPTLS_REQCERT=never ldapsearch -x \
    -H "ldap://127.0.0.1:3389" \
    -D "cn=$ldap_user,dc=home,dc=org" \
    -w "$ldap_pass" \
    -b "dc=home,dc=org" \
    "(objectClass=person)" dn 2>/dev/null || echo "")

  user_count=$(echo "$search_result" | grep -c "^dn:" || echo "0")
  user_count=$(echo "$user_count" | tr -d '\n')

  verbose "Found $user_count users in LDAP directory"

  if [[ "$user_count" -eq 0 ]]; then
    log_skip "No users found in LDAP directory (use --enable-ad for test users)"
    kill $pf_pid 2>/dev/null || true
    return 0
  fi

  # Try to find a test user
  # Basic LDAP users: chengkai.liang, jenkins-admin, test-user (from bootstrap-basic-schema.ldif)
  # AD users: alice, bob, jenkins-svc (from bootstrap-ad-schema.ldif)
  local test_user test_pass directory_type
  test_user=""
  test_pass=""
  directory_type=""

  # First try basic LDAP users (using cn attribute)
  log_info "Searching for basic LDAP test users..."
  for user in chengkai.liang jenkins-admin test-user; do
    if LDAPTLS_REQCERT=never ldapsearch -x \
         -H "ldap://127.0.0.1:3389" \
         -D "cn=$ldap_user,dc=home,dc=org" \
         -w "$ldap_pass" \
         -b "dc=home,dc=org" \
         "(cn=$user)" dn 2>/dev/null | grep -q "^dn:"; then
      test_user="$user"
      directory_type="basic LDAP"
      verbose "Found basic LDAP test user: $test_user"
      break
    fi
  done

  # If no basic LDAP users found, try AD users (using sAMAccountName attribute)
  if [[ -z "$test_user" ]]; then
    log_info "No basic LDAP users found, searching for AD test users..."
    for user in alice bob jenkins-svc; do
      if LDAPTLS_REQCERT=never ldapsearch -x \
           -H "ldap://127.0.0.1:3389" \
           -D "cn=$ldap_user,dc=home,dc=org" \
           -w "$ldap_pass" \
           -b "dc=home,dc=org" \
           "(sAMAccountName=$user)" dn 2>/dev/null | grep -q "^dn:"; then
        test_user="$user"
        directory_type="Active Directory"
        verbose "Found AD test user: $test_user"
        break
      fi
    done
  fi

  kill $pf_pid 2>/dev/null || true

  if [[ -z "$test_user" ]]; then
    log_skip "No known test users found in LDAP directory"
    verbose "Expected users - Basic LDAP: chengkai.liang, jenkins-admin, test-user"
    verbose "Expected users - Active Directory: alice, bob, jenkins-svc"
    return 0
  fi

  log_info "Detected directory type: $directory_type"

  # Retrieve password from Vault for basic LDAP users
  # (AD users use the default "test1234" password from LDIF)
  if [[ "$directory_type" == "basic LDAP" ]]; then
    verbose "Retrieving password from Vault for user: $test_user"
    local vault_path="ldap/users/${test_user}"

    # Check if _vault_exec is available
    if type _vault_exec &>/dev/null; then
      # Use _vault_exec helper function
      test_pass=$(_vault_exec --no-exit vault kv get -field=password "secret/$vault_path" 2>/dev/null) || test_pass=""
    else
      # Fallback: try direct kubectl exec (less reliable)
      verbose "Warning: _vault_exec not available, using fallback method"
      test_pass=$(kubectl exec -n vault vault-0 -- sh -c \
        'vault kv get -field=password "secret/'"$vault_path"'"' 2>/dev/null) || test_pass=""
    fi

    if [[ -z "$test_pass" ]]; then
      log_skip "Unable to retrieve password from Vault for user: $test_user"
      verbose "Vault path: secret/$vault_path"
      verbose "This may indicate Vault is not configured or user password not set"
      return 0
    fi
    verbose "Successfully retrieved password from Vault"
  else
    # AD users use the default password from LDIF
    test_pass="test1234"
  fi

  log_info "Testing authentication with user: $test_user"

  # Test Jenkins login with LDAP credentials
  local http_code response
  response=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    -u "$test_user:$test_pass" \
    -w "\n%{http_code}" \
    "https://$HOST:$PORT/api/json" 2>/dev/null || echo "")

  http_code=$(echo "$response" | tail -1)
  verbose "HTTP response code: $http_code"

  if [[ "$http_code" == "200" ]]; then
    log_pass "Authentication successful with $directory_type user '$test_user' (HTTP $http_code)"
    return 0
  else
    log_fail "Authentication failed with $directory_type user '$test_user' (HTTP $http_code)"
    if [[ "$VERBOSE" == "1" ]]; then
      echo "$response" | head -20
    fi
    verbose "This may indicate:"
    verbose "  - Jenkins LDAP configuration not enabled"
    verbose "  - Password hash mismatch in bootstrap LDIF"
    verbose "  - LDAP bind DN format mismatch"
    return 1
  fi
}

test_login_ad() {
  log_info "Testing Active Directory authentication..."

  if [[ -z "$IP" ]]; then
    log_fail "IP address not available (run connectivity test first)"
    return 1
  fi

  # Detect deployment type: mock AD vs production AD
  local deployment_type
  if kubectl get namespace directory &>/dev/null; then
    # Directory namespace exists - but are we testing local or external Jenkins?
    local local_jenkins_host
    local_jenkins_host=$(kubectl -n istio-system get vs jenkins -o jsonpath='{.spec.hosts[0]}' 2>/dev/null || echo "")

    # Check if target host matches local Jenkins deployment
    if [[ "$HOST" == "$local_jenkins_host" ]] || [[ "$HOST" == "jenkins.dev.local.me" ]]; then
      deployment_type="mock AD"
      log_info "Detected mock AD deployment (test environment)"
    else
      deployment_type="production AD"
      log_info "Detected production AD deployment (external directory)"
      verbose "Testing external host '$HOST' (local Jenkins is at '$local_jenkins_host')"
    fi
  else
    deployment_type="production AD"
    log_info "Detected production AD deployment (external directory)"
  fi

  # Get AD credentials: prioritize env vars, then K8s secret
  local ad_user ad_pass
  ad_user="${AD_TEST_USER:-}"
  ad_pass="${AD_TEST_PASS:-}"

  # If env vars not provided, try to get from K8s secret
  if [[ -z "$ad_user" ]] || [[ -z "$ad_pass" ]]; then
    ad_user=$(kubectl -n "$NAMESPACE" get secret ad-service-account \
      -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    ad_pass=$(kubectl -n "$NAMESPACE" get secret ad-service-account \
      -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  fi

  if [[ -z "$ad_user" ]] || [[ -z "$ad_pass" ]]; then
    log_skip "AD credentials not found"
    if [[ "$deployment_type" == "production AD" ]]; then
      verbose "For production AD testing, set AD_TEST_USER and AD_TEST_PASS environment variables"
      verbose "Example: AD_TEST_USER=\"john.doe\" AD_TEST_PASS=\"secret\" $0"
    fi
    return 0
  fi

  log_info "Testing authentication with AD user: $ad_user"

  # Test Jenkins login with AD credentials
  local http_code response
  response=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    -u "$ad_user:$ad_pass" \
    -w "\n%{http_code}" \
    "https://$HOST:$PORT/api/json" 2>/dev/null || echo "")

  http_code=$(echo "$response" | tail -1)
  verbose "HTTP response code: $http_code"

  if [[ "$http_code" == "200" ]]; then
    log_pass "Authentication successful with $deployment_type user '$ad_user' (HTTP $http_code)"
    return 0
  else
    log_fail "Authentication failed with $deployment_type user '$ad_user' (HTTP $http_code)"
    if [[ "$VERBOSE" == "1" ]]; then
      echo "$response" | head -20
    fi
    verbose "This may indicate:"
    verbose "  - Jenkins AD configuration not enabled or misconfigured"
    verbose "  - AD user credentials incorrect"
    verbose "  - AD group membership issues"
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
    ldap)
      test_login_ldap || true
      ;;
    ad)
      test_login_ad || true
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
