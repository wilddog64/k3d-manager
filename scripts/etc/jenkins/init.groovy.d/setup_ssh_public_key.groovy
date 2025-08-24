import jenkins.model.Jenkins
import org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl
import hudson.model.User
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

def inst = Jenkins.get()

/* ------------------------------------------------------------------
 * 1) Make sure we’re using HudsonPrivateSecurityRealm and that
 *    the “admin” account exists (create only if missing).
 * ---------------------------------------------------------------- */
if (!(inst.securityRealm instanceof HudsonPrivateSecurityRealm)) {
    inst.securityRealm = new HudsonPrivateSecurityRealm(false)
}
def realm = (HudsonPrivateSecurityRealm) inst.securityRealm

/* ------------------------------------------------------------------
 * 2) Read the SSH public key from a mounted file and attach it.
 * ---------------------------------------------------------------- */
def keyPath = System.getenv('ADMIN_SSH_KEY_PATH') ?: '/run/secrets/jenkins_admin_ssh_key.pub'
def keyFile = new File(keyPath)
if (!keyFile.exists() || !keyFile.canRead()) {
    println "WARNING: SSH public key not found at ${keyPath}; skipping injection"
} else {
    def pubKey = keyFile.text.trim()
    admin.addProperty(new UserPropertyImpl(pubKey))
    admin.save()
    println ">>> Injected SSH public key for 'admin' from ${keyPath}"
}

/* ------------------------------------------------------------------
 * 4) Enable the SSHD plugin if the port is not already > 0.
 * ---------------------------------------------------------------- */
def sshd = inst.getDescriptor('org.jenkinsci.main.modules.sshd.SSHD')
if (sshd.port <= 0) {                          // port ≤ 0 ⇒ disabled
    sshd.port = Integer.getInteger('SSH_PORT', 2233)
    sshd.save()
    println ">>> SSHD enabled on port ${sshd.port}"
}
