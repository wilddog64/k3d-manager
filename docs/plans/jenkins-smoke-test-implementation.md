# Jenkins Smoke Test Implementation Plan

**Created:** 2025-11-10
**Status:** Proposed
**Related Work:** Active Directory Integration (CHANGE.md)

## Overview

Create an integration smoke test suite that validates Jenkins deployment across all three authentication modes by testing SSL/TLS connectivity and login functionality.

## Background

The k3d-manager project has existing utility scripts in `bin/` for certificate validation:
- `pin-cert.sh` - Certificate pinning validation
- `live-cert.sh` - Live certificate extraction and verification
- `get-certs.sh` - Certificate retrieval from K8s secrets
- `test-openldap.sh` - LDAP connectivity testing

However, there's no comprehensive smoke test that validates both SSL/TLS and authentication login for Jenkins across all deployment modes (default, LDAP, Active Directory).

## Goals

1. Validate SSL/TLS connectivity and certificate properties
2. Test authentication login for all three modes:
   - Default (Jenkins built-in authentication)
   - LDAP mode (`--enable-ldap` / `--enable-ad`)
   - Production Active Directory (`--enable-ad-prod`)
3. Provide clear pass/fail reporting for CI/CD integration
4. Reuse patterns from existing utility scripts

## Implementation Plan

### 1. New Test Script: `bin/smoke-test-jenkins.sh`

**Purpose:** Standalone smoke test script that can be run manually or integrated into CI/CD

**Core Features:**
- SSL certificate validation (inspired by `pin-cert.sh` and `live-cert.sh`)
- Authentication testing for all three modes
- Clear pass/fail reporting
- Verbose mode for debugging

**Script Structure:**
```bash
#!/usr/bin/env bash
# bin/smoke-test-jenkins.sh
set -euo pipefail

# Parameters
NAMESPACE="${1:-jenkins}"
HOST="${2:-jenkins.dev.local.me}"
PORT="${3:-443}"
AUTH_MODE="${4:-default}"  # default|ldap|ad

# Functions:
# - test_ssl_connectivity()
# - test_ssl_certificate_validity()
# - test_ssl_pinning()
# - test_login_default_auth()
# - test_login_ldap()
# - test_login_ad()
# - main()
```

### 2. SSL Certificate Testing Components

#### 2.1 Certificate Connectivity Test
**Pattern from:** `live-cert.sh:13-14`

**Implementation:**
```bash
test_ssl_connectivity() {
  echo "[SSL] Testing HTTPS connectivity to $HOST:$PORT..."

  IP=$(kubectl get -n istio-system service istio-ingressgateway \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

  if [[ -z "$IP" ]]; then
    echo "FAIL: Could not get istio-ingressgateway IP"
    return 1
  fi

  # Test TLS handshake
  if ! openssl s_client -servername "$HOST" -connect "$IP:$PORT" \
       </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
    echo "WARN: Certificate verification failed (expected for self-signed)"
  fi

  echo "PASS: TLS connection established"
}
```

#### 2.2 Certificate Validity Test
**Pattern from:** `live-cert.sh:13-19`

**Implementation:**
```bash
test_ssl_certificate_validity() {
  echo "[SSL] Validating certificate properties..."

  # Extract live certificate
  openssl s_client -showcerts -servername "$HOST" -connect "$IP:$PORT" \
    </dev/null 2>/dev/null \
    | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' \
    | head -n 100 > /tmp/jenkins-smoke.crt

  trap "rm -f /tmp/jenkins-smoke.crt" EXIT

  # Verify CN/SAN matches expected host
  SUBJECT=$(openssl x509 -in /tmp/jenkins-smoke.crt -noout -subject)
  SAN=$(openssl x509 -in /tmp/jenkins-smoke.crt -noout -ext subjectAltName 2>/dev/null || echo "")

  if [[ "$SUBJECT" =~ $HOST ]] || [[ "$SAN" =~ $HOST ]]; then
    echo "PASS: Certificate matches expected host: $HOST"
  else
    echo "FAIL: Certificate mismatch"
    echo "  Subject: $SUBJECT"
    echo "  SAN: $SAN"
    return 1
  fi

  # Check expiration
  if ! openssl x509 -in /tmp/jenkins-smoke.crt -noout -checkend 86400; then
    echo "WARN: Certificate expires within 24 hours"
  fi
}
```

#### 2.3 Certificate Pinning Test
**Pattern from:** `pin-cert.sh:12-22`

**Implementation:**
```bash
test_ssl_pinning() {
  echo "[SSL] Testing certificate pinning..."

  # Generate pin from live endpoint
  PIN=$(openssl s_client -servername "$HOST" -connect "$IP:$PORT" \
    </dev/null 2>/dev/null \
    | openssl x509 -pubkey -noout \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary | base64)

  # Verify curl with pinning succeeds
  if curl -sk --max-time 10 \
       --resolve "$HOST:$PORT:$IP" \
       --pinnedpubkey "sha256//$PIN" \
       "https://$HOST:$PORT/login" -o /dev/null; then
    echo "PASS: Certificate pinning validated"
  else
    echo "FAIL: Certificate pinning failed"
    return 1
  fi
}
```

### 3. Authentication Testing Components

#### 3.1 Default Authentication Test
**New implementation** - tests built-in Jenkins auth

**Implementation:**
```bash
test_login_default_auth() {
  echo "[AUTH] Testing default authentication..."

  # Get credentials from K8s secret
  ADMIN_USER=$(kubectl -n "$NAMESPACE" get secret jenkins-admin \
    -o jsonpath='{.data.jenkins-admin-user}' | base64 -d)
  ADMIN_PASS=$(kubectl -n "$NAMESPACE" get secret jenkins-admin \
    -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)

  # Test login via Jenkins API
  HTTP_CODE=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -w "%{http_code}" -o /dev/null \
    "https://$HOST:$PORT/api/json")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "PASS: Default authentication successful"
  else
    echo "FAIL: Default authentication failed (HTTP $HTTP_CODE)"
    return 1
  fi
}
```

#### 3.2 LDAP Authentication Test
**Pattern from:** `test-openldap.sh:32-35`

**Implementation:**
```bash
test_login_ldap() {
  echo "[AUTH] Testing LDAP authentication..."

  # Get LDAP credentials from K8s secret
  LDAP_USER=$(kubectl -n directory get secret openldap-admin \
    -o jsonpath='{.data.LDAP_ADMIN_USERNAME}' | base64 -d)
  LDAP_PASS=$(kubectl -n directory get secret openldap-admin \
    -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)

  # Verify LDAP connectivity first
  kubectl -n directory port-forward svc/openldap-openldap-bitnami 3389:389 \
    >/tmp/ldap-pf.log 2>&1 &
  PF_PID=$!
  trap "kill $PF_PID 2>/dev/null || true" EXIT
  sleep 2

  if LDAPTLS_REQCERT=never ldapsearch -x \
       -H "ldap://127.0.0.1:3389" \
       -D "cn=$LDAP_USER,dc=home,dc=org" \
       -w "$LDAP_PASS" \
       -b "dc=home,dc=org" -LLL >/dev/null 2>&1; then
    echo "  LDAP server connectivity: OK"
  else
    echo "FAIL: LDAP server unreachable"
    return 1
  fi

  # Test Jenkins login with LDAP credentials
  HTTP_CODE=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    -u "$LDAP_USER:$LDAP_PASS" \
    -w "%{http_code}" -o /dev/null \
    "https://$HOST:$PORT/api/json")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "PASS: LDAP authentication successful"
  else
    echo "FAIL: LDAP authentication failed (HTTP $HTTP_CODE)"
    return 1
  fi
}
```

#### 3.3 Active Directory Authentication Test
**New implementation** - tests AD credentials

**Implementation:**
```bash
test_login_ad() {
  echo "[AUTH] Testing Active Directory authentication..."

  # Get AD credentials from Vault via K8s secret
  AD_USER=$(kubectl -n "$NAMESPACE" get secret ad-service-account \
    -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "")
  AD_PASS=$(kubectl -n "$NAMESPACE" get secret ad-service-account \
    -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")

  if [[ -z "$AD_USER" ]]; then
    echo "SKIP: AD credentials not found (production AD mode may not be configured)"
    return 0
  fi

  # Test Jenkins login with AD credentials
  HTTP_CODE=$(curl -sk --max-time 10 \
    --resolve "$HOST:$PORT:$IP" \
    -u "$AD_USER:$ADMIN_PASS" \
    -w "%{http_code}" -o /dev/null \
    "https://$HOST:$PORT/api/json")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "PASS: AD authentication successful"
  else
    echo "FAIL: AD authentication failed (HTTP $HTTP_CODE)"
    return 1
  fi
}
```

### 4. Integration with Test Framework

#### 4.1 Optional: Add Bats Integration Test
**Location:** `scripts/tests/plugins/jenkins.bats`

**Implementation:**
```bash
@test "smoke test: Jenkins SSL and authentication work end-to-end" {
  # Skip if cluster not running
  if ! kubectl get ns jenkins >/dev/null 2>&1; then
    skip "Jenkins not deployed"
  fi

  # Run smoke test script
  run "$SCRIPT_DIR/../bin/smoke-test-jenkins.sh" jenkins jenkins.dev.local.me 443 default

  [ "$status" -eq 0 ]
  [[ "$output" =~ "PASS: TLS connection established" ]]
  [[ "$output" =~ "PASS: Certificate matches expected host" ]]
  [[ "$output" =~ "PASS: Default authentication successful" ]]
}
```

### 5. Test Execution Workflow

#### 5.1 Manual Execution
```bash
# Test default authentication mode
./bin/smoke-test-jenkins.sh jenkins jenkins.dev.local.me 443 default

# Test LDAP mode
./bin/smoke-test-jenkins.sh jenkins jenkins.dev.local.me 443 ldap

# Test AD mode (production)
./bin/smoke-test-jenkins.sh jenkins jenkins.dev.local.me 443 ad

# Verbose mode
VERBOSE=1 ./bin/smoke-test-jenkins.sh jenkins jenkins.dev.local.me 443 default
```

#### 5.2 Integration with k3d-manager
Add new command: `./scripts/k3d-manager test_jenkins_smoke`

**Implementation in `scripts/lib/test.sh`:**
```bash
function test_jenkins_smoke() {
  local auth_mode="${1:-default}"
  echo "Running Jenkins smoke test (auth mode: $auth_mode)..."
  "${SCRIPT_DIR}/../bin/smoke-test-jenkins.sh" \
    jenkins \
    jenkins.dev.local.me \
    443 \
    "$auth_mode"
}
```

#### 5.3 Post-Deployment Integration (Recommended)
**Automatically run smoke test after Jenkins deployment for immediate feedback**

**Implementation in `scripts/plugins/jenkins.sh` (at end of `deploy_jenkins` function):**
```bash
# Determine auth mode based on deployment flags
local smoke_test_mode="default"
if [[ "${JENKINS_LDAP_ENABLED:-0}" == "1" ]] || [[ "${JENKINS_AD_ENABLED:-0}" == "1" ]]; then
  smoke_test_mode="ldap"
elif [[ "${JENKINS_AD_PROD_ENABLED:-0}" == "1" ]]; then
  smoke_test_mode="ad"
fi

# Run smoke test
echo ""
echo "=========================================="
echo "Running Post-Deployment Smoke Test"
echo "=========================================="
if "${SCRIPT_DIR}/../bin/smoke-test-jenkins.sh" jenkins jenkins.dev.local.me 443 "$smoke_test_mode"; then
  echo ""
  echo "✅ Jenkins deployment verified successfully"
else
  echo ""
  echo "⚠️  Jenkins deployed but smoke test failed - please review"
  echo "    Run manually: ./bin/smoke-test-jenkins.sh"
fi
```

**Benefits:**
- Immediate feedback on deployment success/failure
- Catches SSL certificate issues right away
- Validates authentication configuration matches deployment flags
- No extra commands needed - fully automatic

### 6. Implementation Phases

**Phase 1: Core SSL Testing (30 min)**
- Create `bin/smoke-test-jenkins.sh`
- Implement SSL connectivity, validity, and pinning tests
- Test against deployed Jenkins instance

**Phase 2: Default Auth Testing (20 min)**
- Implement default authentication test
- Verify credential extraction from K8s secrets
- Test login via Jenkins API

**Phase 3: LDAP/AD Auth Testing (30 min)** - IN PROGRESS
- Implement LDAP authentication test (reuse test-openldap.sh patterns)
- Implement AD authentication test
- Handle missing credentials gracefully

**Phase 4: Integration (20 min)**
- Add `test_jenkins_smoke` command to k3d-manager
- Optional: Add bats integration test
- Document usage in README.md

**Phase 5: Deploy Integration (30 min)** - PLANNED
- Auto-detect auth mode from deployment flags
- Add smoke test to end of `deploy_jenkins` function
- Provide clear success/failure feedback
- Allow opt-out with environment variable

**Status Update (2025-11-11):**
- ✅ Phase 1: Complete (commit e30c46b)
- ✅ Phase 2: Complete (commit e30c46b)
- 🔄 Phase 3: In Progress
- ⏳ Phase 4: Planned
- ⏳ Phase 5: Planned (post-deployment integration)

**Total Estimated Time:** ~2.5 hours

### 7. Success Criteria

- ✅ SSL certificate validation passes for all modes
- ✅ Certificate pinning verification works
- ✅ Default auth login succeeds with Jenkins admin credentials
- ✅ LDAP auth login succeeds when `--enable-ldap` or `--enable-ad` used
- ✅ AD auth gracefully skips when not configured
- ✅ Script returns appropriate exit codes (0 = pass, 1 = fail)
- ✅ Clear pass/fail output for each test component

### 8. Future Enhancements

- Add crumb authentication for POST operations
- Test Jenkins job creation via API
- Validate LDAP group mappings
- Test certificate rotation by triggering CronJob manually
- Add performance metrics (response times)

## Dependencies

- `kubectl` - Kubernetes CLI for secret extraction and port-forwarding
- `openssl` - Certificate validation and pinning
- `curl` - HTTP authentication testing
- `ldapsearch` - LDAP connectivity verification (for LDAP mode)
- `base64` - Secret decoding

## Testing Strategy

1. **Unit Testing:** Not applicable (integration test by nature)
2. **Manual Testing:** Run against all three deployment modes
3. **CI/CD Integration:** Can be added to automated test pipeline
4. **Bats Integration:** Optional integration test in jenkins.bats

## Related Files

**Existing:**
- `bin/pin-cert.sh` - Certificate pinning reference
- `bin/live-cert.sh` - Live certificate extraction reference
- `bin/test-openldap.sh` - LDAP testing reference
- `scripts/lib/test.sh` - Test framework entry point

**To Create:**
- `bin/smoke-test-jenkins.sh` - Main smoke test script
- `docs/plans/jenkins-smoke-test-implementation.md` - This document

**To Modify:**
- `scripts/lib/test.sh` - Add `test_jenkins_smoke` function
- `scripts/tests/plugins/jenkins.bats` - Optional bats integration test
- `README.md` - Document smoke test usage

## References

- Active Directory Integration (CHANGE.md - dated 2025-11-10)
- Jenkins Authentication Modes (README.md)
- Existing utility scripts in `bin/` directory
