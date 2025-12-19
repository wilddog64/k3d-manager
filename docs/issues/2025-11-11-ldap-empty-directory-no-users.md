# LDAP Empty Directory - No Users for Testing

**Date:** 2025-11-11
**Status:** Open
**Priority:** High
**Component:** LDAP, Jenkins Authentication

## Problem Statement

When deploying Jenkins with `--enable-ldap --enable-vault`, the LDAP directory is **empty** with no users, making it impossible to test or login to Jenkins. This creates a poor user experience and breaks smoke testing.

### Current Behavior

```bash
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault
```

**Result:**
- ✅ Jenkins deploys successfully
- ✅ LDAP server is running
- ❌ LDAP directory is empty (0 users)
- ❌ Cannot login to Jenkins (no valid credentials)
- ❌ Smoke test skips authentication (no users found)

### Expected Behavior

When deploying with `--enable-ldap`, the LDAP directory should contain:
- Test users with known credentials
- Organizational structure (OUs for users, groups, service accounts)
- Jenkins admin group with proper permissions
- Realistic group membership matching production patterns

### Baseline Branch Comparison

In the **baseline branch**, AD integration uses:
- Group: `IT DevOps`
- Real user credentials work (e.g., `chengkai.liang`)
- Proper organizational structure
- Realistic testing environment

Current ldap-develop branch lacks this structure.

## Root Cause Analysis

### 1. No Bootstrap LDIF for Basic LDAP Schema

**File:** `scripts/etc/ldap/bootstrap-ad-schema.ldif`
- Only loaded when `--enable-ad` flag is used
- Contains test users: alice, bob, charlie, jenkins-svc
- Not loaded for basic `--enable-ldap` deployments

**Current LDAP deployment** (`--enable-ldap`):
```yaml
Base DN: dc=home,dc=org
Users: 0
Groups: 0
OUs: 0
Structure: Empty
```

**AD schema deployment** (`--enable-ad`):
```yaml
Base DN: DC=corp,DC=example,DC=com
Users: 4 (alice, bob, charlie, jenkins-svc)
Groups: 3 (Jenkins Admins, IT Developers, IT Users)
OUs: 3 (Users, Groups, ServiceAccounts)
Structure: Complete AD-style hierarchy
```

### 2. Group Naming Inconsistency

**Current Implementation:**
- Jenkins expects group: `jenkins-admins` (lowercase, hyphenated)
- Baseline branch uses: `IT DevOps` (title case, space)

**Issue:** Group naming is not aligned with baseline branch patterns.

### 3. Missing User Credentials Documentation

**Current:**
- Test users exist in AD schema but password not documented clearly
- Password: `test1234` (hardcoded in SSHA hash)
- No clear documentation on how to login after deployment

**Needed:**
- Clear documentation of test credentials
- Mapping to jenkins-admin group
- Instructions for smoke testing

## Proposed Solution

### Option 1: Create Basic LDAP Bootstrap LDIF (Recommended)

**Create:** `scripts/etc/ldap/bootstrap-basic-schema.ldif`

**Structure:**
```ldif
# Base DN
dn: dc=home,dc=org
objectClass: top
objectClass: dcObject
objectClass: organization
o: Home Organization
dc: home

# Organizational Units
dn: ou=users,dc=home,dc=org
objectClass: organizationalUnit
ou: users

dn: ou=groups,dc=home,dc=org
objectClass: organizationalUnit
ou: groups

# Test Users (matching baseline branch style)
dn: cn=chengkai.liang,ou=users,dc=home,dc=org
objectClass: inetOrgPerson
objectClass: posixAccount
cn: chengkai.liang
sn: Liang
givenName: Chengkai
displayName: Chengkai Liang
uid: chengkai.liang
uidNumber: 10001
gidNumber: 10000
homeDirectory: /home/chengkai.liang
mail: chengkai.liang@home.org
userPassword: {SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy

dn: cn=jenkins-admin,ou=users,dc=home,dc=org
objectClass: inetOrgPerson
objectClass: posixAccount
cn: jenkins-admin
sn: Admin
givenName: Jenkins
displayName: Jenkins Administrator
uid: jenkins-admin
uidNumber: 10002
gidNumber: 10000
homeDirectory: /home/jenkins-admin
mail: jenkins-admin@home.org
userPassword: {SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy

dn: cn=test-user,ou=users,dc=home,dc=org
objectClass: inetOrgPerson
objectClass: posixAccount
cn: test-user
sn: User
givenName: Test
displayName: Test User
uid: test-user
uidNumber: 10003
gidNumber: 10000
homeDirectory: /home/test-user
mail: test-user@home.org
userPassword: {SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy

# Groups
dn: cn=jenkins-admins,ou=groups,dc=home,dc=org
objectClass: groupOfNames
cn: jenkins-admins
description: Jenkins Administrators Group
member: cn=chengkai.liang,ou=users,dc=home,dc=org
member: cn=jenkins-admin,ou=users,dc=home,dc=org

dn: cn=it-devops,ou=groups,dc=home,dc=org
objectClass: groupOfNames
cn: it-devops
description: IT DevOps Team (matches baseline branch)
member: cn=chengkai.liang,ou=users,dc=home,dc=org
member: cn=jenkins-admin,ou=users,dc=home,dc=org

dn: cn=developers,ou=groups,dc=home,dc=org
objectClass: groupOfNames
cn: developers
description: Development Team
member: cn=test-user,ou=users,dc=home,dc=org
```

**Password for all test users:** `test1234`

### Option 2: Reuse AD Schema for Basic LDAP

**Approach:** Make `bootstrap-ad-schema.ldif` the default for both `--enable-ldap` and `--enable-ad`.

**Pros:**
- No new files needed
- Already has proper structure
- Test users already defined

**Cons:**
- Uses AD-style DNs (DC=corp,DC=example,DC=com)
- May be confusing for basic LDAP testing
- Doesn't match dc=home,dc=org convention

### Option 3: Auto-Bootstrap on First Deployment

**Approach:** Detect empty LDAP directory and auto-load bootstrap data.

**Implementation in `scripts/plugins/ldap.sh`:**
```bash
function _bootstrap_ldap_users() {
  local ldap_pod user_count

  ldap_pod=$(kubectl -n directory get pod -l app.kubernetes.io/name=openldap \
    -o jsonpath='{.items[0].metadata.name}')

  # Check if directory is empty
  user_count=$(kubectl -n directory exec "$ldap_pod" -- \
    ldapsearch -x -H ldap://localhost:389 \
    -D "cn=admin,dc=home,dc=org" \
    -w "$LDAP_ADMIN_PASSWORD" \
    -b "dc=home,dc=org" \
    "(objectClass=person)" dn 2>/dev/null | grep -c "^dn:" || echo "0")

  if [[ "$user_count" -eq 0 ]]; then
    echo "LDAP directory is empty, bootstrapping test users..."
    kubectl -n directory exec "$ldap_pod" -- \
      ldapadd -x -H ldap://localhost:389 \
      -D "cn=admin,dc=home,dc=org" \
      -w "$LDAP_ADMIN_PASSWORD" \
      -f /bootstrap/basic-schema.ldif
    echo "✅ LDAP test users created"
  fi
}
```

## Implementation Plan

### Phase 1: Create Bootstrap LDIF
1. Create `scripts/etc/ldap/bootstrap-basic-schema.ldif`
2. Add test users: chengkai.liang, jenkins-admin, test-user
3. Add groups: jenkins-admins, it-devops, developers
4. Use dc=home,dc=org structure (matches current LDAP config)

### Phase 2: Update LDAP Deployment
1. Mount bootstrap LDIF as ConfigMap
2. Auto-load on first deployment (optional via flag)
3. Add detection logic to skip if users already exist
4. **Integrate smoke test into `deploy_ldap` function**
   - Test LDAP connectivity after deployment
   - Report directory status (empty vs populated)
   - Provide clear feedback about what was tested

### Phase 3: Update Smoke Test
1. Update `test_login_ldap()` to check for chengkai.liang, jenkins-admin
2. Update skip message to be more informative
3. Add verbose output showing available users
4. **Support testing both scenarios:**
   - Empty directories (current behavior - should pass with skip)
   - Populated directories (new behavior - should pass with auth test)
5. **Add clear test descriptions:**
   - "Testing empty LDAP directory handling..."
   - "Testing LDAP authentication with test users..."
   - "Testing Jenkins login with chengkai.liang..."

### Phase 4: Deploy Integration
1. Integrate smoke test into `deploy_ldap` function
2. Integrate smoke test into `deploy_jenkins` function (Phase 5 from smoke test plan)
3. Auto-detect auth mode from deployment flags
4. Provide clear pass/fail/skip feedback

### Phase 5: Documentation
1. Update README.md with test credentials
2. Document group membership
3. Add smoke testing instructions
4. Explain baseline branch alignment
5. Document both empty and populated directory testing scenarios

## Test Credentials Reference

| Username | Password | Groups | Purpose |
|----------|----------|--------|---------|
| chengkai.liang | test1234 | jenkins-admins, it-devops | Admin user (matches baseline) |
| jenkins-admin | test1234 | jenkins-admins, it-devops | Service account |
| test-user | test1234 | developers | Regular user |

## Test User Lifecycle Management

**Important Question:** What happens to test users after smoke testing?

### Proposed Strategy: Conditional Cleanup

**On Smoke Test Success:**
```bash
✅ Smoke test passed
🗑️  Cleaning up test users...
   - Removed: chengkai.liang
   - Removed: jenkins-admin
   - Removed: test-user
✅ LDAP directory cleaned
```
**Result:** Clean directory, no test data pollution

**On Smoke Test Failure:**
```bash
❌ Smoke test failed
⚠️  Preserving test users for debugging
   - User: chengkai.liang (password: test1234)
   - User: jenkins-admin (password: test1234)
   - User: test-user (password: test1234)
ℹ️  To manually cleanup: kubectl -n directory exec <pod> -- ldapdelete ...
```
**Result:** Test users remain for troubleshooting

### Implementation Options

#### Option 1: Ephemeral Test Users (Recommended)
Create test users only for smoke testing, then clean up:
- **Pros:** No test data pollution, clean directory after testing
- **Cons:** Cannot login after deployment (unless users re-created)

#### Option 2: Persistent Test Users
Keep test users permanently in directory:
- **Pros:** Can login anytime for manual testing
- **Cons:** Test credentials in production-like environment

#### Option 3: Flag-Based Control
Add `--skip-cleanup` or `--keep-test-users` flag:
```bash
# Default: cleanup after success
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault

# Keep test users for manual testing
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault --keep-test-users
```
- **Pros:** Flexible, user decides
- **Cons:** More complexity

### Recommended Approach: Option 3 with Smart Defaults

**Default Behavior:**
- Test users created during deployment
- Smoke test runs automatically
- **Success:** Clean up test users (clean directory)
- **Failure:** Preserve test users (debug mode)
- Clear message about what was done

**Override with Flag:**
```bash
--keep-test-users    # Always keep test users (manual testing)
--skip-cleanup       # Never cleanup (debugging)
```

**Implementation Example:**
```bash
function _cleanup_test_users() {
  local ldap_pod cleanup_enabled

  cleanup_enabled="${JENKINS_CLEANUP_TEST_USERS:-1}"  # Default: cleanup enabled

  if [[ "${KEEP_TEST_USERS:-0}" == "1" ]]; then
    echo "ℹ️  Test users preserved (--keep-test-users flag)"
    return 0
  fi

  if [[ "$cleanup_enabled" == "1" ]]; then
    echo "🗑️  Cleaning up test users..."
    ldap_pod=$(kubectl -n directory get pod -l app=openldap -o name | head -1)

    for user in chengkai.liang jenkins-admin test-user; do
      kubectl -n directory exec "$ldap_pod" -- \
        ldapdelete -x -H ldap://localhost:389 \
        -D "cn=admin,dc=home,dc=org" \
        -w "$LDAP_ADMIN_PASSWORD" \
        "cn=$user,ou=users,dc=home,dc=org" 2>/dev/null && \
        echo "   - Removed: $user"
    done

    echo "✅ Test users cleaned up"
  fi
}

# In smoke test:
if smoke_test_passed; then
  _cleanup_test_users
else
  echo "⚠️  Test users preserved for debugging:"
  echo "   chengkai.liang:test1234"
  echo "   jenkins-admin:test1234"
  echo "   test-user:test1234"
fi
```

## Testing Strategy

The smoke test must support and clearly report on **both scenarios**:

### Scenario 1: Empty Directory (Current Behavior)
**Test:** Empty LDAP directory handling
**Expected Result:**
```
[INFO] Testing LDAP authentication...
[INFO] Testing LDAP server connectivity...
[SKIP] No users found in LDAP directory (use --enable-ad for test users)
```
**Exit Code:** 0 (success - gracefully handled)
**Message:** Clear explanation of why skipped and how to get users

### Scenario 2: Populated Directory (After Fix)
**Test:** LDAP authentication with test users
**Expected Result:**
```
[INFO] Testing LDAP authentication...
[INFO] Testing LDAP server connectivity...
[INFO] Found 3 users in LDAP directory
[INFO] Using LDAP test user: chengkai.liang
[PASS] LDAP authentication successful (HTTP 200)
```
**Exit Code:** 0 (success - auth validated)
**Message:** Clear indication which user was tested

### Scenario 3: Populated But Wrong Credentials
**Test:** LDAP authentication failure detection
**Expected Result:**
```
[INFO] Testing LDAP authentication...
[INFO] Testing LDAP server connectivity...
[INFO] Found 3 users in LDAP directory
[INFO] Using LDAP test user: chengkai.liang
[FAIL] LDAP authentication failed (HTTP 401)
```
**Exit Code:** 1 (failure - auth broken)
**Message:** Clear indication of authentication failure

## Success Criteria

After fix:
- ✅ Deploy with `--enable-ldap` creates test users
- ✅ Can login to Jenkins with chengkai.liang:test1234
- ✅ Can login to Jenkins with jenkins-admin:test1234
- ✅ Smoke test passes authentication check with clear messages
- ✅ Smoke test gracefully handles empty directories with clear skip messages
- ✅ Smoke test detects auth failures with clear error messages
- ✅ Group membership works (jenkins-admins has admin rights)
- ✅ Aligned with baseline branch patterns
- ✅ `deploy_ldap` function runs smoke test automatically
- ✅ `deploy_jenkins` function runs smoke test automatically (Phase 5)
- ✅ **Test users cleaned up on success** (no test data pollution)
- ✅ **Test users preserved on failure** (for debugging)
- ✅ **Clear messages about cleanup actions**
- ✅ **`--keep-test-users` flag for manual testing**

## Related Files

**To Create:**
- `scripts/etc/ldap/bootstrap-basic-schema.ldif`

**To Modify:**
- `scripts/plugins/ldap.sh` - Add bootstrap logic
- `bin/smoke-test-jenkins.sh` - Update user detection
- `README.md` - Add test credentials documentation

## References

- Baseline branch AD configuration: `IT DevOps` group
- Current AD schema: `scripts/etc/ldap/bootstrap-ad-schema.ldif`
- Smoke test implementation: `bin/smoke-test-jenkins.sh`
- Smoke test plan: `docs/plans/jenkins-smoke-test-implementation.md`
