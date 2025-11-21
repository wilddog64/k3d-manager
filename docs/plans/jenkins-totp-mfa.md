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
- TOTP (Google Authenticator, Authy, Microsoft Authenticator)
- Email OTP
- Security Questions
- Duo Push (premium)
- Yubikey (premium)

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

## References

- [miniOrange Two-Factor Plugin](https://plugins.jenkins.io/miniorange-two-factor/)
- [miniOrange Setup Guide](https://www.miniorange.com/atlassian/jenkins-two-factor-authentication-2fa-mfa/)
