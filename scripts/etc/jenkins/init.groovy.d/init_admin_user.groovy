#!groovy
import jenkins.model.*
import hudson.security.*
import hudson.security.csrf.DefaultCrumbIssuer

// ── 0) SKIP setup wizard ──────────────────────────────────────────────
// Jenkins.instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// ── 1) ENSURE SECURITY REALM & ADMIN USER ────────────────────────────
def instance = Jenkins.getInstance()
def realm = instance.getSecurityRealm()

if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    // switch to the default in-Jenkins user database
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
}

// aminUser.setPassword(adminPwd)
// 1. define where your Docker-mounted secret will live
def secretPath = '/run/secrets/ADMIN_PASS'

// 2. pick up the password:
//    – if the secret file exists, read it
//    – otherwise fall back to the ENV var
def adminUser = System.getenv('JENKINS_ADMIN_ID')
def adminPwd = System.getenv('JENKINS_ADMIN_PASSWORD')
def secretFile = new File(secretPath)
if ( secretFile.exists() && secretFile.canRead() ) {
    adminPwd = secretFile.text.trim()
    println "ℹ️  Loaded admin password from secret file (${secretPath})"
}
else if ( adminUser && adminPwd ) {
    adminPwd = System.getenv('ADMIN_PASS').trim()
    println "ℹ️  Loaded admin password from ENV var"
}
else {
    throw new IllegalStateException(
        "⚠️  No admin password found: neither ${secretPath} nor ENV[ADMIN_PASS] is set"
    )
}

// create admin account
def adminUser = realm.getUser('admin') ?: realm.createAccount(AdminUser, adminPwd)
adminUser.save()

// ── 2) CRUMB ISSUER (optional, but often wanted) ───────────────────────
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// ── 3) MATRIX AUTHORIZATION STRATEGY ─────────────────────────────────
def oldAuth = instance.getAuthorizationStrategy()
def acl = (oldAuth instanceof GlobalMatrixAuthorizationStrategy)
          ? oldAuth
          : new GlobalMatrixAuthorizationStrategy()

// 3d) grant Overall/Read + Overall/Administer to the final 'admin' row
// Use the built-in constants so we get the correct Permission objects
[ Jenkins.READ, Jenkins.ADMINISTER ].each { perm ->
    if (!acl.grantedPermissions[perm]?.contains('admin')) {
        acl.add(perm, 'admin')
    }
}

// ── 4) INSTALL AND SAVE ────────────────────────────────────────────────
instance.setAuthorizationStrategy(acl)
instance.save()

println "✔ Security realm, admin user, and matrix authorization configured."
