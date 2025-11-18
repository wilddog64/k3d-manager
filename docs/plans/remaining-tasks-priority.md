# Remaining Tasks - Prioritized

**Date**: 2025-11-17
**Status**: Active Directory Implementation - Final Phase

---

## Priority 1: Critical - Validation & Testing (4-6 hours)

### 1.1 Certificate Rotation Validation ⚠️ **HIGH PRIORITY**
**Status**: Implemented but not validated
**Effort**: 2-3 hours
**Files**: `scripts/etc/jenkins/cert-rotator.sh`, `scripts/etc/jenkins/jenkins-cert-rotator.yaml.tmpl`

**What exists:**
- ✅ CronJob implementation (runs every 12 hours by default)
- ✅ Automatic cert renewal when expiry < 5 days
- ✅ Vault PKI integration for minting new certs
- ✅ Old cert revocation in Vault
- ✅ K8s secret updates
- ✅ RBAC permissions configured

**What needs validation:**
- [ ] Manual trigger test: Force cert rotation by setting short TTL
- [ ] Verify CronJob deploys correctly
- [ ] Test cert renewal workflow end-to-end
- [ ] Verify old cert gets revoked in Vault
- [ ] Test Jenkins pod picks up new cert without restart
- [ ] Validate error handling (Vault unreachable, kubectl missing, etc.)
- [ ] Check image pull issues (google/cloud-sdk:slim availability)

**Test Plan:**
```bash
# 1. Deploy Jenkins with short cert TTL for testing
export VAULT_PKI_ROLE_TTL="5m"
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="240"  # 4 minutes
export JENKINS_CERT_ROTATOR_SCHEDULE="*/5 * * * *"  # Every 5 min for testing
./scripts/k3d-manager deploy_jenkins --enable-vault

# 2. Verify initial cert
kubectl get secret -n istio-system jenkins-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# 3. Watch for rotation
kubectl logs -n jenkins -l job-name=jenkins-cert-rotator-<job-id> -f

# 4. Verify new cert issued
kubectl get secret -n istio-system jenkins-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -serial

# 5. Check Vault for revocation
kubectl exec -n vault vault-0 -- vault list pki/certs/revoked
```

**Success Criteria:**
- CronJob runs successfully
- New cert issued before expiry
- Old cert serial appears in Vault revoked list
- Jenkins continues serving HTTPS without interruption
- No errors in rotator logs

---

### 1.2 End-to-End AD Integration Testing
**Status**: Components exist, need full integration test
**Effort**: 2-3 hours

**Test Scenarios:**

**Scenario A: AD Schema Testing (OpenLDAP)**
```bash
# 1. Deploy full stack
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault

# 2. Verify OpenLDAP has AD schema
kubectl exec -n directory <pod> -- ldapsearch -x -b "DC=corp,DC=example,DC=com" -LLL dn

# 3. Test Jenkins login
# Login with: alice/password
# Verify: Jenkins Admins group membership, admin permissions

# 4. Verify Active Directory plugin loaded
kubectl logs -n jenkins deploy/jenkins | grep -i "active.*directory"
```

**Scenario B: Production AD Connection** (requires real AD or mock)
```bash
# Set up AD connection
export AD_DOMAIN=corp.example.com
export AD_SERVER=dc.corp.example.com
export AD_BIND_DN="CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
export AD_BIND_PASSWORD="..."

# Deploy
./scripts/k3d-manager deploy_jenkins --enable-ad-prod --enable-vault

# Validate connectivity before deployment
# Should fail fast if AD unreachable
```

**Success Criteria:**
- Both LDAP and AD modes work
- Authentication succeeds
- Group membership detected
- Authorization rules applied correctly

---

## Priority 2: Documentation Completion (2-3 hours)

### 2.1 Certificate Rotation Documentation
**Effort**: 1 hour

**Create:** `docs/guides/certificate-rotation.md`

**Contents:**
```markdown
# Jenkins Certificate Rotation Guide

## Overview
- How cert rotation works
- CronJob schedule and configuration
- Manual rotation procedures
- Troubleshooting rotation failures

## Configuration
- VAULT_PKI_ROLE_TTL - Cert lifetime
- JENKINS_CERT_ROTATOR_SCHEDULE - CronJob schedule
- JENKINS_CERT_ROTATOR_RENEW_BEFORE - Renewal threshold
- JENKINS_CERT_ROTATOR_IMAGE - Container image

## Manual Operations
- Force immediate rotation
- Check cert expiry
- View rotation logs
- Disable auto-rotation

## Troubleshooting
- Image pull failures
- Vault connection errors
- kubectl not found
- Permission denied errors
```

---

### 2.2 Mac AD Setup Guide
**Effort**: 30 minutes

**Create:** `docs/guides/mac-ad-setup.md`

**Contents:**
```markdown
# Mac Active Directory Setup Guide

## Prerequisites
- Corporate VPN access
- AD service account credentials
- kubectl access to cluster

## One-Time Configuration
1. Create AD config file
2. Source config before deployment
3. Validate connectivity
4. Deploy Jenkins

## Testing Without AD Access
- Use AD_TEST_MODE=1
- Deploy with --enable-ad for schema testing
- Switch to production AD when available

## Troubleshooting
- VPN connectivity
- DNS resolution
- ldapsearch installation (brew install openldap)
```

---

### 2.3 Update directory-service-interface.md
**Effort**: 30 minutes

**Update:** `docs/plans/directory-service-interface.md`

Add Active Directory provider section:
- Provider interface implementation
- AD-specific functions
- Configuration variables
- Differences from OpenLDAP provider

---

### 2.4 AD Connectivity Troubleshooting Guide
**Effort**: 30 minutes

**Create:** `docs/guides/ad-connectivity-troubleshooting.md`

**Contents:**
```markdown
# Active Directory Connectivity Troubleshooting

## Pre-Deployment Validation
- DNS resolution checks
- Port connectivity tests
- LDAP bind authentication
- Group membership queries

## Common Issues
- VPN not connected
- Firewall blocking LDAPS (636)
- Service account locked/expired
- Wrong DN format
- Certificate validation failures

## Diagnostic Commands
- nslookup, host, dig
- nc, telnet port tests
- ldapsearch manual queries
- Vault AD secrets engine status
```

---

## Priority 3: Nice-to-Have Enhancements (Optional)

### 3.1 Monitoring & Alerting Recommendations
**Effort**: 1 hour

**Create:** `docs/guides/monitoring-jenkins.md`

**Contents:**
- Certificate expiry monitoring
- Cert rotation job success/failure alerts
- AD authentication failure metrics
- Vault connectivity health checks
- Recommended Prometheus queries

---

### 3.2 Automated Tests for Certificate Rotation
**Effort**: 2-3 hours

**Create:** `scripts/tests/lib/vault_pki_rotation.bats`

Test scenarios:
- Cert issuance
- Serial extraction
- Revocation
- K8s secret updates
- Error handling

---

### 3.3 Integration Test Suite
**Effort**: 3-4 hours

**Create:** `scripts/tests/integration/jenkins_deployment.bats`

End-to-end tests:
- Full Jenkins deployment
- LDAP integration
- AD integration
- Vault PKI setup
- ESO secret sync

---

## Priority 4: Future Enhancements (Not in Scope)

These were marked as Phase 2/3 in the original plan:

- [ ] Kerberos SSO support
- [ ] Global Catalog integration (ports 3268/3269)
- [ ] Vault LDAP secrets engine for dynamic credentials
- [ ] Multi-domain AD support
- [ ] Azure AD OAuth2/SAML integration
- [ ] AWS Directory Service support

---

## Execution Priority Order

### Week 1: Critical Path
1. **Certificate Rotation Validation** (Day 1-2)
   - Most critical - ensures production reliability
   - Currently unknown if working correctly
   - Blocks production deployment confidence

2. **End-to-End AD Testing** (Day 2-3)
   - Validates full integration
   - Identifies any missing pieces
   - Required before considering "done"

### Week 2: Documentation
3. **Certificate Rotation Docs** (Day 1)
   - Supports operational teams
   - Required for production handoff

4. **Mac AD Setup Guide** (Day 1)
   - Enables developer testing
   - Low effort, high value

5. **Update directory-service-interface.md** (Day 2)
   - Completes architecture documentation
   - Reference for future providers

6. **AD Connectivity Troubleshooting** (Day 2)
   - Reduces support burden
   - Common pain point

### Week 3+: Optional
7. Monitoring recommendations
8. Additional automated tests
9. Future enhancements (as needed)

---

## Success Metrics

**Definition of "Complete":**
- ✅ All Priority 1 tasks validated and working
- ✅ All Priority 2 documentation created
- ✅ No known blocking issues
- ✅ Handoff documentation ready

**Definition of "Production Ready":**
- All above, plus:
- ✅ Tested with real Active Directory (if using AD)
- ✅ Certificate rotation validated in production-like environment
- ✅ Monitoring/alerting configured
- ✅ Runbook documented

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cert rotation broken | High - outages | Priority 1 testing required |
| AD connectivity issues | Medium - auth fails | Comprehensive troubleshooting docs |
| Image pull failures | Low - workaround exists | Document alternative images |
| Missing tests | Low - manual testing possible | Add tests incrementally |

---

## Estimated Total Effort

| Priority | Tasks | Effort |
|----------|-------|--------|
| Priority 1 | Validation & Testing | 4-6 hours |
| Priority 2 | Documentation | 2-3 hours |
| Priority 3 | Enhancements | 6-8 hours (optional) |
| **Total Required** | | **6-9 hours** |
| **Total with Optional** | | **12-17 hours** |

---

## Current Branch Status

Branch: `ldap-develop`

Ready to merge to main after:
- Priority 1 validation complete
- Priority 2 documentation complete
- All tests passing
