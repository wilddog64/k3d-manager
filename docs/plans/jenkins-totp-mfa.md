# Jenkins TOTP/MFA Implementation Plan

**Date:** 2025-11-20
**Status:** Planned
**Priority:** Enhancement

---

## Objective

Add TOTP (Time-based One-Time Password) support to Jenkins for multi-factor authentication (MFA), allowing users to self-enroll via the Jenkins UI using apps like Google Authenticator or Authy.

---

## Recommended Plugin: miniOrange Two-Factor

**Plugin ID:** `miniorange-two-factor`

**Why This Plugin:**
- Actively maintained (April 2025 updates)
- Works with all security realms (LDAP, AD, local)
- No security realm extension required
- Official Jenkins plugin
- Supports TOTP with Mobile Authenticator

**Supported 2FA Methods:**

Free (Community Edition):
- TOTP/Mobile Authenticator (Google Authenticator, Authy, Microsoft Authenticator)
- Email OTP
- Security Questions

Premium (Enterprise Edition):
- Duo Push / Duo Security
- Yubikey Hardware Token
- SMS-based OTP

**Note:** Duo Push requires miniOrange Enterprise license. See [Duo Push Setup](#duo-push-setup-enterprise) section below for details.

---

## Implementation Steps

### Step 1: Add Plugin to Helm Values

```yaml
# scripts/etc/jenkins/values-ldap.yaml.tmpl
controller:
  installPlugins:
    # ... existing plugins ...
    - miniorange-two-factor
```

### Step 2: User Enrollment Flow

1. User logs in with LDAP credentials
2. Redirected to 2FA setup page (first login)
3. User scans QR code with authenticator app
4. User enters verification code to confirm
5. Subsequent logins require TOTP code

### Step 3: Admin Configuration

1. Access Jenkins > Manage Jenkins > miniOrange Two Factor
2. Enable 2FA globally
3. Select TOTP as 2FA method
4. Configure enrollment policies

### Step 4: Testing

1. Test with chengkai.liang (admin)
2. Test with test-user (regular user)
3. Verify LDAP + TOTP flow works
4. Test recovery scenarios

---

## Deployment Flag

MFA enabled by default, with `--disable-mfa` flag to opt out:

```bash
# Default: MFA enabled
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault

# Explicitly disable MFA (not recommended)
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault --disable-mfa
```

**Environment Variables:**
```bash
# MFA enabled by default (1), set to 0 to disable
export JENKINS_MFA_ENABLED="${JENKINS_MFA_ENABLED:-1}"
```

---

## Security Considerations

1. **Recovery Codes** - Users should generate backup codes
2. **Admin Bypass** - Maintain recovery mechanism if admin locked out
3. **Service Accounts** - Exclude CI/CD service accounts from MFA
4. **API Tokens** - API tokens bypass MFA (by design)

---

## Testing Checklist

- [ ] Plugin installs successfully
- [ ] 2FA configuration UI accessible
- [ ] User can enroll via QR code scan
- [ ] Login requires TOTP code after enrollment
- [ ] LDAP authentication still works with MFA
- [ ] Recovery mechanism works
- [ ] API tokens unaffected by MFA
- [ ] Configuration persists across restarts

---

## Timeline

| Task | Effort |
|------|--------|
| Add plugin to values | 15 min |
| Test enrollment flow | 30 min |
| Add --enable-mfa flag | 30 min |
| Documentation | 30 min |
| **Total** | ~2 hours |

---

## Duo Push Setup (Enterprise)

### Overview

Duo Push is a premium 2FA method available through miniOrange Enterprise license. It provides mobile push notifications for authentication instead of requiring manual code entry.

### Prerequisites

1. **miniOrange Enterprise License**
   - Contact miniOrange Sales: https://www.miniorange.com/contact
   - License required for Duo Push feature

2. **Duo Security Account**
   - Sign up at https://duo.com/
   - Free trial available for testing
   - Production requires paid Duo plan

3. **Duo Integration**
   - Create Duo application in Duo Admin Panel
   - Get Integration Key, Secret Key, and API Hostname

### Configuration Steps

#### Step 1: Configure Duo in miniOrange

1. Access Jenkins > Manage Jenkins > miniOrange Two Factor
2. Select "Duo Push" as 2FA method
3. Enter Duo credentials:
   - Integration Key: `${DUO_INTEGRATION_KEY}`
   - Secret Key: `${DUO_SECRET_KEY}`
   - API Hostname: `${DUO_API_HOSTNAME}`

#### Step 2: Store Duo Credentials in Vault

```bash
# Store Duo credentials in Vault
kubectl exec -n vault vault-0 -- \
  vault kv put secret/jenkins/duo-credentials \
  integration_key="YOUR_DUO_INTEGRATION_KEY" \
  secret_key="YOUR_DUO_SECRET_KEY" \
  api_hostname="api-XXXXXXXX.duosecurity.com"
```

#### Step 3: Create ExternalSecret for Duo

```yaml
# scripts/etc/jenkins/duo-external-secret.yaml.tmpl
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: duo-credentials
  namespace: ${JENKINS_NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: duo-credentials
    creationPolicy: Owner
  data:
    - secretKey: integration_key
      remoteRef:
        key: secret/jenkins/duo-credentials
        property: integration_key
    - secretKey: secret_key
      remoteRef:
        key: secret/jenkins/duo-credentials
        property: secret_key
    - secretKey: api_hostname
      remoteRef:
        key: secret/jenkins/duo-credentials
        property: api_hostname
```

#### Step 4: User Enrollment

1. User logs in with LDAP credentials
2. Redirected to Duo enrollment page
3. User scans QR code with Duo Mobile app
4. User receives test push notification
5. User approves test push to complete enrollment
6. Subsequent logins send push notification to mobile device

### Testing Duo Push

```bash
# Test enrollment flow
1. Deploy Jenkins with Duo configured
2. Login as test user (e.g., test-user)
3. Follow Duo enrollment wizard
4. Approve test push on mobile device
5. Verify subsequent login triggers Duo Push
```

### Cost Considerations

**miniOrange Enterprise License:**
- Annual subscription required
- Pricing varies by user count
- Contact miniOrange for quote

**Duo Security:**
- Free: Up to 10 users (suitable for testing)
- Essentials: $3/user/month
- Advantage: $6/user/month
- Premier: $9/user/month

### Alternative: Duo Unix Authentication (Free)

For cost-conscious deployments, consider Duo Unix PAM authentication instead:

```bash
# Install Duo Unix on Jenkins host
# Configure PAM to use Duo
# Integrate with Jenkins via PAM security realm

# Pros: Free for unlimited users
# Cons: More complex setup, requires PAM integration
```

### Fallback to TOTP

If Duo Push is not feasible due to cost, use free TOTP instead:

```yaml
# Default to TOTP (Google Authenticator, Authy)
controller:
  installPlugins:
    - miniorange-two-factor
```

**Benefits of TOTP over Duo Push:**
- No ongoing costs (completely free)
- Works with any TOTP app (Google Authenticator, Authy, Microsoft Authenticator)
- No external service dependency
- Still provides strong 2FA security

**Trade-offs:**
- User must manually enter 6-digit code (vs. push approval)
- Requires time synchronization between client and server
- No push notifications

### Environment Variables

```bash
# Enable MFA with Duo Push (Enterprise only)
export JENKINS_MFA_ENABLED=1
export JENKINS_MFA_METHOD="duo-push"
export DUO_INTEGRATION_KEY="<from-duo-admin-panel>"
export DUO_SECRET_KEY="<from-duo-admin-panel>"
export DUO_API_HOSTNAME="api-XXXXXXXX.duosecurity.com"

# Fallback to TOTP (free)
export JENKINS_MFA_ENABLED=1
export JENKINS_MFA_METHOD="totp"
```

---

## References

- [miniOrange Two-Factor Plugin](https://plugins.jenkins.io/miniorange-two-factor/)
- [miniOrange Setup Guide](https://www.miniorange.com/atlassian/jenkins-two-factor-authentication-2fa-mfa/)
- [Duo Security Documentation](https://duo.com/docs)
- [Duo Pricing](https://duo.com/pricing)
- [Duo Admin Panel](https://admin.duosecurity.com/)
